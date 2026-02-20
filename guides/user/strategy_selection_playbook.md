# Strategy Selection Playbook

You need to choose a strategy before building agents at scale.

After this guide, you can select CoD, CoT, ReAct, AoT, ToT, GoT, TRM, or Adaptive with explicit tradeoffs.

## Strategy Matrix

| Strategy | Use It For | Avoid It For | Agent Macro |
|---|---|---|---|
| CoD | Token-efficient linear reasoning with concise drafts | Deep branching exploration | `Jido.AI.CoDAgent` |
| CoT | Linear reasoning, clear step decomposition | Heavy tool orchestration | `Jido.AI.CoTAgent` |
| ReAct | Tool calls + reasoning loop | Purely static problems | `Jido.AI.Agent` |
| AoT | One-pass algorithmic exploration with explicit final answer | Deep multi-round search orchestration | `Jido.AI.AoTAgent` |
| ToT | Branching search and planning | Low-latency simple Q&A | `Jido.AI.ToTAgent` |
| GoT | Multi-perspective synthesis | Small deterministic tasks | `Jido.AI.GoTAgent` |
| TRM | Iterative improvement / recursive refinement | Fast one-pass answers | `Jido.AI.TRMAgent` |
| Adaptive | Mixed workloads where task type varies | Hard real-time deterministic behavior | `Jido.AI.AdaptiveAgent` |

## Fast Default Recommendation

- Start with `ReAct` if tools matter.
- Start with `CoD` if reasoning is linear and latency/cost matter.
- Use `CoT` when you need more verbose reasoning traces.
- Start with `AoT` when you want strict single-query reasoning with explicit `answer:` extraction.
- Use `Adaptive` only when workload shape varies significantly.

## Runnable Baseline: Adaptive Agent

```elixir
defmodule MyApp.SmartAgent do
  use Jido.AI.AdaptiveAgent,
    name: "smart_agent",
    model: :capable,
    default_strategy: :react,
    available_strategies: [:cod, :cot, :react, :tot, :got, :trm]
end

{:ok, pid} = Jido.AgentServer.start(agent: MyApp.SmartAgent)
{:ok, result} = MyApp.SmartAgent.ask_sync(pid, "Compare three migration plans and pick one")
```

## Failure Mode: Wrong Strategy For Task Shape

Symptom:
- High latency with little quality gain
- Excess iterations without better answers

Fix:
- Move from `ToT`/`GoT` to `CoT` for linear problems
- Move from `CoT` to `CoD` for lower latency/cost
- Move from `CoT` to `ReAct` when tools are essential
- Constrain Adaptive with `available_strategies`

## Defaults You Should Know

- `Adaptive` default strategy: `:react`
- `Adaptive` default available strategies: `[:cod, :cot, :react, :tot, :got, :trm]`
- `Adaptive` can include AoT via opt-in list update: `available_strategies: [:cod, :cot, :react, :aot, :tot, :got, :trm]`
- `AoT` defaults: `profile: :standard`, `search_style: :dfs`, `temperature: 0.0`, `max_tokens: 2048`, `require_explicit_answer: true`
- `TRM` default `max_supervision_steps`: `5`
- `ToT` defaults: `top_k: 3`, `min_depth: 2`, `max_nodes: 100`, `max_tool_round_trips: 3`

## ToT Flexible Config (SDK)

```elixir
defmodule MyApp.PlanningAgent do
  use Jido.AI.ToTAgent,
    name: "planning_agent",
    branching_factor: 3,
    max_depth: 4,
    top_k: 3,
    min_depth: 2,
    max_nodes: 120,
    max_duration_ms: 20_000,
    convergence_window: 2,
    min_score_improvement: 0.02,
    tools: [MyApp.Actions.WeatherLookup],
    max_tool_round_trips: 3
end
```

## When To Use / Not Use

Use this playbook when:
- You are choosing an architecture for new agents
- You are triaging quality/latency tradeoffs

Do not use this playbook when:
- You only need one known strategy already validated in production

## Next

- [First Agent](first_react_agent.md)
- [CLI Workflows](cli_workflows.md)
- [Strategy Internals](../developer/strategy_internals.md)
