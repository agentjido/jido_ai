# Sensors Overview

## Introduction

Sensors are processes in Jido that enable agents to perceive and react to events in their environment. They act as the gateway for external events to be translated into Signals that your Jido Agents can consume. They are the eyes and ears of your agent-based application, providing a standardized way to monitor, detect, and emit signals based on various triggers and conditions.

## Core Concepts

### What is a Sensor?

A Sensor is a specialized GenServer that:

- Monitors specific events or conditions
- Emits standardized Signals when triggered
- Maintains configurable state
- Integrates with Jido's signal dispatch system

### Key Features

- **Event Detection**: Monitor system events, time-based triggers, or external conditions
- **Signal Generation**: Emit structured CloudEvents-compatible signals
- **Configurable**: Easy customization through options and runtime configuration
- **State Management**: Maintain and track sensor-specific state
- **Flexible Dispatch**: Route signals to various destinations using Jido's dispatch system

## Basic Usage

### Creating a Simple Sensor

```elixir
defmodule MyApp.TemperatureSensor do
  use Jido.Sensor,
    name: "temperature_sensor",
    description: "Monitors temperature readings",
    category: :monitoring,
    tags: [:temperature, :environmental],
    vsn: "1.0.0",
    schema: [
      threshold: [
        type: :float,
        default: 25.0,
        doc: "Temperature threshold in Celsius"
      ]
    ]

  @impl true
  def mount(opts) do
    state = %{
      id: opts.id,
      target: opts.target,
      config: %{
        threshold: opts.threshold
      }
    }
    {:ok, state}
  end

  @impl true
  def deliver_signal(state) do
    current_temp = read_temperature()

    {:ok, Jido.Signal.new(%{
      source: "#{state.sensor.name}:#{state.id}",
      type: "temperature.reading",
      data: %{
        temperature: current_temp,
        threshold: state.config.threshold,
        exceeds_threshold: current_temp > state.config.threshold
      }
    })}
  end
end
```

### Starting a Sensor

```elixir
# Start with default configuration
{:ok, sensor} = MyApp.TemperatureSensor.start_link(
  id: "temp_sensor_1",
  target: {:bus, target: :system_bus}
)

# Start with custom configuration
{:ok, sensor} = MyApp.TemperatureSensor.start_link(
  id: "temp_sensor_2",
  target: {:bus, target: :system_bus},
  threshold: 30.0
)
```

## Built-in Sensors

Jido provides several built-in sensors for common use cases:

### Cron Sensor

The Cron sensor emits signals based on scheduled intervals using cron expressions:

```elixir
alias Jido.Sensors.Cron

{:ok, cron} = Cron.start_link(
  id: "scheduled_task",
  target: {:bus, target: :system_bus},
  jobs: [
    # Run every minute
    {~e"* * * * *"e, :minute_task},
    # Run every hour on the hour
    {:hourly, ~e"0 * * * *"e, :hour_task}
  ]
)

# Add a new job later
:ok = Cron.add_job(cron, :custom_job, ~e"*/5 * * * *"e, :five_minute_task)
```

### Heartbeat Sensor

The Heartbeat sensor emits regular signals to indicate system health:

```elixir
alias Jido.Sensors.Heartbeat

{:ok, heartbeat} = Heartbeat.start_link(
  id: "system_health",
  target: {:bus, target: :monitoring_bus},
  interval: 5000,  # 5 seconds
  message: "system_heartbeat"
)
```

## Implementing Custom Sensors

### Sensor Behavior

Custom sensors must implement these callbacks:

- `mount/1`: Initialize sensor state
- `deliver_signal/1`: Generate signals based on current state
- `on_before_deliver/2`: Pre-processing hook for signals (optional)
- `shutdown/1`: Cleanup when sensor stops (optional)

### Example: File Change Sensor

```elixir
defmodule MyApp.FileWatcher do
  use Jido.Sensor,
    name: "file_watcher",
    description: "Monitors file changes",
    category: :filesystem,
    tags: [:files, :monitoring],
    schema: [
      path: [
        type: :string,
        required: true,
        doc: "Path to watch for changes"
      ]
    ]

  @impl true
  def mount(opts) do
    state = %{
      id: opts.id,
      target: opts.target,
      config: %{
        path: opts.path,
        last_modified: get_last_modified(opts.path)
      }
    }
    schedule_check()
    {:ok, state}
  end

  @impl true
  def deliver_signal(state) do
    current_modified = get_last_modified(state.config.path)

    if current_modified > state.config.last_modified do
      {:ok, Jido.Signal.new(%{
        source: "#{state.sensor.name}:#{state.id}",
        type: "file.changed",
        data: %{
          path: state.config.path,
          last_modified: current_modified
        }
      })}
    else
      {:ok, nil}
    end
  end

  # Private helpers
  defp schedule_check do
    Process.send_after(self(), :check_file, 1000)
  end

  defp get_last_modified(path) do
    case File.stat(path) do
      {:ok, stat} -> stat.mtime
      _ -> nil
    end
  end
end
```

## Best Practices

### Configuration Management

1. **Validation**: Define clear schema options for configuration
2. **Defaults**: Provide sensible default values
3. **Runtime Updates**: Support configuration changes during operation

```elixir
# Define schema with validation
schema: [
  interval: [
    type: :pos_integer,
    default: 5000,
    doc: "Check interval in milliseconds"
  ],
  retries: [
    type: :non_neg_integer,
    default: 3,
    doc: "Number of retry attempts"
  ]
]

# Update configuration at runtime
MyApp.FileWatcher.set_config(sensor, :interval, 10000)
```

### Error Handling

1. **Graceful Degradation**: Handle failures without crashing
2. **Retry Logic**: Implement appropriate retry mechanisms
3. **Logging**: Record important events and errors

```elixir
def deliver_signal(state) do
  case read_sensor_data() do
    {:ok, data} ->
      {:ok, build_signal(state, data)}

    {:error, :timeout} ->
      Logger.warn("Sensor timeout, retrying...")
      retry_with_backoff(state)

    {:error, reason} ->
      Logger.error("Sensor error: #{inspect(reason)}")
      {:error, reason}
  end
end
```

### Performance Considerations

1. **Resource Usage**: Monitor memory and CPU usage
2. **Batching**: Group related signals when appropriate
3. **Throttling**: Implement rate limiting if needed

## Testing

Jido provides testing utilities for sensors:

```elixir
defmodule MyApp.SensorTest do
  use JidoTest.Case, async: true

  test "sensor emits signals on events" do
    {:ok, sensor} = MySensor.start_link(
      id: "test_sensor",
      target: {:pid, target: self()}
    )

    # Trigger the sensor
    send(sensor, :check_condition)

    # Assert signal received
    assert_receive {:signal, {:ok, signal}}, 1000
    assert signal.type == "expected.event"
  end
end
```

## See Also

- [Cron & Heartbeat Sensors](cron-heartbeat.md)
- [Signal Overview](../signals/overview.livemd)
- [Signal Testing](../signals/testing.md)
- [Signal Dispatching](../signals/dispatching.md)

For API details, see:

- `Jido.Sensor` - Core sensor behavior
- `Jido.Signal` - Signal structure and creation
- `Jido.Signal.Dispatch` - Signal dispatch system
