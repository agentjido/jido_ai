# 02_18: Request admission events

The [Agent examples](agent.ex)
and [nine example cases](../../../test/examples/02_requests/02_18_admission/02_18_admission_test.exs)
use the core Agent, Router and Session Plugin. The shared model server records
each HTTP request.

```sh
mix test --include example test/examples/02_requests/02_18_admission/02_18_admission_test.exs
```

A rejected request reports the canonical method of its declared profile.
Public CoT and CoD macros, all eight option adapters, custom routes and a
misleading `ai.react.query` route use the same binding lookup. Signal fields
that claim another method or profile cannot change the event identity.

The event retains the request ID, raw error and sequence zero. It uses the
request ID as its synthetic run ID because admission did not create a run.
Policy, busy, invalid request options and invalid caller context all close
the rejected stream. A duplicate ID does not close the original stream.
The original request still completes once, with its own method and result.
Rejected input does not create a request record or make a model call.

A missing Session Plugin retains the declaration error. A route without an
AI binding reports `unknown`. It does not infer a method from the Signal name.
Standalone `Stream.failed_event/3` and `cancelled_event/3` accept an explicit
method and retain their existing `react` default when no method is supplied.

The Session reads the Agent definition before admission, in place of the
previous Plugin-state read. Both that read and the core call use the supplied
admission timeout. This is a bound for each call, not one combined elapsed-time
budget. Errors from a missing or stopped server retain core call semantics.
An atomic guarantee across a concurrent definition upgrade remains part of
the core live-upgrade gate. The test does not claim that guarantee.

This is partial evidence for PR 262 terminal failures and PR 314 canonical
events. Durable delivery, all worker replacements, state conversion and the
root package, consumer, minimum-runtime and rollback checks remain open.
