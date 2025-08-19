# System Monitoring with CRON and Heartbeat Sensors

## Overview

Jido provides two included system monitoring sensors: CRON and Heartbeat. These sensors form the foundation of scheduled task execution and system health monitoring in your agent-based applications. This guide explores their implementation, configuration patterns, and best practices for production use.

## Core Concepts

### CRON Sensor

The CRON sensor integrates with [Quantum](https://hexdocs.pm/quantum/) to provide schedule-based signal emission. Key features:

- Schedule-based task execution
- Dynamic job management
- Configurable dispatch targets
- Built-in error handling

### Heartbeat Sensor

The Heartbeat sensor provides continuous system health monitoring through:

- Configurable interval-based signals
- Customizable health messages
- Multi-target dispatch support
- Timestamp tracking

## Implementation Guide

### Setting Up CRON Monitoring

#### Basic Configuration

```elixir
# Initialize a CRON sensor with basic jobs
{:ok, cron_sensor} = Jido.Sensors.Cron.start_link(
  id: "system_tasks",
  target: {:bus, [target: :system_bus, stream: "scheduled_events"]},
  scheduler: Jido.Scheduler,
  jobs: [
    # Run every minute
    {~e"* * * * *"e, :minute_task},
    # Run at specific times
    {:daily_backup, ~e"0 0 * * *"e, :backup_task},
    {:weekly_cleanup, ~e"0 0 * * 0"e, :cleanup_task}
  ]
)
```

#### Dynamic Job Management

```elixir
# Add a new job
:ok = Jido.Sensors.Cron.add_job(cron_sensor,
  :metrics_collection,
  ~e"*/5 * * * *"e,  # Every 5 minutes
  :collect_metrics
)

# Temporary deactivation
:ok = Jido.Sensors.Cron.deactivate_job(cron_sensor, :metrics_collection)

# Reactivation
:ok = Jido.Sensors.Cron.activate_job(cron_sensor, :metrics_collection)

# Manual execution
:ok = Jido.Sensors.Cron.run_job(cron_sensor, :metrics_collection)

# Remove job
:ok = Jido.Sensors.Cron.remove_job(cron_sensor, :metrics_collection)
```

### Setting Up Health Monitoring

#### Basic Heartbeat Configuration

```elixir
# Initialize a basic heartbeat monitor
{:ok, heartbeat} = Jido.Sensors.Heartbeat.start_link(
  id: "service_health",
  target: {:bus, [target: :monitoring_bus]},
  interval: 5000,  # 5 second interval
  message: "service_health_check"
)
```

#### Advanced Multi-Target Setup

```elixir
# Configure heartbeat with multiple dispatch targets
{:ok, critical_service_monitor} = Jido.Sensors.Heartbeat.start_link(
  id: "critical_service",
  target: [
    {:bus, [target: :monitoring_bus, stream: "health"]},
    {:logger, [level: :info]},
    {:pubsub, [topic: "system.health"]}
  ],
  interval: 1000,  # 1 second for critical services
  message: "critical_service_status"
)
```

## Signal Structure and Handling

### CRON Signals

CRON sensors emit signals with the following structure:

```elixir
%Jido.Signal{
  source: "cron_sensor:system_tasks:daily_backup",
  type: "cron_trigger",
  data: %{
    name: :daily_backup,
    schedule: "0 0 * * *",
    task: :backup_task,
    triggered_at: ~U[2024-02-11 00:00:00Z]
  }
}
```

### Heartbeat Signals

Heartbeat sensors emit signals structured as:

```elixir
%Jido.Signal{
  source: "heartbeat_sensor:service_health",
  type: "heartbeat",
  data: %{
    message: "service_health_check",
    timestamp: ~U[2024-02-11 10:00:00Z],
    last_beat: ~U[2024-02-11 09:59:55Z]
  }
}
```

## Best Practices

### CRON Job Management

1. **Naming Conventions**

   - Use descriptive atom names (e.g., `:daily_user_cleanup`)
   - Follow consistent naming patterns
   - Add domain-specific prefixes for large systems

2. **Schedule Planning**

   ```elixir
   # Spread out resource-intensive jobs
   jobs: [
     {:heavy_task_1, ~e"0 */4 * * *"e, :resource_intensive_1},
     {:heavy_task_2, ~e"0 2-23/4 * * *"e, :resource_intensive_2}
   ]
   ```

3. **Error Handling**

   ```elixir
   defmodule TaskHandler do
     def handle_signal(%{type: "cron_trigger"} = signal) do
       try do
         signal.data.task
         |> execute_task()
         |> handle_task_result()
       rescue
         error ->
           Logger.error("Task execution failed: #{inspect(error)}")
           {:error, :task_failed}
       catch
         kind, reason ->
           Logger.error("Unexpected error: #{inspect({kind, reason})}")
           {:error, :unexpected_failure}
       end
     end

     defp handle_task_result({:ok, _} = result), do: result
     defp handle_task_result({:error, _} = error), do: error
     defp handle_task_result(_), do: {:error, :invalid_result}
   end
   ```

### Heartbeat Monitoring

1. **Interval Configuration**

   ```elixir
   # Adjust intervals based on service criticality
   defmodule MonitoringConfig do
     def get_interval(:critical), do: 1_000    # 1 second
     def get_interval(:important), do: 5_000   # 5 seconds
     def get_interval(:routine), do: 30_000    # 30 seconds
   end
   ```

2. **Health Check Implementation**

   ```elixir
   defmodule HealthMonitor do
     use Jido.Agent,
       name: "health_monitor"

     @max_delay_ms 10_000  # Maximum acceptable delay

     def handle_signal(%{type: "heartbeat"} = signal) do
       delay = calculate_delay(signal.data)

       cond do
         delay > @max_delay_ms ->
           trigger_alert(signal.source, delay)

         delay > @max_delay_ms / 2 ->
           Logger.warning("Service #{signal.source} showing increased latency")

         true ->
           Logger.debug("Service #{signal.source} healthy")
       end
     end

     defp calculate_delay(%{timestamp: current, last_beat: last}) do
       DateTime.diff(current, last, :millisecond)
     end
   end
   ```

## Testing Strategies

### CRON Testing

```elixir
defmodule CronSensorTest do
  use ExUnit.Case

  setup do
    {:ok, sensor} = Jido.Sensors.Cron.start_link(
      id: "test_cron",
      target: {:pid, target: self()},
      scheduler: Jido.Scheduler
    )

    {:ok, sensor: sensor}
  end

  test "schedules and executes jobs", %{sensor: sensor} do
    :ok = Jido.Sensors.Cron.add_job(
      sensor,
      :test_job,
      ~e"* * * * * *"e,
      :test_task
    )

    assert_receive {:signal, {:ok, signal}}, 1000
    assert signal.type == "cron_trigger"
    assert signal.data.name == :test_job
  end

  test "handles job deactivation", %{sensor: sensor} do
    :ok = Jido.Sensors.Cron.add_job(
      sensor,
      :inactive_job,
      ~e"* * * * * *"e,
      :test_task
    )

    :ok = Jido.Sensors.Cron.deactivate_job(sensor, :inactive_job)
    refute_receive {:signal, _}, 1500
  end
end
```

### Heartbeat Testing

```elixir
defmodule HeartbeatSensorTest do
  use ExUnit.Case

  test "emits regular heartbeats with correct data" do
    {:ok, _sensor} = Jido.Sensors.Heartbeat.start_link(
      id: "test_heartbeat",
      target: {:pid, target: self()},
      interval: 100,
      message: "test_heartbeat"
    )

    # Verify multiple heartbeats
    for _i <- 1..3 do
      assert_receive {:signal, {:ok, signal}}, 200
      assert signal.type == "heartbeat"
      assert signal.data.message == "test_heartbeat"
      assert %DateTime{} = signal.data.timestamp
      assert %DateTime{} = signal.data.last_beat
    end
  end
end
```

## Production Patterns

### System Maintenance Automation

```elixir
defmodule MaintenanceOrchestrator do
  def start_maintenance_sensors do
    # Daily maintenance tasks
    {:ok, _daily} = Jido.Sensors.Cron.start_link(
      id: "daily_maintenance",
      target: {:bus, [target: :maintenance_bus]},
      jobs: [
        {:log_rotation, ~e"0 0 * * *"e, :rotate_logs},
        {:temp_cleanup, ~e"0 4 * * *"e, :clean_temp},
        {:metrics_rollup, ~e"*/30 * * * *"e, :rollup_metrics}
      ]
    )

    # Health monitoring
    {:ok, _health} = Jido.Sensors.Heartbeat.start_link(
      id: "system_health",
      target: [
        {:bus, [target: :health_bus]},
        {:logger, [level: :info]}
      ],
      interval: 10_000
    )
  end
end
```

### Service Health Dashboard

```elixir
defmodule HealthDashboard do
  use Jido.Agent,
    name: "health_dashboard"

  def init(state) do
    {:ok, Map.put(state, :service_status, %{})}
  end

  def handle_signal(%{type: "heartbeat"} = signal) do
    service = signal.source
    status = evaluate_health(signal.data)

    update_status(service, status)
    maybe_trigger_alerts(service, status)
  end

  defp evaluate_health(data) do
    case calculate_delay(data) do
      delay when delay > 30_000 -> :critical
      delay when delay > 10_000 -> :warning
      _ -> :healthy
    end
  end

  defp calculate_delay(%{timestamp: current, last_beat: last}) do
    DateTime.diff(current, last, :millisecond)
  end
end
```

## See Also

- [Signal System Overview](signals/overview.md)
- [Signal Dispatching](signals/dispatching.md)
- [Agent System](agents/overview.md)
- [Testing Guide](testing.md)

## Contributing

Found an issue or have a suggestion? Please open an issue or submit a pull request on our [GitHub repository](https://github.com/your-org/jido).
