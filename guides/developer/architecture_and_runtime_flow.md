# Architecture And Runtime Flow

This guide shows how one AI request moves through Jido AI V3.

## Runtime Flow

1. An Agent receives a routed query signal.
2. The AI route selects one validated `Jido.AI.Profile`.
3. `Jido.AI.Session` admits the request and stores its request record.
4. The common reasoning Flow runs the selected method.
5. AI Actions call ReqLLM and execute declared tools through `Jido.Exec`.
6. The Session records model, tool, usage, and terminal events.
7. The final candidate Agent state passes core validation and commits once.

There is no private Jido AI Directive executor in V3. Core Jido Directives are
still valid for post-commit effects. Model and tool work that must finish before
the Agent commit runs through Actions and Flows.

## Main Boundaries

- `Jido.AI.Models` resolves optional application model aliases.
- `Jido.AI.Profile`, `Jido.AI.DSL`, and `Jido.AI.Authoring` define inert AI configuration.
- `Jido.AI.Session` owns live request admission, work, events, and completion.
- `Jido.AI.Reasoning` selects and runs one reasoning method.
- `Jido.AI.Actions.*` owns model, tool, planning, retrieval, and quota operations.
- `Jido.AI.Signal.*` owns typed public event data.

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
- Fix request ownership, cancellation, and completion in `Jido.AI.Session`.
- Fix domain state validation and commit behavior in the Agent boundary.
- Fix reasoning policy in the selected method implementation.

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

- [Strategy Internals](strategy_internals.md)
- [Signals, Namespaces, Contracts](signals_namespaces_contracts.md)
- [Plugins And Actions Composition](plugins_and_actions_composition.md)
