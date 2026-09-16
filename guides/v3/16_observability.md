# Observability and diagnostics

An AI request has a request ID and a run ID. Use them to join an admission
record, runtime events, model/tool operations, and settlement. AgentServer
state is the committed view. Live inspection is a later sample of active
work, not one atomic snapshot with state. Stream events are useful for a UI,
but they are not a replacement for retained request status.

```elixir
ai :assistant do
  observability do
    store_content true
  end
end
```

Content retention is a privacy choice. Keep it off unless a support or audit
use case needs it. Diagnostics that include content need both profile
permission and an explicit inspection request. Normal inspection excludes
content. Redact secrets before they become model input, tool output, or trace
content; a later display filter cannot undo a stored secret.

For an incident, record the request ID, selected profile and model, started
model-call count, tool names and outcomes, final status, and committed Agent
revision. Do not store worker PIDs in portable state. A saved trace can be a
prefix and must not be treated as a complete durable event log. For a live
debug view, use public `Jido.AI.Orchestration.snapshot/2`; for the Agent's
committed revision use core AgentServer inspection.

The [request-inspection example](../../examples/02_requests/02_22_request_inspection/README.md)
shows both live and committed views. The [stream-usage example](../../examples/02_requests/02_24_stream_usage/README.md)
shows usage arriving through a stream. Continue with [Session, Thread, and
Context](17_session_thread_context.md).
