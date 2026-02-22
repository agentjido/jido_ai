# [P0] Retrieval ETS table bootstrap is race-prone under concurrent first writes

## Summary
`Retrieval.Store.ensure_table!/0` uses non-atomic `whereis` + `new` and is invoked from `upsert/2`. Concurrent first writes trigger ETS creation races and table identifier errors.

Severity: `P0`  
Type: `race`, `logic`

## Impact
Concurrent memory upserts can fail unexpectedly during service warm-up or burst traffic.

## Evidence
- Non-atomic table creation: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/retrieval/store.ex:106`.
- Hot path invocation from `upsert/2`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/retrieval/store.ex:20`.

Observed validation command (2026-02-21):
```bash
mix run -e '
alias Jido.AI.Retrieval.Store
case :ets.whereis(:jido_ai_retrieval_store) do :undefined -> :ok; tid -> :ets.delete(tid) end
results = 1..120 |> Enum.map(fn i -> Task.async(fn ->
  try do Store.upsert("ns", %{id: "id-#{i}", text: "hello"}); :ok rescue e -> {:error, Exception.message(e)} end
end) end) |> Enum.map(&Task.await(&1, 10_000))
IO.inspect(Enum.frequencies(results))
'
```

Observed output:
```text
%{
  :ok => 98,
  {:error, "... table name already exists ..."} => 20,
  {:error, "... table identifier does not refer to an existing ETS table ..."} => 2
}
```

## Reproduction / Validation
1. Delete retrieval ETS table.
2. Launch concurrent `upsert/2` calls.
3. Observe intermittent `ArgumentError` ETS failures.

## Expected vs Actual
Expected: first-use upserts are safe and idempotent under concurrency.  
Actual: concurrent writers can crash on table initialization race.

## Why This Is Non-Idiomatic (if applicable)
Concurrent bootstrap of shared ETS resources should tolerate already-created table races as normal operation.

## Suggested Fix
Same pattern as quota store: robust idempotent table creation or startup-time ownership in supervised process.

## Acceptance Criteria
- [ ] Concurrent first upserts do not raise ETS creation errors.
- [ ] Retrieval store behaves deterministically under load.
- [ ] Add concurrency regression test for retrieval bootstrap.

## Labels
- `priority:P0`
- `type:race`
- `type:logic`
- `area:quality-quota`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/retrieval/store.ex`
