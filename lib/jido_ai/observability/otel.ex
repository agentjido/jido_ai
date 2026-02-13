defmodule Jido.AI.Observability.OTel do
  @moduledoc """
  Optional OpenTelemetry bridge for Jido.AI telemetry events.

  This module is intentionally defensive:
  - If OpenTelemetry libraries are not loaded, all functions are no-ops
  - If runtime API shapes differ, errors are swallowed and telemetry flow continues

  The bridge tracks request-level spans and creates child spans for LLM/tool work
  when supported by the runtime OpenTelemetry APIs.
  """

  @span_table :jido_ai_otel_spans

  @spec handle_telemetry_event([atom()], map(), map()) :: :ok
  def handle_telemetry_event(event, _measurements, metadata) when is_list(event) do
    if otel_available?() do
      ensure_table()
      route_event(event, metadata)
    end

    :ok
  rescue
    _ -> :ok
  end

  defp route_event([:jido, :ai, :react, :request, :start], metadata) do
    maybe_start_request_span(metadata)
  end

  defp route_event([:jido, :ai, :react, :request, event], metadata)
       when event in [:complete, :failed, :cancelled, :rejected] do
    maybe_end_request_span(metadata)
  end

  defp route_event([:jido, :ai, :react, :llm, :start], metadata) do
    maybe_add_event("react.llm.start", metadata)
  end

  defp route_event([:jido, :ai, :react, :llm, :complete], metadata) do
    maybe_add_event("react.llm.complete", metadata)
  end

  defp route_event([:jido, :ai, :react, :llm, :error], metadata) do
    maybe_add_event("react.llm.error", metadata)
  end

  defp route_event([:jido, :ai, :react, :tool, :start], metadata) do
    maybe_add_event("react.tool.start", metadata)
  end

  defp route_event([:jido, :ai, :react, :tool, :retry], metadata) do
    maybe_add_event("react.tool.retry", metadata)
  end

  defp route_event([:jido, :ai, :react, :tool, :complete], metadata) do
    maybe_add_event("react.tool.complete", metadata)
  end

  defp route_event([:jido, :ai, :react, :tool, :error], metadata) do
    maybe_add_event("react.tool.error", metadata)
  end

  defp route_event([:jido, :ai, :react, :tool, :timeout], metadata) do
    maybe_add_event("react.tool.timeout", metadata)
  end

  defp route_event(_event, _metadata), do: :ok

  defp maybe_start_request_span(metadata) do
    run_id = metadata[:run_id] || metadata[:request_id]

    if is_binary(run_id) do
      attrs = metadata_to_attributes(metadata)

      span_ctx =
        cond do
          function_exported?(:otel_tracer, :start_span, 2) ->
            apply(:otel_tracer, :start_span, ["react.request", attrs])

          function_exported?(:otel_tracer, :start_span, 3) ->
            apply(:otel_tracer, :start_span, ["react.request", attrs, %{}])

          true ->
            nil
        end

      if span_ctx != nil do
        :ets.insert(@span_table, {run_id, span_ctx})
      end
    end
  rescue
    _ -> :ok
  end

  defp maybe_end_request_span(metadata) do
    run_id = metadata[:run_id] || metadata[:request_id]

    if is_binary(run_id) do
      case :ets.lookup(@span_table, run_id) do
        [{^run_id, span_ctx}] ->
          cond do
            function_exported?(:otel_tracer, :end_span, 1) ->
              apply(:otel_tracer, :end_span, [span_ctx])

            function_exported?(:otel_span, :end_span, 1) ->
              apply(:otel_span, :end_span, [span_ctx])

            true ->
              :ok
          end

          :ets.delete(@span_table, run_id)

        _ ->
          :ok
      end
    end
  rescue
    _ -> :ok
  end

  defp maybe_add_event(name, metadata) do
    run_id = metadata[:run_id] || metadata[:request_id]
    attrs = metadata_to_attributes(metadata)

    span_ctx =
      case if(is_binary(run_id), do: :ets.lookup(@span_table, run_id), else: []) do
        [{_, stored}] -> stored
        _ -> nil
      end

    cond do
      span_ctx && function_exported?(:otel_span, :add_event, 3) ->
        apply(:otel_span, :add_event, [span_ctx, name, attrs])

      span_ctx && function_exported?(:otel_tracer, :add_event, 2) ->
        apply(:otel_tracer, :add_event, [name, attrs])

      true ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp metadata_to_attributes(metadata) do
    metadata
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_value(v) when is_binary(v), do: v
  defp normalize_value(v) when is_number(v), do: v
  defp normalize_value(v) when is_boolean(v), do: v
  defp normalize_value(v) when is_atom(v), do: Atom.to_string(v)
  defp normalize_value(v), do: inspect(v)

  defp ensure_table do
    case :ets.whereis(@span_table) do
      :undefined ->
        :ets.new(@span_table, [:named_table, :set, :public, read_concurrency: true])
        :ok

      _ ->
        :ok
    end
  end

  defp otel_available? do
    Code.ensure_loaded?(:otel_tracer)
  end
end
