# Directives in Jido

Directives are the control system of Jido agents, providing a safe, validated way to modify agent behavior and state at runtime. They act as discrete, immutable instructions that tell agents how to change their state or behavior.

## Overview

Directives serve two main purposes:

1. Modifying agent state through validated operations
2. Controlling server behavior in agent processes

Each directive is implemented as a distinct struct with its own validation rules, helping ensure type safety and consistent state transitions.

## Agent Directives

Agent directives modify the core agent struct and its internal state. They handle tasks like:

- Queueing new instructions
- Managing action registrations
- Managing child processes

### Available Agent Directives

#### Enqueue

Adds a new instruction to the agent's pending queue:

```elixir
%Directive.Enqueue{
  action: :calculate_sum,
  params: %{numbers: [1, 2, 3]},
  context: %{user_id: "123"},
  opts: [retry: true]
}
```

#### RegisterAction

Registers a new action module with the agent:

```elixir
%Directive.RegisterAction{
  action_module: MyApp.Actions.Calculate
}
```

#### DeregisterAction

Removes an action module from the agent:

```elixir
%Directive.DeregisterAction{
  action_module: MyApp.Actions.Calculate
}
```

### Using Agent Directives

Actions can return directives to modify agent behavior. This is done by returning a tuple with both the result and directive:

```elixir
defmodule MyAction do
  use Jido.Action

  def run(_params, _context) do
    # Return both a result and a directive
    directive = %Directive.Enqueue{
      action: :next_step,
      params: %{value: 42}
    }

    {:ok, %{completed: true}, directive}
  end
end
```

Multiple directives can be returned as a list:

```elixir
def run(_params, _context) do
  directives = [
    %Directive.Enqueue{action: :step_one},
    %Directive.Enqueue{action: :step_two}
  ]

  {:ok, %{completed: true}, directives}
end
```

## Server Directives

Server directives control the behavior of the underlying GenServer that hosts the agent. They handle operations like:

- Process spawning and termination
- Router management
- Event subscription

### Available Server Directives

#### Spawn

Spawns a child process under the agent's supervisor:

```elixir
%Directive.Spawn{
  module: MyWorker,
  args: [id: 1]
}
```

#### Kill

Terminates a child process:

```elixir
%Directive.Kill{
  pid: worker_pid
}
```

### Using Server Directives

Server directives are typically used in system management actions:

```elixir
defmodule SpawnWorker do
  use Jido.Action

  def run(%{worker_module: module} = params, _context) do
    directive = %Directive.Spawn{
      module: module,
      args: params.args
    }

    {:ok, %{spawned: true}, directive}
  end
end
```

## Directive Processing

When an action returns a directive, it goes through several stages:

1. Validation - The directive structure and content are validated
2. Classification - Directives are split into agent and server types
3. Application - Each directive is applied in order
4. State Update - The agent/server state is updated accordingly

### Validation Rules

Each directive type has specific validation rules:

```elixir
# Enqueue requires a valid action atom
validate_directive(%Enqueue{action: nil})
  # => {:error, :invalid_action}

# RegisterAction requires a valid module
validate_directive(%RegisterAction{action_module: MyAction})
  # => :ok
```

### Error Handling

Directive application uses tagged tuples for consistent error handling:

```elixir
case Directive.apply_directives(agent, directives) do
  {:ok, updated_agent, server_directives} ->
    # Handle success

  {:error, reason} ->
    # Handle error
end
```

## Best Practices

1. **Atomic Changes**

   - Return related directives together
   - Keep directive changes focused and minimal

2. **Validation**

   - Always validate input parameters
   - Use strict typing for directive fields

3. **Error Handling**

   - Implement compensation logic for failures
   - Handle partial directive application

4. **Testing**
   - Test directive validation
   - Verify state changes
   - Check error conditions

## Common Patterns

### Sequential Operations

Chain multiple operations using Enqueue directives:

```elixir
directives = [
  %Directive.Enqueue{action: :validate_input},
  %Directive.Enqueue{action: :process_data},
  %Directive.Enqueue{action: :save_results}
]
```

### Dynamic Action Registration

Register actions based on runtime conditions:

```elixir
def run(%{feature_enabled: true} = _params, _context) do
  directive = %Directive.RegisterAction{
    action_module: MyApp.Actions.FeatureAction
  }
  {:ok, %{}, directive}
end
```

### Worker Management

Manage worker processes with spawn/kill directives:

```elixir
def run(%{worker_count: count} = _params, _context) do
  directives = for i <- 1..count do
    %Directive.Spawn{
      module: MyApp.Worker,
      args: [id: i]
    }
  end

  {:ok, %{}, directives}
end
```

## See Also

- [Agent State Management](../agents/stateful.md)
- [Action Development](overview.md)
- [Testing Actions](testing.md)
