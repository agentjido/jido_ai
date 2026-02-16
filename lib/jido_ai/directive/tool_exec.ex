defmodule Jido.AI.Directive.ToolExec do
  @moduledoc """
  Directive to execute a Jido.Action as a tool.

  The runtime will execute this asynchronously and send the result back
  as a `ai.tool.result` signal.

  ## Execution Modes

  1. **Direct module execution** (preferred): When `action_module` is provided,
     the module is executed directly via `Turn.execute_module/4`, bypassing
     name-based lookup. This is used by strategies that maintain their own tool lists.

  2. **Name lookup**: When `action_module` is nil, runtime resolves the tool name
     against the current strategy/plugin tool map and executes via `Jido.AI.Turn`.

  ## Argument Normalization

  LLM tool calls return arguments with string keys (from JSON). The execution
  normalizes arguments using the tool's schema before execution:
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
                Zoi.string(
                  description: "Name of the tool (resolved from runtime tool map if action_module not provided)"
                ),
              action_module:
                Zoi.atom(description: "Module to execute directly (bypasses name lookup)")
                |> Zoi.optional(),
              arguments:
                Zoi.map(description: "Arguments from LLM (string keys, normalized before exec)")
                |> Zoi.default(%{}),
              context:
                Zoi.map(description: "Execution context passed to Jido.Exec.run/3")
                |> Zoi.default(%{}),
              timeout_ms: Zoi.integer(description: "Per-attempt timeout in milliseconds") |> Zoi.optional(),
              max_retries:
                Zoi.integer(description: "Maximum retry attempts after initial failure")
                |> Zoi.default(0),
              retry_backoff_ms:
                Zoi.integer(description: "Fixed retry backoff in milliseconds")
                |> Zoi.default(0),
              request_id: Zoi.string(description: "Request correlation ID") |> Zoi.optional(),
              iteration: Zoi.integer(description: "Current ReAct iteration") |> Zoi.optional(),
              metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Create a new ToolExec directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid ToolExec: #{inspect(errors)}"
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as a `ai.tool.result` signal.

  Supports two execution modes:
  1. Direct module execution when `action_module` is provided (bypasses Registry)
  2. Registry lookup by `tool_name` when `action_module` is nil

  Uses `Jido.AI.Turn` for execution, which provides consistent error
  handling, parameter normalization, and telemetry.

  ## Error Handling (Issue #2 Fix)

  The entire task body is wrapped in try/rescue/catch to ensure that a
  `tool_result` signal is always sent back to the agent, even if:
  - Tool execution raises an exception
  - Signal construction fails
  - Any other unexpected error occurs

  This prevents the Machine from deadlocking in `awaiting_tool` state.
  """

  alias Jido.AI.Observe
  alias Jido.AI.Signal
  alias Jido.AI.Turn
  alias Jido.Tracing.Context, as: TraceContext

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      arguments: arguments,
      context: context
    } = directive

    action_module = Map.get(directive, :action_module)
    timeout_ms = Map.get(directive, :timeout_ms)
    max_retries = max(Map.get(directive, :max_retries, 0), 0)
    retry_backoff_ms = max(Map.get(directive, :retry_backoff_ms, 0), 0)
    metadata = Map.get(directive, :metadata, %{})
    obs_cfg = metadata[:observability] || context[:observability] || %{}
    request_id = Map.get(directive, :request_id) || metadata[:request_id] || context[:request_id]
    iteration = Map.get(directive, :iteration) || metadata[:iteration] || context[:iteration]
    run_id = metadata[:run_id] || context[:run_id] || request_id
    agent_id = metadata[:agent_id] || context[:agent_id]

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    # Get tools from state (agent's registered actions from skill or strategy)
    tools = get_tools_from_state(state)

    # Capture parent trace context before spawning
    parent_trace_ctx = TraceContext.get()

    case Task.Supervisor.start_child(task_supervisor, fn ->
           # Restore trace context in child task
           if parent_trace_ctx, do: Process.put({:jido, :trace_context}, parent_trace_ctx)

           event_meta = %{
             agent_id: agent_id,
             request_id: request_id,
             run_id: run_id,
             iteration: iteration,
             llm_call_id: nil,
             tool_call_id: call_id,
             tool_name: tool_name,
             model: nil,
             termination_reason: nil,
             error_type: nil
           }

           start_ms = System.monotonic_time(:millisecond)
           span_ctx = Observe.start_span(obs_cfg, Observe.tool(:span), event_meta)

           maybe_emit(
             obs_cfg,
             Observe.tool(:start),
             %{duration_ms: 0, queue_ms: 0, retry_count: 0},
             event_meta
           )

           {result, retry_count} =
             execute_with_retries(
               task_supervisor,
               action_module,
               tool_name,
               arguments,
               context,
               tools,
               timeout_ms,
               max_retries,
               retry_backoff_ms,
               event_meta,
               obs_cfg
             )

           duration_ms = System.monotonic_time(:millisecond) - start_ms

           case result do
             {:ok, _res} ->
               Observe.finish_span(span_ctx, %{duration_ms: duration_ms, retry_count: retry_count})

               maybe_emit(
                 obs_cfg,
                 Observe.tool(:complete),
                 %{duration_ms: duration_ms, retry_count: retry_count},
                 event_meta
               )

             {:error, %{type: :timeout} = error} ->
               Observe.finish_span_error(span_ctx, :error, error, [])

               timeout_meta = Map.merge(event_meta, %{error_type: :timeout})

               maybe_emit(
                 obs_cfg,
                 Observe.tool(:timeout),
                 %{duration_ms: duration_ms, retry_count: retry_count},
                 timeout_meta
               )

               maybe_emit(
                 obs_cfg,
                 Observe.tool(:error),
                 %{duration_ms: duration_ms, retry_count: retry_count},
                 Map.put(timeout_meta, :termination_reason, :error)
               )

             {:error, %{type: type}} ->
               Observe.finish_span_error(span_ctx, :error, %{type: type}, [])

               maybe_emit(
                 obs_cfg,
                 Observe.tool(:error),
                 %{duration_ms: duration_ms, retry_count: retry_count},
                 Map.merge(event_meta, %{error_type: type, termination_reason: :error})
               )

             {:error, _other} ->
               Observe.finish_span_error(span_ctx, :error, %{type: :executor}, [])

               maybe_emit(
                 obs_cfg,
                 Observe.tool(:error),
                 %{duration_ms: duration_ms, retry_count: retry_count},
                 Map.merge(event_meta, %{error_type: :executor, termination_reason: :error})
               )
           end

           # Signal construction in a separate try to ensure we always attempt delivery
           send_tool_result(agent_pid, call_id, tool_name, result)
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        send_tool_result(
          agent_pid,
          call_id,
          tool_name,
          {:error, error_envelope(:supervisor, "Failed to start tool execution task", %{reason: inspect(reason)}, true)}
        )

        {:ok, state}
    end
  end

  defp execute_with_retries(
         task_supervisor,
         action_module,
         tool_name,
         arguments,
         context,
         tools,
         timeout_ms,
         max_retries,
         retry_backoff_ms,
         event_meta,
         obs_cfg
       ) do
    0..max_retries
    |> Enum.reduce_while({{:error, error_envelope(:executor, "uninitialized error")}, 0}, fn attempt, _acc ->
      if attempt > 0 do
        maybe_emit(obs_cfg, Observe.tool(:retry), %{duration_ms: 0, retry_count: attempt}, event_meta)

        if retry_backoff_ms > 0, do: Process.sleep(retry_backoff_ms)
      end

      result =
        execute_attempt(
          task_supervisor,
          action_module,
          tool_name,
          arguments,
          context,
          tools,
          timeout_ms
        )

      case result do
        {:ok, _} = ok ->
          {:halt, {ok, attempt}}

        {:error, error} ->
          retryable? = retryable_error?(error)

          if retryable? and attempt < max_retries do
            {:cont, {result, attempt}}
          else
            {:halt, {result, attempt}}
          end
      end
    end)
  end

  defp execute_attempt(
         task_supervisor,
         action_module,
         tool_name,
         arguments,
         context,
         tools,
         timeout_ms
       ) do
    if is_integer(timeout_ms) and timeout_ms > 0 do
      task =
        Task.Supervisor.async_nolink(task_supervisor, fn ->
          execute_action(action_module, tool_name, arguments, context, tools)
        end)

      try do
        case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
          {:ok, result} ->
            normalize_result(result, tool_name)

          {:exit, _reason} ->
            {:error, error_envelope(:timeout, "Tool execution timed out", %{timeout_ms: timeout_ms}, true)}

          nil ->
            {:error, error_envelope(:timeout, "Tool execution timed out", %{timeout_ms: timeout_ms}, true)}
        end
      after
        Process.demonitor(task.ref, [:flush])
      end
    else
      execute_action(action_module, tool_name, arguments, context, tools)
      |> normalize_result(tool_name)
    end
  end

  defp execute_action(action_module, tool_name, arguments, context, tools) do
    try do
      case action_module do
        nil ->
          Turn.execute(tool_name, arguments, context, tools: tools)

        module when is_atom(module) ->
          Turn.execute_module(module, arguments, context)
      end
    rescue
      e ->
        {:error,
         error_envelope(
           :exception,
           Exception.message(e),
           %{tool_name: tool_name, exception_type: inspect(e.__struct__)},
           false
         )}
    catch
      kind, reason ->
        {:error,
         error_envelope(
           :exception,
           "Caught #{kind}: #{inspect(reason)}",
           %{tool_name: tool_name},
           false
         )}
    end
  end

  defp normalize_result({:ok, _} = result, _tool_name), do: result

  defp normalize_result({:error, reason}, tool_name) do
    {:error, normalize_error(reason, tool_name)}
  end

  defp normalize_result(other, tool_name) do
    {:error,
     error_envelope(
       :executor,
       "Unexpected tool execution result: #{inspect(other)}",
       %{tool_name: tool_name},
       false
     )}
  end

  defp normalize_error(%{type: type, message: message} = error, _tool_name)
       when is_atom(type) and is_binary(message) do
    %{
      type: type,
      message: message,
      retryable?: Map.get(error, :retryable?, type == :timeout),
      details: Map.get(error, :details, %{})
    }
  end

  defp normalize_error({:unknown_tool, message}, _tool_name) when is_binary(message) do
    error_envelope(:unknown_tool, message, %{}, false)
  end

  defp normalize_error({:validation, details}, _tool_name) do
    error_envelope(:validation, "Tool validation failed", %{details: details}, false)
  end

  defp normalize_error(:timeout, _tool_name) do
    error_envelope(:timeout, "Tool execution timed out", %{}, true)
  end

  defp normalize_error(reason, _tool_name) when is_atom(reason) do
    error_envelope(:executor, Atom.to_string(reason), %{reason: reason}, false)
  end

  defp normalize_error(reason, _tool_name) do
    error_envelope(:executor, "Tool execution failed", %{reason: inspect(reason)}, false)
  end

  defp retryable_error?(%{retryable?: retryable?}) when is_boolean(retryable?), do: retryable?

  defp error_envelope(type, message, details \\ %{}, retryable? \\ false) do
    %{
      type: type,
      message: message,
      retryable?: retryable?,
      details: details
    }
  end

  defp maybe_emit(obs_cfg, event, measurements, metadata) do
    Observe.emit(obs_cfg, event, measurements, metadata)
  end

  # Sends tool result signal, with fallback for signal construction failures
  defp send_tool_result(agent_pid, call_id, tool_name, result) do
    signal =
      Signal.ToolResult.new!(%{
        call_id: call_id,
        tool_name: tool_name,
        result: result
      })

    Jido.AgentServer.cast(agent_pid, signal)
  rescue
    e ->
      # If signal construction fails, try with a minimal error signal
      fallback_signal =
        Signal.ToolResult.new!(%{
          call_id: call_id,
          tool_name: tool_name || "unknown",
          result:
            {:error,
             %{
               error: "Signal construction failed: #{Exception.message(e)}",
               type: :internal_error
             }}
        })

      Jido.AgentServer.cast(agent_pid, fallback_signal)
  end

  defp get_tools_from_state(%Jido.AgentServer.State{agent: agent}) do
    get_tools_from_state(agent.state)
  end

  defp get_tools_from_state(state) when is_map(state) do
    # Check for tools in strategy config first (ReAct pattern)
    case get_in(state, [:__strategy__, :config, :actions_by_name]) do
      tools when is_map(tools) and map_size(tools) > 0 ->
        tools

      _ ->
        # Fall back to direct tools key or tool_calling skill state
        state[:tools] || get_in(state, [:tool_calling, :tools]) || %{}
    end
  end
end
