> Seam alignment review. Pending approval.

# Observation and diagnostics alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [10 Authoring and portable definitions](../10_authoring_definitions/alignment.md), [11 Checkpoints and resume](../11_checkpoints_resume/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Telemetry and transport sanitizers redact and bound values differently. Typed Signal and stream projections exist. Inspection separates committed records from live samples and bounds retained traces. Current observation tests deliberately preserve some nested tool_result content; the strict content-free telemetry target is therefore not fully met.

- Current owner: Observe, sanitization, Runtime.Event/Telemetry, typed Signal projections, Request metadata, and Orchestration.Inspection.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve a complete versioned event contract, request/model/tool/delegation lineage, safe default projections, explicit rich-content policy, bounded diagnostics, and compatibility testing.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/observe.ex](../../../lib/jido_ai/observe.ex) | Telemetry boundary |
| [lib/jido_ai/observe/sanitize.ex](../../../lib/jido_ai/observe/sanitize.ex) | Telemetry/transport profiles |
| [lib/jido_ai/runtime/event.ex](../../../lib/jido_ai/runtime/event.ex) | Runtime event projection |
| [lib/jido_ai/signal.ex](../../../lib/jido_ai/signal.ex) | Typed Signal facade |
| [lib/jido_ai/orchestration/inspection.ex](../../../lib/jido_ai/orchestration/inspection.ex) | Committed/live inspection |

### Examples and tests

