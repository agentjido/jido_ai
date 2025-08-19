# AGENT.md - Jido Behavior Tree Development Guide

## Build/Test/Lint Commands
- `mix test` - Run tests (excludes flaky tests)  
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture

This is an Elixir library for **Jido native Behavior Trees** with integrated action support:
- **Jido.BehaviorTree** - Main API for creating and managing behavior trees
- **Jido.BehaviorTree.Status** - Status enumeration (`:success`, `:failure`, `:running`, `{:error, term}`)
- **Jido.BehaviorTree.Blackboard** - Shared state management with get/put/update operations
- **Jido.BehaviorTree.Tick** - Execution context with timestamp and sequence tracking
- **Jido.BehaviorTree.Node** - Behavior protocol for all tree nodes with telemetry support
- **Jido.BehaviorTree.Tree** - Tree management and execution
- **Jido.BehaviorTree.Agent** - GenServer-based stateful execution engine
- **Jido.BehaviorTree.Skill** - AI-compatible skill wrapper for behavior trees

## Key Features

✅ **Core Foundation Complete**
- Full behavior tree execution engine without external dependencies
- Comprehensive test coverage (88 tests passing)
- Telemetry integration for monitoring and debugging
- Type safety with TypedStruct and @spec annotations
- Blackboard pattern for shared state between nodes

✅ **Agent & Skill Integration**
- GenServer-based Agent for stateful tree execution
- Manual and automatic execution modes
- AI-compatible Skill wrapper with OpenAI tool format conversion
- Parameter validation and output formatting

## Usage Examples

### Basic Tree Creation and Execution

```elixir
# Create a simple test node
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

# Switch to auto mode
Jido.BehaviorTree.Agent.set_mode(agent, :auto)
```

### AI Skill Integration

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

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Nodes use `@behaviour Jido.BehaviorTree.Node` and implement `tick/2` and `halt/1` callbacks
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Core types in `lib/jido_behaviortree/`, nodes in `lib/jido_behaviortree/nodes/`
- Testing: Use ExUnit with test support nodes in `test/support/test_nodes.ex`
- Naming: Snake_case for functions/variables, PascalCase for modules

## Testing Patterns

Use the pre-built test nodes for consistent testing:

```elixir
alias Jido.BehaviorTree.Test.Nodes.{SimpleNode, RunningNode, FailureNode, ErrorNode}

# Node that always succeeds
node = SimpleNode.new("test_data")

# Node that runs for N ticks then succeeds  
node = RunningNode.new(3)

# Node that always fails
node = FailureNode.new("test failure")

# Node that throws an error
node = ErrorNode.new("test error")
```

## Telemetry Events

The package emits telemetry events for monitoring:

- `[:jido_behaviortree, :node, :tick, :start]` - Node tick started
- `[:jido_behaviortree, :node, :tick, :stop]` - Node tick completed
- `[:jido_behaviortree, :node, :tick, :exception]` - Node tick threw exception
- `[:jido_behaviortree, :agent, :tick, :start]` - Agent tick started  
- `[:jido_behaviortree, :agent, :tick, :stop]` - Agent tick completed

## Future Implementation

🚧 **Planned Components** (not yet implemented):
- Composite nodes (Sequence, Selector, Parallel)
- Decorator nodes (Inverter, Repeat, Timeout)  
- Action leaf nodes that execute Jido Actions
- Integration with jido_action for seamless workflow composition

## Integration with Jido Action

This package is designed to integrate seamlessly with `jido_action` from the same monorepo:
- Shared patterns for parameter validation and error handling
- Compatible with Jido's execution and instruction systems
- Follows same code quality standards and testing approaches
