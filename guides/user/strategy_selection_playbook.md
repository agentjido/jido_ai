# Strategy Selection Playbook

You need to choose a strategy before building agents at scale.

After this guide, you can select CoT, ReAct, ToT, GoT, TRM, or Adaptive with explicit tradeoffs.

## Strategy Matrix

| Strategy | Use It For | Avoid It For | Agent Macro |
|---|---|---|---|
| CoT | Linear reasoning, clear step decomposition | Heavy tool orchestration | `Jido.AI.CoTAgent` |
| ReAct | Tool calls + reasoning loop | Purely static problems | `Jido.AI.Agent` |
| ToT | Branching search and planning | Low-latency simple Q&A | `Jido.AI.ToTAgent` |
| GoT | Multi-perspective synthesis | Small deterministic tasks | `Jido.AI.GoTAgent` |
| TRM | Iterative improvement / recursive refinement | Fast one-pass answers | `Jido.AI.TRMAgent` |
| Adaptive | Mixed workloads where task type varies | Hard real-time deterministic behavior | `Jido.AI.AdaptiveAgent` |

## Fast Default Recommendation

- Start with `ReAct` if tools matter.
- Start with `CoT` if reasoning is linear and tool-free.
- Use `Adaptive` only when workload shape varies significantly.

## Runnable Baseline: Adaptive Agent

```elixir
defmodule MyApp.SmartAgent do
  use Jido.AI.AdaptiveAgent,
    name: "smart_agent",
    model: :capable,
    default_strategy: :react,
    available_strategies: [:cot, :react, :tot, :got, :trm]
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
- Move from `CoT` to `ReAct` when tools are essential
- Constrain Adaptive with `available_strategies`

## Defaults You Should Know

- `Adaptive` default strategy: `:react`
- `Adaptive` default available strategies: `[:cot, :react, :tot, :got, :trm]`
- `TRM` default `max_supervision_steps`: `5`

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
