defmodule Jido.AI.Test.LiveTrace do
  @moduledoc """
  Writes a small, normalized trace for one live AI request.

  Traces contain the test input and selected response fields. They do not
  contain HTTP headers, provider metadata, API keys, or raw provider payloads.
  Use synthetic test prompts because the input and output text are stored.
  """

  @trace_root Path.expand("../../tmp/jido_ai_traces", __DIR__)
  @option_keys [:max_tokens, :temperature, :receive_timeout]
  @usage_keys [
    :model_calls,
    :tool_calls,
    :iterations,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :input_cost,
    :output_cost,
    :reasoning_cost,
    :total_cost
  ]
  @runtime_metadata_keys [
    :action_name,
    :component,
    :node_path,
    :component_kind,
    :dispatch_phase,
    :flow,
    :kind,
    :outcome,
    :effect_count,
    :attempt,
    :request_id,
    :operation,
    :mode,
    :provider,
    :model,
    :transport,
    :finish_reason,
    :http_status,
    :agent_id,
    :agent_module,
    :turn_id,
    :signal_id,
    :signal_type,
    :status,
    :stage,
    :committed?,
    :trace_id,
    :span_id,
    :parent_span_id,
    :causation_id
  ]
  @runtime_measurement_keys [
    :state_version,
    :state_version_before,
    :state_version_after,
    :directive_count,
    :directive_completed,
    :directive_failed,
    :directive_skipped,
    :queue_depth,
    :wait_duration
  ]

  @type request :: %{
          required(:scenario) => String.t(),
          required(:model) => String.t(),
          required(:instructions) => String.t(),
          required(:input) => String.t(),
          required(:options) => keyword()
        }

  @spec capture(request(), (-> term())) :: {term(), Path.t()}
  def capture(request, fun) when is_map(request) and is_function(fun, 0) do
    started_at = DateTime.utc_now()
    started_ms = System.monotonic_time(:millisecond)
    {handler, observation} = observe_runtime()

    try do
      result = fun.()
      duration_ms = System.monotonic_time(:millisecond) - started_ms
      trace = build_trace(request, result, started_at, duration_ms, drain_runtime(observation))
      {result, write_trace!(request, trace, started_at)}
    rescue
      error ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        trace =
          build_exception_trace(
            request,
            error,
            started_at,
            duration_ms,
            drain_runtime(observation)
          )

        write_trace!(request, trace, started_at)
        reraise error, __STACKTRACE__
    catch
      kind, reason ->
        duration_ms = System.monotonic_time(:millisecond) - started_ms

        trace =
          build_catch_trace(
            request,
            kind,
            started_at,
            duration_ms,
            drain_runtime(observation)
          )

        write_trace!(request, trace, started_at)
        :erlang.raise(kind, reason, __STACKTRACE__)
    after
      :telemetry.detach(handler)
    end
  end

  @doc false
  def telemetry(event, measurements, metadata, {owner, observation}) do
    send(owner, {__MODULE__, observation, event, measurements, metadata})
  end

  defp build_trace(
         request,
         {:ok, %{output: output, usage: usage, trace: events}},
         started_at,
         duration_ms,
         runtime_events
       )
       when is_map(usage) and is_list(events) do
    request_data = request |> started_event() |> Map.fetch!("data")

    base_trace(request, started_at, duration_ms)
    |> Map.put("schema_version", 2)
    |> Map.put("status", "ok")
    |> Map.put("request", request_data)
    |> Map.put("result", normalize_reasoning_result(output, usage))
    |> Map.put("events", events)
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_trace(
         request,
         {:ok, %{output: _output, usage: _usage, trace: _events} = result, effects},
         started_at,
         duration_ms,
         runtime_events
       )
       when is_list(effects) do
    request
    |> build_trace({:ok, result}, started_at, duration_ms, runtime_events)
    |> put_in(["result", "effect_count"], length(effects))
  end

  defp build_trace(
         request,
         {:ok, %ReqLLM.Response{} = response},
         started_at,
         duration_ms,
         runtime_events
       ) do
    output = normalize_response(response)

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_trace(request, {:ok, text}, started_at, duration_ms, runtime_events)
       when is_binary(text) do
    output = %{
      "model" => request.model,
      "text" => text,
      "finish_reason" => nil,
      "tool_call_count" => 0,
      "usage" => %{}
    }

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_trace(request, {:ok, object}, started_at, duration_ms, runtime_events)
       when is_map(object) do
    output = %{
      "model" => request.model,
      "object" => object,
      "finish_reason" => nil,
      "tool_call_count" => 0,
      "usage" => %{}
    }

    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "ok")
    |> Map.put("events", [started_event(request), completed_event(output, duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_trace(request, {:error, reason}, started_at, duration_ms, runtime_events) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "error")
    |> Map.put("events", [started_event(request), failed_event(error_type(reason), duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_trace(request, result, started_at, duration_ms, runtime_events) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "unexpected_result")
    |> Map.put("events", [started_event(request), failed_event(error_type(result), duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_exception_trace(request, error, started_at, duration_ms, runtime_events) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "exception")
    |> Map.put("events", [started_event(request), failed_event(error_type(error), duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp build_catch_trace(request, kind, started_at, duration_ms, runtime_events) do
    base_trace(request, started_at, duration_ms)
    |> Map.put("status", "caught")
    |> Map.put("events", [started_event(request), failed_event(to_string(kind), duration_ms)])
    |> Map.put("runtime_events", runtime_events)
  end

  defp base_trace(request, started_at, duration_ms) do
    %{
      "schema_version" => 1,
      "scenario" => request.scenario,
      "recorded_at" => DateTime.to_iso8601(started_at),
      "duration_ms" => duration_ms
    }
  end

  defp started_event(request) do
    %{
      "sequence" => 1,
      "offset_ms" => 0,
      "type" => "ai.request.started",
      "data" => %{
        "model" => request.model,
        "instructions" => request.instructions,
        "input" => request.input,
        "options" => normalize_options(request.options)
      }
    }
  end

  defp completed_event(output, duration_ms) do
    %{
      "sequence" => 2,
      "offset_ms" => duration_ms,
      "type" => "ai.response.completed",
      "data" => output
    }
  end

  defp failed_event(type, duration_ms) do
    %{
      "sequence" => 2,
      "offset_ms" => duration_ms,
      "type" => "ai.response.failed",
      "data" => %{"error_type" => type}
    }
  end

  defp normalize_response(response) do
    %{
      "model" => response.model,
      "text" => ReqLLM.Response.text(response),
      "finish_reason" => normalize_atom(response.finish_reason),
      "tool_call_count" => response |> ReqLLM.Response.tool_calls() |> length(),
      "usage" => normalize_usage(response.usage)
    }
  end

  defp normalize_reasoning_result(output, usage) do
    %{
      "output" => normalize_output(output),
      "usage" => normalize_usage(usage)
    }
  end

  defp normalize_output(output) when is_binary(output), do: %{"text" => output}
  defp normalize_output(output) when is_map(output), do: %{"object" => output}
  defp normalize_output(output), do: %{"summary" => inspect(output, limit: 20, printable_limit: 200)}

  defp normalize_options(options) do
    options
    |> Keyword.take(@option_keys)
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end

  defp normalize_usage(usage) when is_map(usage) do
    Enum.reduce(@usage_keys, %{}, fn key, normalized ->
      case Map.get(usage, key) || Map.get(usage, to_string(key)) do
        value when is_number(value) -> Map.put(normalized, to_string(key), value)
        _value -> normalized
      end
    end)
  end

  defp normalize_usage(_usage), do: %{}

  defp normalize_atom(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_atom(value), do: value

  defp error_type(%module{}), do: inspect(module)
  defp error_type({type, _reason}) when is_atom(type), do: Atom.to_string(type)
  defp error_type(type) when is_atom(type), do: Atom.to_string(type)
  defp error_type(_reason), do: "unknown"

  defp observe_runtime do
    observation = make_ref()
    handler = {__MODULE__, observation}

    semantic_events =
      Jido.Telemetry.metrics()
      |> Enum.map(& &1.event_name)

    events =
      (Jido.Exec.Telemetry.event_names() ++ ReqLLM.Telemetry.stable_events() ++ semantic_events)
      |> Enum.uniq()

    :ok =
      :telemetry.attach_many(
        handler,
        events,
        &__MODULE__.telemetry/4,
        {self(), observation}
      )

    {handler, observation}
  end

  defp drain_runtime(observation, events \\ []) do
    receive do
      {__MODULE__, ^observation, event, measurements, metadata} ->
        drain_runtime(observation, [{event, measurements, metadata} | events])
    after
      0 ->
        events
        |> Enum.reverse()
        |> Enum.with_index(1)
        |> Enum.map(fn {{event, measurements, metadata}, sequence} ->
          normalize_runtime_event(event, measurements, metadata, sequence)
        end)
    end
  end

  defp normalize_runtime_event(event, measurements, metadata, sequence) do
    %{
      "sequence" => sequence,
      "source" => runtime_source(event),
      "type" => Enum.join(event, "."),
      "measurements" => normalize_runtime_measurements(measurements),
      "metadata" => normalize_runtime_metadata(metadata)
    }
  end

  defp runtime_source([:jido | _event]), do: "jido"
  defp runtime_source([:req_llm | _event]), do: "req_llm"
  defp runtime_source(_event), do: "unknown"

  defp normalize_runtime_measurements(measurements) when is_map(measurements) do
    Enum.reduce(measurements, %{}, fn
      {:duration, duration}, normalized when is_integer(duration) ->
        milliseconds = System.convert_time_unit(duration, :native, :millisecond)
        Map.put(normalized, "duration_ms", milliseconds)

      {:tokens, tokens}, normalized when is_map(tokens) ->
        Map.merge(normalized, normalize_usage(tokens))

      {:cost, cost}, normalized when is_number(cost) ->
        Map.put_new(normalized, "total_cost", cost)

      {key, value}, normalized when key in @usage_keys and is_number(value) ->
        Map.put(normalized, to_string(key), value)

      {key, value}, normalized when key in @runtime_measurement_keys and is_integer(value) ->
        Map.put(normalized, to_string(key), value)

      {_key, _value}, normalized ->
        normalized
    end)
  end

  defp normalize_runtime_measurements(_measurements), do: %{}

  defp normalize_runtime_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.take(@runtime_metadata_keys)
    |> Enum.reduce(%{}, fn {key, value}, normalized ->
      case normalize_runtime_value(key, value) do
        nil -> normalized
        value -> Map.put(normalized, to_string(key), value)
      end
    end)
  end

  defp normalize_runtime_metadata(_metadata), do: %{}

  defp normalize_runtime_value(:model, %{id: id}) when is_binary(id), do: id
  defp normalize_runtime_value(_key, nil), do: nil
  defp normalize_runtime_value(_key, value) when is_binary(value), do: value
  defp normalize_runtime_value(_key, value) when is_boolean(value), do: value
  defp normalize_runtime_value(_key, value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_runtime_value(_key, value) when is_number(value), do: value

  defp normalize_runtime_value(:node_path, value) when is_list(value) do
    if Enum.all?(value, &is_binary/1), do: value
  end

  defp normalize_runtime_value(_key, _value), do: nil

  defp write_trace!(request, trace, started_at) do
    path = trace_path(request, started_at)
    temporary_path = path <> ".tmp"

    path |> Path.dirname() |> File.mkdir_p!()
    File.write!(temporary_path, Jason.encode!(trace, pretty: true))
    File.rename!(temporary_path, path)
    path
  end

  defp trace_path(request, started_at) do
    {provider, model} = split_model(request.model)

    filename =
      started_at
      |> DateTime.to_iso8601()
      |> slug()
      |> Kernel.<>("_#{System.unique_integer([:positive])}.json")

    Path.join([@trace_root, slug(request.scenario), slug(provider), slug(model), filename])
  end

  defp split_model(model) do
    case String.split(model, ":", parts: 2) do
      [provider, name] -> {provider, name}
      [name] -> {"unknown", name}
    end
  end

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "_")
    |> String.trim("_")
  end
end
