> Seam alignment review. Pending approval.

# Request orchestration and active input alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Orchestration owns the live API; Jido.Session is a separate portable value. Record is a validated internal map with pending/completed/failed statuses. Cancellation and interruption are failure outcomes rather than distinct record status atoms. Coordinator owns active workers, completion, recovery, and ordered commit coordination. Request streams are best-effort views, not durable logs.

- Current owner: Request, Orchestration and Coordinator, PendingInputServer, Thread.Control, and core Plugin integration.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Define one request contract across authored and standalone paths, plus advanced linked delegation, handoff, bounded active input, and explicit delivery/cancellation guarantees.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/orchestration.ex](../../../lib/jido_ai/orchestration.ex) | Live public API |
| [lib/jido_ai/orchestration/coordinator.ex](../../../lib/jido_ai/orchestration/coordinator.ex) | Process and settlement owner |
| [lib/jido_ai/orchestration/record.ex](../../../lib/jido_ai/orchestration/record.ex) | Actual record schema |
| [lib/jido_ai/orchestration/cancel.ex](../../../lib/jido_ai/orchestration/cancel.ex) | Cancellation transition |
| [lib/jido_ai/request.ex](../../../lib/jido_ai/request.ex) | Handles and waiting |
| [lib/jido_ai/tool_source.ex](../../../lib/jido_ai/tool_source.ex) | Inert delegation declarations |

### Examples and tests

