# 14_05: Worker lifetime on native Sessions

[Agents](agent.ex) and
[tests](../../../test/examples/14_resume/14_05_worker_lifecycle/14_05_worker_lifecycle_test.exs) use the public
ReAct and CoT Agents. Both submit work to the native Session and common Flow.
ReAct holds a real tool. CoT holds a real model connection. The shared MockLLM
server supplies all model replies.

## Ownership and failure

Core owns the Session Plugin child. Session owns each request task. Core Exec
owns model and tool work under that task. A request starts execution after its
admission record commits. No separate AI worker Agent or event-forwarding loop
is needed.

The nine new cases prove these boundaries for both public methods:

- Task failure stops held work and commits one failed request. A later request
  succeeds on the same Agent. Late task results, task exit messages and runtime
  events cannot finish that later request.
- Session owner loss stops the request task and held work. The replacement
  owner marks the stored request interrupted, then accepts new work.
- Normal parent shutdown stops the Session, task and held work without retry.
- Wrong-run events, usage and failure metadata cannot change an active request.
  Old worker Signals cannot publish a forged result.

Task failure retains the public `:worker_crash` result. Request metadata now
also retains `error_type: :worker_task` and a portable `worker_exit_reason`.
The first failure check found that the native Session discarded that reason.
Known usage survives task failure. A held first CoT response has no observed
usage; this is not a claim about provider billing.

The ReAct tool receives the current tenant context. A separate file case sends
text and an uploaded file ID through the public Agent and the actual model
request. It proves the request path from PR 304. It does not upload file bytes
or prove every provider file format.

Session-owner loss differs from request-task loss. Its stored request recovers,
but the old volatile stream sink is not restored. These tests do not claim a
terminal event was delivered to that lost sink. Durable delivery and fresh-VM
Agent recovery remain separate requirements.

## Removed implementation layer

The four old internal ReAct/CoT Worker Agent and Worker Strategy modules are
removed. Their task loops and private `ai.*.worker.*` message protocol are
replaced by Session task ownership and canonical events. The old ReAct worker
test only called v2 Strategy callbacks with a stubbed model. The real file and
lifetime cases replace it.

Use public `ask`, `await`, request streams and Session cancellation. Internal
worker child tags, Strategy callback commands and worker PIDs are not v3 APIs.
The native Plugin child starts with its parent; request tasks start on demand.
Standalone stream adapters still accept an optional Task supervisor.

The old parent ReAct Strategy source remains outside the v3 acceptance build.
Its trace retention, active inspection, context lane/compaction, skill/resource
and state-conversion work must be mapped before that module can be retired.
Its old worker references and related root callback tests are migration work,
not supported v3 entry points. Root package compilation has not passed.

Existing Session, stream activity, Signal delivery and linear method examples
also cover busy rejection, cancellation, correlation, timeouts, observations
and result formats. Run the focused set from the repository root:

```sh
mix test test/examples/14_resume/14_05_worker_lifecycle/14_05_worker_lifecycle_test.exs test/examples/02_requests/02_01_session/02_01_session_test.exs test/examples/02_requests/02_14_stream_activity/02_14_stream_activity_test.exs test/examples/02_requests/02_17_signal_delivery/02_17_signal_delivery_test.exs test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs --include example --seed 0
```

See the [implementation record](../../../docs/v3-spike/implementation.md) for
validation results and the remaining package gates.
