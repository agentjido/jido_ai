defmodule Jido.AI.Directive do
  @moduledoc """
  Generic LLM-related directives for Jido agents.

  These directives are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They represent side effects that the AgentServer runtime should execute.

  ## Available Directives

  - `Jido.AI.Directive.ReqLLMStream` - Stream an LLM response with optional tool support
  - `Jido.AI.Directive.ToolExec` - Execute a Jido.Action as a tool

  ## Usage

      alias Jido.AI.Directive

      # Create an LLM streaming directive
      directive = Directive.ReqLLMStream.new!(%{
        id: "call_123",
        model: "anthropic:claude-haiku-4-5",
        context: messages,
        tools: tools
      })

      # Create a tool execution directive
      directive = Directive.ToolExec.new!(%{
        id: "tool_456",
        tool_name: "calculator",
        action_module: MyApp.Actions.Calculator,
        arguments: %{a: 1, b: 2, operation: "add"}
      })
  """

  defmodule ReqLLMStream do
    @moduledoc """
    Directive asking the runtime to stream an LLM response via ReqLLM.

    Uses ReqLLM for streaming. The runtime will execute this asynchronously
    and send partial tokens as `reqllm.partial` signals and the final result
    as a `reqllm.result` signal.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model: Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'"),
                context:
                  Zoi.any(
                    description:
                      "Conversation context: [ReqLLM.Message.t()] or ReqLLM.Context.t()"
                  ),
                tools:
                  Zoi.list(Zoi.any(),
                    description: "List of ReqLLM.Tool.t() structs (schema-only, callback ignored)"
                  )
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, tool_name}")
                  |> Zoi.default(:auto),
                max_tokens:
                  Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature:
                  Zoi.number(description: "Sampling temperature (0.0–2.0)") |> Zoi.default(0.2),
                metadata:
                  Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema

    @doc "Create a new ReqLLMStream directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ReqLLMStream: #{inspect(errors)}"
      end
    end
  end

  defmodule ToolExec do
    @moduledoc """
    Directive to execute a Jido.Action as a tool.

    The runtime will execute this asynchronously and send the result back
    as an `ai.tool_result` signal.

    ## Argument Normalization

    LLM tool calls return arguments with string keys (from JSON). The execution
    normalizes arguments using the action's schema before execution:
    - Converts string keys to atom keys
    - Parses string numbers to integers/floats based on schema type

    This ensures consistent argument semantics whether tools are called via
    DirectiveExec or any other path.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Tool call ID from LLM (ReqLLM.ToolCall.id)"),
                tool_name:
                  Zoi.string(description: "Name of the tool (matches Jido.Action.name/0)"),
                action_module: Zoi.any(description: "Module implementing Jido.Action behaviour"),
                arguments:
                  Zoi.map(description: "Arguments from LLM (string keys, normalized before exec)")
                  |> Zoi.default(%{}),
                context:
                  Zoi.map(description: "Execution context passed to Jido.Exec.run/3")
                  |> Zoi.default(%{}),
                metadata:
                  Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    def schema, do: @schema

    @doc "Create a new ToolExec directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid ToolExec: #{inspect(errors)}"
      end
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ReqLLMStream do
  @moduledoc """
  Spawns an async task to stream an LLM response and sends results back to the agent.

  This implementation provides **true streaming**: as tokens arrive from the LLM,
  they are immediately sent as `reqllm.partial` signals. When the stream completes,
  a final `reqllm.result` signal is sent with the full classification (tool calls
  or final answer).

  Error handling: If the LLM call raises an exception, the error is caught
  and sent back as an error result to prevent the agent from getting stuck.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      model: model,
      context: context,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    } = directive

    agent_pid = self()
    task_sup = if state.jido, do: Jido.task_supervisor_name(state.jido), else: Jido.TaskSupervisor

    Task.Supervisor.start_child(task_sup, fn ->
      result =
        try do
          stream_with_callbacks(
            call_id,
            model,
            context,
            tools,
            tool_choice,
            max_tokens,
            temperature,
            agent_pid
          )
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason)}}
        end

      signal = Signal.ReqLLMResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp stream_with_callbacks(
         call_id,
         model,
         context,
         tools,
         tool_choice,
         max_tokens,
         temperature,
         agent_pid
       ) do
    opts =
      []
      |> add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)

    messages = normalize_messages(context)

    case ReqLLM.stream_text(model, messages, opts) do
      {:ok, stream_response} ->
        on_content = fn text ->
          partial_signal =
            Signal.ReqLLMPartial.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :content
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)
        end

        on_thinking = fn text ->
          partial_signal =
            Signal.ReqLLMPartial.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :thinking
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)
        end

        case ReqLLM.StreamResponse.process_stream(stream_response,
               on_result: on_content,
               on_thinking: on_thinking
             ) do
          {:ok, response} ->
            {:ok, classify_response(response)}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp classify_response(response) do
    tool_calls = response.message.tool_calls || []

    type =
      cond do
        tool_calls != [] -> :tool_calls
        response.finish_reason == :tool_calls -> :tool_calls
        true -> :final_answer
      end

    %{
      type: type,
      text: extract_text(response.message.content),
      tool_calls: Enum.map(tool_calls, &normalize_tool_call/1)
    }
  end

  defp extract_text(nil), do: ""
  defp extract_text(content) when is_binary(content), do: content

  defp extract_text(content) when is_list(content) do
    content
    |> Enum.filter(&match?(%{type: :text}, &1))
    |> Enum.map_join("", & &1.text)
  end

  defp normalize_messages(%{messages: msgs}), do: msgs
  defp normalize_messages(msgs) when is_list(msgs), do: msgs
  defp normalize_messages(context), do: context

  defp normalize_tool_call(%ReqLLM.ToolCall{} = tc) do
    %{
      id: tc.id || "call_#{:erlang.unique_integer([:positive])}",
      name: ReqLLM.ToolCall.name(tc),
      arguments: ReqLLM.ToolCall.args_map(tc) || %{}
    }
  end

  defp normalize_tool_call(tool_call) when is_map(tool_call) do
    %{
      id: tool_call[:id] || tool_call["id"] || "call_#{:erlang.unique_integer([:positive])}",
      name: tool_call[:name] || tool_call["name"],
      arguments: parse_arguments(tool_call[:arguments] || tool_call["arguments"] || %{})
    }
  end

  defp parse_arguments(args) when is_binary(args) do
    case Jason.decode(args) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  defp parse_arguments(args) when is_map(args), do: args
  defp parse_arguments(_), do: %{}

  defp add_tools_opt(opts, []), do: opts
  defp add_tools_opt(opts, tools), do: Keyword.put(opts, :tools, tools)
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as an `ai.tool_result` signal.

  If the action raises an exception, the error is caught and sent back as an
  error result to prevent the agent from getting stuck in an awaiting state.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      action_module: action_module,
      arguments: arguments,
      context: context
    } = directive

    agent_pid = self()
    task_sup = if state.jido, do: Jido.task_supervisor_name(state.jido), else: Jido.TaskSupervisor

    Task.Supervisor.start_child(task_sup, fn ->
      result =
        try do
          normalized_args = normalize_arguments(action_module, arguments)

          case Jido.Exec.run(action_module, normalized_args, context) do
            {:ok, output} -> {:ok, output}
            {:error, reason} -> {:error, reason}
          end
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason)}}
        end

      signal =
        Signal.ToolResult.new!(%{
          call_id: call_id,
          tool_name: tool_name,
          result: result
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp normalize_arguments(action_module, arguments) do
    schema = action_module.schema()
    Jido.Action.Tool.convert_params_using_schema(arguments, schema)
  end
end
