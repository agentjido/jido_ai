# 02_17: Automatic session Signal delivery

The [Agent and outbound Plugin](agent.ex)
and [26 example tests](../../../test/examples/02_requests/02_17_signal_delivery/02_17_signal_delivery_test.exs)
use the shared mock LLM, real tools, and core Agent commits and dispatch.
The native DSL and the public `Jido.AI.Agent` facade use the same path.

```sh
mix test --include example test/examples/02_requests/02_17_signal_delivery/02_17_signal_delivery_test.exs
```

The session owner assigns each canonical event its sequence and sends it to
the public request stream. A separate, owned process projects typed Signals
and holds a bounded transient queue. It submits one batch at a time to the
owning Agent. A private reference ticket grants one use of that batch. The
admission Plugin replaces any caller-supplied grant. A stale or reused ticket
cannot authorize another publication.

The publication Action returns the current complete Agent state, core Emit
Directives, and a final receipt Directive. Core commits that state, prepares
each outbound Signal through Plugins, and calls its dispatch adapter. The
receipt can run only when all earlier Directives succeed. Signal publication
therefore adds normal Agent revisions, Plugin reductions and persistence
writes. A batch is subject to the Agent's Directive limits.

Without `default_dispatch`, core sends each Signal back to the owning Agent.
Declared host routes still run, including wildcard routes. An unhandled known
AI observation uses an internal no-op Action. The receipt confirms dispatch
success. It does not confirm that a receiving process handled the Signal.
The PID adapter cannot provide that stronger guarantee.

The examples prove early tool-name delivery before complete arguments,
ordered model/tool/result/usage events, actual provider failure, cancellation,
multimodal request starts, disabled observations, source-format parity, queue
limits, real adapter and Plugin failures, stale tickets, timeouts and process
cleanup. The request-start Signal now accepts the same query forms as the
public request API, including content-part lists.

Use the existing observation block:

```elixir
ai :assistant do
  observability(%{emit_signals?: true, emit_llm_deltas?: true})
  # Models, reasoning, tools, requests, and result declarations follow.
end
```

`emit_signals?` defaults to `true`. Setting it to `false` preserves the canonical
stream, answer, and independent telemetry policy. Setting `emit_llm_deltas?`
to `false` suppresses delta capture before sequence assignment; other typed
Signals can still be delivered. These flags use the same lowerer for DSL,
data, Builder and source JSON.

The application can set `:jido_ai, :signal_delivery` before Agent activation:

| Option | Default | Allowed range |
| --- | --- | --- |
| `queue_limit` | 256 events | 1–4096 |
| `byte_limit` | 8,388,608 bytes | 1–67,108,864 |
| `batch_size` | 16 events | 1–64 |
| `timeout` | 15,000 ms | 1–60,000 |

Both queue limits include the active batch. The byte limit uses the local
encoded term size of projected Signals. It is not a network-byte limit.
One canonical model completion can produce both a response and a usage Signal.
The batch size counts canonical events that have a typed projection. Allow
space for all their Emits and one receipt in core's Directive limit.

`Jido.AI.Session.delivery_status(server, request_id)` returns a transient report.
Statuses are `:pending`, `:disabled`, `:delivered`, `:failed`, or `:unconfirmed`.
The report retains the actual request and run IDs. Its counters count events,
not Signal envelopes. `enqueued` counts accepted events; `delivered` counts
confirmed events. `dropped` includes refused events and queued events removed
on failure, so it is not limited to previously enqueued events. `unconfirmed`
counts batch events with no reliable receipt. `last_seq` is the last accepted
event sequence. `terminal?` records whether the canonical terminal event arrived.
Keep at most 100 finished reports plus reports still needed by active work.
An older report returns `:unknown_delivery`.

Queue overflow closes observation for that request and removes its queued
tail. It does not remove canonical stream events or retry model/tool work.
Confirmed publication rejection reports `:failed`. A lost receipt, uncertain
storage result, or lost call reports `:unconfirmed` while the owner is available.
No committed batch is retried. Only the three explicit core reentry refusals
can retry before their bounded admission deadline.

`Request.await` confirms the answer commit. It can return before final Signal
delivery. Core serializes turns and Directives, so slow outbound work can delay
history, completion, or cancellation commits. Core's `directive_timeout` stops
a held outbound worker. The AI receipt timeout only closes its own observation
batch. It cannot retract a committed Emit: that Emit can finish later, and the
report remains unconfirmed. A partial batch is also unconfirmed because there
is no receipt for each individual Emit.

Owner or Agent loss stops the transient delivery queue and submission task.
Core owns any Emit already committed. Old tickets fail after restart. The
existing request recovery marks pending work interrupted; it does not restore
old delivery reports, sinks, or Signal batches. A completed request can remain
stored while its delivery report is lost. Durable delivery, replay, v2 state
conversion, other reasoning methods and full root-package checks remain open.

The earlier completion fault fixture now selects the actual terminal request
write from the real checkpoint. It still proves one completion attempt,
conflict handling and an indeterminate stored result. Observation writes no
longer cause that fixture to fail before the model/tool work under test.
