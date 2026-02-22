# [P2] Tool execution telemetry emits native monotonic `duration` while contract requires `duration_ms`

## Summary
Tool execute telemetry uses `System.monotonic_time()` deltas directly in `duration`, while `Jido.AI.Observe` standardizes required measurements around `duration_ms`. This produces inconsistent units and leaves `duration_ms` at default `0`.

Severity: `P2`  
Type: `observability`, `logic`

## Impact
Telemetry consumers receive misleading timing data (`duration_ms: 0`) and a non-standard field with native-time units.

## Evidence
- Required measurement keys include `:duration_ms`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/observe.ex:31`.
- Tool execute stop emits `%{duration: duration}` from monotonic delta: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/turn.ex:578` and `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/turn.ex:597`.

Observed validation command (2026-02-21):
```bash
mix run -e '
handler = "audit-turn-telemetry-#{System.unique_integer([:positive])}"
:telemetry.attach(handler, [:jido, :ai, :tool, :execute, :stop], fn _e, m, _md, _ -> IO.inspect(m) end, nil)
_ = Jido.AI.Turn.execute_module(Jido.AI.Examples.Tools.ConvertTemperature, %{value: 0.0, from: "celsius", to: "fahrenheit"}, %{observability: %{emit_telemetry?: true}})
:telemetry.detach(handler)
'
```

Observed output excerpt:
```text
%{duration: 58696250, duration_ms: 0, ...}
```

## Reproduction / Validation
1. Attach telemetry handler to `[:jido, :ai, :tool, :execute, :stop]`.
2. Execute any tool via `Turn.execute_module/4`.
3. Inspect measurement map.

## Expected vs Actual
Expected: duration published in `duration_ms` with millisecond units (and optional compatible alias if needed).  
Actual: raw native-unit `duration` is emitted; `duration_ms` remains zero-filled.

## Why This Is Non-Idiomatic (if applicable)
Elixir telemetry conventions typically use explicit unit-bearing keys (like `_ms`) and avoid raw-unit ambiguity.

## Suggested Fix
Convert monotonic delta to milliseconds and emit as `duration_ms`:
- `System.convert_time_unit(duration, :native, :millisecond)`
- Keep/phase out legacy `duration` field with explicit migration note.

## Acceptance Criteria
- [ ] Tool execute telemetry includes accurate `duration_ms`.
- [ ] No consumer receives `duration_ms: 0` for non-zero executions.
- [ ] Add telemetry contract test for unit correctness.

## Labels
- `priority:P2`
- `type:observability`
- `type:logic`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/turn.ex`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/observe.ex`