- [Example briefing](../../../examples/02_requests/02_01_session/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/02_requests/02_01_session): deterministic example evidence.
- [test/jido_ai/orchestration/orchestration_test.exs](../../../test/jido_ai/orchestration/orchestration_test.exs): detailed boundary evidence.
- [test/jido_ai/orchestration/inspection_test.exs](../../../test/jido_ai/orchestration/inspection_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Define one request contract across authored and standalone paths, plus advanced linked delegation, handoff, bounded active input, and explicit delivery/cancellation guarantees.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `SES-GAP-001` | `SES-REQ-018`, `SES-REQ-019` | Request.await_many exists; the prior row incorrectly linked it to the stream-sink requirement. | Implemented; evidence incomplete | Keep ordering/timeout/cleanup proof as an API evidence item, separate from SES-REQ-022. |
| `SES-GAP-002` | `SES-REQ-011`, `SES-REQ-013`, `SES-REQ-014`, `SES-REQ-015`, `SES-REQ-024`, `SES-REQ-025` | Start/settle/cancel transitions and failure retention exist. Proposed statuses and replies differ from Record and current APIs. | Partially implemented | Resolve record vocabulary, reply compatibility, and rollback limits. |
| `SES-GAP-003` | `SES-REQ-027`, `SES-REQ-028`, `SES-REQ-029`, `SES-REQ-030` | Steering, injection, source references, and bounded input exist. Queued input is not proof of model consumption. | Implemented; evidence incomplete | Complete malformed/stale/queued/applied acceptance cases. |
| `SES-GAP-004` | `SES-REQ-020`, `SES-REQ-021`, `SES-REQ-022`, `SES-REQ-032` | Coordinator and streams have lifecycle policies. A full sink/caller/owner loss matrix is still required. | Implemented; evidence incomplete | Do not conflate caller exit with cancellation of shared work. |
| `SES-GAP-005` | Resolved compile and naming issue | The former compile blocker is resolved and Orchestration replaces the live Session namespace. | Superseded | Retain current lifecycle gates. |
| `SES-GAP-006` | `SES-REQ-035`, `SES-REQ-036`, `SES-REQ-037`, `SES-REQ-038`, `SES-REQ-039`, `SES-REQ-040`, `SES-REQ-041`, `SES-REQ-042` | Subagent/handoff declarations do not implement linked requests, context transfer, fan-out, or peer cancellation. | Proposed; not implemented | Retain delegation requirements with 03/06/11/12; core owns topology. |

## Request adapter review gap

The [data-boundary proposal](design.md#proposed-data-boundary) replaces neither
core commit nor Coordinator lifetime ownership.
[Transcript](../../../lib/jido_ai/orchestration/transcript.ex) records message
maps and waits for publication before extending history_delta.
[Coordinator](../../../lib/jido_ai/orchestration/coordinator.ex) exposes separate
history, checkpoint, progress, and control calls. Their replies do not have one
validated vocabulary for receipt, commit, and checkpoint acknowledgment.

Resolve seam 01 batch/receipt data and seam 04 safe positions first. Future
acceptance evidence covers accepted versus committed replies, rejection,
commit-unknown without retry, ordered input, caller loss, and checkpoint
acknowledgment without a durability claim. Exact adapter tags and combined
input/checkpoint control remain decisions, not implemented contracts.

## Selected conversation policy: gaps and acceptance

The [selected policy](design.md#selected-conversation-commit-policy) is not
fully implemented. Session mode publishes history as work proceeds through
[Transcript](../../../lib/jido_ai/orchestration/transcript.ex). Turn mode
appends history_delta only on success in
[Runtime.Run](../../../lib/jido_ai/runtime/run.ex). Failed turn-mode evidence
and success-only projection need alignment. Delegation declarations do not
implement parent-owned result acceptance.

Use one complete support-agent example with deterministic MockLLM scenarios,
a command runner, README, manifest, and executable tests. Add Livebook where
useful. This is acceptance design, not authorization to build it now.

| Scenario | Acceptance evidence | Requirements |
| --- | --- | --- |
| Two successful requests | Second request continues the first completed conversation | SES-REQ-044, VAL-REQ-023 |
| Failure after a completed tool round | Log retains work; next context excludes failed work | SES-REQ-043, SES-REQ-045 |
| Cancellation during parallel tools | Completed results retained; unresolved calls excluded from next context | SES-REQ-043, SES-REQ-045, VAL-REQ-024 |
| Queued versus consumed steering | Only consumed input enters history | SES-REQ-043, SES-REQ-046 |
| Bounded delegation | Limited context, parent append once, duplicate and late-result rejection | SES-REQ-047, SES-REQ-048 |
| Deferred context replacement | Active work isolated; replacement promoted only after success | SES-REQ-044, SES-REQ-045 |

All new acceptance cases are Proposed; not implemented as a complete policy.
Use controlled worker release, not timing-based sleeps. Resolve promotion
metadata with seam 01, safe boundaries with 04, and recovery with 11.

Pattern references, not Jido AI acceptance proof:
[atomic continuation](../../../../jidoka/test/jidoka/session_atomic_continuation_test.exs),
[memory after commit](../../../../jidoka/test/jidoka/session_memory_commit_order_test.exs),
[delegation versus handoff](../../../../jidoka/test/parity/bounded_delegation_vs_ownership_handoff_test.exs),
[controlled parallel work](../../../../jidoka/examples/durable_refund/lib/scenarios/parallel_operations.ex),
and [complete example layout](../../../../jidoka/examples/README.md).

## Request and attempt policy gap

The [selected meanings](design.md#selected-request-and-attempt-meanings) exceed
the current Record schema: pending/completed/failed with request and run IDs.
Explicit attempt history and failure classification need alignment. Existing
error details are not proof of the complete classification contract.

Acceptance evidence covers a failed attempt followed by success, retained
prior outcomes, stale/superseded settlement rejection, delivery failure after
commit, and cancellation with uncertain external effects. SES-REQ-013 now
uses active attempt identity rather than assuming run_id uniquely identifies
an attempt. The acceptance matrix reflects this selected identity meaning.
Delegation links remain recommended data, separate from topology. Resolve
representation with seam 11 and observation with seam 12; no structs selected.

## Decisions and dependency gates

Resolve record/error semantics and cancellation replies before changing current API shapes. Define child/peer delegation as linked work above core topology, not a new Agent model.

- Prerequisites: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md).
- Dependents: 08, 09, 11.
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
| `SES-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Every AI request shall have a nonempty request ID and run ID before admission commits. |
| `SES-REQ-002` | Decision required | See current contract and gap register | Verify the target behavior: A request ID shall identify the logical request and a run ID shall identify one live execution attempt. |
| `SES-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: When the same request ID already exists in retained Agent state, admission shall reject the request as a duplicate. |
| `SES-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: For the first V3 release, session admission shall reject a new request while another request record is pending for the same Agent. |
| `SES-REQ-005` | Decision required | See current contract and gap register | Verify the target behavior: `ask/3` shall return a handle only after the admission candidate and request record commit successfully. |
| `SES-REQ-006` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Untrusted request input shall not set a runtime stream sink, provider client, credential, or transport option. |
| `SES-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Turn mode shall execute the canonical AI Flow inside one core Turn and shall return only after the final candidate commits or the Turn fails. |
| `SES-REQ-008` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Session mode shall commit admission before it starts model or tool work. |
| `SES-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Session mode shall start live work only from a validated post-commit Directive owned by the Orchestration Plugin. |
| `SES-REQ-010` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Turn and session modes shall use the same effective profile, model gateway, tool bridge, reasoning method, limits, output validation, and result contract. |
| `SES-REQ-011` | Decision required | See current contract and gap register | Verify the target behavior: A committed request record shall be portable and shall not contain a server reference, PID, task, monitor, stream sink, provider object, or Exec handle. |
| `SES-REQ-012` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The Orchestration Plugin shall own request records under one declared Agent state key. |
| `SES-REQ-013` | Partially implemented | Current request/run matching lacks distinct attempt identity | Verify logical request and active attempt matching, with stale and duplicate settlement rejection. |
| `SES-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A successful settlement shall assemble the complete candidate Agent, update the declared result and history fields, update the request record, and return approved Directives in one Turn result. |
| `SES-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A failed settlement shall preserve the prior domain state except for the terminal request record and approved failure metadata. |
| `SES-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A committed request outcome shall be authoritative even if a later terminal stream item cannot be delivered. |
| `SES-REQ-017` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Request retention shall never evict pending work and shall use a deterministic order for terminal record eviction. |
| `SES-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: `await/2` shall use public AgentServer or session APIs and shall select the record by request ID. |
| `SES-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An await timeout shall not change the committed request status or cancel the request unless the caller explicitly requests cancellation. |
| `SES-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A request stream shall be an ordered best-effort live view and shall not be described as a durable event log. |
| `SES-REQ-021` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A request stream shall contain exactly one terminal item when its sink remains available through termination. |
| `SES-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: If a stream sink terminates, the request shall continue unless profile policy explicitly requires stream ownership. |
| `SES-REQ-023` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A cancellation request shall name a request ID or resolve unambiguously to the single pending request. |
| `SES-REQ-024` | Decision required | See current contract and gap register | Verify the target behavior: If cancellation commits before settlement, the record shall become `:cancelled`, pending continuations shall stop, and later settlement shall be stale. |
| `SES-REQ-025` | Decision required | See current contract and gap register | Verify the target behavior: If settlement commits before cancellation, cancellation shall return `:request_already_finished` and shall not replace the terminal result. |
| `SES-REQ-026` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The cancellation contract shall state that it cannot roll back a model call, tool call, or other external effect that completed before cancellation. |
| `SES-REQ-027` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Steering and injection shall be available only for a method and profile that declare active-input support. |
| `SES-REQ-028` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A control item shall include a control ID, kind, visible content, expected request ID, source, and bounded references. |
| `SES-REQ-029` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A control acknowledgement shall state whether the item was queued, rejected, or applied; a queued result shall not claim consumption. |
| `SES-REQ-030` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The live control queue shall be bounded and shall not be stored as a generic Agent mailbox. |
| `SES-REQ-031` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Standalone request APIs shall use the same public Agent, Plugin, Flow, Exec, and request contracts as authored Agents. |
| `SES-REQ-032` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A standalone facade shall own and stop any local AgentServer that it creates. |
| `SES-REQ-033` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Session inspection shall separate the committed request record from transient live samples. |
| `SES-REQ-034` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Inspection shall bound trace and metadata size and shall mark truncated data. |
| `SES-REQ-035` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When an Agent delegates work, Orchestration shall correlate the delegated request with its originating request and target Agent identity. |
| `SES-REQ-036` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When Orchestration sends delegated work, it shall transfer only context selected by the configured delegation policy. |
| `SES-REQ-037` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When a delegated result arrives, the originating Orchestration shall apply the parent request policy before proposing a parent Thread update. |
| `SES-REQ-038` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: If the parent request is terminal when a delegated result arrives, then Orchestration shall apply an explicit late-result policy without silently replacing the committed outcome. |
| `SES-REQ-039` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When a caller cancels delegated work on a peer, Orchestration shall cancel only the selected work unless the host separately authorizes stopping that Agent. |
| `SES-REQ-040` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: Where delegation is enabled, Orchestration shall validate finite depth, concurrency, and request-budget limits before admitting delegated work. |
| `SES-REQ-041` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When a host authorizes a handoff, Orchestration shall record which request owner is responsible for subsequent completion and cancellation. |
| `SES-REQ-042` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When Orchestration emits a delegation lifecycle event, it shall include the parent and delegated request identities through seam 12's observation contract. |

## Migration and compatibility

Resolve record/error semantics and cancellation replies before changing current API shapes. Define child/peer delegation as linked work above core topology, not a new Agent model.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
