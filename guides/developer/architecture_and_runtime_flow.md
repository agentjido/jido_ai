# Architecture And Runtime Flow

You need a mental model of how a query moves through strategy, directives, signals, and runtime execution.

After this guide, you can trace one request end-to-end and debug failures at the correct layer.

## Runtime Flow

1. Agent receives query signal (for example `ai.react.query`).
2. Strategy (`Jido.AI.Reasoning.*.Strategy`) translates instruction into machine message.
3. Machine emits directives (`Jido.AI.Directive.*`).
4. Runtime executes directives (LLM, tools, embedding, emits lifecycle signals).
5. Signals (`Jido.AI.Signal.*`) route back into strategy commands.
6. Strategy updates state and eventually completes request.

## Key Boundaries

- Strategy: state transitions and orchestration policy
- Directive: side-effect intent only
- Runtime: side-effect execution and signal emission
- Signal: typed contract between runtime and strategy

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

## Failure Mode: Fixing Bugs In The Wrong Layer

Symptom:
- strategy logic changed to fix provider/network behavior

Fix:
- keep strategy pure and orchestration-focused
- fix provider behavior at the direct `ReqLLM` call-site
- fix execution semantics in directive runtime path

## Defaults You Should Know

- strategies store internal data in `agent.state.__strategy__`
- request lifecycle signals are standardized under `ai.request.*`
- canonical signal contracts are defined by `Jido.AI.Signal` and strategy routes

## Registry Lifecycle Guarantees

`Jido.AI.Skill.Registry` supports:

- explicit supervised startup via `start_link/1`
- lazy startup via `ensure_started/0` for call-site safety
- startup-order independence for library consumers

## When To Use / Not Use

Use this guide when:
- you are debugging execution flow or extending runtime behavior

Do not use this guide when:
- you only need to build and run an agent quickly

## Next

- [Strategy Internals](strategy_internals.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Signals, Namespaces, Contracts](signals_namespaces_contracts.md)
