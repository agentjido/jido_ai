defmodule Jido.Telemetry do
  @moduledoc """
  Handles telemetry events for the Jido application.

  This module provides a centralized way to handle and report telemetry events
  throughout the application. It implements common telemetry patterns and provides
  a consistent interface for event handling.
  """

  use GenServer
  require Logger

  @typedoc """
  Supported telemetry event names.
  """
  @type event_name :: [atom(), ...]

  @typedoc """
  Telemetry measurements map.
  """
  @type measurements :: %{
          optional(:system_time) => integer(),
          optional(:duration) => integer(),
          atom() => term()
        }

  @typedoc """
  Telemetry metadata map.
  """
  @type metadata :: %{
          optional(:error) => term(),
          optional(:result) => term(),
          atom() => term()
        }

  @doc """
  Starts the telemetry handler.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    # Define metrics
    [
      # Operation metrics
      Telemetry.Metrics.counter(
        "jido.operation.count",
        description: "Total number of operations"
      ),
      Telemetry.Metrics.sum(
        "jido.operation.duration",
        unit: {:native, :millisecond},
        description: "Total duration of operations"
      ),
      Telemetry.Metrics.sum(
        "jido.operation.error.count",
        description: "Total number of operation errors"
      ),
      Telemetry.Metrics.last_value(
        "jido.operation.duration.max",
        unit: {:native, :millisecond},
        description: "Maximum duration of operations"
      )
    ]

    # Attach custom handlers
    :telemetry.attach_many(
      "jido-metrics",
      [
        [:jido, :operation, :start],
        [:jido, :operation, :stop],
        [:jido, :operation, :exception]
      ],
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, opts}
  end

  @doc """
  Handles telemetry events.
  """
  @spec handle_event(event_name(), measurements(), metadata(), config :: term()) :: :ok
  def handle_event([:jido, :operation, :start], measurements, metadata, _config) do
    Logger.info("Operation started",
      event: :operation_started,
      measurements: measurements,
      metadata: metadata
    )
  end

  def handle_event([:jido, :operation, :stop], measurements, metadata, _config) do
    Logger.info("Operation completed",
      event: :operation_completed,
      duration: Map.get(measurements, :duration),
      measurements: measurements,
      metadata: metadata
    )
  end

  def handle_event(
        [:jido, :operation, :exception],
        measurements,
        %{error: error} = metadata,
        _config
      ) do
    Logger.warning("Operation failed",
      event: :operation_failed,
      error: inspect(error),
      measurements: measurements,
      metadata: metadata
    )
  end

  @doc """
  Executes a function while emitting telemetry events for its execution.
  """
  @spec span(String.t(), (-> result)) :: result when result: term()
  def span(operation_name, func) when is_function(func, 0) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [:jido, :operation, :start],
      %{system_time: System.system_time()},
      %{operation: operation_name}
    )

    try do
      result = func.()

      :telemetry.execute(
        [:jido, :operation, :stop],
        %{
          duration: System.monotonic_time() - start_time
        },
        %{operation: operation_name, result: result}
      )

      result
    catch
      kind, reason ->
        stack = __STACKTRACE__

        :telemetry.execute(
          [:jido, :operation, :exception],
          %{
            duration: System.monotonic_time() - start_time
          },
          %{
            operation: operation_name,
            kind: kind,
            error: reason,
            stacktrace: stack
          }
        )

        :erlang.raise(kind, reason, stack)
    end
  end
end
