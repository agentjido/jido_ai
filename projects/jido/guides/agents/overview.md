# Agents Overview

_Part of the "Agents" section in the documentation._

This guide provides a comprehensive introduction to agents in Jido. It covers the core concepts of agents, their role in the system, and how they integrate with actions, sensors, and signals to create autonomous behaviors.

# Understanding Agents and State Management

## Overview

Agents are the foundational building blocks of Jido applications. They represent stateful processes that encapsulate business logic, manage state transitions, and coordinate workflows. Built on top of OTP's GenServer, agents provide a robust, fault-tolerant way to maintain state while handling concurrent operations.

### Core Principles

1. **State Encapsulation**

   - Each agent maintains its own isolated state
   - State changes are validated through schema definitions
   - Lifecycle hooks for state transition control

2. **Instruction Processing**

   - Queue-based execution model
   - Support for synchronous and asynchronous operations
   - Built-in compensation handling

3. **Fault Tolerance**
   - OTP supervision integration
   - Graceful error handling
   - State recovery mechanisms

## Implementation

### Basic Agent Structure

```elixir
defmodule MyApp.TaskAgent do
  use Jido.Agent

  @type status :: :pending | :running | :completed | :failed
  @type t :: %__MODULE__{
    id: String.t(),
    name: String.t(),
    status: status(),
    metadata: map()
  }

  schema do
    field :id, :string, required: true
    field :name, :string, required: true
    field :status, :atom, default: :pending
    field :metadata, :map, default: %{}
  end

  @impl true
  def on_before_validate_state(%{status: new_status} = state) do
    if valid_status_transition?(state.status, new_status) do
      {:ok, state}
    else
      {:error, :invalid_transition}
    end
  end

  @impl true
  def on_after_validate_state(state) do
    Logger.info("Task state updated: #{inspect(state)}")
    {:ok, state}
  end

  # Private Helpers

  defp valid_status_transition?(current, next) do
    transitions = %{
      pending: [:running],
      running: [:completed, :failed],
      completed: [],
      failed: [:pending]
    }

    next in Map.get(transitions, current, [])
  end
end
```

### Agent Server Implementation

The agent server handles the core lifecycle and state management:

```elixir
defmodule MyApp.TaskAgent.Server do
  use Jido.Agent.Server

  @impl true
  def init(opts) do
    initial_state = %{
      id: opts[:id] || Jido.ID.generate(),
      name: opts[:name] || "Task-#{:rand.uniform(1000)}",
      status: :pending,
      metadata: %{}
    }

    {:ok, initial_state}
  end

  @impl true
  def handle_instruction({action, params}, state) do
    case apply_instruction(action, params, state) do
      {:ok, new_state} -> {:ok, new_state}
      {:error, reason} -> {:error, reason, state}
    end
  end

  # Private Helpers

  defp apply_instruction(action, params, state) do
    with {:ok, validated} <- validate_params(params),
         {:ok, new_state} <- action.run(state, validated) do
      {:ok, new_state}
    end
  end
end
```

## State Management

### Schema Validation

Jido uses NimbleOptions for schema validation:

```elixir
defmodule MyApp.TaskAgent.Schema do
  @schema [
    id: [
      type: :string,
      required: true,
      doc: "Unique identifier for the task"
    ],
    name: [
      type: :string,
      required: true,
      doc: "Human-readable task name"
    ],
    status: [
      type: :atom,
      values: [:pending, :running, :completed, :failed],
      default: :pending,
      doc: "Current task status"
    ],
    metadata: [
      type: :map,
      default: %{},
      doc: "Additional task metadata"
    ]
  ]

  def validate(params) do
    NimbleOptions.validate(params, @schema)
  end
end
```

### State Transitions

State transitions are managed through lifecycle hooks:

1. **Before Validation**

   ```elixir
   @impl true
   def on_before_validate_state(state) do
     # Custom validation logic
     {:ok, state}
   end
   ```

2. **After Validation**

   ```elixir
   @impl true
   def on_after_validate_state(state) do
     # Post-validation processing
     {:ok, state}
   end
   ```

