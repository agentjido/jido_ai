# Signals, Namespaces, Contracts

You need stable event names and payload semantics across strategies, runtime, and tooling.

After this guide, you can add signals without namespace drift.

## Canonical Namespace Helpers

`Jido.AI.Namespaces` centralizes runtime strings like:

- strategy queries: `ai.react.query`, `ai.cot.query`, `ai.tot.query`, `ai.got.query`, `ai.trm.query`, `ai.adaptive.query`
- lifecycle: `ai.request.started`, `ai.request.completed`, `ai.request.failed`, `ai.request.error`
- llm/tool/embed: `ai.llm.*`, `ai.tool.*`, `ai.embed.*`

Use helper functions (`react_query/0`, `tool_result/0`, etc.) instead of hard-coded strings.

## Signal Modules

`Jido.AI.Signal` defines typed signal structs such as:
- `Signal.LLMResponse`
- `Signal.LLMDelta`
- `Signal.ToolResult`
- `Signal.RequestError`
- `Signal.Usage`

## Example: Emit Standard Request Error

```elixir
{:ok, sig} = Jido.AI.Signal.RequestError.new(%{
  request_id: "req-1",
  reason: :busy,
  message: "Agent is processing another request"
})
```

## Failure Mode: Namespace Drift

Symptom:
- strategy route never fires

Fix:
- use `Jido.AI.Namespaces` helpers everywhere signals are created
- keep `signal_routes/1` aligned with canonical names

## Defaults You Should Know

- `Jido.AI.Namespaces.all_signals/0` gives the canonical list
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
