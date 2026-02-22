# [P0] Quota ETS table bootstrap is race-prone and raises under concurrent first access

## Summary
`Quota.Store.ensure_table!/0` uses a non-atomic `whereis` + `new` sequence. Concurrent first-use callers race and raise `ArgumentError` (`table name already exists`) and related ETS errors.

Severity: `P0`  
Type: `race`, `logic`

## Impact
First burst of concurrent quota operations can crash tasks and fail request handling.

## Evidence
- Non-atomic table creation: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex:105`.
- `add_usage/3` calls `ensure_table!` on hot path: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex:18`.

Observed validation command (2026-02-21):
```bash
mix run -e '
alias Jido.AI.Quota.Store
case :ets.whereis(:jido_ai_quota_store) do :undefined -> :ok; tid -> :ets.delete(tid) end
results = 1..120 |> Enum.map(fn _ -> Task.async(fn ->
  try do Store.ensure_table!(); :ok rescue e -> {:error, Exception.message(e)} end
end) end) |> Enum.map(&Task.await(&1, 10_000))
IO.inspect(Enum.frequencies(results))
'
```

Observed output:
```text
%{:ok => 104, {:error, "... table name already exists ..."} => 16}
```

## Reproduction / Validation
1. Delete ETS table.
2. Launch many concurrent `ensure_table!/0` calls.
3. Observe raised `ArgumentError` from ETS.

## Expected vs Actual
Expected: table initialization is idempotent and safe under concurrency.  
Actual: concurrent callers raise.

## Why This Is Non-Idiomatic (if applicable)
ETS named-table creation should treat "already exists" as expected concurrent outcome, not fatal path.

## Suggested Fix
Wrap `:ets.new/2` in `try/rescue` (or `catch`) and treat already-exists as success, or create table once in supervised process startup.

## Acceptance Criteria
- [ ] Concurrent first-use no longer raises.
- [ ] `add_usage/3` succeeds under bootstrap contention.
- [ ] Add concurrency regression test for bootstrap.

## Labels
- `priority:P0`
- `type:race`
- `type:logic`
- `area:quality-quota`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/quota/store.ex`
