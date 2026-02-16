# Strategy Internals

You want to extend strategy behavior without breaking machine/runtime contracts.

After this guide, you can safely modify strategy adapters and preserve signal/directive semantics.

## Strategy Modules

- `Jido.AI.Strategies.ReAct`
- `Jido.AI.Strategies.ChainOfThought`
- `Jido.AI.Strategies.TreeOfThoughts`
- `Jido.AI.Strategies.GraphOfThoughts`
- `Jido.AI.Strategies.TRM`
- `Jido.AI.Strategies.Adaptive`

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

- most strategies default model to `anthropic:claude-haiku-4-5`
- request error routing is standardized via `ai.request.error`
- Adaptive delegates to selected strategy and can re-evaluate on new prompts

## When To Use / Not Use

Use this when:
- adding strategy features or new control signals

Do not use this when:
- you only need tool definitions or plugin-level changes

## Next

- [Architecture And Runtime Flow](architecture_and_runtime_flow.md)
- [Directives Runtime Contract](directives_runtime_contract.md)
- [Configuration Reference](configuration_reference.md)
