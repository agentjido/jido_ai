defmodule Jido.AI.Observability.Events do
  @moduledoc """
  Canonical observability event paths and normalization helpers.
  """

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

  @required_measurement_keys [
    :duration_ms,
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :retry_count,
    :queue_ms
  ]

  @doc """
  Builds an LLM telemetry event path under `[:jido, :ai, :llm, ...]`.
  """
  @spec llm(atom()) :: [atom()]
  def llm(event), do: [:jido, :ai, :llm, event]

  @doc """
  Builds a tool telemetry event path under `[:jido, :ai, :tool, ...]`.
  """
  @spec tool(atom()) :: [atom()]
  def tool(event), do: [:jido, :ai, :tool, event]

  @doc """
  Builds a request telemetry event path under `[:jido, :ai, :request, ...]`.
  """
  @spec request(atom()) :: [atom()]
  def request(event), do: [:jido, :ai, :request, event]

  @doc """
  Builds a strategy telemetry event path under `[:jido, :ai, :strategy, strategy, ...]`.
  """
  @spec strategy(atom(), atom()) :: [atom()]
  def strategy(strategy, event), do: [:jido, :ai, :strategy, strategy, event]

  @doc """
  Ensures required metadata keys are present with `nil` defaults.
  """
  @spec ensure_required_metadata(map()) :: map()
  def ensure_required_metadata(metadata) when is_map(metadata) do
    Enum.reduce(@required_metadata_keys, metadata, fn key, acc ->
      Map.put_new(acc, key, nil)
    end)
  end

  @doc """
  Ensures required measurement keys are present with `0` defaults.
  """
  @spec ensure_required_measurements(map()) :: map()
  def ensure_required_measurements(measurements) when is_map(measurements) do
    Enum.reduce(@required_measurement_keys, measurements, fn key, acc ->
      Map.put_new(acc, key, 0)
    end)
  end
end
