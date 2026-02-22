# [P1] LLMResponse helper functions crash when `result` tuple payload is not a map/turn

## Summary
`extract_tool_calls/1` and `tool_call?/1` assume `data.result` is `{:ok, map_or_turn}` and call `Turn.from_result_map/1`. If payload is non-map (for example string), both helpers raise `FunctionClauseError`.

Severity: `P1`  
Type: `logic`, `api`

## Impact
Malformed or legacy signal payloads can crash helper callers instead of returning safe defaults.

## Evidence
- Helper path pipes directly into `Turn.from_result_map/1`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/signals/llm_response.ex:27` and `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/signals/llm_response.ex:39`.
- `Turn.from_result_map/1` only matches map/turn: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/turn.ex:105`.

Observed validation command (2026-02-21):
```bash
mix run -e '
sig = %{type: "ai.llm.response", data: %{result: {:ok, "plain"}}}
_ = Jido.AI.Signal.LLMResponse.extract_tool_calls(sig)
'
```

Observed output:
```text
** (FunctionClauseError) no function clause matching in Jido.AI.Turn.from_result_map/1
```

## Reproduction / Validation
1. Build `ai.llm.response` signal map with `result: {:ok, "plain"}`.
2. Call `extract_tool_calls/1` or `tool_call?/1`.
3. Observe crash.

## Expected vs Actual
Expected: helper returns `[]` / `false` for unsupported payload shapes.  
Actual: helper crashes.

## Why This Is Non-Idiomatic (if applicable)
Signal helper APIs are typically defensive and shape-tolerant to isolate callers from envelope drift.

## Suggested Fix
Add guard clauses for tuple payload shape and fallback safely on non-map `{:ok, payload}` values.

## Acceptance Criteria
- [ ] Non-map `{:ok, payload}` does not raise in helper functions.
- [ ] Helpers return safe defaults for unsupported shapes.
- [ ] Add tests for malformed payload variants.

## Labels
- `priority:P1`
- `type:logic`
- `type:api`
- `area:signals`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/signals/llm_response.ex`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/turn.ex`
