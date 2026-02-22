# [P1] Quota counter updates are non-atomic and can lose increments

## Summary
`add_usage/3` reads current value (`get/1`), computes updated counts, then writes via `:ets.insert/2`. Concurrent callers overwrite each other because this is a read-modify-write race.

Severity: `P1`  
Type: `race`, `logic`

## Impact
Quota enforcement can undercount requests/tokens, weakening budget protections and policy checks.

## Evidence
- Read-modify-write flow: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex:22` and `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex:37`.

Observed validation command (2026-02-21):
```bash
mix run -e '
alias Jido.AI.Quota.Store
Store.ensure_table!(); Store.reset("race_scope_no_bootstrap")
tasks = for _ <- 1..500, do: Task.async(fn -> Store.add_usage("race_scope_no_bootstrap", 1, 60_000) end)
Enum.each(tasks, &Task.await(&1, 15_000))
IO.inspect(Store.get("race_scope_no_bootstrap"))
'
```

Observed output:
```text
%{requests: 489, total_tokens: 489, ...}   # expected 500
```

## Reproduction / Validation
1. Pre-create table to avoid bootstrap race.
2. Reset one scope.
3. Run high-concurrency `add_usage/3` operations.
4. Compare final count with expected increments.

## Expected vs Actual
Expected: final counters equal total operations.  
Actual: counters are lower due to lost updates.

## Why This Is Non-Idiomatic (if applicable)
Counter-like shared state in ETS should use atomic operations (`:ets.update_counter/4`) rather than non-atomic read-modify-write.

## Suggested Fix
Use atomic ETS counters (or serialized ownership process) for request/token increments; isolate window reset logic with CAS-like guard.

## Acceptance Criteria
- [ ] Concurrent increments preserve all updates.
- [ ] Token/request counts match expected totals under stress.
- [ ] Add stress test for concurrent increments.

## Labels
- `priority:P1`
- `type:race`
- `type:logic`
- `area:quality-quota`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex`
