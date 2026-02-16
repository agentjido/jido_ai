defmodule Jido.AI.Directive.LLMStream do
  @moduledoc """
  Directive asking the runtime to stream an LLM response via ReqLLM.

  Uses ReqLLM for streaming. The runtime will execute this asynchronously
  and send partial tokens as `ai.llm.delta` signals and the final result
  as a `ai.llm.response` signal.

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

defimpl Jido.AgentServer.DirectiveExec, for: Jido.AI.Directive.LLMStream do
  @moduledoc """
  Spawns an async task to stream an LLM response and sends results back to the agent.

  This implementation provides **true streaming**: as tokens arrive from the LLM,
  they are immediately sent as `ai.llm.delta` signals. When the stream completes,
  a final `ai.llm.response` signal is sent with the full classification (tool calls
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

  alias Jido.AI.{Observe, Signal, Turn}
  alias Jido.AI.Directive.Helper
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
    model = Helper.resolve_directive_model(directive)
    system_prompt = Map.get(directive, :system_prompt)
    timeout = Map.get(directive, :timeout)
    metadata = Map.get(directive, :metadata, %{})
    obs_cfg = metadata[:observability] || %{}

    event_meta = %{
      agent_id: metadata[:agent_id],
      request_id: metadata[:request_id],
      run_id: metadata[:run_id] || metadata[:request_id],
      iteration: metadata[:iteration],
      llm_call_id: call_id,
      tool_call_id: nil,
      tool_name: nil,
      model: model,
      termination_reason: nil,
      error_type: nil
    }

    agent_pid = self()
    task_supervisor = Helper.get_task_supervisor(state)

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
      agent_pid: agent_pid,
      event_meta: event_meta,
      obs_cfg: obs_cfg
    }

    # Capture parent trace context before spawning
    parent_trace_ctx = TraceContext.get()

    case Task.Supervisor.start_child(task_supervisor, fn ->
           # Restore trace context in child task
           if parent_trace_ctx, do: Process.put({:jido, :trace_context}, parent_trace_ctx)

           started_at = System.monotonic_time(:millisecond)
           span_ctx = Observe.start_span(obs_cfg, Observe.llm(:span), event_meta)

           maybe_emit(obs_cfg, Observe.llm(:start), %{duration_ms: 0, queue_ms: 0}, event_meta)

           result =
             try do
               stream_with_callbacks(stream_opts)
             rescue
               e ->
                 {:error, %{exception: Exception.message(e), type: e.__struct__, error_type: Helper.classify_error(e)}}
             catch
               kind, reason ->
                 {:error, %{caught: kind, reason: inspect(reason), error_type: :unknown}}
             end

           duration_ms = System.monotonic_time(:millisecond) - started_at

           case result do
             {:ok, _} ->
               Observe.finish_span(span_ctx, %{duration_ms: duration_ms})
               maybe_emit(obs_cfg, Observe.llm(:complete), %{duration_ms: duration_ms}, event_meta)

             {:error, reason} ->
               Observe.finish_span_error(span_ctx, :error, reason, [])

               error_type =
                 case reason do
                   %{error_type: type} when is_atom(type) -> type
                   _ -> :unknown
                 end

               maybe_emit(
                 obs_cfg,
                 Observe.llm(:error),
                 %{duration_ms: duration_ms},
                 Map.put(event_meta, :error_type, error_type)
               )
           end

           signal = Signal.LLMResponse.new!(%{call_id: call_id, result: result})
           Jido.AgentServer.cast(agent_pid, signal)
         end) do
      {:ok, _pid} ->
        {:async, nil, state}

      {:error, reason} ->
        signal =
          Signal.LLMResponse.new!(%{
            call_id: call_id,
            result: {:error, %{type: :supervisor, reason: inspect(reason), error_type: :unknown}}
          })

        Jido.AgentServer.cast(agent_pid, signal)
        {:ok, state}
    end
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
         agent_pid: agent_pid,
         event_meta: event_meta,
         obs_cfg: obs_cfg
       }) do
    opts =
      []
      |> Helper.add_tools_opt(tools)
      |> Keyword.put(:tool_choice, tool_choice)
      |> Keyword.put(:max_tokens, max_tokens)
      |> Keyword.put(:temperature, temperature)
      |> Helper.add_timeout_opt(timeout)

    messages = Helper.build_directive_messages(context, system_prompt)

    case ReqLLM.stream_text(model, messages, opts) do
      {:ok, stream_response} ->
        on_content = fn text ->
          partial_signal =
            Signal.LLMDelta.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :content
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)

          maybe_emit_delta(obs_cfg, Observe.llm(:delta), %{duration_ms: 0}, event_meta)
        end

        on_thinking = fn text ->
          partial_signal =
            Signal.LLMDelta.new!(%{
              call_id: call_id,
              delta: text,
              chunk_type: :thinking
            })

          Jido.AgentServer.cast(agent_pid, partial_signal)

          maybe_emit_delta(obs_cfg, Observe.llm(:delta), %{duration_ms: 0}, event_meta)
        end

        case ReqLLM.StreamResponse.process_stream(stream_response,
               on_result: on_content,
               on_thinking: on_thinking
             ) do
          {:ok, response} ->
            turn = Turn.from_response(response, model: model)

            # Emit usage report signal for per-call tracking
            emit_usage_report(agent_pid, call_id, model, turn.usage)

            {:ok, turn}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Emit ai.usage signal for per-call usage tracking
  defp emit_usage_report(_agent_pid, _call_id, _model, nil), do: :ok

  defp emit_usage_report(agent_pid, call_id, model, usage) when is_map(usage) do
    input_tokens = Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") || 0
    output_tokens = Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") || 0

    if input_tokens > 0 or output_tokens > 0 do
      signal =
        Signal.Usage.new!(%{
          call_id: call_id,
          model: model,
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

  defp maybe_emit(obs_cfg, event, measurements, metadata) do
    Observe.emit(obs_cfg, event, measurements, metadata)
  end

  defp maybe_emit_delta(obs_cfg, event, measurements, metadata) do
    Observe.emit(obs_cfg, event, measurements, metadata, feature_gate: :llm_deltas)
  end
end
