# Jido.AI Strategies Guide

This guide covers all reasoning strategies available in Jido.AI, their use cases, and how to use them.

## Table of Contents

1. [Overview](#overview)
2. [ReAct (Reason-Act)](#react-reason-act)
3. [Chain-of-Thought](#chain-of-thought)
4. [Tree-of-Thoughts](#tree-of-thoughts)
5. [Graph-of-Thoughts](#graph-of-thoughts)
6. [TRM (Tiny-Recursive-Model)](#trm-tiny-recursive-model)
7. [Adaptive Strategy](#adaptive-strategy)
8. [Strategy Comparison](#strategy-comparison)
9. [Creating Custom Strategies](#creating-custom-strategies)

---

## Overview

Jido.AI provides multiple reasoning strategies, each optimized for different types of tasks:

| Strategy | Best For | Tool Support | Complexity |
|----------|----------|--------------|------------|
| **ReAct** | Tool-based reasoning | ✅ | Medium |
| **Chain-of-Thought** | Step-by-step reasoning | ❌ | Low |
| **Tree-of-Thoughts** | Exploratory search | ❌ | High |
| **Graph-of-Thoughts** | Multi-perspective analysis | ❌ | High |
| **TRM** | Iterative improvement | ❌ | Medium |
| **Adaptive** | Auto-selecting strategy | ✅ | High |

---

## ReAct (Reason-Act)

**Module**: `Jido.AI.Strategies.ReAct`

### Overview

ReAct (Reason-Act) alternates between **reasoning** (LLM calls) and **acting** (tool execution) in a loop until a final answer is reached.

### When to Use

- Tasks requiring external information (file I/O, API calls, databases)
- Multi-step problem solving with tool use
- Agent workflows with action capabilities

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     ReAct Flow                               │
│                                                              │
│   User Query → LLM → Tool Calls → Tool Results → LLM → ...  │
│                                                              │
│   Loop until:                                                │
│   - Final answer received                                    │
│   - Max iterations reached                                   │
│   - Error occurs                                             │
└─────────────────────────────────────────────────────────────┘
```

### State Machine

States: `idle` → `awaiting_llm` → `awaiting_tool` → `completed`/`error`

```elixir
defmodule Jido.AI.ReAct.Machine do
  @type status :: :idle | :awaiting_llm | :awaiting_tool | :completed | :error

  # Messages
  {:start, query, call_id}
  {:llm_result, call_id, result}
  {:llm_partial, call_id, delta, chunk_type}
  {:tool_result, call_id, result}

  # Directives
  {:call_llm_stream, id, context}
  {:exec_tool, id, tool_name, arguments}
end
```

### Usage

```elixir
use Jido.Agent,
  name: "my_react_agent",
  strategy: {
    Jido.AI.Strategies.ReAct,
    tools: [
      MyApp.Actions.Calculator,
      MyApp.Actions.Search
    ],
    model: "anthropic:claude-sonnet-4-20250514",
    max_iterations: 10,
    system_prompt: "You are a helpful assistant..."
  }

# Start a conversation
Agent.dispatch(agent, {:react_user_query, %{query: "What is 2 + 2?"}})
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:tools` | `[module()]` | **required** | List of Jido.Action modules |
| `:model` | `String.t()` | `"anthropic:claude-haiku-4-5"` | LLM model |
| `:max_iterations` | `pos_integer()` | `10` | Max reasoning loops |
| `:system_prompt` | `String.t()` | See below | Custom system prompt |
| `:use_registry` | `boolean()` | `false` | Also use Tools.Registry |

### Signal Routes

```elixir
"react.user_query"  → :react_start
"reqllm.result"     → :react_llm_result
"ai.tool_result"    → :react_tool_result
"reqllm.partial"    → :react_llm_partial
```

### Example: Calculator Agent

```elixir
defmodule CalculatorAction do
  use Jido.Action

  @impl true
  def schema do
    Zoi.object(%{
      expression: Zoi.string()
    })
  end

  @impl true
  def run(params, _context) do
    expr = params["expression"]
    result = Code.eval_string(expr)
    {:ok, %{result: elem(result, 0)}}
  end
end

defmodule CalculatorAgent do
  use Jido.Agent,
    name: "calculator",
    strategy: {
      Jido.AI.Strategies.ReAct,
      tools: [CalculatorAction],
      max_iterations: 5
    }
end
```

---

## Chain-of-Thought

**Module**: `Jido.AI.Strategies.ChainOfThought`

### Overview

Chain-of-Thought (CoT) breaks down complex problems into explicit step-by-step reasoning. It's simpler than ReAct as it doesn't use tools.

### When to Use

- Mathematical reasoning
- Logic puzzles
- Multi-step questions without external tools
- Tasks requiring explicit reasoning trace

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Chain-of-Thought Flow                      │
│                                                              │
│   Query → LLM (step-by-step) → Extract Steps → Conclusion    │
│                                                              │
│   Response format:                                           │
│   "Step 1: First I need to..."                               │
│   "Step 2: Then I'll consider..."                            │
│   "Conclusion: The answer is..."                             │
└─────────────────────────────────────────────────────────────┘
```

### State Machine

States: `idle` → `reasoning` → `completed`/`error`

```elixir
defmodule Jido.AI.ChainOfThought.Machine do
  # Messages
  {:start, prompt, call_id}
  {:llm_result, call_id, result}
  {:llm_partial, call_id, delta, chunk_type}

  # Directives
  {:call_llm_stream, id, conversation}
end
```

### Usage

```elixir
use Jido.Agent,
  name: "math_solver",
  strategy: {
    Jido.AI.Strategies.ChainOfThought,
    model: "anthropic:claude-sonnet-4-20250514",
    system_prompt: "You are a mathematician. Think step by step."
  }

# Get reasoning steps
steps = ChainOfThought.get_steps(agent)
conclusion = ChainOfThought.get_conclusion(agent)
```

### Helper Functions

```elixir
# Extract steps from response
{:ok, result} = ChainOfThought.Machine.extract_steps(response_text)

# Get formatted steps
steps = ChainOfThought.get_steps(agent)
# => [%{number: 1, content: "First, ..."}, ...]

# Get conclusion
conclusion = ChainOfThought.get_conclusion(agent)
# => "The answer is 42"
```

---

## Tree-of-Thoughts

**Module**: `Jido.AI.Strategies.TreeOfThoughts`

### Overview

Tree-of-Thoughts (ToT) explores multiple reasoning paths simultaneously, evaluating each and expanding the most promising branches. Like search algorithms (BFS, DFS, best-first).

### When to Use

- Puzzles and games
- Planning and scheduling
- Creative writing with options
- Complex reasoning requiring exploration

### Architecture

```
                    Root (Query)
                       │
           ┌───────────┼───────────┐
           ▼           ▼           ▼
        Thought A   Thought B   Thought C
           │           │           │
       ┌───┴───┐       │       ┌───┴───┐
       ▼       ▼       ▼       ▼       ▼
    A1      A2      B1      C1      C2
       │       │       │
       ▼       ▼       ▼
     A1a     A2a     B1a

    Traverse: Best node selection → Solution path
```

### State Machine

Features branching exploration with evaluation:

```elixir
# Configuration
branching_factor: 3  # Thoughts per node
max_depth: 4          # Max tree depth
traversal_strategy: :best_first | :bfs | :dfs
```

### Usage

```elixir
use Jido.Agent,
  name: "puzzle_solver",
  strategy: {
    Jido.AI.Strategies.TreeOfThoughts,
    model: "anthropic:claude-sonnet-4-20250514",
    branching_factor: 3,
    max_depth: 4,
    traversal_strategy: :best_first
  }

# Get solution path
solution_path = TreeOfThoughts.get_solution_path(agent)
# => ["root", "thought_2", "thought_2_1", "thought_2_1_a"]

# Get best node
best_node = TreeOfThoughts.get_best_node(agent)
```

### Traversal Strategies

| Strategy | Description | Use When |
|----------|-------------|----------|
| `:bfs` | Breadth-first search | All paths equally important |
| `:dfs` | Depth-first search | Deep exploration needed |
| `:best_first` | Best score first | Quality-based selection (default) |

---

## Graph-of-Thoughts

**Module**: `Jido.AI.Strategies.GraphOfThoughts`

### Overview

Graph-of-Thoughts (GoT) extends Tree-of-Thoughts by allowing nodes to have multiple parents, enabling synthesis of competing ideas and multi-perspective analysis.

### When to Use

- Problems requiring synthesis of competing ideas
- Multi-perspective analysis
- Complex causal reasoning
- Knowledge integration from multiple sources

### Architecture

```
      ┌──────────────┐
      │   Query     │
      └──────┬───────┘
             │
    ┌────────┴────────┐
    ▼                 ▼
Thought A         Thought B
    │                 │
    └────────┬────────┘
             ▼
      Synthesis Node
    (combines A + B)
             │
             ▼
        Conclusion
```

### Key Differences from ToT

| Feature | Tree-of-Thoughts | Graph-of-Thoughts |
|---------|------------------|-------------------|
| Structure | Tree (each node has 1 parent) | Graph (nodes can have multiple parents) |
| Aggregation | Sequential | Synthesis of multiple thoughts |
| Best For | Search problems | Synthesis and integration |

### Usage

```elixir
use Jido.Agent,
  name: "analyst",
  strategy: {
    Jido.AI.Strategies.GraphOfThoughts,
    model: "anthropic:claude-sonnet-4-20250514",
    max_nodes: 20,
    max_depth: 5,
    aggregation_strategy: :synthesis
  }

# Get all nodes and edges
nodes = GraphOfThoughts.get_nodes(agent)
edges = GraphOfThoughts.get_edges(agent)

# Get best solution
best = GraphOfThoughts.get_best_node(agent)
solution_path = GraphOfThoughts.get_solution_path(agent)
```

### Aggregation Strategies

| Strategy | Description |
|----------|-------------|
| `:voting` | Majority vote among thoughts |
| `:weighted` | Weighted by quality scores |
| `:synthesis` | LLM synthesizes combined answer (default) |

---

## TRM (Tiny-Recursive-Model)

**Module**: `Jido.AI.Strategies.TRM`

### Overview

TRM (Tiny-Recursive-Model) iteratively improves answers through a **reason-supervise-improve** cycle. Each iteration generates insights, evaluates quality, and applies feedback.

### When to Use

- Tasks requiring iterative refinement
- Quality-critical outputs
- Complex reasoning needing self-correction

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                       TRM Loop                               │
│                                                              │
│   ┌─────────┐     ┌──────────┐     ┌──────────┐            │
│   │ Reason  │ ──▶ │Supervise │ ──▶ │ Improve  │            │
│   │         │     │          │     │          │            │
│   │ Generate│     │Evaluate  │     │ Apply    │            │
│   │ insights│     │ quality  │     │ feedback │            │
│   └─────────┘     └──────────┘     └──────────┘            │
│        │                                   │                │
│        └───────────────────┬───────────────┘                │
│                            ▼                                │
│                     Check confidence                        │
│                            │                                │
│                ┌───────────┴───────────┐                    │
│                ▼                       ▼                    │
│            Above threshold        Below/Max steps           │
│                │                       │                    │
│                ▼                       ▼                    │
│            Return result           Continue loop            │
└─────────────────────────────────────────────────────────────┘
```

### State Machine

Three-phase cycle with ACT (Adaptive Computational Time):

```elixir
# Phases
:reasoning   # Generate insights about current answer
:supervising  # Evaluate quality and provide feedback
:improving    # Apply feedback to improve answer

# ACT (Adaptive Computational Time)
act_threshold: 0.9  # Stop if confidence above this
max_supervision_steps: 5  # Max iterations
```

### Usage

```elixir
use Jido.Agent,
  name: "writer",
  strategy: {
    Jido.AI.Strategies.TRM,
    model: "anthropic:claude-sonnet-4-20250514",
    max_supervision_steps: 5,
    act_threshold: 0.9
  }

# Get improvement history
answer_history = TRM.get_answer_history(agent)
best_answer = TRM.get_best_answer(agent)
confidence = TRM.get_confidence(agent)
step = TRM.get_supervision_step(agent)
```

### TRM Prompts

Each phase has specialized prompts:

```elixir
# Default prompts (available for reference)
TRM.default_reasoning_prompt()    # Initial reasoning
TRM.default_supervision_prompt()  # Quality evaluation
TRM.default_improvement_prompt()  # Feedback application
```

---

## Adaptive Strategy

**Module**: `Jido.AI.Strategies.Adaptive`

### Overview

The Adaptive strategy automatically selects the best reasoning strategy based on task characteristics (complexity, tool requirements, etc.).

### When to Use

- Uncertain which strategy to use
- Diverse task types
- Production environments needing flexibility

### Usage

```elixir
use Jido.Agent,
  name: "adaptive_agent",
  strategy: {
    Jido.AI.Strategies.Adaptive,
    available_strategies: [
      {Jido.AI.Strategies.ChainOfThought, simple: true},
      {Jido.AI.Strategies.ReAct, tools: true},
      {Jido.AI.Strategies.TreeOfThoughts, complex: true}
    ],
    selection_criteria: :automatic
  }
```

---

## Strategy Comparison

### Decision Tree

```
Need tools?
├─ Yes → ReAct
└─ No
    ├─ Multi-path exploration?
    │   ├─ Yes → Tree-of-Thoughts (search) or Graph-of-Thoughts (synthesis)
    │   └─ No → Iterative improvement needed?
    │       ├─ Yes → TRM
    │       └─ No → Chain-of-Thought
```

### Complexity vs Capability

```
High ┃    ┌──────────┐
     ┃    │ GoT, ToT │  Complex reasoning
Capability├──────────┤
     ┃    │   TRM    │  Iterative improvement
     ┃    ├──────────┤
     ┃    │   ReAct  │  Tool-based reasoning
     ┃    ├──────────┤
Low  ┃    │   CoT    │  Step-by-step reasoning
     └────────────────────────────────────────
        Low    Medium    High
               Complexity
```

---

## Creating Custom Strategies

### Strategy Boilerplate

All strategies follow the same pattern:

```elixir
defmodule Jido.AI.Strategies.MyCustom do
  @moduledoc """
  Custom strategy description...
  """

  use Jido.Agent.Strategy

  alias Jido.Agent
  alias Jido.Agent.Strategy.State, as: StratState
  alias Jido.AI.MyCustom.Machine

  @start :my_start
  @llm_result :my_llm_result

  @action_specs %{
    @start => %{
      schema: Zoi.object(%{prompt: Zoi.string()}),
      doc: "Start custom reasoning",
      name: "my.start"
    },
    @llm_result => %{
      schema: Zoi.object(%{call_id: Zoi.string(), result: Zoi.any()}),
      doc: "Handle LLM response",
      name: "my.llm_result"
    }
  }

  @impl true
  def action_spec(action), do: Map.get(@action_specs, action)

  @impl true
  def signal_routes(_ctx) do
    [
      {"my.query", {:strategy_cmd, @start}},
      {"reqllm.result", {:strategy_cmd, @llm_result}}
    ]
  end

  @impl true
  def init(%Agent{} = agent, ctx) do
    config = build_config(agent, ctx)
    machine = Machine.new()

    state =
      machine
      |> Machine.to_map()
      |> Map.put(:config, config)

    agent = StratState.put(agent, state)
    {agent, []}
  end

  @impl true
  def cmd(%Agent{} = agent, instructions, _ctx) do
    # Process instructions
    # Update machine state
    # Return {agent, directives}
  end

  @impl true
  def snapshot(%Agent{} = agent, _ctx) do
    # Return strategy snapshot
  end

  # Private helpers...
end
```

### State Machine Pattern

```elixir
defmodule Jido.AI.MyCustom.Machine do
  use Fsmx.Struct,
    state_field: :status,
    transitions: %{
      "idle" => ["processing"],
      "processing" => ["completed", "error"],
      "completed" => [],
      "error" => []
    }

  defstruct status: "idle",
            result: nil,
            started_at: nil

  @type t :: %__MODULE__{
          status: String.t(),
          result: term(),
          started_at: integer() | nil
        }

  def new, do: %__MODULE__{}

  def update(machine, {:start, prompt, call_id}, env) do
    # Handle start message
    # Return {machine, directives}
  end

  def update(machine, {:llm_result, call_id, result}, env) do
    # Handle LLM result
    # Return {machine, directives}
  end

  def to_map(%__MODULE__{} = machine), do: Map.from_struct(machine)
  def from_map(map) when is_map(map), do: struct(__MODULE__, map)
end
```

### Key Implementation Points

1. **Use Fsmx** for state machine transitions
2. **Pure functions** in state machine (no side effects)
3. **Directives** describe effects; don't execute them
4. **Signal routes** define automatic message routing
5. **Snapshot** provides state inspection

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [State Machines Guide](./03_state_machines.md) - State machine patterns
- [Directives Guide](./04_directives.md) - Directive system
- [Signals Guide](./05_signals.md) - Signal types and routing
- [Tool System Guide](./06_tool_system.md) - Tool registry and execution
