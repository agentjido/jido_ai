defmodule Jido.AI.Test.ReActScript do
  @moduledoc """
  Deterministic ReAct script returned by `Jido.AI.Test.expect_react/1`.

  Treat this struct as opaque. Pass it to `Jido.AI.Test.react_opts/1` for agent
  requests or `Jido.AI.Test.react_llm_opts/1` for standalone ReAct configs.
  """

  alias Jido.AI.Turn

  @registry_key {__MODULE__, :scripts}
  @option_key :jido_ai_react_script

  defstruct [:id, :user, turns: []]

  @type turn :: %{
          required(:type) => :tool_call | :answer | :fail,
          optional(:tool_calls) => [map()],
          optional(:text) => String.t(),
          optional(:reason) => term(),
          optional(:usage) => map(),
          optional(:finish_reason) => atom()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          user: String.t(),
          turns: [turn()]
        }

  @doc false
  @spec new(map()) :: t()
  def new(%{user: user, turns: turns} = attrs) when is_list(turns) do
    normalized_user = normalize_user!(user)
    normalized_turns = normalize_turns!(turns)

    %__MODULE__{
      id: Map.get(attrs, :id) || "react_script_#{Jido.Util.generate_id()}",
      user: normalized_user,
      turns: normalized_turns
    }
  end

  def new(_attrs) do
    raise ArgumentError, "react test script requires user/1 and at least one model turn"
  end

  @doc false
  @spec llm_opts(t()) :: keyword()
  def llm_opts(%__MODULE__{} = script), do: [{:jido_ai_model_call, &__MODULE__.model_call/2}, {@option_key, script}]

  @doc false
  @spec react_opts(t()) :: keyword()
  def react_opts(%__MODULE__{} = script), do: [llm_opts: llm_opts(script)]

  @doc false
  @spec register(t()) :: t()
  def register(%__MODULE__{} = script) do
    install_option_binder()
    scripts = Process.get(@registry_key, %{})
    Process.put(@registry_key, Map.put(scripts, script.user, script))
    script
  end

  @doc false
  @spec clear_current_owner() :: :ok
  def clear_current_owner do
    Process.delete(@registry_key)
    :ok
  end

  @doc false
  def install_option_binder,
    do: Jido.AI.Model.Transport.put_option_binder(&__MODULE__.bind_model_options/2)

  @doc false
  def bind_model_options(%ReqLLM.Context{messages: messages}, options),
    do: bind_model_options(messages, options)

  def bind_model_options(messages, options) when is_list(messages) do
    case bind_messages(messages, options) do
      options when is_list(options) ->
        if Keyword.keyword?(options) and Keyword.has_key?(options, @option_key),
          do: Keyword.put(options, :jido_ai_model_call, &__MODULE__.model_call/2),
          else: options

      options when is_map(options) and not is_struct(options) ->
        if Map.has_key?(options, @option_key) or Map.has_key?(options, Atom.to_string(@option_key)),
          do: Map.put(options, :jido_ai_model_call, &__MODULE__.model_call/2),
          else: options

      options ->
        options
    end
  end

  def bind_model_options(_input, options), do: options

  @doc false
  def model_call(call, next) do
    case request(call.kind, call.input, call.options, fn model, options ->
           next.(call.kind, model, call.input, options, call.schema)
         end) do
      :not_scripted -> next.(call.kind, call.model, call.input, call.options, call.schema)
      result -> result
    end
  end

  @doc false
  @spec next_response(keyword(), list()) ::
          :not_scripted | {:ok, map()} | {:error, term()}
  def next_response(llm_opts, messages) when is_list(llm_opts) and is_list(messages) do
    case resolve_script(llm_opts, messages) do
      {:ok, script, source} ->
        build_next_response(script, source, messages)

      :not_scripted ->
        :not_scripted
    end
  rescue
    error in ArgumentError ->
      {:error, %{type: :invalid_react_test_script, message: Exception.message(error)}}
  end

  def next_response(_llm_opts, _messages), do: :not_scripted

  @doc false
  def bind_options(query, options), do: bind_messages([%{role: :user, content: query}], options)

  @doc false
  def bind_messages(messages, options) when is_list(options) do
    if not Keyword.keyword?(options) or Keyword.has_key?(options, @option_key) do
      options
    else
      case resolve_registered_script(messages) do
        {:ok, script, _source} -> Keyword.put(options, @option_key, script)
        :not_scripted -> options
      end
    end
  end

  def bind_messages(messages, options) when is_map(options) and not is_struct(options) do
    if Map.has_key?(options, @option_key) or Map.has_key?(options, Atom.to_string(@option_key)) do
      options
    else
      case resolve_registered_script(messages) do
        {:ok, script, _source} -> Map.put(options, @option_key, script)
        :not_scripted -> options
      end
    end
  end

  def bind_messages(messages, nil) do
    case resolve_registered_script(messages) do
      {:ok, script, _source} -> [{@option_key, script}]
      :not_scripted -> nil
    end
  end

  def bind_messages(_messages, options), do: options

  @doc false
  def request(kind, messages, options, request_fun) do
    messages =
      case messages do
        %ReqLLM.Context{messages: values} -> values
        values -> values
      end

    case next_response(options, messages) do
      :not_scripted ->
        :not_scripted

      {:error, _} = error ->
        error

      {:ok, response} when kind in [:text, :stream] ->
        # The same HTTP/SSE server serves package helpers and acceptance cases.
        # A stream keeps its server until the model task exits.
        reply = http_reply(response, kind)
        {:ok, server} = Jido.AI.Test.MockLLM.start_link(script: [%{reply: reply}], owner: self())

        options =
          options
          |> Keyword.drop([@option_key, :jido_ai_model_call])
          |> Keyword.merge(Jido.AI.Test.MockLLM.options(server))

        try do
          request_fun.(Jido.AI.Test.MockLLM.model(), options)
        after
          if kind != :stream and Process.alive?(server), do: GenServer.stop(server)
        end

      {:ok, _} ->
        {:error, %{type: :invalid_react_test_script, message: "ReAct scripts support text and stream requests"}}
    end
  end

  defp http_reply(response, :text) do
    {:raw,
     %{
       id: "scripted-response",
       object: "chat.completion",
       created: 1,
       model: "gpt-4o-mini",
       choices: [%{index: 0, message: http_message(response.message), finish_reason: to_string(response.finish_reason)}],
       usage: http_usage(response.usage)
     }}
  end

  defp http_reply(response, :stream) do
    delta = http_message(response.message) |> Map.delete(:role)

    delta =
      if delta[:tool_calls],
        do:
          Map.update!(delta, :tool_calls, fn calls ->
            Enum.with_index(calls, fn call, index -> Map.put(call, :index, index) end)
          end),
        else: delta

    {:stream, [delta], to_string(response.finish_reason), http_usage(response.usage)}
  end

  defp http_message(message) do
    base = %{role: "assistant", content: message.content}

    case message.tool_calls do
      nil ->
        base

      calls ->
        Map.put(
          base,
          :tool_calls,
          Enum.map(calls, fn call ->
            %{id: call.id, type: "function", function: %{name: call.name, arguments: Jason.encode!(call.arguments)}}
          end)
        )
    end
  end

  defp http_usage(usage),
    do: %{
      prompt_tokens: Map.get(usage, :input_tokens, 0),
      completion_tokens: Map.get(usage, :output_tokens, 0),
      total_tokens: Map.get(usage, :total_tokens, Map.get(usage, :input_tokens, 0) + Map.get(usage, :output_tokens, 0))
    }

  defp resolve_script(llm_opts, messages) do
    case Keyword.fetch(llm_opts, @option_key) do
      {:ok, %__MODULE__{} = script} ->
        {:ok, script, :explicit}

      {:ok, %{} = attrs} ->
        {:ok, new(attrs), :explicit}

      {:ok, other} ->
        raise ArgumentError,
              "jido_ai_react_script must be a #{inspect(__MODULE__)} struct or a map, got: #{inspect(other)}"

      :error ->
        resolve_registered_script(messages)
    end
  end

  defp resolve_registered_script(messages) do
    user = latest_user_text(messages)
    owners = [self() | Process.get(:"$callers", [])] |> Enum.filter(&is_pid/1) |> Enum.uniq()

    Enum.find_value(owners, :not_scripted, fn owner ->
      case Process.info(owner, :dictionary) do
        {:dictionary, dictionary} ->
          case (List.keyfind(dictionary, @registry_key, 0, {@registry_key, %{}}) |> elem(1))[user] do
            %__MODULE__{} = script -> {:ok, script, {:registry, owner}}
            _ -> nil
          end

        nil ->
          nil
      end
    end)
  end

  defp build_next_response(%__MODULE__{} = script, source, messages) do
    case validate_user_match(script, messages) do
      :ok ->
        build_response_at_turn(script, source, messages)

      {:error, reason} ->
        maybe_unregister(script, source)
        {:error, reason}
    end
  end

  defp build_response_at_turn(%__MODULE__{} = script, source, messages) do
    index = consumed_tool_turns(messages)

    case Enum.at(script.turns, index) do
      nil ->
        maybe_unregister(script, source)

        {:error,
         %{
           type: :react_test_script_exhausted,
           message: "ReAct test script for #{inspect(script.user)} has no turn at index #{index}",
           script_id: script.id
         }}

      %{type: :fail, reason: reason} ->
        maybe_unregister(script, source)
        {:error, reason}

      %{type: :answer} = turn ->
        maybe_unregister(script, source)
        {:ok, response(script, turn)}

      %{type: :tool_call} = turn ->
        {:ok, response(script, turn)}
    end
  end

  defp validate_user_match(%__MODULE__{user: expected, id: script_id}, messages) do
    case latest_user_text(messages) do
      ^expected ->
        :ok

      actual ->
        {:error,
         %{
           type: :react_test_script_user_mismatch,
           message: "ReAct test script expected user #{inspect(expected)}, got #{inspect(actual)}",
           script_id: script_id,
           expected_user: expected,
           actual_user: actual
         }}
    end
  end

  defp response(%__MODULE__{} = script, %{type: :tool_call} = turn) do
    %{
      message: %{
        content: Map.get(turn, :text),
        tool_calls: Map.fetch!(turn, :tool_calls),
        metadata: %{react_test_script_id: script.id}
      },
      finish_reason: Map.get(turn, :finish_reason, :tool_calls),
      usage: Map.get(turn, :usage, %{}),
      model: Map.get(turn, :model)
    }
  end

  defp response(%__MODULE__{} = script, %{type: :answer} = turn) do
    %{
      message: %{
        content: Map.get(turn, :text, ""),
        tool_calls: nil,
        metadata: %{react_test_script_id: script.id}
      },
      finish_reason: Map.get(turn, :finish_reason, :stop),
      usage: Map.get(turn, :usage, %{}),
      model: Map.get(turn, :model)
    }
  end

  defp maybe_unregister(%__MODULE__{} = script, {:registry, owner}) when owner == self() do
    Process.put(@registry_key, Map.delete(Process.get(@registry_key, %{}), script.user))
    :ok
  end

  defp maybe_unregister(_script, _source), do: :ok

  defp normalize_user!(user) do
    user
    |> normalize_content()
    |> case do
      "" -> raise ArgumentError, "react test script requires a non-empty user/1 prompt"
      text -> text
    end
  end

  defp normalize_turns!([]),
    do: raise(ArgumentError, "react test script requires at least one call/2, answer/1, or fail/1")

  defp normalize_turns!(turns) do
    {normalized, _call_index, terminal_seen?} =
      Enum.reduce(turns, {[], 0, false}, fn
        _turn, {_acc, _call_index, true} ->
          raise ArgumentError, "react test script cannot add turns after answer/1 or fail/1"

        %{type: :tool_call} = turn, {acc, call_index, false} ->
          next_index = call_index + 1
          {[normalize_tool_call_turn!(turn, next_index) | acc], next_index, false}

        %{type: :answer} = turn, {acc, call_index, false} ->
          {[normalize_answer_turn!(turn) | acc], call_index, true}

        %{type: :fail} = turn, {acc, call_index, false} ->
          {[normalize_fail_turn!(turn) | acc], call_index, true}

        other, _state ->
          raise ArgumentError, "invalid react test script turn: #{inspect(other)}"
      end)

    normalized = Enum.reverse(normalized)

    unless terminal_seen? do
      raise ArgumentError, "react test script must end with answer/1 or fail/1"
    end

    normalized
  end

  defp normalize_tool_call_turn!(%{name: name, arguments: arguments} = turn, index) do
    name = normalize_tool_name!(name)
    arguments = normalize_arguments!(arguments)
    opts = Map.get(turn, :opts, []) || []
    id = opts[:id] || "tc_#{index}"

    %{
      type: :tool_call,
      text: opts[:text],
      tool_calls: [
        %{
          id: to_string(id),
          name: name,
          arguments: arguments
        }
      ],
      finish_reason: :tool_calls,
      usage: Map.get(turn, :usage, opts[:usage] || %{})
    }
  end

  defp normalize_answer_turn!(%{text: text} = turn) do
    opts = Map.get(turn, :opts, []) || []

    %{
      type: :answer,
      text: normalize_content(text),
      finish_reason: opts[:finish_reason] || :stop,
      usage: Map.get(turn, :usage, opts[:usage] || %{})
    }
  end

  defp normalize_fail_turn!(%{reason: reason} = turn) do
    opts = Map.get(turn, :opts, []) || []

    %{
      type: :fail,
      reason: reason,
      usage: Map.get(turn, :usage, opts[:usage] || %{})
    }
  end

  defp normalize_tool_name!(name) do
    name = to_string(name)

    if name == "" do
      raise ArgumentError, "call/2 requires a non-empty tool name"
    else
      name
    end
  end

  defp normalize_arguments!(arguments) when is_map(arguments), do: arguments
  defp normalize_arguments!(_arguments), do: raise(ArgumentError, "call/2 arguments must be a map")

  defp latest_user_text(messages) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value("", fn
      %{role: role, content: content} when role in [:user, "user"] -> normalize_content(content)
      %ReqLLM.Message{role: role, content: content} when role in [:user, "user"] -> normalize_content(content)
      _other -> nil
    end)
  end

  defp consumed_tool_turns(messages) when is_list(messages) do
    Enum.count(messages, fn
      %{role: role, tool_calls: calls} when role in [:assistant, "assistant"] -> non_empty_list?(calls)
      %ReqLLM.Message{role: role, tool_calls: calls} when role in [:assistant, "assistant"] -> non_empty_list?(calls)
      _other -> false
    end)
  end

  defp non_empty_list?([_ | _]), do: true
  defp non_empty_list?(_), do: false

  defp normalize_content(content) when is_binary(content), do: content
  defp normalize_content(content) when is_list(content), do: Turn.extract_from_content(content)
  defp normalize_content(nil), do: ""
  defp normalize_content(content), do: to_string(content)
end
