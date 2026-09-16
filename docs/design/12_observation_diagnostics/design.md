> Target seam design. This document is pending approval.

# Observation and diagnostics design

## Architecture and contract status

- Architecture category: [Observation and diagnostics](../ARCHITECTURE.md).
- Owning subsystem: Observe, sanitization, Observe.Event/Telemetry, typed Signal projections, Request metadata, and Orchestration.Inspection.
- Complete target: Preserve a complete versioned event contract, request/model/tool/delegation lineage, safe default projections, explicit rich-content policy, bounded diagnostics, and compatibility testing.
- Decision boundary: Decide the common event representation and default rich/thinking-content policy. Observation must not become an execution or durable-event owner.
- Current implementation, module links, example proof, and exact differences:
  [alignment](alignment.md). This design is a target, not an API reference.

The requirements and proposed signatures below remain pending approval.
Illustrative types are not evidence that a module or function exists. A
requirement is not removed merely because the current implementation differs.
Use the alignment matrix to distinguish current behavior from the full target.

## Selected request and attempt meanings

Apply the [request/attempt policy](../07_request_sessions/design.md#selected-request-and-attempt-meanings)
to observations: one logical request can have multiple attempts and preserved
attempt outcomes. ReAct run_id is not sufficient as a unique attempt ID.
Distinguish execution, commit, and delivery failures from uncertainty,
cancellation, and supersession. Delivery failure does not rewrite a committed
outcome. Exact event fields and compatibility remain open; no new struct is
selected. Document approval remains pending.

## Selected content permissions

User-selected on 2026-09-15. Each permission applies only to its destination
and content class. Stream permission cannot authorize storage. Rich content
includes tool arguments, tool results, and media. Reasoning content includes
hidden thinking and provider reasoning details. All permissions default off.

`OBS-REQ-032`: Stream projection shall exclude rich content unless stream-specific permission permits it.

`OBS-REQ-033`: Storage projection shall exclude rich content unless separate storage-specific permission permits it.

`OBS-REQ-034`: Stream projection shall exclude reasoning content unless separate trusted stream-reasoning permission permits it.

`OBS-REQ-035`: Storage projection shall exclude reasoning content unless separate trusted storage-reasoning permission permits it.

`OBS-REQ-036`: Diagnostics projection shall exclude content unless both trusted access and explicit diagnostics content permission permit it.

`OBS-REQ-037`: Telemetry projection shall exclude content regardless of rich-content or reasoning permissions.

`OBS-REQ-038`: Every permitted content projection shall remove credentials and apply size limits.

These rules do not change native ReqLLM data needed during execution. They
govern exposure and storage, including canonical log payloads and snapshots.
Retention of execution evidence is not permission to retain rich or reasoning
content: preserve permitted identity, order, status, and bounded metadata.
The current implementation uses Profile observability fields `stream_content`,
`store_content`, `stream_reasoning`, `store_reasoning`, and `diagnostics_content`.
See [alignment evidence and migration limits](alignment.md#content-permission-acceptance-additions)
for the supported paths and remaining proof. Preserve canonical
Session/Thread, Agent + DSL + Profile, all methods, advanced capabilities,
and core topology ownership. Named-document approval remains pending.

## Scope and owner

- Owner: `Jido.AI.Observe`, sanitization, AI lifecycle event definitions, typed AI Signal data, public stream event views, inspection data, and diagnostic helpers.
- In scope: Event names, stages, correlation, measurements, metadata, sanitization, redaction, size bounds, telemetry spans, Signal projections, stream projections, inspection, and failure diagnostics.
- Out of scope: Telemetry backends, log stores, durable event logs, Signal buses, dashboards, request control, billing systems, and provider tracing infrastructure.

## V2 capability anchor

V2 supplied telemetry events, request and model Signals, token streaming, tool events, usage data, strategy diagnostics, and debug views. V3 keeps these operational features and gives them one semantic event model with separate projections for telemetry, Signals, user streams, and inspection.

| V2 capability | V3 target |
| --- | --- |
| Strategy telemetry | Method and execution events with stable correlation |
| Typed lifecycle Signals | Strict AI data projected into `Jido.Signal` |
| Token callbacks | Ordered request stream items |
| Tool and model metadata | Safe low-cardinality telemetry metadata |
| Debug state | Bounded inspection view separated from committed Agent state |
| Usage event | Canonical seam 01 Usage value and measurements |

## Model

One internal semantic event can have up to four projections:

```text
Jido.AI.Event
  ├─ telemetry projection: low-cardinality measurements and metadata
  ├─ Signal projection: portable typed data in a Jido.Signal envelope
  ├─ stream projection: ordered user-facing live item
  └─ inspection projection: bounded diagnostic snapshot
```

Creating a semantic event does not require every projection. Profile observation policy selects enabled projections. Disabling observation does not change request results or Agent state.

Every applicable event uses this correlation chain:

```text
agent_id -> request_id -> run_id -> model_call_id -> tool_call_id
```

It also carries method, iteration, operation, origin, and sequence values where applicable. A resumed request keeps the logical request link, records the prior run ID, and uses a new run ID.

The stable public lifecycle groups are:

- Request: start, complete, failed, rejected, cancelled, interrupted.
- Model: start, delta, complete, error.
- Tool: start, retry-decision, complete, error, timeout.
- Output: validation, repair, complete, error.
- Reasoning: method start, candidate, selection, complete, error.
- Capability: policy decision, retrieval, quota decision, skill activation.

Only a selected subset becomes stable public Signals. Internal telemetry events can be more detailed.

## Requirements

### Event identity and correlation

`OBS-REQ-001`: Each semantic AI event shall have a stable event name, lifecycle stage, timestamp or monotonic measurement context, correlation map, measurements, metadata, and projection policy.

`OBS-REQ-002`: Every request event shall include agent ID when available, request ID, run ID, profile ID, and method ID.

`OBS-REQ-003`: Every model event shall include model-call ID and effective safe model identifier.

`OBS-REQ-004`: Every tool event shall include tool-call ID, public tool name, attempt number, and parent model-call ID when available.

`OBS-REQ-005`: Every ordered delta or stream event shall include a monotonic sequence number within its declared scope.

`OBS-REQ-006`: A resume event shall link the prior run ID and new run ID without reusing a live-event sequence.

### Telemetry

`OBS-REQ-007`: Telemetry event names shall use the `[:jido, :ai, ...]` prefix and a documented finite event vocabulary.

`OBS-REQ-008`: Telemetry metadata shall be low-cardinality by default and shall not contain full prompts, full model responses, tool arguments, tool results, file content, or stacktraces.

`OBS-REQ-009`: Telemetry measurements shall use documented numeric keys for duration, token counts, retries, queue time, candidate counts, and other bounded metrics.

`OBS-REQ-010`: A span shall emit one stop or exception result for each successful start unless observation is disabled before the start.

`OBS-REQ-011`: Observation failure shall not fail the AI request unless an explicit host policy makes an observation sink mandatory.

`OBS-REQ-012`: Disabled observation shall be a no-op with bounded constant overhead and shall not change execution semantics.

### Signal and stream projections

`OBS-REQ-013`: A public AI Signal shall use the typed Signal data contract from seam 06 and public `jido_signal` envelope and dispatch functions.

`OBS-REQ-014`: Signal projection shall include portable bounded data and shall not include a PID, exception struct, provider response, anonymous function, or runtime handle.

`OBS-REQ-015`: A user stream shall distinguish content deltas, progress, keepalive, control, usage, and terminal items with tagged event types.

`OBS-REQ-016`: A keepalive shall contain no model or tool content and shall not reset the execution deadline.

`OBS-REQ-017`: Stream and Signal projection failure shall not change the committed request outcome unless delivery is an explicit request requirement.

`OBS-REQ-018`: A completed request record shall be the authority for outcome; no event projection shall claim stronger durability.

### Sanitization and size bounds

`OBS-REQ-019`: Before telemetry projection, Jido AI shall sanitize metadata with the telemetry profile.

`OBS-REQ-020`: Before Signal or stream projection, Jido AI shall sanitize data with the transport profile.

`OBS-REQ-021`: Sanitization shall redact known credential keys recursively, bound depth and collection length, truncate text and binaries, and summarize provider-shaped payloads.

`OBS-REQ-022`: Tool arguments and results shall be redacted by default in telemetry and included in transport only when explicit policy permits them.

`OBS-REQ-023`: Hidden thinking and provider reasoning details shall be excluded from all projections by default.

`OBS-REQ-024`: Sanitization shall return valid bounded data for arbitrary input and shall never raise from public observation functions.

### Inspection and diagnostics

`OBS-REQ-025`: Inspection shall separate committed Agent state from transient live samples.

`OBS-REQ-026`: A request inspection view shall identify status, effective safe configuration, limits, usage, current phase, last sequence, truncation, and normalized error when present.

`OBS-REQ-027`: A trace prefix stored in Agent state shall have explicit event-count and byte limits and shall record when events were omitted.

`OBS-REQ-028`: Diagnostics shall distinguish validation, provider, model policy, tool, effect, session, checkpoint, resource-limit, and observation failures.

`OBS-REQ-029`: Debug formatting shall be safe by default and shall require explicit trusted policy to show prompt or content payloads.

### Compatibility

`OBS-REQ-030`: Stable public event and Signal fields shall use additive compatible changes within a major version.

`OBS-REQ-031`: Internal telemetry events not marked public can change without compatibility support, but their status shall be documented.

## Public contract

Recommended semantic value:

```elixir
%Jido.AI.Event{
  name: atom(),
  stage: atom(),
  correlation: %{
    agent_id: term(),
    request_id: String.t() | nil,
    run_id: String.t() | nil,
    model_call_id: String.t() | nil,
    tool_call_id: String.t() | nil,
    sequence: non_neg_integer() | nil
  },
  measurements: map(),
  metadata: map(),
  payload: term(),
  projections: MapSet.t()
}
```

Recommended observation API:

```elixir
Jido.AI.Observe.emit(config, event) :: :ok
Jido.AI.Observe.start_span(config, prefix, metadata) :: span_context | :noop
Jido.AI.Observe.finish_span(span_context, measurements) :: :ok
Jido.AI.Observe.finish_span_error(span_context, kind, reason, stacktrace) :: :ok
Jido.AI.Observe.sanitize(value, :telemetry | :transport, opts \\ []) :: term()
Jido.AI.Observe.inspect_request(agent_or_server, request_id, opts \\ []) ::
  {:ok, map()} | {:error, term()}
```

Stable telemetry prefixes:

```text
[:jido, :ai, :request, event]
[:jido, :ai, :llm, event]
[:jido, :ai, :tool, event]
[:jido, :ai, :output, event]
[:jido, :ai, :reasoning, method, event]
[:jido, :ai, :capability, capability, event]
```

Stable public Signal types for the first V3 release are the request, model, tool, usage, and embedding event types listed in seam 06. Reasoning candidate detail remains telemetry or inspection data unless approved later.

## Invariants

- `OBS-INV-001`: Observation does not change AI result semantics.
- `OBS-INV-002`: Correlation IDs remain stable within their scope.
- `OBS-INV-003`: Telemetry metadata is low-cardinality and safe by default.
- `OBS-INV-004`: Transport payloads are portable and bounded.
- `OBS-INV-005`: Hidden reasoning is not emitted by default.
- `OBS-INV-006`: The committed request record is the outcome authority.
- `OBS-INV-007`: A live stream is not a durable event log.
- `OBS-INV-008`: Observation functions do not raise for arbitrary payloads.

## Downstream guarantees

| Consumer seam | Guaranteed contract |
| --- | --- |
| 90 Delivery | Stable public event list, diagnostic categories, and compatibility rules |
| Host telemetry | Low-cardinality event names, measurements, and safe metadata |
| Host Signal dispatch | Typed portable event data |
| User interfaces | Ordered stream items and one terminal state when delivery remains available |

## Open design decisions

| ID | Question | Recommended option | Effect |
| --- | --- | --- | --- |
| `OBS-DEC-001` | Which events are stable Signals? | Request, model, tool, usage, and embedding lifecycle events | Keeps the public transport surface bounded |
| `OBS-DEC-002` | Are reasoning candidate events public? | No for V3.0; telemetry and inspection only | Avoids exposing private reasoning and unstable method detail |
| `OBS-DEC-003` | Is content ever in telemetry by default? | No | Reduces privacy and cardinality risk |
| `OBS-DEC-004` | Can observation failure fail a request? | Only with explicit mandatory-sink host policy | Keeps default operation resilient |
