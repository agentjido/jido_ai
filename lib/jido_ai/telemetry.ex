defmodule Jido.AI.Telemetry do
  @moduledoc """
  The public observability API for AI Agent execution.

  Jido AI emits semantic Agent and tool events under `[:jido, :ai]`. Model
  request, streaming, token, cache, and cost data remain owned by ReqLLM. Use
  `events/0` to get the complete event inventory and `metrics/0` to configure a
  `Telemetry.Metrics` reporter.

  Semantic logging consumes the same events. Configure it with:

      config :jido_ai, :telemetry,
        semantic_log_mode: :interesting,
        semantic_slow_threshold_ms: 1_000

  Supported log modes are `:off`, `:errors`, `:interesting`, and `:all`.
  Prompts, model output, reasoning text, tool arguments, tool results, Agent
  state, and raw errors are not logged.

  If the optional `opentelemetry_api` dependency and a host-managed SDK are
  active, Jido AI maps Agent and tool operations to OpenTelemetry spans and
  enables ReqLLM's GenAI model span bridge. Jido AI does not start an SDK or
  configure sampling and export.
  """

  require Logger

  alias Jido.AI.Telemetry.{OpenTelemetry, Storage}

  @request_type "jido.ai.request"
  @runtime_handler_id "jido-ai-runtime-telemetry"
  @semantic_handler_id "jido-ai-semantic-logger"
  @log_modes [:off, :errors, :interesting, :all]

  @agent_events [
    [:jido, :ai, :agent, :start],
    [:jido, :ai, :agent, :stop],
    [:jido, :ai, :agent, :exception]
  ]

  @tool_events [
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :stop],
    [:jido, :ai, :tool, :exception]
  ]

  @owned_events @agent_events ++ @tool_events

  @model_log_events [
    [:req_llm, :request, :start],
    [:req_llm, :request, :stop],
    [:req_llm, :request, :exception]
  ]

  @runtime_events [
    [:jido, :agent_server, :turn, :start],
    [:jido, :agent_server, :turn, :stop],
    [:jido, :agent_server, :turn, :exception],
    [:jido, :action, :start],
    [:jido, :action, :stop],
    [:jido, :action, :exception]
  ]

  @typedoc "A telemetry event name."
  @type event_name :: [atom(), ...]

  @doc "Returns the complete AI Agent event inventory, including lower layers."
  @spec events() :: [event_name()]
  def events do
    (@owned_events ++
       @runtime_events ++
       Jido.Exec.Telemetry.event_names() ++
       Runic.Runner.Telemetry.event_names() ++ ReqLLM.Telemetry.events())
    |> Enum.uniq()
  end

  @doc false
  @spec owned_events() :: [event_name()]
  def owned_events, do: @owned_events

  @doc "Returns low-cardinality metrics for Agent, tool, and model operations."
  @spec metrics() :: [Telemetry.Metrics.t()]
  def metrics do
    [
      Telemetry.Metrics.counter("jido.ai.agent.stop.count",
        tags: [:status, :reasoning_name]
      ),
      Telemetry.Metrics.summary("jido.ai.agent.stop.duration",
        tags: [:status, :reasoning_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.ai.tool.stop.count", tags: [:status, :tool_name]),
      Telemetry.Metrics.summary("jido.ai.tool.stop.duration",
        tags: [:status, :tool_name],
        unit: {:native, :millisecond}
      ),
      Telemetry.Metrics.counter("jido.ai.model.request.count",
        event_name: [:req_llm, :request, :stop],
        tags: [:provider, :model, :operation]
      ),
      Telemetry.Metrics.counter("jido.ai.model.request.exception.count",
        event_name: [:req_llm, :request, :exception],
        tags: [:provider, :model, :operation]
      ),
      Telemetry.Metrics.summary("jido.ai.model.request.duration",
        event_name: [:req_llm, :request, :stop],
        measurement: :duration,
        tags: [:provider, :model, :operation],
        unit: {:native, :millisecond}
      )
    ] ++ usage_metrics()
  end

  @doc "Attaches one handler to the complete event inventory."
  @spec attach(term(), :telemetry.handler_function(), term()) :: :ok | {:error, :already_exists}
  def attach(handler_id, handler, config \\ nil) when is_function(handler, 4) do
    :telemetry.attach_many(handler_id, events(), handler, config)
  end

  @doc "Returns true when optional OpenTelemetry mapping is active."
  @spec open_telemetry?() :: boolean()
  def open_telemetry?, do: OpenTelemetry.enabled?()

  @doc "Attaches optional Agent, tool, and ReqLLM OpenTelemetry bridges."
  @spec attach_open_telemetry(keyword()) :: :ok
  def attach_open_telemetry(opts \\ []), do: OpenTelemetry.attach(opts)

  @doc false
  @spec attach_default_handlers() :: :ok
  def attach_default_handlers do
    attach_once(@runtime_handler_id, @runtime_events, &__MODULE__.handle_runtime_event/4)

    attach_once(
      @semantic_handler_id,
      @owned_events ++ @model_log_events,
      &__MODULE__.handle_semantic_event/4
    )

    attach_open_telemetry(configured_open_telemetry_options())
  end

  @doc false
  @spec with_agent_span(map(), (-> result)) :: result when result: term()
  def with_agent_span(context, fun), do: OpenTelemetry.with_agent_span(context, fun)

  @doc false
  @spec record_agent_summary(map(), map()) :: :ok
  def record_agent_summary(context, summary) when is_map(context) and is_map(summary) do
    case Map.get(context, :turn_id) do
      turn_id when is_binary(turn_id) ->
        Storage.put({:summary, turn_id}, normalize_summary(summary))

      _other ->
        :ok
    end
  end

  @doc false
  def handle_runtime_event([:jido, :agent_server, :turn, ending], measurements, metadata, _config)
      when ending in [:start, :stop, :exception] do
    if ai_turn?(metadata) do
      bridge_agent_event(ending, measurements, metadata)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_runtime_event([:jido, :action, ending], measurements, metadata, _config)
      when ending in [:start, :stop, :exception] do
    if ai_tool_action?(metadata) do
      bridge_tool_event(ending, measurements, metadata)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  def handle_runtime_event(_event, _measurements, _metadata, _config), do: :ok

  @doc false
  def handle_semantic_event(event, measurements, metadata, _config) do
    mode = semantic_log_mode()

    if log_semantic?(mode, event, measurements, metadata) do
      fields = log_fields(event, measurements, metadata)

      message =
        "[jido.ai.semantic] event=#{event |> Enum.drop(1) |> Enum.join(".")} " <>
          format_fields(fields)

      if semantic_error?(event, metadata),
        do: Logger.warning(message),
        else: Logger.debug(message)
    end

    :ok
  rescue
    _error -> :ok
  catch
    _kind, _reason -> :ok
  end

  defp bridge_agent_event(:start, measurements, metadata) do
    ai_metadata = agent_metadata(metadata)
    Storage.put({:agent, metadata.turn_id}, ai_metadata)
    :telemetry.execute([:jido, :ai, :agent, :start], measurements, ai_metadata)
  end

  defp bridge_agent_event(ending, measurements, metadata) do
    summary = Storage.take({:summary, metadata.turn_id}) || %{measurements: %{}, metadata: %{}}
    started = Storage.get({:agent, metadata.turn_id}) || agent_metadata(metadata)

    ai_metadata =
      started
      |> Map.merge(agent_terminal_metadata(ending, metadata))
      |> Map.merge(summary.metadata)

    measurements = Map.merge(measurements, summary.measurements)
    :telemetry.execute([:jido, :ai, :agent, ending], measurements, ai_metadata)
    Storage.take({:agent, metadata.turn_id})
    :ok
  end

  defp bridge_tool_event(ending, measurements, metadata) do
    agent = Storage.get({:agent, metadata.turn_id}) || %{}

    ai_metadata =
      agent
      |> Map.take([
        :agent_id,
        :agent_module,
        :agent_name,
        :reasoning,
        :reasoning_name,
        :request_id,
        :turn_id,
        :trace_id,
        :span_id,
        :parent_span_id
      ])
      |> Map.merge(%{
        action: metadata[:action],
        tool_name: metadata[:action_name],
        node_name: metadata[:node_name],
        activation_id: metadata[:activation_id],
        attempt_id: metadata[:attempt_id],
        attempt: metadata[:attempt],
        status: tool_status(ending, metadata)
      })
      |> compact()

    :telemetry.execute([:jido, :ai, :tool, ending], measurements, ai_metadata)
  end

  defp agent_metadata(metadata) do
    agent_module = metadata[:agent_module]
    reasoning = reasoning(agent_module)

    %{
      agent_id: metadata[:agent_id],
      agent_module: agent_module,
      agent_name: metadata[:agent_name] || agent_name(agent_module),
      reasoning: reasoning,
      reasoning_name: reasoning_name(reasoning),
      request_id: metadata[:signal_id],
      turn_id: metadata[:turn_id],
      trace_id: metadata[:trace_id],
      span_id: metadata[:span_id],
      parent_span_id: metadata[:parent_span_id]
    }
    |> compact()
  end

  defp agent_terminal_metadata(:exception, metadata) do
    %{
      status: :error,
      error_type: metadata[:error_type],
      error_code: metadata[:error_code]
    }
    |> compact()
  end

  defp agent_terminal_metadata(:stop, metadata) do
    %{
      status: metadata[:status],
      committed?: metadata[:committed?],
      error_type: metadata[:error_type],
      error_code: metadata[:error_code]
    }
    |> compact()
  end

  defp normalize_summary(summary) do
    usage = Map.get(summary, :usage, %{})

    measurements =
      summary
      |> Map.take([:model_calls, :tool_rounds, :tool_calls, :tool_errors, :retries])
      |> Map.merge(%{
        input_tokens: usage_value(usage, :input_tokens),
        output_tokens: usage_value(usage, :output_tokens),
        cache_read_tokens: usage_value(usage, :cache_read_tokens),
        cache_write_tokens: usage_value(usage, :cache_write_tokens),
        reasoning_tokens: usage_value(usage, :reasoning_tokens),
        total_cost: usage_value(usage, :total_cost)
      })

    metadata =
      summary
      |> Map.take([:status, :run_id, :session_id, :thread_id, :guardrail])
      |> compact()

    %{measurements: measurements, metadata: metadata}
  end

  defp ai_turn?(%{signal_type: @request_type, turn_id: turn_id}) when is_binary(turn_id),
    do: true

  defp ai_turn?(_metadata), do: false

  defp ai_tool_action?(%{turn_id: turn_id, component: "tools", component_kind: :parallel})
       when is_binary(turn_id) do
    not is_nil(Storage.get({:agent, turn_id}))
  end

  defp ai_tool_action?(_metadata), do: false

  defp tool_status(:exception, _metadata), do: :error
  defp tool_status(:start, _metadata), do: nil
  defp tool_status(:stop, %{outcome: :ok}), do: :ok
  defp tool_status(:stop, %{outcome: :error}), do: :error
  defp tool_status(:stop, _metadata), do: :unknown

  defp reasoning(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :reasoning, 0), do: module.reasoning()
  rescue
    _error -> nil
  end

  defp reasoning(_module), do: nil

  defp agent_name(module) when is_atom(module) and not is_nil(module) do
    module.definition().name
  rescue
    _error -> nil
  end

  defp agent_name(_module), do: nil

  defp reasoning_name(module) when is_atom(module) and not is_nil(module) do
    if function_exported?(module, :name, 0), do: module.name(), else: Atom.to_string(module)
  rescue
    _error -> Atom.to_string(module)
  end

  defp reasoning_name(_module), do: nil

  defp usage_metrics do
    for key <- [
          :input_tokens,
          :output_tokens,
          :cache_read_tokens,
          :cache_write_tokens,
          :reasoning_tokens,
          :total_cost
        ] do
      Telemetry.Metrics.sum("jido.ai.model.#{key}",
        event_name: [:req_llm, :request, :stop],
        measurement: fn _measurements, metadata -> usage_value(metadata[:usage], key) end,
        tags: [:provider, :model]
      )
    end
  end

  defp usage_value(usage, key) when is_map(usage) do
    direct = Map.get(usage, key, Map.get(usage, Atom.to_string(key)))
    tokens = Map.get(usage, :tokens, Map.get(usage, "tokens", %{}))

    case direct || Map.get(tokens, key, Map.get(tokens, Atom.to_string(key))) do
      value when is_number(value) -> value
      _other -> 0
    end
  end

  defp usage_value(_usage, _key), do: 0

  defp semantic_log_mode do
    case config_value(telemetry_config(), :semantic_log_mode) do
      mode when mode in @log_modes -> mode
      _other -> :off
    end
  end

  defp semantic_slow_threshold_ms do
    case config_value(telemetry_config(), :semantic_slow_threshold_ms) do
      value when is_integer(value) and value >= 0 -> value
      _other -> 1_000
    end
  end

  defp log_semantic?(:off, _event, _measurements, _metadata), do: false
  defp log_semantic?(:all, _event, _measurements, _metadata), do: true

  defp log_semantic?(:errors, event, _measurements, metadata),
    do: semantic_error?(event, metadata)

  defp log_semantic?(:interesting, event, measurements, metadata),
    do:
      semantic_error?(event, metadata) or interesting_outcome?(event, metadata) or
        slow_semantic?(measurements)

  defp semantic_error?(event, metadata) do
    List.last(event) == :exception or metadata[:status] in [:error, :failed] or
      metadata[:outcome] == :error or error_http_status?(metadata[:http_status])
  end

  defp error_http_status?(status) when is_integer(status), do: status >= 400
  defp error_http_status?(_status), do: false

  defp interesting_outcome?([:jido, :ai, :agent, ending], metadata)
       when ending in [:stop, :exception],
       do: metadata[:status] not in [nil, :completed]

  defp interesting_outcome?(_event, _metadata), do: false

  defp slow_semantic?(measurements) do
    case measurements[:duration] do
      duration when is_integer(duration) and duration >= 0 ->
        System.convert_time_unit(duration, :native, :microsecond) / 1_000 >=
          semantic_slow_threshold_ms()

      _other ->
        false
    end
  end

  defp log_fields([:req_llm | _rest], measurements, metadata) do
    usage = metadata[:usage] || %{}

    metadata
    |> Map.take([
      :request_id,
      :conversation_id,
      :provider,
      :model,
      :operation,
      :mode,
      :transport,
      :http_status,
      :finish_reason,
      :error_type
    ])
    |> Map.merge(Map.take(measurements, [:duration, :system_time]))
    |> Map.merge(%{
      input_tokens: usage_value(usage, :input_tokens),
      output_tokens: usage_value(usage, :output_tokens),
      cache_read_tokens: usage_value(usage, :cache_read_tokens),
      cache_write_tokens: usage_value(usage, :cache_write_tokens),
      reasoning_tokens: usage_value(usage, :reasoning_tokens),
      total_cost: usage_value(usage, :total_cost)
    })
    |> compact()
  end

  defp log_fields(_event, measurements, metadata) do
    metadata
    |> Map.take([
      :agent_id,
      :agent_module,
      :agent_name,
      :reasoning,
      :request_id,
      :run_id,
      :session_id,
      :thread_id,
      :turn_id,
      :tool_name,
      :status,
      :guardrail,
      :error_type,
      :error_code,
      :retryable?
    ])
    |> Map.merge(
      Map.take(measurements, [
        :duration,
        :model_calls,
        :tool_rounds,
        :tool_calls,
        :tool_errors,
        :retries,
        :input_tokens,
        :output_tokens,
        :cache_read_tokens,
        :cache_write_tokens,
        :reasoning_tokens,
        :total_cost
      ])
    )
    |> compact()
  end

  defp format_fields(fields) do
    fields
    |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
    |> Enum.map_join(" ", fn {key, value} -> "#{key}=#{format_value(value)}" end)
  end

  defp format_value(value) when is_atom(value), do: Atom.to_string(value)
  defp format_value(value) when is_binary(value), do: value |> escape() |> truncate(128)
  defp format_value(value) when is_number(value) or is_boolean(value), do: to_string(value)
  defp format_value(value), do: inspect(value, limit: 4, printable_limit: 128)

  defp escape(value) do
    for <<codepoint::utf8 <- value>>, into: "" do
      case codepoint do
        ?\\ ->
          "\\\\"

        ?\r ->
          "\\r"

        ?\n ->
          "\\n"

        ?\t ->
          "\\t"

        codepoint when codepoint < 32 or codepoint in 127..159 ->
          "\\u{" <> Integer.to_string(codepoint, 16) <> "}"

        codepoint ->
          <<codepoint::utf8>>
      end
    end
  end

  defp truncate(value, max) when byte_size(value) <= max, do: value

  defp truncate(value, max) do
    value
    |> String.codepoints()
    |> Enum.reduce_while({[], 0}, fn codepoint, {acc, size} ->
      next = size + byte_size(codepoint)

      if next <= max - 3,
        do: {:cont, {[codepoint | acc], next}},
        else: {:halt, {acc, size}}
    end)
    |> elem(0)
    |> Enum.reverse()
    |> IO.iodata_to_binary()
    |> Kernel.<>("...")
  end

  defp compact(values) do
    values
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Map.new()
  end

  defp attach_once(id, events, handler) do
    case :telemetry.attach_many(id, events, handler, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  defp configured_open_telemetry_options do
    config_value(Application.get_env(:jido_ai, :opentelemetry, []), :options) || []
  end

  defp telemetry_config, do: Application.get_env(:jido_ai, :telemetry, [])
  defp config_value(config, key) when is_list(config), do: Keyword.get(config, key)
  defp config_value(config, key) when is_map(config), do: Map.get(config, key)
  defp config_value(_config, _key), do: nil
end
