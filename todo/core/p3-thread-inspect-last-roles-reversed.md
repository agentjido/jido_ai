# [P3] `Inspect` output for thread "last" roles is reversed

## Summary
`Jido.AI.Thread` stores entries in reverse order for append efficiency, but `Inspect` calculates `last_roles` with `Enum.take(-2)` on the reversed list without reordering. Debug output reports roles in reverse chronology.

Severity: `P3`  
Type: `logic`, `observability`

## Impact
Debug output is misleading during incident triage and local debugging.

## Evidence
- Reverse-order internal storage is documented: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex:82`.
- Inspect implementation derives "last" directly from `thread.entries`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex:447`.

Observed validation command (2026-02-21):
```bash
mix run -e '
thread = Jido.AI.Thread.new() |> Jido.AI.Thread.append_user("u") |> Jido.AI.Thread.append_assistant("a")
IO.puts(inspect(thread))
'
```

Observed output:
```text
#Thread<2 entries, last: [:assistant, :user]>
```

## Reproduction / Validation
1. Append `:user` then `:assistant`.
2. Inspect thread.
3. Observe reversed "last" role ordering.

## Expected vs Actual
Expected: `last` roles in chronological order (oldest to newest in displayed slice).  
Actual: `last` roles are newest-first from internal storage order.

## Why This Is Non-Idiomatic (if applicable)
Debug representations should match user mental model and documented chronology, especially when module docs highlight projection order.

## Suggested Fix
Reverse before taking last roles for inspect view, or explicitly label order as reverse chronology.

## Acceptance Criteria
- [ ] Inspect `last` roles reflect chronological order.
- [ ] Add unit test for inspect output ordering.

## Labels
- `priority:P3`
- `type:logic`
- `type:observability`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex`
