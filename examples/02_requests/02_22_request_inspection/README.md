# 02_22: Request inspection and saved trace prefixes

[Agent](agent.ex) and
[tests](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs) use the
compiled Session, core Agent Server, real tools and the shared HTTP model server.

## Public contract

```elixir
{:ok, view} = Jido.AI.Session.snapshot(server)
{:ok, view} = Jido.AI.Session.snapshot(server, request_id: request.id)

view.state_version
view.request.status
view.request.result
view.request.error
view.details.trace
view.live
```

The default selects pending work, then the latest retained request. An explicit
unknown ID returns `{:error, :request_not_found}`. An idle Agent returns an empty
view. The envelope includes the committed Agent and its core revision. The
request record is from that revision. `live`, when present, is a later sample
from the Session with the same request and run IDs. It includes its observation
time and worker PID. These process identifiers never enter stored Agent state.
A Session restart can make the live sample unavailable; the committed view
remains usable. The API does not make the two samples atomic.

Details expose phase, reasoning position, started model calls, model label,
model-call ID, usage, output metadata, stream text/thinking, per-call thinking,
active tools, completed tool results, duration, and cancellation reason.
Configuration and conversation use the selected request's current profile.
The request's final result and raw stored failure remain in `view.request`.

## Trace and commit rules

A trace retains at most the first 2,000 observed events for a request. Overflow
sets `truncated?`; `seq` still records the last sampled event sequence. Phase and
stream projections continue after the event cap. Request retention also bounds
the number of saved traces. The normal terminal view keeps the observed prefix
before the final outcome commit. The committed record proves the outcome; the
canonical stream emits its terminal event after commit.

`scope: :observed_prefix` is explicit. It is not a receipt for every emitted
Signal or a complete durable event log. A cancellation Turn can commit while
new events arrive. Its saved prefix then ends before those events. The race
example holds cancellation admission, emits another event, and proves that
the canonical sequence remains ordered while the saved prefix stays truthful.
No stream event or sequence number is allocated inside the pure outcome Turn.

The existing history commit stores the current trace prefix and request
metadata. Session recovery retains that prefix, fails interrupted work and
starts no replacement model or tool. Events after the last history commit
can be lost. Profiles without history retain their trace at terminal commit;
this port adds no per-event persistence loop. Durable completion storage is
covered with a lost reply and a new Agent Server. If the durable store refuses
the completion commit, the Agent Server stops and the caller gets
`:agent_server_unavailable`. The durable request stays pending and no false
completed event is stored. This example does not cover all pending-work storage
failures or guaranteed terminal delivery.

If the Agent's byte limit cannot hold trace data, the stored trace is omitted
and marked truncated. A compact terminal failure can also omit trace details.
Request completion retains its existing reserve and failure rules. Trace data
cannot create another executor or require successful Signal delivery.

Portable events keep their data shape. Live tool-effect values use the existing
transport sanitizer before storage. Private `react_checkpoint` transfer data is
removed from trace event data and nested event metadata. The canonical stream
keeps its existing payload. Trace inspection does not replay tool effects.

## Evidence and refinement

Sixteen example cases cover idle/unknown requests, held model and tool
work, retained older requests, cancellation, task failure, Session recovery,
the event cap, wrong-run data, decoded thinking, absent history, durable
completion recovery, refused completion that stops the Agent Server, and
concurrent cancellation events.
Two new named buffered and streaming Agents execute successful and failed tools.
They replay a real completion twice while the next model call is held. The
phase stays `:awaiting_llm`, completed results remain unique, and the final HTTP
history has one message per tool. Stale events cannot change a completed record.
A new request starts with empty tool results; the old request stays selectable.
Active calls include `result: nil`. Completed records contain validated arguments;
active calls contain the prepared provider arguments. Typed Action error maps
retain their type, message and retry flag, with tool identity in the details.
The [ReAct transfer](../../../docs/v3-spike/react-inspection-test-transfer.md)
records the source cases and the narrow shared fixes.
The existing completion examples also check state limits and compact failure.
The shared mock is the only model server.

An initial design prepared terminal stream events inside the outcome Turn.
Review exposed the cancellation race. The simpler design stores the observed
prefix and the committed outcome separately. It reuses the existing live event
publisher. It adds no runtime owner, queue, executor or DSL term.

CLI adapters, method-specific active tree and graph inspection, context lanes,
operation deduplication, and skill compaction are outside this example.

Run from the repository root:

```sh
mix test test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs --include example
```

The first full run passed 1,032 of 1,033 checks. Its fresh-runtime tool case
exposed a shutdown race in the shared mock: an owned acceptor could send a
shutdown exit back through the mock to its linked caller. A direct mock test
reproduced that failure. Cleanup now unlinks owned processes before it stops
them. The new default test checks caller survival and owned-process cleanup.
The focused mock, Session and inspection run then passed all 56 cases.


The first complete run of the tool-error change found an existing skill case
with a nested exception in its typed error. Retry-hint lookup assumed Access
support and failed. It now uses Map functions for map/struct fields. A new
boundary test covers atom/string details containing the skill exception. All
37 skill-authoring and inspection cases pass together. The full package result
is recorded in the [root checkpoint](../../../docs/v3-spike/root-package-checkpoint.md).