- [Example briefing](../../../examples/02_requests/02_22_request_inspection/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/02_requests/02_22_request_inspection): deterministic example evidence.
- [test/jido_ai/observe_test.exs](../../../test/jido_ai/observe_test.exs): detailed boundary evidence.
- [test/jido_ai/orchestration/inspection_test.exs](../../../test/jido_ai/orchestration/inspection_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve a complete versioned event contract, request/model/tool/delegation lineage, safe default projections, explicit rich-content policy, bounded diagnostics, and compatibility testing.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `OBS-GAP-001` | `OBS-REQ-001` | Runtime.Event and typed projections exist; there is no single public Event value matching all proposed fields. | Partially implemented | Keep event semantics and versioning work. |
| `OBS-GAP-002` | `OBS-REQ-002`, `OBS-REQ-003`, `OBS-REQ-004`, `OBS-REQ-005`, `OBS-REQ-007`, `OBS-REQ-009` | Lifecycle IDs and measurements exist. A complete finite vocabulary and correlation matrix remains. | Implemented; evidence incomplete | Retain per-event schema and measurement proof. |
| `OBS-GAP-003` | `OBS-REQ-006` | ReAct run identity is retained across resume rather than replaced with linked identity. | Decision required | Resolve with 11 before asserting OBS-REQ-006. |
| `OBS-GAP-004` | `OBS-REQ-008`, `OBS-REQ-022` | observe_test explicitly preserves nested tool_result payload fields after sanitization. | Decision required | Review the strict no-content default against current consumers. |
| `OBS-GAP-005` | `OBS-REQ-023`, `OBS-REQ-029` | Reasoning details can remain in results/projections. A universal private-thinking exclusion is a stronger target. | Decision required | Specify trusted opt-in policy with 01/05. |
| `OBS-GAP-006` | `OBS-REQ-019`, `OBS-REQ-020`, `OBS-REQ-021`, `OBS-REQ-024`, `OBS-REQ-025`, `OBS-REQ-026`, `OBS-REQ-027`, `OBS-REQ-028`, `OBS-REQ-030`, `OBS-REQ-031` | Bounds and sanitizers exist; full cross-projection/version compatibility evidence remains. | Partially implemented | Retain golden projection, cardinality, and arbitrary-input safety tests. |

## Attempt identity alignment gap

The [selected meanings](design.md#selected-request-and-attempt-meanings) need
distinct attempt correlation, retained prior outcomes, and separate execution,
commit, and delivery failure observations. Current request/run fields alone
do not prove that contract. Resolve identity representation with 07/11 before
event-schema changes. Future evidence includes resumed attempts, superseded
results, and delivery failure with unchanged committed outcome. No tests ran.

## Decisions and dependency gates

Decide the common event representation and default rich/thinking-content policy. Observation must not become an execution or durable-event owner.

- Prerequisites: [10 Authoring and portable definitions](../10_authoring_definitions/alignment.md), [11 Checkpoints and resume](../11_checkpoints_resume/alignment.md).
- Dependents: 90.
- Blocker: approval of the affected target decisions, not a historical package compile failure.
- Assumption: the current public lower-package contracts remain the integration boundary. A proposed API in this design is not evidence of an upstream API.
- Re-review dependents when an owning contract changes. Do not infer approval from a passing test or a category rename.

## High-level work sequence

1. Resolve prerequisite ownership and the decisions above. Exit: each changed contract has an explicit decision and compatibility scope.
2. Align current public contracts and retained target requirements. Exit: current behavior and intended changes are distinct, with no fictional API presented as implemented.
3. Specify acceptance cases for each approved change, including examples, failure paths, and cleanup. Exit: each requirement has direct evidence or a named missing test outcome.
4. Review dependent seams, migrations, and release implications. Exit: no dependent document assumes an unapproved guarantee.

This is a dependency and outcome plan, not a formal implementation task list.
Implementation planning follows approval of the seam intent and requirements.

## Acceptance matrix

This table is rebuilt from the actual requirement IDs in `design.md`; earlier
tables sometimes mapped evidence to the wrong requirement. “Implemented;
evidence incomplete” means the subsystem has relevant code, not that every
clause is met. No row below grants approval or claims a fresh test run.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `OBS-REQ-001` | Decision required | See current contract and gap register | Verify the target behavior: Each semantic AI event shall have a stable event name, lifecycle stage, timestamp or monotonic measurement context, correlation map, measurements, metadata, and projection policy. |
| `OBS-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every request event shall include agent ID when available, request ID, run ID, profile ID, and method ID. |
| `OBS-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every model event shall include model-call ID and effective safe model identifier. |
| `OBS-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every tool event shall include tool-call ID, public tool name, attempt number, and parent model-call ID when available. |
| `OBS-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every ordered delta or stream event shall include a monotonic sequence number within its declared scope. |
| `OBS-REQ-006` | Decision required | See current contract and gap register | Verify the target behavior: A resume event shall link the prior run ID and new run ID without reusing a live-event sequence. |
| `OBS-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Telemetry event names shall use the `[:jido, :ai, ...]` prefix and a documented finite event vocabulary. |
| `OBS-REQ-008` | Decision required | See current contract and gap register | Verify the target behavior: Telemetry metadata shall be low-cardinality by default and shall not contain full prompts, full model responses, tool arguments, tool results, file content, or stacktraces. |
| `OBS-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Telemetry measurements shall use documented numeric keys for duration, token counts, retries, queue time, candidate counts, and other bounded metrics. |
| `OBS-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A span shall emit one stop or exception result for each successful start unless observation is disabled before the start. |
| `OBS-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Observation failure shall not fail the AI request unless an explicit host policy makes an observation sink mandatory. |
| `OBS-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Disabled observation shall be a no-op with bounded constant overhead and shall not change execution semantics. |
| `OBS-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A public AI Signal shall use the typed Signal data contract from seam 06 and public `jido_signal` envelope and dispatch functions. |
| `OBS-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Signal projection shall include portable bounded data and shall not include a PID, exception struct, provider response, anonymous function, or runtime handle. |
| `OBS-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A user stream shall distinguish content deltas, progress, keepalive, control, usage, and terminal items with tagged event types. |
| `OBS-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A keepalive shall contain no model or tool content and shall not reset the execution deadline. |
| `OBS-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Stream and Signal projection failure shall not change the committed request outcome unless delivery is an explicit request requirement. |
| `OBS-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A completed request record shall be the authority for outcome; no event projection shall claim stronger durability. |
| `OBS-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Before telemetry projection, Jido AI shall sanitize metadata with the telemetry profile. |
| `OBS-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Before Signal or stream projection, Jido AI shall sanitize data with the transport profile. |
| `OBS-REQ-021` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Sanitization shall redact known credential keys recursively, bound depth and collection length, truncate text and binaries, and summarize provider-shaped payloads. |
| `OBS-REQ-022` | Decision required | See current contract and gap register | Verify the target behavior: Tool arguments and results shall be redacted by default in telemetry and included in transport only when explicit policy permits them. |
| `OBS-REQ-023` | Decision required | See current contract and gap register | Verify the target behavior: Hidden thinking and provider reasoning details shall be excluded from all projections by default. |
| `OBS-REQ-024` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Sanitization shall return valid bounded data for arbitrary input and shall never raise from public observation functions. |
| `OBS-REQ-025` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Inspection shall separate committed Agent state from transient live samples. |
| `OBS-REQ-026` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A request inspection view shall identify status, effective safe configuration, limits, usage, current phase, last sequence, truncation, and normalized error when present. |
| `OBS-REQ-027` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A trace prefix stored in Agent state shall have explicit event-count and byte limits and shall record when events were omitted. |
| `OBS-REQ-028` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Diagnostics shall distinguish validation, provider, model policy, tool, effect, session, checkpoint, resource-limit, and observation failures. |
| `OBS-REQ-029` | Decision required | See current contract and gap register | Verify the target behavior: Debug formatting shall be safe by default and shall require explicit trusted policy to show prompt or content payloads. |
| `OBS-REQ-030` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Stable public event and Signal fields shall use additive compatible changes within a major version. |
| `OBS-REQ-031` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Internal telemetry events not marked public can change without compatibility support, but their status shall be documented. |

## Migration and compatibility

Decide the common event representation and default rich/thinking-content policy. Observation must not become an execution or durable-event owner.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Content-permission acceptance additions

Current [Sanitize](../../../lib/jido_ai/observe/sanitize.ex) has telemetry and
transport profiles. These do not establish the full set of independent
stream, storage, reasoning, and diagnostics permissions selected in the design.

| Requirement | Evidence state | Acceptance outcome |
| --- | --- | --- |
| OBS-REQ-032 | Proposed; not implemented | Stream projection shall exclude rich content unless stream-specific permission permits it. |
| OBS-REQ-033 | Proposed; not implemented | Storage projection shall exclude rich content unless separate storage-specific permission permits it. |
| OBS-REQ-034 | Proposed; not implemented | Stream projection shall exclude reasoning content unless separate trusted stream-reasoning permission permits it. |
| OBS-REQ-035 | Proposed; not implemented | Storage projection shall exclude reasoning content unless separate trusted storage-reasoning permission permits it. |
| OBS-REQ-036 | Proposed; not implemented | Diagnostics projection shall exclude content unless both trusted access and explicit diagnostics content permission permit it. |
| OBS-REQ-037 | Proposed; not implemented | Telemetry projection shall exclude content regardless of rich-content or reasoning permissions. |
| OBS-REQ-038 | Proposed; not implemented | Every permitted content projection shall remove credentials and apply size limits. |

Test each destination with default-off, its own permission, and every unrelated
permission. Include nested tool arguments/results, media, provider thinking,
credentials, and oversized values. Telemetry stays content-free even with all
permissions enabled. Native execution payloads remain intact. Storage checks
cover Thread payloads, retained request data, traces, and checkpoint snapshots.
Reconcile sanitized recovery with seam 11; no safe replay is inferred from
redacted content. No tests ran in this documentation task.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
