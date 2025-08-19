# Child Processes in Jido Agents

## Overview

Jido agents are built on top of DynamicSupervisor, allowing them to dynamically spawn and manage child processes at runtime. This capability enables agents to coordinate complex distributed workflows by managing a hierarchy of worker processes, including other agents.

## Core Concepts

- Each agent has its own DynamicSupervisor
- Child processes can be any valid OTP process
- Processes can be spawned directly or via directives
- Child process lifecycle is tied to the parent agent
- Automatic cleanup on process termination

## Basic Child Process Management

### Starting Child Processes Directly

The most straightforward way to start child processes is through the agent's supervisor:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "process_manager",
    description: "Manages worker processes"

  def start_worker(agent, worker_module, args) do
    case DynamicSupervisor.start_child(
      agent.child_supervisor,
      {worker_module, args}
    ) do
      {:ok, pid} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end

# Usage
{:ok, agent} = MyAgent.new()
{:ok, worker_pid} = MyAgent.start_worker(agent, MyWorker, [id: 1])
```

### Using Child Specifications

For more control, define explicit child specifications:

```elixir
defmodule MyAgent do
  use Jido.Agent,
    name: "process_manager"

  def start_with_spec(agent) do
    child_spec = %{
      id: MyWorker,
      start: {MyWorker, :start_link, [[id: 1]]},
      restart: :temporary,
      shutdown: 5000,
      type: :worker
    }

    DynamicSupervisor.start_child(agent.child_supervisor, child_spec)
  end
end
```

## Using Directives

While direct process management works, the recommended approach is using Jido's directive system. This provides better encapsulation and integration with the agent's lifecycle management.

### Spawn Directive

The `Spawn` directive handles process creation:

```elixir
defmodule ProcessManagementAction do
  use Jido.Action,
    name: "manage_processes",
    description: "Manages worker processes"

  def run(_params, _context) do
    # Create spawn directive
    directive = %Jido.Agent.Directive.Spawn{
      module: MyWorker,
      args: [id: 1]
    }

    {:ok, %{spawned: true}, directive}
  end
end
```

### Kill Directive

The `Kill` directive handles process termination:

```elixir
defmodule TerminateWorkerAction do
  use Jido.Action,
    name: "terminate_worker",
    description: "Terminates a worker process"

  def run(%{worker_pid: pid}, _context) do
    directive = %Jido.Agent.Directive.Kill{
      pid: pid
    }

    {:ok, %{terminated: true}, directive}
  end
end
```

## Managing Child Agents

Agents can spawn other agents as child processes, creating hierarchical agent networks:

```elixir
defmodule ParentAgent do
  use Jido.Agent,
    name: "parent_agent"

  def spawn_child_agent(agent, child_module, opts \\ []) do
    child_spec = %{
      id: child_module,
      start: {child_module, :start_link, [opts]},
      restart: :temporary
    }

    DynamicSupervisor.start_child(agent.child_supervisor, child_spec)
  end
end

# Usage
{:ok, parent} = ParentAgent.new()
{:ok, child_pid} = ParentAgent.spawn_child_agent(parent, ChildAgent, id: "child_1")
```

### Child Agent Directives

Use directives to manage child agents through the agent system:

```elixir
defmodule SpawnChildAgentAction do
  use Jido.Action,
    name: "spawn_child_agent",
    schema: [
      agent_module: [type: :atom, required: true],
      agent_id: [type: :string, required: true]
    ]

  def run(%{agent_module: module, agent_id: id}, _context) do
    directive = %Jido.Agent.Directive.Spawn{
      module: module,
      args: [id: id]
    }

    {:ok, %{child_spawned: true}, directive}
  end
end
```

## Process Monitoring

Agents automatically monitor their child processes and receive notifications when they terminate:

```elixir
defmodule MonitoredAgent do
  use Jido.Agent,
    name: "monitored_agent"

  def handle_signal(%Signal{type: "jido.agent.event.process.terminated"} = signal) do
    # Handle process termination
    Logger.info("Process terminated: #{inspect(signal.data.pid)}")
    {:ok, signal}
  end
end
```

## Best Practices

1. **Use Directives**: Prefer directives over direct process management for better integration
2. **Handle Termination**: Implement proper cleanup in process termination handlers
3. **Monitor Health**: Track process status through the agent's monitoring system
4. **Limit Hierarchy**: Keep agent hierarchies shallow to manage complexity
5. **Resource Management**: Consider memory and CPU impact when spawning processes

## Error Handling

Implement comprehensive error handling for process operations:

```elixir
defmodule ResilientAgent do
  use Jido.Agent,
    name: "resilient_agent"

  def handle_signal(%Signal{type: "jido.agent.event.process.failed"} = signal) do
    # Handle process failure
    %{error: reason, child_spec: spec} = signal.data

    Logger.error("Process failed",
      error: reason,
      spec: spec
    )

    # Attempt recovery
    case recover_failed_process(spec) do
      {:ok, _pid} -> {:ok, signal}
      {:error, _} -> {:error, "Recovery failed"}
    end
  end

  defp recover_failed_process(spec) do
    # Implement recovery logic
  end
end
```

## Testing

Test process management thoroughly:

```elixir
defmodule ProcessManagementTest do
  use ExUnit.Case

  test "spawns and terminates child process" do
    {:ok, agent} = TestAgent.new()

    {:ok, pid} = TestAgent.start_worker(agent, TestWorker, [])
    assert Process.alive?(pid)

    :ok = TestAgent.terminate_worker(agent, pid)
    refute Process.alive?(pid)
  end

  test "handles process failure" do
    {:ok, agent} = TestAgent.new()

    # Test failure handling
    {:ok, pid} = TestAgent.start_worker(agent, CrashingWorker, [])
    ref = Process.monitor(pid)

    # Trigger crash
    send(pid, :crash)

    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    # Verify agent handled failure
    assert_receive {:signal, %{type: "jido.agent.event.process.failed"}}
  end
end
```

## See Also

- [Directives Guide](directives.html) - Detailed information about the directive system
- [Agent Runtime Guide](runtime.html) - Understanding agent runtime behavior
- [Testing Guide](testing.html) - Comprehensive testing strategies
