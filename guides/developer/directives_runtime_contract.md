# Directives Runtime Contract

You need to modify runtime side effects (LLM/tool/embed/lifecycle) without breaking strategy semantics.

After this guide, you can add directive behavior while preserving correlation, retries, and signal contracts.

## Core Directives

- `Jido.AI.Directive.LLMStream`
- `Jido.AI.Directive.LLMGenerate`
- `Jido.AI.Directive.LLMEmbed`
- `Jido.AI.Directive.ToolExec`
- `Jido.AI.Directive.EmitToolError`
- `Jido.AI.Directive.EmitRequestError`

## Contract Rules

- Directives describe work; they do not own strategy state transitions.
- Every side effect emits a matching signal with correlation IDs.
- Retry/timeout metadata must remain explicit in directive fields.
- Errors must resolve to structured signal payloads, not silent drops.

## Example: ToolExec Fields That Matter

```elixir
%Jido.AI.Directive.ToolExec{
  id: "tool_call_1",
  tool_name: "multiply",
  arguments: %{a: 2, b: 3},
  timeout_ms: 15_000,
  max_retries: 1,
  retry_backoff_ms: 200,
  request_id: "req_123",
  iteration: 2
}
```

## Failure Mode: Deadlock Waiting For Tool Result

Symptom:
- strategy remains in `:awaiting_tool`

Fix:
- ensure runtime always emits either `ai.tool.result` or `EmitToolError`
- preserve `id` correlation from tool call to result signal

## Defaults You Should Know

- `LLM*` directives support either direct `model` or `model_alias`
- `ToolExec` retries default to `0` unless set
- metadata fields are designed for observability and debugging

## When To Use / Not Use

Use this guide when:
- changing execution semantics, timeout policy, or signal emission behavior

Do not use this guide when:
- changing only strategy heuristics or prompts

## Next

- [Signals, Namespaces, Contracts](signals_namespaces_contracts.md)
- [Security And Validation](security_and_validation.md)
- [Error Model And Recovery](error_model_and_recovery.md)
