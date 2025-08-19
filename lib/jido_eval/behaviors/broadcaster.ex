defmodule Jido.Eval.Broadcaster do
  @moduledoc """
  Behavior for broadcasting evaluation events.

  Broadcasters handle real-time event publishing during evaluation runs.
  They can send events to various destinations like message queues, websockets,
  or telemetry systems.

  ## Callbacks

  - `c:publish/3` - Publish an event (required)

  ## Examples

      defmodule TelemetryBroadcaster do
        @behaviour Jido.Eval.Broadcaster
        
        def publish(event, data, opts) do
          prefix = Keyword.get(opts, :prefix, [:jido, :eval])
          measurements = if is_map(data), do: Map.take(data, [:count, :duration, :score]), else: %{}
          metadata = %{data: data}
          :telemetry.execute(prefix ++ [event], measurements, metadata)
          :ok
        end
      end
  """

  @doc """
  Publish an evaluation event.

  Called to broadcast events during evaluation runs.

  ## Parameters

  - `event` - The event name/type
  - `data` - Event data payload
  - `opts` - Broadcaster configuration options

  ## Returns

  - `:ok` - Success
  - `{:error, reason}` - Publishing failed
  """
  @callback publish(event :: atom(), data :: any(), opts :: keyword()) ::
              :ok | {:error, any()}
end
