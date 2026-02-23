# Strategy Recipes

You want copy-paste patterns for every built-in strategy, not just a comparison matrix.

After this guide, you can stand up ReAct, Chain-of-Draft, Chain-of-Thought, Algorithm-of-Thoughts, Tree-of-Thoughts, Graph-of-Thoughts, TRM, and Adaptive agents quickly.

## Shared Setup

All recipes assume:

- dependencies added (`jido`, `jido_ai`)
- model aliases configured (`:fast`, `:capable`, `:reasoning`, etc.)
- agent process started with `Jido.AgentServer.start/1`

```elixir
{:ok, pid} = Jido.AgentServer.start(agent: MyApp.SomeAgent)
```

## ReAct Recipe (`Jido.AI.Agent`)

Use when you need tool-calling plus iterative reasoning.

```elixir
defmodule MyApp.Actions.Multiply do
  use Jido.Action,
    name: "multiply",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  @impl true
  def run(%{a: a, b: b}, _context), do: {:ok, %{product: a * b}}
end

defmodule MyApp.ReActAgent do
  use Jido.AI.Agent,
    name: "react_agent",
    model: :fast,
    tools: [MyApp.Actions.Multiply],
    llm_opts: [thinking: %{type: :enabled, budget_tokens: 1024}, reasoning_effort: :high]
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.ReActAgent)
{:ok, answer} = MyApp.ReActAgent.ask_sync(pid, "Use multiply to compute 17 * 9")
```

## Chain-of-Draft Recipe (`Jido.AI.CoDAgent`)

Use when you want concise reasoning with lower latency/token cost.

```elixir
defmodule MyApp.CoDAgent do
  use Jido.AI.CoDAgent,
    name: "cod_agent",
    model: :fast
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.CoDAgent)
{:ok, result} = MyApp.CoDAgent.draft_sync(pid, "Give a concise rollout plan with one backup.")
```

## Chain-of-Thought Recipe (`Jido.AI.CoTAgent`)

Use when you want explicit intermediate reasoning steps for multi-step problems.

```elixir
defmodule MyApp.CoTAgent do
  use Jido.AI.CoTAgent,
    name: "cot_agent",
    model: :fast
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.CoTAgent)
{:ok, result} = MyApp.CoTAgent.think_sync(pid, "Solve this in steps: 15% of 340, then add 27.")
```

## Algorithm-of-Thoughts Recipe (`Jido.AI.AoTAgent`)

Use when you want single-query algorithmic exploration with explicit finalization.

```elixir
defmodule MyApp.AoTAgent do
  use Jido.AI.AoTAgent,
    name: "aot_agent",
    model: :fast,
    profile: :standard,
    search_style: :dfs,
    require_explicit_answer: true
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.AoTAgent)
{:ok, result} = MyApp.AoTAgent.explore_sync(pid, "Compare three migration options and pick one.")
```

## Tree-of-Thoughts Recipe (`Jido.AI.ToTAgent`)

Use when you need branching search across multiple candidate paths.

```elixir
defmodule MyApp.ToTAgent do
  use Jido.AI.ToTAgent,
    name: "tot_agent",
    model: :fast,
    branching_factor: 3,
    max_depth: 4,
    top_k: 3,
    max_nodes: 100
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.ToTAgent)
{:ok, result} = MyApp.ToTAgent.explore_sync(pid, "Generate three implementation options with tradeoffs.")

best_answer = Jido.AI.Reasoning.TreeOfThoughts.Result.best_answer(result)
top_two = Jido.AI.Reasoning.TreeOfThoughts.Result.top_candidates(result, 2)
```

ToT returns a structured map (`best`, `candidates`, `termination`, `tree`, `usage`, `diagnostics`).

## Graph-of-Thoughts Recipe (`Jido.AI.GoTAgent`)

Use when you need synthesis across multiple perspectives.

```elixir
defmodule MyApp.GoTAgent do
  use Jido.AI.GoTAgent,
    name: "got_agent",
    model: :fast,
    max_nodes: 20,
    max_depth: 5,
    aggregation_strategy: :synthesis
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.GoTAgent)
{:ok, result} = MyApp.GoTAgent.explore_sync(pid, "Synthesize one plan from product, engineering, and support viewpoints.")
```

## TRM Recipe (`Jido.AI.TRMAgent`)

Use when you want recursive iterative improvement until confidence is high enough.

```elixir
defmodule MyApp.TRMAgent do
  use Jido.AI.TRMAgent,
    name: "trm_agent",
    model: :fast,
    max_supervision_steps: 5,
    act_threshold: 0.9
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.TRMAgent)
{:ok, result} = MyApp.TRMAgent.reason_sync(pid, "Improve this incident response draft until it is production-ready.")
```

## Adaptive Recipe (`Jido.AI.AdaptiveAgent`)

Use when task shape varies and you want automatic strategy selection.

```elixir
defmodule MyApp.AdaptiveAgent do
  use Jido.AI.AdaptiveAgent,
    name: "adaptive_agent",
    model: :capable,
    default_strategy: :react,
    available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm]
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.AdaptiveAgent)
{:ok, result} = MyApp.AdaptiveAgent.ask_sync(pid, "Pick the best strategy and propose a migration plan with one backup.")
```

## Strategy Method Cheatsheet

- ReAct: `ask_sync/3`
- Chain-of-Draft: `draft_sync/3`
- Chain-of-Thought: `think_sync/3`
- Algorithm-of-Thoughts: `explore_sync/3`
- Tree-of-Thoughts: `explore_sync/3`
- Graph-of-Thoughts: `explore_sync/3`
- TRM: `reason_sync/3`
- Adaptive: `ask_sync/3`

## Failure Mode: Wrong Method Name For Strategy

Symptom:
- `undefined function` when calling strategy sync methods

Fix:
- use the method generated by that macro (`draft_sync`, `think_sync`, `explore_sync`, `reason_sync`, or `ask_sync`)
- verify agent module uses the intended strategy macro

## Failure Mode: Strategy Choice Causes Poor Latency/Quality

Symptom:
- high latency with no quality gain, or low quality with short latency

Fix:
- move from `ToT`/`GoT` to `CoT` or `CoD` for linear tasks
- move from `CoT` to `ReAct` when tools are required
- constrain Adaptive with `available_strategies`

## Defaults You Should Know

- ReAct max iterations default: `10`
- AoT defaults: `profile: :standard`, `search_style: :dfs`, `temperature: 0.0`, `max_tokens: 2048`, `require_explicit_answer: true`
- ToT defaults include `top_k: 3`, `min_depth: 2`, `max_nodes: 100`, `max_tool_round_trips: 3`
- GoT defaults include `max_nodes: 20`, `max_depth: 5`, `aggregation_strategy: :synthesis`
- TRM defaults include `max_supervision_steps: 5`, `act_threshold: 0.9`
- Adaptive defaults include `default_strategy: :react`, `available_strategies: [:cod, :cot, :react, :tot, :got, :trm]`

## Next

- [Strategy Selection Playbook](strategy_selection_playbook.md)
- [First Agent](first_react_agent.md)
- [Strategy Internals](../developer/strategy_internals.md)
