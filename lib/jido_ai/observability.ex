defmodule Jido.AI.Observability do
  @moduledoc """
  Shared observability helpers for Jido.AI runtime components.

  Provides a stable wrapper around Telemetry emission and an optional
  OpenTelemetry bridge. All functions are safe to call even when
  OpenTelemetry is not configured.
  """

  alias Jido.AI.Observability.OTel

  @required_metadata_keys [
    :agent_id,
    :request_id,
    :run_id,
    :iteration,
    :llm_call_id,
    :tool_call_id,
    :tool_name,
    :model,
    :termination_reason,
    :error_type
  ]

  @required_measurement_keys [:duration_ms, :input_tokens, :output_tokens, :total_tokens, :retry_count, :queue_ms]

  @spec emit([atom()], map(), map(), keyword()) :: :ok
  def emit(event, measurements, metadata, opts \\ []) when is_list(event) do
    normalized_measurements = ensure_required_measurements(measurements || %{})
    normalized_metadata = ensure_required_metadata(metadata || %{})

    :telemetry.execute(event, normalized_measurements, normalized_metadata)

    if Keyword.get(opts, :bridge_otel, true) do
      OTel.handle_telemetry_event(event, normalized_measurements, normalized_metadata)
    end

    :ok
  end

  @spec ensure_required_metadata(map()) :: map()
  def ensure_required_metadata(metadata) when is_map(metadata) do
    Enum.reduce(@required_metadata_keys, metadata, fn key, acc ->
      Map.put_new(acc, key, nil)
    end)
  end

  @spec ensure_required_measurements(map()) :: map()
  def ensure_required_measurements(measurements) when is_map(measurements) do
    Enum.reduce(@required_measurement_keys, measurements, fn key, acc ->
      Map.put_new(acc, key, 0)
    end)
  end
end
