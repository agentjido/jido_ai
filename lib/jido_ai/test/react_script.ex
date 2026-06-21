defmodule Jido.AI.Test.ReActScript do
  @moduledoc """
  Deterministic ReAct script returned by `Jido.AI.Test.expect_react/1`.

  Treat this struct as opaque. Pass it to `Jido.AI.Test.react_opts/1` for agent
  requests or `Jido.AI.Test.react_llm_opts/1` for standalone ReAct configs.
  """

  alias Jido.AI.Turn

  @table :jido_ai_react_scripts
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
  def llm_opts(%__MODULE__{} = script), do: [{@option_key, script}]

  @doc false
  @spec react_opts(t()) :: keyword()
  def react_opts(%__MODULE__{} = script), do: [llm_opts: llm_opts(script)]

  @doc false
  @spec register(t()) :: t()
  def register(%__MODULE__{} = script) do
    table = table()
    key = registry_key(owner_key(), script.user)
    :ets.insert(table, {key, script})
    script
  end

  @doc false
  @spec clear_current_owner() :: :ok
  def clear_current_owner do
    clear_owner(owner_key())
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
    with table when table != :undefined <- :ets.whereis(@table),
         user when user != "" <- latest_user_text(messages),
         [{_key, %__MODULE__{} = script}] <- :ets.lookup(table, registry_key(owner_key(), user)) do
      {:ok, script, :registry}
    else
      _ -> :not_scripted
    end
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

  defp maybe_unregister(%__MODULE__{} = script, :registry) do
    :ets.delete(table(), registry_key(owner_key(), script.user))
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

  defp table do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true, write_concurrency: true])
        rescue
          ArgumentError -> @table
        end

      _tid ->
        @table
    end
  end

  defp clear_owner(owner) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      table ->
        table
        |> :ets.match_object({{:react_script, owner, :_}, :_})
        |> Enum.each(fn {key, _script} -> :ets.delete(table, key) end)
    end

    :ok
  end

  defp registry_key(owner, user), do: {:react_script, owner, user}
  defp owner_key, do: Process.group_leader()
end
