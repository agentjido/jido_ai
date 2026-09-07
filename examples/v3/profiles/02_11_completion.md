# 02_11: Completion commit and failure

The [Agent and Plugin](../lib/examples/02_requests/02_11_completion/agent.ex),
[storage adapter](../lib/examples/02_requests/02_11_completion/store.ex), and
[11 integration tests](../test/examples/02_requests/02_11_completion_test.exs)
use the shared HTTP model mock and real core validation, commits and storage
callbacks.

```sh
mix test --include integration test/examples/02_requests/02_11_completion_test.exs
```

Core replies to an Agent call after the state commit. It then dispatches the
Directives. The AI request owner now observes that reply. It can detect a
failed completion commit without repeating model or tool work.

The example proves these cases:

- A Plugin can reject final state reduction, or produce state that exceeds
  the Agent limit. AI submits a failure record with no original tool effects.
  Tool execution and the rejected effect reduction occur only once. The Agent
  accepts a later request.
- An oversized answer becomes a small failure record. A new pending record
  reserves 512 string bytes for that failure. Completion and cancellation
  release those bytes. If full failure details do not fit, the stored error is
  `{:completion_failed, :details_elided}` and metadata is
  `%{completion: %{details_elided?: true}}`. The answer is not stored as success.
- Another Turn can fill the state to its exact byte limit while the model
  waits. The small failure still fits, and the other Turn's changes remain.
  If the reserve cannot fit at admission, no model work starts.
- A post-commit Directive failure preserves the committed answer. Core stops
  the remaining Directive batch. AI emits one completed event and does not
  repeat the effects. `Request.await` confirms the answer commit; it does not
  confirm that every post-commit Directive succeeded.
- A Plugin that denies every settlement causes one failed stream event with
  `committed?: false`. Await returns `{:error, {:completion_uncommitted, reason}}`.
  The actual stored request stays pending. A later explicit cancellation can
  update it without sending a second terminal stream event.
- A storage conflict produces the same explicit uncommitted boundary. AI does
  not submit another completion write against the stale revision.
- A storage adapter can save the answer and then return an indeterminate
  result or raise before returning its reply. Core stops the Agent. The stored
  answer can be loaded, but the pending Directives were not dispatched and AI
  did not repeat the tool or completion write. Await on the stopped PID reports
  `:agent_server_unavailable`.
- An earlier pending v3 record without the reserve field can be parsed and
  marked interrupted during activation. This is not v2 state conversion.

When the owner observes an unknown call or storage result before it stops, its
failure is `{:completion_uncertain, reason}` with `committed?: :unknown`.
Terminal delivery is not guaranteed after owner or Agent loss. Do not treat a
missing reply as proof that storage did not change.

The storage fixture selects the actual terminal request write from the core
checkpoint and counts completion attempts separately from observation writes.
Automatic Signal publication adds normal core commits. The tests still prove
one completion attempt and compare the restored revision with actual writes.

The storage adapter is an in-memory fault fixture. It exercises the real core
storage protocol; it is not durable disk storage. Full recovery, fresh-process
conversion, sink recovery, all cancellation/storage failures and durable
post-commit work remain open. The full migration cannot be inferred from these
completion checks.
