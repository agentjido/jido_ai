# [P0] Cancel path can overwrite already-completed request state

## Summary
A cancellation event can mark a request as `:failed` even after it was already completed. This is a state-corruption race between completion and cancel handling.

Severity: `P0`  
Type: `race`, `logic`

## Impact
Completed requests can be retroactively marked failed, which breaks `ask/await` semantics and can misreport user-visible outcomes and downstream telemetry/signals.

## Evidence
- Cancel handler always calls `Request.fail_request/3` when `request_id` exists: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agent.ex:421`.
- `Request.fail_request/3` overwrites status unconditionally, including completed requests: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/request.ex:403`.
- `Request.complete_request/4` and `Request.fail_request/3` both mutate the same `state.requests[request_id]` slot with no state guard: `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/request.ex:378` and `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/request.ex:403`.

Observed validation command (2026-02-21):
```bash
mix run -e '
agent = %{state: %{requests: %{"req-1" => %{status: :pending, result: nil, error: nil, inserted_at: 0, completed_at: nil}}, completed: false, last_answer: nil}}
agent = Jido.AI.Request.complete_request(agent, "req-1", "done")
agent = Jido.AI.Request.fail_request(agent, "req-1", {:cancelled, :user_cancelled})
IO.inspect(get_in(agent.state, [:requests, "req-1"]), label: "request_after_complete_then_fail")
'
```

Observed output:
```text
request_after_complete_then_fail: %{status: :failed, result: "done", error: {:cancelled, :user_cancelled}, ...}
```

## Reproduction / Validation
1. Start from a request in `:pending` state.
2. Mark it completed.
3. Invoke cancellation path (`Request.fail_request/3` via `on_after_cmd` cancel branch).
4. Observe status transitions to `:failed` despite prior completion.

## Expected vs Actual
Expected: once request status is `:completed`, cancel should be ignored or reported as no-op for that request.  
Actual: cancel force-overwrites request status to `:failed`.

## Why This Is Non-Idiomatic (if applicable)
Elixir state machines typically enforce monotonic terminal transitions (`:completed`/`:failed`) instead of allowing terminal-state regression without guards.

## Suggested Fix
Guard cancellation failure transition with current status check:
- Only mark failed when current status is `:pending`.
- Keep completion terminal and idempotent.
- Emit explicit `:ignored_cancel`/`already_completed` metadata when cancel arrives late.

## Acceptance Criteria
- [ ] Completed request cannot transition to failed due to late cancel.
- [ ] Cancel during pending still marks failed/cancelled.
- [ ] Add regression test covering complete-then-cancel ordering.

## Labels
- `priority:P0`
- `type:race`
- `type:logic`
- `area:core`

## Related Files
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/agent.ex`
- `/Users/mhostetler/Source/Jido/jido_ai/lib/jido_ai/request.ex`
