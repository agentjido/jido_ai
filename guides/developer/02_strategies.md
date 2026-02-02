# Strategies Guide

This guide covers the strategy system in Jido.AI, which implements different reasoning patterns for AI agents.

## Table of Contents

- [Overview](#overview)
- [Available Strategies](#available-strategies)
- [Strategy Interface](#strategy-interface)
- [ReAct Strategy](#react-strategy)
- [Chain-of-Thought Strategy](#chain-of-thought-strategy)
- [Tree-of-Thoughts Strategy](#tree-of-thoughts-strategy)
- [Graph-of-Thoughts Strategy](#graph-of-thoughts-strategy)
- [TRM Strategy](#trm-strategy)
- [Adaptive Strategy](#adaptive-strategy)
- [Creating Custom Strategies](#creating-custom-strategies)

## Overview

Strategies in Jido.AI implement different reasoning patterns for agent execution. Each strategy:

- Implements the `Jido.Agent.Strategy` behavior
- Uses a pure state machine for state transitions
- Returns directives describing side effects
- Routes signals to strategy commands
- Stores state in `agent.state.__strategy__`

### Strategy Location

All strategy modules are located in `lib/jido_ai/strategy/`:

```
lib/jido_ai/strategy/
├── react.ex              # ReAct strategy
├── chain_of_thought.ex   # Chain-of-Thought strategy
├── tree_of_thoughts.ex   # Tree-of-Thoughts strategy
├── graph_of_thoughts.ex  # Graph-of-Thoughts strategy
├── trm.ex                # TRM strategy
├── adaptive.ex           # Adaptive strategy
└── state_ops_helpers.ex  # StateOps helper functions
```

## Available Strategies

| Strategy | Module | Description |
|----------|--------|-------------|
| **ReAct** | `Jido.AI.Strategies.ReAct` | Multi-step reasoning with tool use |
| **Chain-of-Thought** | `Jido.AI.Strategies.ChainOfThought` | Step-by-step sequential reasoning |
| **Tree-of-Thoughts** | `Jido.AI.Strategies.TreeOfThoughts` | Branching exploration with evaluation |
| **Graph-of-Thoughts** | `Jido.AI.Strategies.GraphOfThoughts` | Graph-based reasoning with synthesis |
| **TRM** | `Jido.AI.Strategies.TRM` | Thought-Refine-Merge with supervision |
| **Adaptive** | `Jido.AI.Strategies.Adaptive` | Automatic strategy selection |

## Strategy Interface

All strategies implement the `Jido.Agent.Strategy` behavior:

```elixir
@callback init(agent :: Agent.t(), ctx :: map()) :: {Agent.t(), [Directive.t()]}

@callback cmd(agent :: Agent.t(), instructions :: [Instruction.t()], ctx :: map()) ::
  {Agent.t(), [Directive.t()]}

@callback signal_routes(ctx :: map()) :: [{Signal.type(), route()}]

@callback action_spec(action :: atom()) :: %{schema: Zoi.schema(), doc: String.t()} | nil

@callback snapshot(agent :: Agent.t(), ctx :: map()) :: Strategy.Snapshot.t()
```

### Required Actions

Strategies define actions they handle via `@action_specs`:

```elixir
@action_specs %{
  @start => %{
    schema: Zoi.object(%{query: Zoi.string()}),
    doc: "Start a new conversation",
    name: "strategy.start"
  }
}
```

## ReAct Strategy

The ReAct (Reason-Act) strategy implements a multi-step reasoning loop with tool use.

### Configuration

```elixir
use Jido.Agent,
  name: "my_react_agent",
  strategy: {
    Jido.AI.Strategies.ReAct,
    tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
    system_prompt: "You are a helpful assistant...",
    model: "anthropic:claude-haiku-4-5",
    max_iterations: 10
  }
```

### Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| `:tools` | `[module()]` | Yes | - | List of Jido.Action modules |
| `:system_prompt` | `String.t()` | No | Default prompt | Custom system prompt |
| `:model` | `String.t()` | No | `claude-haiku-4-5` | Model identifier |
| `:max_iterations` | `pos_integer()` | No | 10 | Maximum reasoning iterations |

### State Structure

```elixir
%{
  status: :idle | :awaiting_llm | :awaiting_tool | :completed | :error,
  iteration: non_neg_integer(),
  conversation: [ReqLLM.Message.t()],
  pending_tool_calls: [%{id: String.t(), name: String.t(), arguments: map(), result: term()}],
  final_answer: String.t() | nil,
  current_llm_call_id: String.t() | nil,
  termination_reason: :final_answer | :max_iterations | :error | nil,
  config: config()
}
```

### Signal Routes

```elixir
def signal_routes(_ctx) do
  [
    {"react.input", {:strategy_cmd, :react_start}},
    {"react.llm.response", {:strategy_cmd, :react_llm_result}},
    {"react.tool.result", {:strategy_cmd, :react_tool_result}},
    {"react.llm.delta", {:strategy_cmd, :react_llm_partial}}
  ]
end
```

### Dynamic Tool Registration

```elixir
# Register a tool at runtime
Jido.AgentServer.cast(agent_pid, %Jido.Signal{
  type: "react.register_tool",
  data: %{tool_module: MyApp.Actions.NewTool}
})

# Unregister a tool
Jido.AgentServer.cast(agent_pid, %Jido.Signal{
  type: "react.unregister_tool",
  data: %{tool_name: "old_tool"}
})
```

## Chain-of-Thought Strategy

The Chain-of-Thought strategy implements step-by-step reasoning.

### Configuration

```elixir
use Jido.Agent,
  name: "my_cot_agent",
  strategy: {
    Jido.AI.Strategies.ChainOfThought,
    system_prompt: "Think step by step...",
    model: "anthropic:claude-haiku-4-5"
  }
```

### State Structure

```elixir
%{
  status: :idle | :thinking | :completed | :error,
  reasoning_steps: [String.t()],
  final_answer: String.t() | nil
}
```

## Tree-of-Thoughts Strategy

The Tree-of-Thoughts strategy implements branching exploration with thought evaluation.

### Configuration

```elixir
use Jido.Agent,
  name: "my_tot_agent",
  strategy: {
    Jido.AI.Strategies.TreeOfThoughts,
    branching_factor: 3,
    max_depth: 4,
    traversal_strategy: :best_first,  # :bfs, :dfs, :best_first
    model: "anthropic:claude-haiku-4-5"
  }
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:branching_factor` | `integer()` | 3 | Thoughts to generate per step |
| `:max_depth` | `integer()` | 4 | Maximum reasoning depth |
| `:traversal_strategy` | `atom()` | `:best_first` | How to traverse thoughts |

### Traversal Strategies

- `:bfs` - Breadth-first search: explores all thoughts at current depth before going deeper
- `:dfs` - Depth-first search: explores each branch completely before backtracking
- `:best_first` - Best-first search: always explores the highest-scoring thought first

## Graph-of-Thoughts Strategy

The Graph-of-Thoughts strategy implements graph-based reasoning with thought aggregation.

### Configuration

```elixir
use Jido.Agent,
  name: "my_got_agent",
  strategy: {
    Jido.AI.Strategies.GraphOfThoughts,
    branching_factor: 3,
    max_depth: 4,
    aggregation_method: :weighted_vote,  # :majority_vote, :weighted_vote
    model: "anthropic:claude-haiku-4-5"
  }
```

### Key Differences from Tree-of-Thoughts

- Thoughts can have multiple parents (graph vs tree)
- Supports thought aggregation and synthesis
- Better for multi-perspective analysis

## TRM Strategy

The TRM (Thought-Refine-Merge) strategy implements iterative reasoning with supervision.

### Configuration

```elixir
use Jido.Agent,
  name: "my_trm_agent",
  strategy: {
    Jido.AI.Strategies.TRM,
    max_refinements: 3,
    supervision_mode: :automatic,  # :automatic, :manual
    model: "anthropic:claude-haiku-4-5"
  }
```

### TRM States

| State | Description |
|-------|-------------|
| `:act` | Generate initial thoughts |
| `:reasoning` | Refine thoughts through reasoning |
| `:supervision` | Evaluate and select best thoughts |
| `:merge` | Merge selected thoughts |

## Adaptive Strategy

The Adaptive strategy automatically selects the best strategy based on task characteristics.

### Configuration

```elixir
use Jido.Agent,
  name: "my_adaptive_agent",
  strategy: {
    Jido.AI.Strategies.Adaptive,
    strategies: [:react, :cot, :tot, :got],
    model: "anthropic:claude-haiku-4-5",
    tools: [MyApp.Actions.Calculator]
  }
```

### Strategy Selection Logic

```elixir
defp select_strategy(prompt, config) do
  cond do
    has_tool_keywords?(prompt) and config[:tools] != [] ->
      :react

    has_synthesis_keywords?(prompt) ->
      :got

    has_exploration_keywords?(prompt) ->
      :tot

    needs_iteration?(prompt) ->
      :trm

    true ->
      :cot
  end
end
```

### Keywords for Selection

| Strategy | Keywords |
|----------|----------|
| ReAct | "use", "call", "execute", "tool", "function" |
| GoT | "combine", "synthesize", "merge", "perspectives" |
| ToT | "explore", "alternatives", "options", "branches" |
| TRM | "refine", "improve", "iterate", "supervise" |
| CoT | Default fallback |

## StateOpsHelpers

The `StateOpsHelpers` module provides helper functions for creating state operations.

```elixir
alias Jido.AI.Strategy.StateOpsHelpers

# Update strategy state
StateOpsHelpers.update_strategy_state(%{status: :awaiting_llm})

# Set iteration
StateOpsHelpers.set_iteration(3)

# Set iteration status
StateOpsHelpers.set_iteration_status(:completed)

# Append to conversation
StateOpsHelpers.append_conversation([%{role: :user, content: "Hello"}])

# Set pending tools
StateOpsHelpers.set_pending_tools([
  %{id: "tc_1", name: "calculator", arguments: %{a: 1, b: 2}}
])

# Clear pending tools
StateOpsHelpers.clear_pending_tools()

# Update config
StateOpsHelpers.update_config(%{model: "new:model"})

# Set final answer
StateOpsHelpers.set_final_answer("42")

# Set termination reason
StateOpsHelpers.set_termination_reason(:final_answer)
```

## Creating Custom Strategies

To create a custom strategy:

```elixir
defmodule MyApp.Strategies.MyStrategy do
  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState

  # Define your state machine
  defmodule Machine do
    use Fsmx.Struct,
      state_field: :status,
      transitions: %{
        "idle" => ["processing", "completed"],
        "processing" => ["completed", "error"],
        "completed" => [],
        "error" => []
      }

    defstruct status: "idle",
              iteration: 0,
              result: nil

    def new, do: %__MODULE__{}

    def update(machine, {:start, input}, _env) do
      # Process input and return {machine, directives}
    end

    def to_map(%__MODULE__{} = machine), do: Map.from_struct(machine)
    def from_map(map), do: struct(__MODULE__, map)
  end

  # Implement strategy callbacks

  @impl true
  def init(%Agent{} = agent, _ctx) do
    machine = Machine.new()
    state = StratState.put(agent, Machine.to_map(machine))
    {state, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    state_map = StratState.get(agent, %{})
    machine = Machine.from_map(state_map)

    {machine, directives} =
      Enum.reduce(instructions, {machine, []}, fn instr, {m, dirs} ->
        case process_instruction(m, instr) do
          {new_machine, new_dirs} -> {new_machine, dirs ++ new_dirs}
          :noop -> {m, dirs}
        end
      end)

    agent = StratState.put(agent, Machine.to_map(machine))
    {agent, directives}
  end

  @impl true
  def signal_routes(_ctx) do
    [
      {"my.signal", {:strategy_cmd, :my_action}}
    ]
  end

  @impl true
  def action_spec(:my_action) do
    %{
      schema: Zoi.object(%{input: Zoi.string()}),
      doc: "Process an input",
      name: "my_strategy.process"
    }
  end

  def action_spec(_), do: nil

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    state_map = StratState.get(agent, %{})
    status = state_map[:status] || :idle

    %Jido.Agent.Strategy.Snapshot{
      status: status,
      done?: status in [:completed, :error],
      result: state_map[:result]
    }
  end
end
```

## Next Steps

- [State Machines Guide](./03_state_machines.md) - Pure state machine patterns
- [Directives Guide](./04_directives.md) - Side effects and execution
- [Tool System Guide](./06_tool_system.md) - Tool execution
