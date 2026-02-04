defmodule Jido.AI.Directive do
  @moduledoc """
  Generic LLM-related directives for Jido agents.

  These directives are reusable across different LLM strategies (ReAct, Chain of Thought, etc.).
  They represent side effects that the AgentServer runtime should execute.

  ## Available Directives

  - `Jido.AI.Directive.LLMStream` - Stream an LLM response with optional tool support
  - `Jido.AI.Directive.ToolExec` - Execute a Jido.Action as a tool

  ## Usage

      alias Jido.AI.Directive

      # Create an LLM streaming directive
      directive = Directive.LLMStream.new!(%{
        id: "call_123",
        model: "anthropic:claude-haiku-4-5",
        context: messages,
        tools: tools
      })

      # Create a tool execution directive
      directive = Directive.ToolExec.new!(%{
        id: "tool_456",
        tool_name: "calculator",
        arguments: %{a: 1, b: 2, operation: "add"}
      })
  """

  defmodule LLMStream do
    @moduledoc """
    Directive asking the runtime to stream an LLM response via ReqLLM.

    Uses ReqLLM for streaming. The runtime will execute this asynchronously
    and send partial tokens as `react.llm.delta` signals and the final result
    as a `react.llm.response` signal.

    ## New Fields

    - `system_prompt` - Optional system prompt prepended to context
    - `model_alias` - Model alias (e.g., `:fast`) resolved via `Jido.AI.resolve_model/1`
    - `timeout` - Request timeout in milliseconds

    Either `model` or `model_alias` must be provided. If `model_alias` is used,
    it is resolved to a model spec at execution time.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model:
                  Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'")
                  |> Zoi.optional(),
                model_alias:
                  Zoi.atom(description: "Model alias (e.g., :fast) resolved via Config")
                  |> Zoi.optional(),
                system_prompt:
                  Zoi.string(description: "Optional system prompt prepended to context")
                  |> Zoi.optional(),
                context: Zoi.any(description: "Conversation context: [ReqLLM.Message.t()] or ReqLLM.Context.t()"),
                tools:
                  Zoi.list(Zoi.any(),
                    description: "List of ReqLLM.Tool.t() structs (schema-only, callback ignored)"
                  )
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, tool_name}")
                  |> Zoi.default(:auto),
                max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature: Zoi.number(description: "Sampling temperature (0.0–2.0)") |> Zoi.default(0.2),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new LLMStream directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid LLMStream: #{inspect(errors)}"
      end
    end
  end

  defmodule ToolExec do
    @moduledoc """
    Directive to execute a Jido.Action as a tool.

    The runtime will execute this asynchronously and send the result back
    as a `react.tool.result` signal.

    ## Execution Modes

    1. **Direct module execution** (preferred): When `action_module` is provided,
       the module is executed directly via `Executor.execute_module/4`, bypassing
       Registry lookup. This is used by strategies that maintain their own tool lists.

    2. **Registry lookup**: When `action_module` is nil, looks up the action in
       `Jido.AI.Tools.Registry` by name and executes via `Jido.AI.Tools.Executor`.

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
                  Zoi.string(description: "Name of the tool (used for Registry lookup if action_module not provided)"),
                action_module:
                  Zoi.atom(description: "Module to execute directly (bypasses Registry lookup)")
                  |> Zoi.optional(),
                arguments:
                  Zoi.map(description: "Arguments from LLM (string keys, normalized before exec)")
                  |> Zoi.default(%{}),
                context:
                  Zoi.map(description: "Execution context passed to Jido.Exec.run/3")
                  |> Zoi.default(%{}),
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

  defmodule EmitToolError do
    @moduledoc """
    Directive to immediately emit a tool error result signal.

    Used when a tool cannot be executed (e.g., unknown tool name, configuration error).
    This directive ensures the Machine receives a tool_result signal and doesn't deadlock
    waiting for a response that will never arrive.

    Unlike `ToolExec`, this directive does not spawn a task - it synchronously emits
    an error signal back to the agent.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Tool call ID from LLM (ReqLLM.ToolCall.id)"),
                tool_name: Zoi.string(description: "Name of the tool that could not be resolved"),
                error: Zoi.any(description: "Error tuple or map describing the failure")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new EmitToolError directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid EmitToolError: #{inspect(errors)}"
      end
    end
  end

  defmodule EmitRequestError do
    @moduledoc """
    Directive to immediately emit a request error signal.

    Used when a request cannot be processed (e.g., agent is busy). This ensures
    the caller receives feedback instead of the request being silently dropped.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                call_id: Zoi.string(description: "Correlation ID for the request"),
                reason: Zoi.atom(description: "Error reason atom (e.g., :busy)"),
                message: Zoi.string(description: "Human-readable error message")
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new EmitRequestError directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid EmitRequestError: #{inspect(errors)}"
      end
    end
  end

  defmodule LLMGenerate do
    @moduledoc """
    Directive asking the runtime to generate an LLM response (non-streaming).

    Uses `ReqLLM.Generation.generate_text/3` for non-streaming text generation.
    The runtime will execute this asynchronously and send the result as a
    `react.llm.response` signal.

    This is simpler than `LLMStream` for cases where streaming is not needed.
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model:
                  Zoi.string(description: "Model spec, e.g. 'anthropic:claude-haiku-4-5'")
                  |> Zoi.optional(),
                model_alias:
                  Zoi.atom(description: "Model alias (e.g., :fast) resolved via Config")
                  |> Zoi.optional(),
                system_prompt:
                  Zoi.string(description: "Optional system prompt prepended to context")
                  |> Zoi.optional(),
                context: Zoi.any(description: "Conversation context: [ReqLLM.Message.t()] or ReqLLM.Context.t()"),
                tools:
                  Zoi.list(Zoi.any(),
                    description: "List of ReqLLM.Tool.t() structs (schema-only, callback ignored)"
                  )
                  |> Zoi.default([]),
                tool_choice:
                  Zoi.any(description: "Tool choice: :auto | :none | {:required, tool_name}")
                  |> Zoi.default(:auto),
                max_tokens: Zoi.integer(description: "Maximum tokens to generate") |> Zoi.default(1024),
                temperature: Zoi.number(description: "Sampling temperature (0.0–2.0)") |> Zoi.default(0.2),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new LLMGenerate directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid LLMGenerate: #{inspect(errors)}"
      end
    end
  end

  defmodule LLMEmbed do
    @moduledoc """
    Directive asking the runtime to generate embeddings via ReqLLM.

    Uses `ReqLLM.Embedding.embed/3` for embedding generation. The runtime will
    execute this asynchronously and send the result as a `react.embed.result` signal.

    Supports both single text and batch embedding (list of texts).
    """

    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.string(description: "Unique call ID for correlation"),
                model: Zoi.string(description: "Embedding model spec, e.g. 'openai:text-embedding-3-small'"),
                texts: Zoi.any(description: "Text string or list of text strings to embed"),
                dimensions:
                  Zoi.integer(description: "Number of dimensions for embedding vector")
                  |> Zoi.optional(),
                timeout: Zoi.integer(description: "Request timeout in milliseconds") |> Zoi.optional(),
                metadata: Zoi.map(description: "Arbitrary metadata for tracking") |> Zoi.default(%{})
              },
              coerce: true
            )

    @type t :: unquote(Zoi.type_spec(@schema))
    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)

    @doc false
    def schema, do: @schema

    @doc "Create a new LLMEmbed directive."
    def new!(attrs) when is_map(attrs) do
      case Zoi.parse(@schema, attrs) do
        {:ok, directive} -> directive
        {:error, errors} -> raise "Invalid LLMEmbed: #{inspect(errors)}"
      end
    end
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMStream do
  @moduledoc """
  Spawns an async task to stream an LLM response and sends results back to the agent.

  This implementation provides **true streaming**: as tokens arrive from the LLM,
  they are immediately sent as `react.llm.delta` signals. When the stream completes,
  a final `react.llm.response` signal is sent with the full classification (tool calls
  or final answer).

  Supports:
  - `model_alias` resolution via `Jido.AI.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options

  Error handling: If the LLM call raises an exception, the error is caught
  and sent back as an error result to prevent the agent from getting stuck.

  ## Task Supervisor

  This implementation uses the agent's per-instance task supervisor stored in
  `state[:task_supervisor]`. The supervisor is started automatically by Jido.AI
  when an agent is created.
  """

  alias Jido.AI.{Helpers, Signal}
  alias Jido.Tracing.Context, as: TraceContext

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      context: context,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    } = directive

    # Resolve model from either model or model_alias
    model = Helpers.resolve_directive_model(directive)
    system_prompt = Map.get(directive, :system_prompt)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    stream_opts = %{
      call_id: call_id,
      model: model,
      context: context,
      system_prompt: system_prompt,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature,
      timeout: timeout,
      agent_pid: agent_pid
    }

    # Capture parent trace context before spawning
    parent_trace_ctx = TraceContext.get()

    Task.Supervisor.start_child(task_supervisor, fn ->
      # Restore trace context in child task
      if parent_trace_ctx, do: Process.put({:jido, :trace_context}, parent_trace_ctx)

      result =
        try do
          stream_with_callbacks(stream_opts)
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.LLMResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp stream_with_callbacks(%{
         call_id: call_id,
         model: model,
         context: context,
         system_prompt: system_prompt,
         tools: tools,
         tool_choice: tool_choice,
         max_tokens: max_tokens,
         temperature: temperature,
         timeout: timeout,
         agent_pid: agent_pid
       }) do
    opts =
      []
      |> Helpers.add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> Helpers.add_timeout_opt(timeout)

    messages = Helpers.build_directive_messages(context, system_prompt)

    case ReqLLM.stream_text(model, messages, opts) do
      {:ok, stream_response} ->
        on_content = fn text ->
          partial_signal =
            Signal.LLMPartial.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :content
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)
        end

        on_thinking = fn text ->
          partial_signal =
            Signal.LLMPartial.new!(%{
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
            classified = Helpers.classify_llm_response(response)

            # Emit usage report signal for per-call tracking
            emit_usage_report(agent_pid, call_id, model, classified[:usage])

            {:ok, classified}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Emit react.usage signal for per-call usage tracking
  defp emit_usage_report(_agent_pid, _call_id, _model, nil), do: :ok

  defp emit_usage_report(agent_pid, call_id, model, usage) when is_map(usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0

    if input_tokens > 0 or output_tokens > 0 do
      signal =
        Signal.UsageReport.new!(%{
          call_id: call_id,
          model: model || "unknown",
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: input_tokens + output_tokens,
          metadata: %{
            cache_creation_input_tokens: Map.get(usage, :cache_creation_input_tokens),
            cache_read_input_tokens: Map.get(usage, :cache_read_input_tokens)
          }
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end

    :ok
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMEmbed do
  @moduledoc """
  Spawns an async task to generate embeddings and sends the result back to the agent.

  Uses `ReqLLM.Embedding.embed/3` for embedding generation. The result is sent
  as a `react.embed.result` signal.

  Supports both single text and batch embedding (list of texts).
  """

  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      model: model,
      texts: texts
    } = directive

    dimensions = Map.get(directive, :dimensions)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        try do
          generate_embeddings(model, texts, dimensions, timeout)
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.EmbedResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp generate_embeddings(model, texts, dimensions, timeout) do
    opts =
      []
      |> add_dimensions_opt(dimensions)
      |> Helpers.add_timeout_opt(timeout)

    case ReqLLM.Embedding.embed(model, texts, opts) do
      {:ok, embeddings} ->
        {:ok, %{embeddings: embeddings, count: count_embeddings(embeddings)}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp count_embeddings(embeddings) when is_list(embeddings), do: length(embeddings)

  defp add_dimensions_opt(opts, nil), do: opts

  defp add_dimensions_opt(opts, dimensions) when is_integer(dimensions) do
    Keyword.put(opts, :dimensions, dimensions)
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.ToolExec do
  @moduledoc """
  Spawns an async task to execute a Jido.Action and sends the result back
  to the agent as a `react.tool.result` signal.

  Supports two execution modes:
  1. Direct module execution when `action_module` is provided (bypasses Registry)
  2. Registry lookup by `tool_name` when `action_module` is nil

  Uses `Jido.AI.Tools.Executor` for execution, which provides consistent error
  handling, parameter normalization, and telemetry.

  ## Error Handling (Issue #2 Fix)

  The entire task body is wrapped in try/rescue/catch to ensure that a
  `tool_result` signal is always sent back to the agent, even if:
  - The Executor raises an exception
  - Signal construction fails
  - Any other unexpected error occurs

  This prevents the Machine from deadlocking in `awaiting_tool` state.
  """

  alias Jido.AI.Signal
  alias Jido.AI.Tools.Executor
  alias Jido.Tracing.Context, as: TraceContext

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      arguments: arguments,
      context: context
    } = directive

    action_module = Map.get(directive, :action_module)
    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    # Get tools from state (agent's registered actions from skill or strategy)
    tools = get_tools_from_state(state)

    # Capture parent trace context before spawning
    parent_trace_ctx = TraceContext.get()

    Task.Supervisor.start_child(task_supervisor, fn ->
      # Restore trace context in child task
      if parent_trace_ctx, do: Process.put({:jido, :trace_context}, parent_trace_ctx)

      # Issue #2 fix: Wrap entire task body in try/rescue/catch to guarantee
      # a tool_result signal is always sent back to the agent
      result =
        try do
          case action_module do
            nil ->
              Executor.execute(tool_name, arguments, context, tools: tools)

            module when is_atom(module) ->
              Executor.execute_module(module, arguments, context)
          end
        rescue
          e ->
            {:error,
             %{
               error: Exception.message(e),
               tool_name: tool_name,
               type: :exception,
               exception_type: e.__struct__
             }}
        catch
          kind, reason ->
            {:error,
             %{
               error: "Caught #{kind}: #{inspect(reason)}",
               tool_name: tool_name,
               type: :caught
             }}
        end

      # Signal construction in a separate try to ensure we always attempt delivery
      send_tool_result(agent_pid, call_id, tool_name, result)
    end)

    {:async, nil, state}
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

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.EmitToolError do
  @moduledoc """
  Immediately emits a tool error result signal without spawning a task.

  Used when a tool cannot be resolved (Issue #1 fix). This ensures the Machine
  receives a tool_result signal for every pending tool call, preventing deadlock.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      tool_name: tool_name,
      error: error
    } = directive

    agent_pid = self()

    # Emit the error result synchronously (no task needed)
    signal =
      Signal.ToolResult.new!(%{
        call_id: call_id,
        tool_name: tool_name,
        result: {:error, error}
      })

    Jido.AgentServer.cast(agent_pid, signal)

    {:sync, nil, state}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.EmitRequestError do
  @moduledoc """
  Immediately emits a request error signal without spawning a task.

  Used when a request cannot be processed (Issue #3 fix). This ensures
  callers receive feedback when the agent is busy instead of silent drops.
  """

  alias Jido.AI.Signal

  def exec(directive, _input_signal, state) do
    %{
      call_id: call_id,
      reason: reason,
      message: message
    } = directive

    agent_pid = self()

    # Emit the request error synchronously
    signal =
      Signal.RequestError.new!(%{
        call_id: call_id,
        reason: reason,
        message: message
      })

    Jido.AgentServer.cast(agent_pid, signal)

    {:sync, nil, state}
  end
end

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMGenerate do
  @moduledoc """
  Spawns an async task to generate an LLM response (non-streaming) and sends
  the result back to the agent.

  Uses `ReqLLM.Generation.generate_text/3` for non-streaming text generation.
  The result is sent as a `react.llm.response` signal.

  Supports:
  - `model_alias` resolution via `Jido.AI.resolve_model/1`
  - `system_prompt` prepended to context messages
  - `timeout` passed to HTTP options

  ## Task Supervisor

  This implementation uses the agent's per-instance task supervisor stored in
  `state[:task_supervisor]`. The supervisor is started automatically by Jido.AI
  when an agent is created.
  """

  alias Jido.AI.{Helpers, Signal}

  def exec(directive, _input_signal, state) do
    %{
      id: call_id,
      context: context,
      tools: tools,
      tool_choice: tool_choice,
      max_tokens: max_tokens,
      temperature: temperature
    } = directive

    model = Helpers.resolve_directive_model(directive)
    system_prompt = Map.get(directive, :system_prompt)
    timeout = Map.get(directive, :timeout)

    agent_pid = self()
    task_supervisor = Jido.AI.Directive.Helper.get_task_supervisor(state)

    Task.Supervisor.start_child(task_supervisor, fn ->
      result =
        try do
          generate_text(
            agent_pid,
            call_id,
            model,
            context,
            system_prompt,
            tools,
            tool_choice,
            max_tokens,
            temperature,
            timeout
          )
        rescue
          e ->
            {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helpers.classify_error(e)}}
        catch
          kind, reason ->
            {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
        end

      signal = Signal.LLMResult.new!(%{call_id: call_id, result: result})
      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp generate_text(
         agent_pid,
         call_id,
         model,
         context,
         system_prompt,
         tools,
         tool_choice,
         max_tokens,
         temperature,
         timeout
       ) do
    opts =
      []
      |> Helpers.add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> Helpers.add_timeout_opt(timeout)

    messages = Helpers.build_directive_messages(context, system_prompt)

    case ReqLLM.Generation.generate_text(model, messages, opts) do
      {:ok, response} ->
        classified = Helpers.classify_llm_response(response)

        # Emit usage report signal for per-call tracking
        emit_usage_report(agent_pid, call_id, model, classified[:usage])

        {:ok, classified}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Emit react.usage signal for per-call usage tracking
  defp emit_usage_report(_agent_pid, _call_id, _model, nil), do: :ok

  defp emit_usage_report(agent_pid, call_id, model, usage) when is_map(usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0

    if input_tokens > 0 or output_tokens > 0 do
      signal =
        Signal.UsageReport.new!(%{
          call_id: call_id,
          model: model || "unknown",
          input_tokens: input_tokens,
          output_tokens: output_tokens,
          total_tokens: input_tokens + output_tokens,
          metadata: %{
            cache_creation_input_tokens: Map.get(usage, :cache_creation_input_tokens),
            cache_read_input_tokens: Map.get(usage, :cache_read_input_tokens)
          }
        })

      Jido.AgentServer.cast(agent_pid, signal)
    end

    :ok
  end
end

# Helper functions for DirectiveExec implementations
defmodule Jido.AI.Directive.Helper do
  @moduledoc """
  Helper functions for DirectiveExec implementations.
  """

  @doc """
  Gets the task supervisor from agent state.

  First checks the TaskSupervisorSkill's internal state (`__task_supervisor_skill__`),
  then falls back to the top-level `:task_supervisor` field for standalone usage.

  ## Examples

      iex> state = %{__task_supervisor_skill__: %{supervisor: supervisor_pid}}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

      iex> state = %{task_supervisor: supervisor_pid}
      iex> Jido.AI.Directive.Helper.get_task_supervisor(state)
      supervisor_pid

  """
  def get_task_supervisor(%Jido.AgentServer.State{agent: agent}) do
    # Handle AgentServer.State struct - extract the agent's state
    get_task_supervisor(agent.state)
  end

  def get_task_supervisor(state) when is_map(state) do
    # First check TaskSupervisorSkill's internal state
    case Map.get(state, :__task_supervisor_skill__) do
      %{supervisor: supervisor} when is_pid(supervisor) ->
        supervisor

      _ ->
        # Fall back to top-level state field (for standalone usage)
        case Map.get(state, :task_supervisor) do
          nil ->
            raise """
            Task supervisor not found in agent state.

            In Jido 2.0, each agent instance requires its own task supervisor.
            Ensure your agent is started with Jido.AI which will automatically
            create and store a per-instance supervisor in the agent state.

            Example:
                use Jido.AI.ReActAgent,
                  name: "my_agent",
                  tools: [MyApp.Tool1, MyApp.Tool2]
            """

          supervisor when is_pid(supervisor) ->
            supervisor
        end
    end
  end
end
