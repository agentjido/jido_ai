# Strategy Internals

You want to extend strategy behavior without breaking machine/runtime contracts.

After this guide, you can safely modify strategy adapters and preserve signal/directive semantics.

## Strategy Modules

- `Jido.AI.Reasoning.ReAct.Strategy`
- `Jido.AI.Reasoning.ChainOfThought.Strategy`
- `Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy`
- `Jido.AI.Reasoning.TreeOfThoughts.Strategy`
- `Jido.AI.Reasoning.GraphOfThoughts.Strategy`
- `Jido.AI.Reasoning.TRM.Strategy`
- `Jido.AI.Reasoning.Adaptive.Strategy`

Each strategy acts as a thin adapter around a state machine and implements:
- `action_spec/1`
- `signal_routes/1`
- `snapshot/2`
- `init/2`
- `cmd/3`

## Extension Pattern

1. Add new action atom and schema in `@action_specs`.
2. Route incoming signal in `signal_routes/1`.
3. Translate to machine message in instruction processing.
4. Lift machine directives into runtime directives.
5. Keep state updates inside strategy state (`__strategy__`).

## Example: New Strategy Signal Route

```elixir
@impl true
def signal_routes(_ctx) do
  [
    {"ai.react.query", {:strategy_cmd, @start}},
    {"ai.llm.response", {:strategy_cmd, @llm_result}},
    {"ai.request.error", {:strategy_cmd, @request_error}}
  ]
end
```

## Failure Mode: Contract Drift Between Strategy And Machine

Symptom:
- machine receives unknown event shape
- request never completes

Fix:
- keep translation layer explicit and typed
- update both strategy instruction mapping and machine update clauses together

## Defaults You Should Know

- most strategies default model alias to `:fast` (resolved via `Jido.AI.resolve_model/1`)
- request error routing is standardized via `ai.request.error`
- Adaptive delegates to selected strategy and can re-evaluate on new prompts

## Algorithm-of-Thoughts Specific Internals

`Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy` is single-query by design:

- one `Directive.LLMStream` call per request
- machine flow is `idle -> exploring -> completed/error`
- query signal is `ai.aot.query`
- plugin run signal is `reasoning.aot.run`

AoT result contract is structured:

- `answer`
- `found_solution?`
- `first_operations_considered`
- `backtracking_steps`
- `raw_response`
- `usage`
- `termination` (`reason`, `status`, `duration_ms`)
- `diagnostics`

## Tree-of-Thoughts Specific Internals

`Jido.AI.Reasoning.TreeOfThoughts.Strategy` now enforces a structured result contract from the machine:

- `snapshot.result` is a map (best/candidates/termination/tree/usage/diagnostics)
- CLI adapters should project `result.best.content` for human-readable answer text
- full structured payload should be preserved in metadata (`tot_result`)

ToT parser flow is JSON-first with regex fallback:

1. Parse strict JSON for generation/evaluation outputs
2. Fallback to regex parsing
3. Retry once (configurable) with repair prompt
4. Emit structured diagnostics on terminal parse failure

ToT tool orchestration is strategy-managed:

- `ai.tool.result` signals (including error envelopes) are routed back into the strategy
- machine progression pauses during tool rounds
- tool effects are applied in original tool-call order after the round is complete
- follow-up LLM calls are issued with assistant tool-call + tool messages
- follow-up tool messages preserve original tool-call order
- round trips are bounded by `max_tool_round_trips`

## When To Use / Not Use

Use this when:
- adding strategy features or new control signals

Do not use this when:
- you only need tool definitions or plugin-level changes

## Next

- [Architecture And Runtime Flow](architecture_and_runtime_flow.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Configuration Reference](configuration_reference.md)
