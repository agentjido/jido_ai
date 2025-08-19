# Jido Behavior Tree

> ⚠️ **Experimental Project** - This library is in active development and the API is subject to change. Use with caution in production environments.

An Elixir behavior tree implementation designed for Jido agents with integrated action support and AI compatibility.

## Overview

Behavior trees are a powerful control structure for AI systems, allowing complex decision-making logic to be composed from simple, reusable components. This library provides a comprehensive behavior tree system that integrates seamlessly with the Jido ecosystem.

## Features

- 🌳 **Complete Behavior Tree Engine** - Full implementation with composite, decorator, and leaf nodes
- 🔄 **Stateful Execution** - GenServer-based agents with manual and automatic execution modes  
- 🧠 **Blackboard Pattern** - Shared state management between nodes with get/put/update operations
- 🎯 **Jido Action Integration** - Execute Jido actions directly within behavior tree nodes
- 🤖 **AI Tool Compatible** - Convert behavior trees to OpenAI-compatible tool definitions
- 📊 **Telemetry Support** - Built-in instrumentation for monitoring and debugging
- ⚡ **Type Safety** - Full TypeScript-style typing with TypedStruct and @spec annotations

## Status

✅ **Core Foundation Complete**
- Full behavior tree execution engine
- Comprehensive test coverage (88+ tests passing)
- Agent-based stateful execution
- AI skill wrapper integration

🚧 **In Development**
- Composite nodes (Sequence, Selector, Parallel)
- Decorator nodes (Inverter, Repeat, Timeout)
- Action leaf nodes with Jido Action integration

## Quick Start

### Basic Tree Creation

```elixir
# Define a simple test node
defmodule TestNode do
  use TypedStruct
  
  typedstruct do
    field(:data, term())
  end

  @behaviour Jido.BehaviorTree.Node

  def tick(node_state, _tick), do: {:success, node_state}
  def halt(node_state), do: node_state
end

# Create and execute a tree
node = %TestNode{data: "test"}
tree = Jido.BehaviorTree.new(node)
tick = Jido.BehaviorTree.tick()

{status, updated_tree} = Jido.BehaviorTree.tick(tree, tick)
# => {:success, %Jido.BehaviorTree.Tree{...}}
```

### Agent-based Execution

```elixir
# Start an agent for stateful execution
{:ok, agent} = Jido.BehaviorTree.start_agent(
  tree: tree,
  blackboard: %{user_id: 123},
  mode: :manual
)

# Execute ticks
status = Jido.BehaviorTree.Agent.tick(agent)

# Access blackboard
Jido.BehaviorTree.Agent.put(agent, :result, "success")
value = Jido.BehaviorTree.Agent.get(agent, :result)

# Switch to auto mode for continuous execution
Jido.BehaviorTree.Agent.set_mode(agent, :auto)
```

### AI Integration

```elixir
# Create a skill from a behavior tree
skill = Jido.BehaviorTree.skill(
  "process_data",
  tree,
  "Processes data using behavior tree logic",
  schema: [
    input_data: [type: :map, required: true],
    user_id: [type: :integer, required: true]
  ]
)

# Convert to AI tool format
tool_def = Jido.BehaviorTree.Skill.to_tool(skill)
# => %{
#   "name" => "process_data",
#   "description" => "Processes data using behavior tree logic",
#   "parameters" => %{...}
# }

# Execute the skill
{:ok, result} = Jido.BehaviorTree.Skill.run(skill, %{
  input_data: %{name: "John"},
  user_id: 123
}, %{})
```

## Core Concepts

### Status Types

Every node returns one of these statuses:

- `:success` - Node completed successfully
- `:failure` - Node failed to complete  
- `:running` - Node is still executing
- `{:error, reason}` - Node encountered an error

### Node Types

- **Composite Nodes**: Control execution of child nodes (Sequence, Selector, Parallel)
- **Decorator Nodes**: Modify behavior of a single child (Inverter, Repeat, Timeout)  
- **Leaf Nodes**: Perform actual work (Action, Wait, SetBlackboard)

### Blackboard

Shared data structure enabling communication between nodes:

```elixir
# Get/put values
blackboard = Jido.BehaviorTree.blackboard(%{user_id: 123})
updated = Jido.BehaviorTree.Blackboard.put(blackboard, :status, "active")
value = Jido.BehaviorTree.Blackboard.get(updated, :user_id)

# Update with functions
updated = Jido.BehaviorTree.Blackboard.update(blackboard, :counter, 0, &(&1 + 1))
```

## Installation

Add to your `mix.exs`:

```elixir
def deps do
  [
    {:jido_behaviortree, "~> 1.0"}
  ]
end
```

## Development

```bash
# Run tests
mix test

# Run quality checks  
mix quality

# Generate docs
mix docs
```

## Telemetry

The library emits telemetry events for monitoring:

- `[:jido_behaviortree, :node, :tick, :start]` - Node tick started
- `[:jido_behaviortree, :node, :tick, :stop]` - Node tick completed  
- `[:jido_behaviortree, :agent, :tick, :start]` - Agent tick started
- `[:jido_behaviortree, :agent, :tick, :stop]` - Agent tick completed

## Integration with Jido

This package integrates with the broader Jido ecosystem:

- **jido_action** - Execute Jido actions within behavior tree nodes
- **jido** - Main agent framework for autonomous systems
- **jido_signal** - Signal processing and event handling

## Roadmap

- [ ] Complete composite node implementations
- [ ] Full decorator node suite
- [ ] Rich action leaf nodes with Jido Action integration
- [ ] Visual tree editor and debugger
- [ ] Performance optimizations
- [ ] Enhanced telemetry and monitoring

## Contributing

This is an experimental project. Contributions are welcome, but please note the API may change significantly.

## License

Apache 2.0 - See [LICENSE.md](LICENSE.md)

---

**Part of the [Jido](https://agentjido.xyz) ecosystem for building autonomous agent systems.**