3. **Error Handling**
   ```elixir
   @impl true
   def on_validation_error(error, state) do
     Logger.error("Validation failed: #{inspect(error)}")
     {:error, error}
   end
   ```

## Testing & Verification

### Unit Tests

```elixir
defmodule MyApp.TaskAgentTest do
  use ExUnit.Case
  use Jido.Test.AgentCase

  alias MyApp.TaskAgent

  describe "state transitions" do
    test "allows valid transitions" do
      {:ok, agent} = start_supervised_agent(TaskAgent, id: "test-1", name: "Test Task")

      assert {:ok, %{status: :running}} =
        Jido.Agent.cmd(agent, MyApp.Actions.StartTask, %{})

      assert {:ok, %{status: :completed}} =
        Jido.Agent.cmd(agent, MyApp.Actions.CompleteTask, %{})
    end

    test "prevents invalid transitions" do
      {:ok, agent} = start_supervised_agent(TaskAgent, id: "test-2", name: "Test Task")

      assert {:error, :invalid_transition} =
        Jido.Agent.cmd(agent, MyApp.Actions.CompleteTask, %{})
    end
  end

  describe "state validation" do
    test "enforces schema rules" do
      assert {:error, _} = TaskAgent.start_link([])  # Missing required fields

      assert {:ok, pid} = TaskAgent.start_link(id: "test-3", name: "Valid Task")
      assert is_pid(pid)
    end
  end
end
```

### Property-Based Tests

```elixir
defmodule MyApp.TaskAgent.PropertyTest do
  use ExUnit.Case
  use PropCheck

  property "state transitions maintain invariants" do
    forall {id, name, transitions} <- {
      string(:alphanumeric),
      string(:alphanumeric),
      list(transition())
    } do
      {:ok, agent} = start_supervised_agent(TaskAgent, id: id, name: name)

      Enum.all?(transitions, fn transition ->
        case apply_transition(agent, transition) do
          {:ok, _} -> true
          {:error, :invalid_transition} -> true
          _ -> false
        end
      end)
    end
  end

  # Generators

  def transition do
    oneof([
      {:start, :running},
      {:complete, :completed},
      {:fail, :failed},
      {:retry, :pending}
    ])
  end
end
```

## Production Readiness

### Configuration

```elixir
# config/runtime.exs
config :my_app, MyApp.TaskAgent,
  max_queue_size: 1000,
  shutdown_timeout: :timer.seconds(30),
  retry_count: 3,
  retry_backoff: :timer.seconds(5)
```

### Monitoring

1. **Telemetry Events**

   ```elixir
   :telemetry.attach(
     "task-agent-metrics",
     [:jido, :agent, :state_transition],
     &MyApp.Metrics.handle_state_transition/4,
     nil
   )
   ```

2. **Health Checks**
   ```elixir
   def health_check(agent) do
     case Jido.Agent.get_state(agent) do
       {:ok, %{status: :failed}} -> {:error, :agent_failed}
       {:ok, _} -> :ok
       _ -> {:error, :agent_unavailable}
     end
   end
   ```

### Common Issues

1. **Queue Overflow**

   - Monitor queue size with `:telemetry`
   - Implement backpressure mechanisms
   - Consider scaling horizontally

2. **State Corruption**

   - Use strict schema validation
   - Implement state recovery mechanisms
   - Log all state transitions

3. **Performance**
   - Profile state update patterns
   - Optimize validation logic
   - Consider state partitioning

## Best Practices

1. **State Design**

   - Keep state minimal and focused
   - Use strict typing and validation
   - Document state transitions

2. **Error Handling**

   - Implement proper compensation
   - Log validation failures
   - Use telemetry for monitoring

3. **Testing**

   - Write comprehensive unit tests
   - Use property-based testing
   - Test concurrent operations

4. **Production**
   - Monitor queue sizes
   - Set appropriate timeouts
   - Implement health checks

## Further Reading

- [Actions and Workflows](../actions/overview.md)
- [Signal Routing](../signals/overview.md)

## See Also

- [Agent State Management](stateful.md)
- [Agent Output](output.md)
- [Signal Overview](../signals/overview.livemd)
- [Testing Guide](../signals/testing.md)
- [Child Processes](child-processes.md)
- [Directives](directives.md)
