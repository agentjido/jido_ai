> Seam alignment review. Pending approval.

# Observation and diagnostics alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: [10 Authoring and portable definitions](../10_authoring_definitions/alignment.md), [11 Checkpoints and resume](../11_checkpoints_resume/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Telemetry and transport sanitizers redact and bound values differently. Typed Signal and stream projections exist. Inspection separates committed records from live samples and bounds retained traces. Current observation tests deliberately preserve some nested tool_result content; the strict content-free telemetry target is therefore not fully met.

- Current owner: Observe, sanitization, Observe.Event/Telemetry, typed Signal projections, Request metadata, and Orchestration.Inspection.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve a complete versioned event contract, request/model/tool/delegation lineage, safe default projections, explicit rich-content policy, bounded diagnostics, and compatibility testing.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/observe.ex](../../../lib/jido_ai/observe.ex) | Telemetry boundary |
| [lib/jido_ai/observe/sanitize.ex](../../../lib/jido_ai/observe/sanitize.ex) | Telemetry/transport profiles |
| [lib/jido_ai/observe/event.ex](../../../lib/jido_ai/observe/event.ex) | Runtime event projection |
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
migration. The initial audit changed examples and tests. The implementation follow-up also changes the runtime; see the current evidence below.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `OBS-GAP-001` | `OBS-REQ-001` | Observe.Event and typed projections exist; there is no single public Event value matching all proposed fields. | Partially implemented | Keep event semantics and versioning work. |
| `OBS-GAP-002` | `OBS-REQ-002`, `OBS-REQ-003`, `OBS-REQ-004`, `OBS-REQ-005`, `OBS-REQ-007`, `OBS-REQ-009` | Lifecycle IDs and measurements exist. A complete finite vocabulary and correlation matrix remains. | Implemented; evidence incomplete | Retain per-event schema and measurement proof. |
| `OBS-GAP-003` | `OBS-REQ-006` | ReAct run identity is retained across resume rather than replaced with linked identity. | Decision required | Resolve with 11 before asserting OBS-REQ-006. |
| `OBS-GAP-004` | `OBS-REQ-008`, `OBS-REQ-022` | observe_test explicitly preserves nested tool_result payload fields after sanitization. | Decision required | Review the strict no-content default against current consumers. |
| `OBS-GAP-005` | `OBS-REQ-023`, `OBS-REQ-029` | Independent default-off content and reasoning permissions now exist; broader provider and nested-payload coverage remains. | Partially implemented | Extend the destination matrix with 01/05/11. |
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

## Example-driven review

