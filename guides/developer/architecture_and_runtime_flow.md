# Architecture and runtime Flow

This guide shows how one AI request moves through Jido AI V3.

## Runtime Flow

1. An Agent receives a routed query signal.
2. Jido AI prepares the model, context, visible tools, output contract, and
   limits.
3. `Jido.AI.Flow.Reason` selects the Flow returned by `Agent.graph/0`.
4. `CallModel` produces a portable `ModelOutcome`.
5. `InterpretOutcome` produces an `AgentDecision`.
6. An Invoke node uses one trusted mapper to select the next model, review,
   tool, or terminal executable.
7. Tool planning adds only tools declared by the Agent.
8. The graph returns one `Jido.AI.Result`.
9. For a routed turn, core Jido validates and commits candidate Agent state.

There is no private Jido AI Directive executor in V3. Core Jido Directives are
still valid for post-commit effects. Model and tool work that must finish before
the Agent commit runs through Actions and Flows.

The Agent behavior is the Flow graph. `AgentServer` can host and resume work,
but it does not define AI behavior.

```text
prepared request
      |
      v
  CallModel --------> ModelOutcome
                          |
                          v
                  InterpretOutcome
                          |
                          v
                    AgentDecision
                     /          \
                    v            v
              Complete       PlanTools
                                  |
                                  v
                              ToolPlan
                                  |
                                  v
                       tool nodes -> observe
                                  |
                                  +----> CallModel
```

## Main Boundaries

- `Jido.AI.Models` resolves optional application model aliases.
- `Jido.AI.Plugin` stores inert Agent graph configuration.
- `Jido.AI.Request` prepares inspectable input without model work.
- `Jido.AI.Flow.Reason` composes controls around the selected Agent graph.
- `Jido.AI.Flow.ReAct` is the default explicit AI graph.
- `Jido.AI.ModelOutcome`, `AgentDecision`, and `ToolPlan` are portable graph
  contracts.
- `Jido.AI.Actions.*` owns bounded model interpretation and planning work.
- `Jido.AI.Result` and `Jido.AI.Event` own public completion data.

## Minimal Trace Setup

```elixir
:telemetry.attach_many(
  "jido-ai-trace",
  [
    [:jido, :ai, :llm, :start],
    [:jido, :ai, :llm, :complete],
    [:jido, :ai, :tool, :start],
    [:jido, :ai, :tool, :complete]
  ],
  fn event, measurements, metadata, _ ->
    IO.inspect({event, measurements, metadata})
  end,
  nil
)
```

## Failure Triage

- Fix model selection and provider options at the ReqLLM request boundary.
- Fix tool input and output behavior in the Action or `Jido.Exec` call path.
- Fix branch selection in `InterpretOutcome`, `ExpandDecision`, or
  `ExpandTools`.
- Fix domain state validation and commit behavior in the Agent boundary.
- Fix behavior policy in the selected Agent graph.

## Compile-Cycle Triage

Use `mix xref` when one change recompiles more code than expected:

```bash
mix xref graph --format cycles --label compile-connected
mix xref graph --format stats --label compile-connected
mix xref graph --source lib/path_a.ex --sink lib/path_b.ex
mix xref graph --label compile --source lib/path_a.ex
```

Compile edges have the highest rebuild cost. Runtime edges have the lowest
compile-time cost.

## Next

- [Signals, Namespaces, Contracts](signals_namespaces_contracts.md)
- [Plugins And Actions Composition](plugins_and_actions_composition.md)
