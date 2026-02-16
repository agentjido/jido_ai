defmodule Jido.AI.Observability.Emitter do
  @moduledoc """
  Telemetry emitter with normalized metadata and measurements.
  """

  alias Jido.AI.Observability.Events

  @doc """
  Emits a telemetry event when `:emit_telemetry?` is enabled in `obs_cfg`.

  Metadata and measurements are normalized to include required keys before
  dispatching through `:telemetry.execute/3`.
  """
  @spec emit(map(), [atom()], map(), map()) :: :ok
  def emit(obs_cfg, event, measurements, metadata) do
    if Map.get(obs_cfg, :emit_telemetry?, true) do
      :telemetry.execute(
        event,
        Events.ensure_required_measurements(measurements || %{}),
        Events.ensure_required_metadata(metadata || %{})
      )
    end

    :ok
  end
end