This follow-up uses the later selected decisions when older wording conflicts.
The [audit summary](../README.md#example-driven-design-audit) separates target
failures, related scenarios, API gates, and non-example release checks. All
requirements in this seam appear in the acceptance matrix below.

The new target checks extend existing example lessons. They use public APIs and
the local MockLLM transport. No target failure is skipped or changed to accept
the current behavior. Tests blocked by an unspecified public contract are
marked as a gate; no invented API is presented as an executable example.

## Acceptance matrix

Requirement IDs and target wording come from `design.md`. The evidence column
now names related example scenarios. **Related evidence is partial**, not full
requirement acceptance. A passing target check proves only its stated case.
`To be implemented — reproduced` identifies a failed target assertion, not a
failure inferred from a missing example. Source/release checks and public API
gates are separate. No row grants document approval.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `OBS-REQ-001` | Decision required | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Each semantic AI event shall have a stable event name, lifecycle stage, timestamp or monotonic measurement context, correlation map, measurements, metadata, and projection policy. |
| `OBS-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Every request event shall include agent ID when available, request ID, run ID, profile ID, and method ID. |
| `OBS-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Every model event shall include model-call ID and effective safe model identifier. |
| `OBS-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Every tool event shall include tool-call ID, public tool name, attempt number, and parent model-call ID when available. |
| `OBS-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Every ordered delta or stream event shall include a monotonic sequence number within its declared scope. |
| `OBS-REQ-006` | Decision required | Reconcile run-ID wording with selected request/attempt meanings. Link prior/new attempts; do not require a new ReAct run ID merely to satisfy old wording. | Verify the target behavior: A resume event shall link the prior run ID and new run ID without reusing a live-event sequence. |
| `OBS-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Telemetry event names shall use the `[:jido, :ai, ...]` prefix and a documented finite event vocabulary. |
| `OBS-REQ-008` | Decision required | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Telemetry metadata shall be low-cardinality by default and shall not contain full prompts, full model responses, tool arguments, tool results, file content, or stacktraces. |
| `OBS-REQ-009` | Implemented; evidence incomplete | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Telemetry measurements shall use documented numeric keys for duration, token counts, retries, queue time, candidate counts, and other bounded metrics. |
| `OBS-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: A span shall emit one stop or exception result for each successful start unless observation is disabled before the start. |
| `OBS-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [a post-commit directive failure preserves the answer and is not retried](../../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs). | Verify the target behavior: Observation failure shall not fail the AI request unless an explicit host policy makes an observation sink mandatory. |
| `OBS-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [AoT telemetry and Signal flags stay separate and known control errors retain their type](../../../test/examples/09_reasoning/09_03_aot/09_03_aot_test.exs). The same policy failure remains a failure with telemetry enabled or disabled. Constant overhead and all execution paths remain unproved. | Verify the target behavior: Disabled observation shall be a no-op with bounded constant overhead and shall not change execution semantics. |
| `OBS-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [unknown keys and duplicate atom-string aliases cannot overwrite validated fields or create atoms](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: A public AI Signal shall use the typed Signal data contract from seam 06 and public `jido_signal` envelope and dispatch functions. |
| `OBS-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs); [unknown keys and duplicate atom-string aliases cannot overwrite validated fields or create atoms](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: Signal projection shall include portable bounded data and shall not include a PID, exception struct, provider response, anonymous function, or runtime handle. |
| `OBS-REQ-015` | Implemented; evidence incomplete | Related example evidence (partial): [real SSE text and request headers precede the final commit](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [steer and inject during a real tool keep one handle, FIFO input and committed consumption](../../../test/examples/02_requests/02_02_steering/02_02_steering_test.exs). | Verify the target behavior: A user stream shall distinguish content deltas, progress, keepalive, control, usage, and terminal items with tagged event types. |
| `OBS-REQ-016` | Implemented; evidence incomplete | Target scenario passed: [OBS-REQ-016 target check](../../../test/examples/02_requests/02_01_session/design_requirements_test.exs). A held real tool emits content-free keepalives, then the request deadline fails the request and terminates the tool. | Verify the target behavior: A keepalive shall contain no model or tool content and shall not reset the execution deadline. |
| `OBS-REQ-017` | Implemented; evidence incomplete | Related example evidence (partial): [a post-commit directive failure preserves the answer and is not retried](../../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs). | Verify the target behavior: Stream and Signal projection failure shall not change the committed request outcome unless delivery is an explicit request requirement. |
| `OBS-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [a post-commit directive failure preserves the answer and is not retried](../../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs). | Verify the target behavior: A completed request record shall be the authority for outcome; no event projection shall claim stronger durability. |
| `OBS-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Before telemetry projection, Jido AI shall sanitize metadata with the telemetry profile. |
| `OBS-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Before Signal or stream projection, Jido AI shall sanitize data with the transport profile. |
| `OBS-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Sanitization shall redact known credential keys recursively, bound depth and collection length, truncate text and binaries, and summarize provider-shaped payloads. |
| `OBS-REQ-022` | Decision required | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Tool arguments and results shall be redacted by default in telemetry and included in transport only when explicit policy permits them. |
| `OBS-REQ-023` | Implemented; evidence incomplete | Target scenario repaired: [OBS-REQ-023 target check](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs). Separate default-off permissions control provider reasoning in stream, storage, and diagnostics. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Hidden thinking and provider reasoning details shall be excluded from all projections by default. |
| `OBS-REQ-024` | Implemented; evidence incomplete | Target scenario passed: [OBS-REQ-024 target check](../../../test/examples/02_requests/02_27_thread_session_values/design_requirements_test.exs). Public transport sanitization accepts invalid UTF-8, runtime values, deep nesting, and long text; output is bounded JSON-safe data with synthetic credentials removed. This fixed case is not arbitrary-input proof. | Verify the target behavior: Sanitization shall return valid bounded data for arbitrary input and shall never raise from public observation functions. |
| `OBS-REQ-025` | Implemented; evidence incomplete | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Inspection shall separate committed Agent state from transient live samples. |
| `OBS-REQ-026` | Implemented; evidence incomplete | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: A request inspection view shall identify status, effective safe configuration, limits, usage, current phase, last sequence, truncation, and normalized error when present. |
| `OBS-REQ-027` | Implemented; evidence incomplete | Related example evidence (partial): [the trace cap keeps the first 2000 events and records overflow without hiding completion](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: A trace prefix stored in Agent state shall have explicit event-count and byte limits and shall record when events were omitted. |
| `OBS-REQ-028` | Implemented; evidence incomplete | Related example evidence (partial): [task failure keeps the actual failure and the trace before the task stopped](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Diagnostics shall distinguish validation, provider, model policy, tool, effect, session, checkpoint, resource-limit, and observation failures. |
| `OBS-REQ-029` | Decision required | Related example evidence (partial): [a held model has live identity and a separate committed request](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Debug formatting shall be safe by default and shall require explicit trusted policy to show prompt or content payloads. |
| `OBS-REQ-030` | Implemented; evidence incomplete | Release check: compare public event/Signal schemas with the approved major-version baseline. | Verify the target behavior: Stable public event and Signal fields shall use additive compatible changes within a major version. |
| `OBS-REQ-031` | Implemented; evidence incomplete | Documentation check: mark internal telemetry events separately from stable public events. | Verify the target behavior: Internal telemetry events not marked public can change without compatibility support, but their status shall be documented. |
| `OBS-REQ-032` | Implemented; evidence incomplete | Target scenario repaired: [media example](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs) and [tool permission matrix](../../../test/jido_ai/observe/content_test.exs). Default public streams omit media and tool payloads. Stream permission does not grant storage permission. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Stream projection shall exclude rich content unless stream-specific permission permits it. |
| `OBS-REQ-033` | Implemented; evidence incomplete | Target scenario repaired: [media example](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs) and [tool permission matrix](../../../test/jido_ai/observe/content_test.exs). Default retained request and Thread data omit media and tool payloads. Missing content is not copied into a second store. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Storage projection shall exclude rich content unless separate storage-specific permission permits it. |
| `OBS-REQ-034` | Implemented; evidence incomplete | Target scenario repaired: [OBS-REQ-034 target check](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs). Default streams omit provider reasoning. The stream-reasoning permission is separate from media permission. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Stream projection shall exclude reasoning content unless separate trusted stream-reasoning permission permits it. |
| `OBS-REQ-035` | Implemented; evidence incomplete | Target scenario repaired: [OBS-REQ-035 target check](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs). Default retained records, traces, and Thread data omit provider reasoning. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Storage projection shall exclude reasoning content unless separate trusted storage-reasoning permission permits it. |
| `OBS-REQ-036` | Implemented; evidence incomplete | Target scenario repaired: [OBS-REQ-036 target check](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs). Diagnostics omit content unless both Profile permission and explicit include_content access are present. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: Diagnostics projection shall exclude content unless both trusted access and explicit diagnostics content permission permit it. |
| `OBS-REQ-037` | Decision required | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). Related examples do not prove the complete destination-specific content policy. | Verify the target behavior: Telemetry projection shall exclude content regardless of rich-content or reasoning permissions. |
| `OBS-REQ-038` | Decision required | Related example evidence (partial): [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). Related examples do not prove the complete destination-specific content policy. | Verify the target behavior: Every permitted content projection shall remove credentials and apply size limits. |

## Migration and compatibility

Decide the common event representation and default rich/thinking-content policy. Observation must not become an execution or durable-event owner.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Content-permission acceptance additions

[Content projection](../../../lib/jido_ai/observe/content.ex) now applies separate
Profile permissions: `stream_content`, `store_content`, `stream_reasoning`,
`store_reasoning`, and `diagnostics_content`. All default to false. Inspection
also requires `include_content: true`. Ordinary user and assistant text remains
in storage. Tool arguments and results require `store_content: true` for storage
and `stream_content: true` for public streams. These permissions are independent.
Known credential keys are removed even when content is permitted.

Execution uses native data. Retained history uses omission markers when content
is removed. Later model continuation returns `context_content_not_retained`
instead of fabricating missing input. Standalone checkpoint export is withheld
when the native payload cannot satisfy storage and stream permissions. The
private standalone Agent is a live execution resource, not an exported store.
No second result store was added. `Request.await/2` reads the retained result.

Evidence: [permission matrix](../../../test/jido_ai/observe/content_test.exs),
[authoring](../../../test/jido_ai/authoring/content_permissions_test.exs), and
[default projection examples](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs).
Full provider-shape coverage, global byte budgets, and the advanced event/version
contract remain broader work. Existing telemetry sanitization is unchanged; do
not infer full telemetry conformance from these stream/storage repairs.

## Runtime repair follow-up

The current worktree adds runtime repairs over the audit baseline. Dependencies
are unchanged. The [audit summary](../README.md#example-driven-design-audit)
separates the repaired scenarios from the remaining advanced API gates. A passing
scenario is not complete requirement conformance.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
