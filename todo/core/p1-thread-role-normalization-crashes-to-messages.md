# [P1] Thread accepts roles that `to_messages/2` cannot project

## Summary
`Thread.normalize_role/1` accepts `:developer` and `:function`, but `entry_to_message/1` has no matching clauses for those roles. The thread can be built successfully and then crash at projection time.

Severity: `P1`  
Type: `logic`, `api`

## Impact
Valid-looking thread data causes runtime `FunctionClauseError` when converting to ReqLLM message format. This is a hard failure on normal flow (`append_messages` -> `to_messages`).

## Evidence
- Role normalization accepts additional roles: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex:432`.
- Message projection clauses only handle `:user`, `:assistant`, `:tool`, `:system`: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex:340`.

Observed validation command (2026-02-21):
```bash
mix run -e '
thread = Jido.AI.Thread.new() |> Jido.AI.Thread.append_messages([%{role: "developer", content: "x"}])
_ = Jido.AI.Thread.to_messages(thread)
'
```

Observed output:
```text
** (FunctionClauseError) no function clause matching in Jido.AI.Thread.entry_to_message/1
```

## Reproduction / Validation
1. Append an imported message with `role: "developer"`.
2. Call `Thread.to_messages/2`.
3. Observe crash from unmatched role clause.

## Expected vs Actual
Expected: unsupported roles are rejected early or mapped to supported ReqLLM roles.  
Actual: unsupported roles are stored and crash later.

## Why This Is Non-Idiomatic (if applicable)
The validation boundary should reject invalid states before persistence. Deferred crashes during projection violate fail-fast data normalization patterns.

## Suggested Fix
- Restrict `normalize_role/1` to roles supported by projection.
- Or add explicit projection rules for all accepted roles.
- Return `{:error, :unsupported_role}` for unknown imports.

## Acceptance Criteria
- [ ] `append_messages/2` cannot produce entries that crash `to_messages/2`.
- [ ] Unsupported role input is rejected with explicit error.
- [ ] Add test for `developer`/`function` role import behavior.

## Labels
- `priority:P1`
- `type:logic`
- `type:api`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/thread.ex`
