# Agent Directives Guide

## Overview

Directives provide a type-safe mechanism for modifying agent behavior and state at runtime. They act as discrete, immutable instructions that tell agents how to change their state or behavior. This guide covers directive types, usage patterns, and state management considerations.

## Core Concepts

Directives in Jido fall into two main categories:

1. **Agent Directives**: Modify the core agent struct and its internal state

   - Queueing instructions
   - Managing action registrations
   - State transitions

2. **Server Directives**: Control server behavior in agent processes
   - Process spawning and termination
   - Router management
   - Event subscription

## Agent Directives

### Enqueue Directive

The most common directive type, used to add new instructions to an agent's pending queue:

```elixir
%Directive.Enqueue{
  action: :process_data,
  params: %{file: "data.csv"},
  context: %{user_id: "123"},
  opts: [retry: true]
}
```

### RegisterAction Directive

Registers a new action module with the agent:

```elixir
%Directive.RegisterAction{
  action_module: MyApp.Actions.ProcessData
}
```

### DeregisterAction Directive

Removes an action module from the agent:

```elixir
%Directive.DeregisterAction{
  action_module: MyApp.Actions.ProcessData
}
```

## Server Directives

### Spawn Directive

Spawns a child process under the agent's supervisor:

```elixir
%Directive.Spawn{
  module: MyWorker,
  args: [id: 1]
}
```

### Kill Directive

Terminates a specific child process:

```elixir
%Directive.Kill{
  pid: worker_pid
}
```

## Returning Directives from Actions

Actions can return directives in several ways:

### 1. Return a Single Directive

```elixir
defmodule MyAction do
  use Jido.Action

  def run(_params, _context) do
    directive = %Directive.Enqueue{
      action: :next_step,
      params: %{value: 42}
    }

    {:ok, %{completed: true}, directive}
  end
end
```

### 2. Return Multiple Directives

```elixir
defmodule ChainedAction do
  use Jido.Action

  def run(_params, _context) do
    directives = [
      %Directive.Enqueue{action: :validate_data},
      %Directive.Enqueue{action: :process_data},
      %Directive.Enqueue{action: :save_results}
    ]

    {:ok, %{chain_started: true}, directives}
  end
end
```

### 3. Return Instructions Directly

Instructions are automatically converted to Enqueue directives:

```elixir
defmodule InstructionAction do
  use Jido.Action

  def run(_params, _context) do
    instruction = %Instruction{
      action: :process_data,
      params: %{file: "data.csv"}
    }

    {:ok, %{setup_complete: true}, instruction}
  end
end
```

## State Management Considerations

### Stateless Agents

Stateless agents ([see Stateless Agents Guide](agents/stateless.md)) handle directives differently:

- Will enqueue instructions but not execute them
- Return the full queue for external processing
- Ignore state-modifying directives
- Maintain immutability guarantees

Example of stateless agent behavior:

```elixir
defmodule StatelessAgent do
  use Jido.Agent,
    name: "stateless_example",
    state_type: :stateless

  def run(_params, _context) do
    # Instructions are queued but not executed
    directive = %Directive.Enqueue{action: :process}
    {:ok, %{queued: true}, directive}
  end
end
```

### Stateful Agents

Stateful agents ([see Stateful Agents Guide](agents/stateful.md)) provide full directive support:

- Execute queued instructions
- Apply state modifications
- Handle all directive types
- Maintain execution context

Example of stateful agent behavior:

```elixir
defmodule StatefulAgent do
  use Jido.Agent,
    name: "stateful_example",
    state_type: :stateful

  def run(_params, _context) do
    # Instructions are queued and executed
    directives = [
      %Directive.Enqueue{action: :validate},
      %Directive.Enqueue{action: :process},
      %Directive.RegisterAction{action_module: NewAction}
    ]
    {:ok, %{processing: true}, directives}
  end
end
```

## Directive Processing

When an action returns a directive, it goes through several stages:

1. **Validation**: The directive structure and content are validated
2. **Classification**: Directives are split into agent and server types
3. **Application**: Each directive is applied in order
4. **State Update**: The agent/server state is updated accordingly

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

## Future Considerations

The directive system is designed for extensibility. Future directives might include:

- Mode changes
- Verbosity controls
- Router management
- Skill management
- Dispatcher configuration

## See Also

- [Agent State Management](../agents/stateful.md)
- [Action Development](overview.md)
- [Testing Actions](testing.md)
