# Signals, Namespaces, Contracts

You need stable event names and payload semantics across strategies, runtime, and tooling.

After this guide, you can add signals without namespace drift.

## Canonical Signal Names

Signal names are stable string contracts:

- strategy queries:
  `ai.react.query`, `ai.cod.query`, `ai.cot.query`, `ai.aot.query`, `ai.tot.query`, `ai.got.query`, `ai.trm.query`, `ai.adaptive.query`
- plugin strategy runs:
  `reasoning.cod.run`, `reasoning.cot.run`, `reasoning.aot.run`, `reasoning.tot.run`, `reasoning.got.run`, `reasoning.trm.run`, `reasoning.adaptive.run`
- runtime emitted signals:
  `ai.request.started`, `ai.request.completed`, `ai.request.failed`, `ai.request.error`, `ai.llm.response`, `ai.llm.delta`, `ai.tool.result`, `ai.embed.result`, `ai.usage`, `ai.react.worker.event`

ReAct worker control/internal runtime signals (for worker orchestration) are separate from the public contracts above:
`ai.react.worker.start`, `ai.react.worker.cancel`, `ai.react.worker.runtime.event`, `ai.react.worker.runtime.done`, `ai.react.worker.runtime.failed`.

## Signal Modules

Typed signal modules define payload contracts and canonical signal types:

- `Jido.AI.Signal.RequestStarted` -> `ai.request.started`
- `Jido.AI.Signal.RequestCompleted` -> `ai.request.completed`
- `Jido.AI.Signal.RequestFailed` -> `ai.request.failed`
- `Jido.AI.Signal.RequestError` -> `ai.request.error`
- `Jido.AI.Signal.LLMResponse` -> `ai.llm.response`
- `Jido.AI.Signal.LLMDelta` -> `ai.llm.delta`
- `Jido.AI.Signal.ToolResult` -> `ai.tool.result`
- `Jido.AI.Signal.EmbedResult` -> `ai.embed.result`
- `Jido.AI.Signal.Usage` -> `ai.usage`
- `Jido.AI.Reasoning.ReAct.Signal` -> `ai.react.worker.event`

## Example: Emit Standard Request Error

```elixir
sig = Jido.AI.Signal.RequestError.new!(%{
  request_id: "req-1",
  reason: :busy,
  message: "Agent is processing another request"
})
```

## Failure Mode: Namespace Drift

Symptom:
- strategy route never fires

Fix:
- use canonical signal strings consistently everywhere signals are created
- keep `signal_routes/1` aligned with canonical names

## Defaults You Should Know

- canonical list lives in module type declarations (`Jido.AI.Signal.*`) and strategy/plugin route declarations (`signal_routes/1`, plugin `signal_types/0`)
- signal payload schemas should remain backward compatible when possible

## When To Use / Not Use

Use this guide when:
- adding or renaming signal types
- integrating external handlers for telemetry or routing

Do not use this guide when:
- changes are internal and do not alter signal contracts

## Next

- [Architecture And Runtime Flow](architecture_and_runtime_flow.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Observability Basics](../user/observability_basics.md)
