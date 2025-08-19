defmodule Jido.Eval.Broadcaster.Telemetry do
  @moduledoc """
  Telemetry broadcaster for evaluation events.

  This broadcaster publishes evaluation events to the telemetry system using
  `:telemetry.execute/3`. Events are published with configurable prefixes and
  proper measurement maps.

  ## Options

  - `:prefix` - Event name prefix (default: `[:jido, :eval]`)

  ## Examples

      # Default configuration
      {Jido.Eval.Broadcaster.Telemetry, []}

      # Custom prefix
      {Jido.Eval.Broadcaster.Telemetry, [prefix: [:my_app, :evaluation]]}

  """

  @behaviour Jido.Eval.Broadcaster

  @doc """
  Publishes an evaluation event to the telemetry system.

  The event will be published with the configured prefix and the event name.
  If data contains measurement values, they are converted to a proper measurements map.

  ## Parameters

  - `event` - The event name/type (atom)
  - `data` - Event data payload (any term)
  - `opts` - Configuration options with optional `:prefix`

  ## Returns

  Always returns `:ok` as telemetry publishing does not fail.

  ## Examples

      iex> publish(:started, %{count: 10}, prefix: [:my_app])
      :ok

      iex> publish(:completed, %{duration: 1500}, [])
      :ok

  """
  @spec publish(atom(), any(), keyword()) :: :ok
  def publish(event, data, opts) do
    prefix = Keyword.get(opts, :prefix, [:jido, :eval])
    event_name = prefix ++ [event]

    measurements = extract_measurements(data)
    metadata = extract_metadata(data)

    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end

  # Extract numeric measurements from data for telemetry
  @spec extract_measurements(any()) :: map()
  defp extract_measurements(data) when is_struct(data) do
    data
    |> Map.from_struct()
    |> extract_measurements()
  end

  defp extract_measurements(data) when is_map(data) do
    data
    |> Enum.filter(fn {_key, value} -> is_number(value) end)
    |> Map.new()
  end

  defp extract_measurements(_data), do: %{}

  # Extract metadata (non-numeric values) from data
  @spec extract_metadata(any()) :: map()
  defp extract_metadata(data) when is_struct(data) do
    struct_name = data.__struct__
    Map.put(%{struct: struct_name}, :data, data)
  end

  defp extract_metadata(data) when is_map(data) do
    data
    |> Enum.reject(fn {_key, value} -> is_number(value) end)
    |> Map.new()
  end

  defp extract_metadata(data), do: %{data: data}
end
