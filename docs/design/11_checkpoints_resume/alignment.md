> Seam alignment review. Pending approval.

# Checkpoints and resume alignment

## Status

- Reviewed: 2026-09-15.
- Code: `v3-spike`, HEAD `c4e57c8d34d09ffc922c37fb41cccc2e1491123e`, plus the uncommitted Orchestration and canonical-value file reorganization.
- Prerequisite alignments used: [04 Shared AI execution](../04_ai_execution/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: source and test inspection in this documentation task. The preceding code-change run reported 2,809 passing tests and one existing exclusion, including authoring and MockLLM examples. That run is not proof of every target requirement; no Elixir tests were rerun here.

## Current architecture

Runtime.Checkpoint owns shared capture/restore, portable field selection, and deadlines. ReAct.Checkpoint owns adapter encoding and fingerprints. ReAct.State and Token retain the standalone format and run identity. Orchestration owns process recovery; restored pending work is not a live saved task. Canonical Session/Thread codecs are separate from runtime snapshots.

- Current owner: Runtime.Checkpoint, standalone ReAct Checkpoint/State/Token, and Orchestration recovery integration.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve advanced atomic resource restoration, linked resume identity, no-repeat completed work, bounded codecs, and uncertain-effect decisions. Storage and durable deduplication services remain host concerns.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/runtime/checkpoint.ex](../../../lib/jido_ai/runtime/checkpoint.ex) | Shared snapshot boundary |
| [lib/jido_ai/reasoning/react/checkpoint.ex](../../../lib/jido_ai/reasoning/react/checkpoint.ex) | ReAct encoding adapter |
| [lib/jido_ai/reasoning/react/state.ex](../../../lib/jido_ai/reasoning/react/state.ex) | Standalone format and identity |
| [lib/jido_ai/reasoning/react/token.ex](../../../lib/jido_ai/reasoning/react/token.ex) | Token codec |
| [lib/jido_ai/orchestration/coordinator.ex](../../../lib/jido_ai/orchestration/coordinator.ex) | Runtime recovery owner |

### Examples and tests

- [Example briefing](../../../examples/14_resume/14_03_checkpoint_resume/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/14_resume/14_03_checkpoint_resume): deterministic example evidence.
- [test/jido_ai/runtime/checkpoint_test.exs](../../../test/jido_ai/runtime/checkpoint_test.exs): detailed boundary evidence.
- [test/authoring/agents/recovery_test.exs](../../../test/authoring/agents/recovery_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve advanced atomic resource restoration, linked resume identity, no-repeat completed work, bounded codecs, and uncertain-effect decisions. Storage and durable deduplication services remain host concerns.

Preserve current public behavior unless an approved decision includes a
migration. No runtime or example changes are authorized by this review.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `RES-GAP-001` | `RES-REQ-001`, `RES-REQ-002`, `RES-REQ-003`, `RES-REQ-004`, `RES-REQ-005`, `RES-REQ-006`, `RES-REQ-007` | Shared snapshot schema and standalone codecs exist; complete target envelope and every bound still need comparison. | Partially implemented | Keep portable-only snapshot rules and method-specific scope. |
| `RES-GAP-002` | `RES-REQ-008`, `RES-REQ-015`, `RES-REQ-016` | Trusted data is rebound and deadlines are limited. Full atomic model/skill/capability/host-resource resolution is broader. | Partially implemented | Retain staged all-resource restore acceptance. |
| `RES-GAP-003` | `RES-REQ-017`, `RES-REQ-021` | Standalone resume retains run_id; it is not a unique attempt identity. | Partially implemented | Keep logical request identity and add distinct attempt identity; representation and migration remain open with 07/12. |
| `RES-GAP-004` | `RES-REQ-018` | Fresh Agent/runtime work receives selected portable snapshot data; no live Exec state is encoded. | Implemented; evidence incomplete | Extend no-runtime-reconstruction proof to the full target matrix. |
| `RES-GAP-005` | `RES-REQ-010`, `RES-REQ-022`, `RES-REQ-023`, `RES-REQ-024` | General durable deduplication and explicit uncertain-effect host decisions are not a complete current protocol. | Proposed; not implemented | Retain stable effect identity and blocked-resume decisions; host owns durable storage. |
| `RES-GAP-006` | `RES-REQ-026`, `RES-REQ-027`, `RES-REQ-028`, `RES-REQ-029` | Current-version guards exist. The preceding suite covers recovery, but every target version/rejection boundary needs mapping. | Implemented; evidence incomplete | Keep explicit version rejection; do not infer V2 import support. |

## Batch recovery review gap

[Runtime.Checkpoint](../../../lib/jido_ai/runtime/checkpoint.ex) uses a direct
Coordinator checkpoint call. Coordinator has a separate checkpoint acknowledgment
path. Neither an acknowledgment nor an entry ID establishes durable storage
or a complete deduplication protocol.

The [recovery proposal](design.md#proposed-batch-and-boundary-recovery-contract)
depends on seams 01 and 07 defining batches, receipts, and commit-unknown.
Future evidence covers lost replies, no retry after unknown commit, stale
snapshots, stable batch references, and host durability confirmation. Combining
checkpoint and input control remains open. Retain current token compatibility
and all advanced recovery requirements; no new tests ran here.

## Decisions and dependency gates

Decide new-run lineage, effect identity, and atomic binding restoration without assuming exactly-once effects or extending resume to all methods automatically.

- Prerequisites: [04 Shared AI execution](../04_ai_execution/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Dependents: 12.
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
| `RES-REQ-001` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI Agent persistence shall use `Jido.Agent.checkpoint/2`, `Jido.Agent.restore/3`, and `Jido.Persistence` public contracts. |
| `RES-REQ-002` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall not define a competing Agent checkpoint envelope, persistence adapter, revision scheme, or restore supervisor. |
| `RES-REQ-003` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A generated AI Agent checkpoint callback shall compose with the core default checkpoint and shall preserve Agent module, version, identity, and complete portable state. |
| `RES-REQ-004` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A Jido AI restore callback shall return a fully validated Agent of the requested module and version through the core restore contract. |
| `RES-REQ-005` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An AI execution checkpoint shall have a type and version and shall contain only portable semantic data. |
| `RES-REQ-006` | Decision required | See current contract and gap register | Verify the target behavior: An AI execution checkpoint shall identify profile, method, request, original run, phase, context, method state, result state, remaining limits, completed calls, effects, and required binding references. |
| `RES-REQ-007` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Checkpoint creation shall reject a live Exec state, compiled workflow, PID, task, monitor, stream sink, function, client, secret, or unsupported struct. |
| `RES-REQ-008` | Decision required | See current contract and gap register | Verify the target behavior: A checkpoint shall store stable registry references for executable modules, schemas, skills, and provider-independent models instead of live values. |
| `RES-REQ-009` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Remaining limits shall never be greater than the limits of the original request. |
| `RES-REQ-010` | Decision required | See current contract and gap register | Verify the target behavior: Completed tool calls shall keep their call ID, tool identity, portable result, effect identity, and idempotency metadata. |
| `RES-REQ-011` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A core Agent checkpoint can contain a pending request record, but it shall not claim that the matching live session task is saved. |
| `RES-REQ-012` | Decision required | See current contract and gap register | Verify the target behavior: When an Agent restores with a pending request and no live runtime ownership, Jido AI shall normalize the record to `:interrupted` before new request admission. |
| `RES-REQ-013` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Restore shall not start a model call, tool call, Flow, stream, or session automatically unless the host explicitly selects an approved auto-resume policy. |
| `RES-REQ-014` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A restored stream sink shall always be absent; a resumed caller shall attach a new sink to the new run. |
| `RES-REQ-015` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A restored runtime resource shall be re-resolved from trusted host context and shall never be taken from checkpoint data. |
| `RES-REQ-016` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Resume shall validate Agent identity, Agent version, AI checkpoint version, profile ID, method compatibility, skill versions, registry references, and remaining limits before work starts. |
| `RES-REQ-017` | Partially implemented | See RES-GAP-003 | Verify retained logical request identity and a new attempt ID on resume. |
| `RES-REQ-018` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Resume shall create a new canonical Flow execution and shall not reconstruct a live Exec or Runic state. |
| `RES-REQ-019` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Resume shall not repeat a completed model or tool step when its complete portable result is present and accepted by the method contract. |
| `RES-REQ-020` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: If a required prior result is absent or incompatible, resume shall fail or restart from an explicitly approved safe phase; it shall not guess. |
| `RES-REQ-021` | Partially implemented | See RES-GAP-003 | Verify previous/new attempt IDs, phase, skipped work, and delivery-risk metadata. |
| `RES-REQ-022` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: The public resume contract shall state that external effects are not exactly once. |
| `RES-REQ-023` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When a tool declares idempotency support, Jido AI shall reuse its stable effect or call idempotency key on resume. |
| `RES-REQ-024` | Proposed; not implemented | No complete implementation claimed | Verify the target behavior: When a non-idempotent completed effect has uncertain checkpoint status, resume shall require an explicit host decision or return a blocked-resume error. |
| `RES-REQ-025` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Checkpoint success shall not imply that later Signal delivery, stream delivery, or external side effects are durable. |
| `RES-REQ-026` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: An AI checkpoint decoder shall accept only the current V3 version and shall reject every other version. |
| `RES-REQ-027` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A checkpoint without an explicit current version shall fail before restore or resume work starts. |
| `RES-REQ-028` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: Jido AI shall not import V2 Agent, Strategy, session, or ReAct checkpoint formats. |
| `RES-REQ-029` | Implemented; evidence incomplete | [Current subsystem evidence](#inputs-and-evidence); not full requirement proof | Verify the target behavior: A failed decode or validation shall not modify the stored source checkpoint. |

## Migration and compatibility

Decide new-run lineage, effect identity, and atomic binding restoration without assuming exactly-once effects or extending resume to all methods automatically.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Attempt and uncertainty acceptance additions

| Requirement | Evidence state | Acceptance outcome |
| --- | --- | --- |
| RES-REQ-030 | Proposed; not implemented | Retry/resume retains request ID but assigns a distinct attempt ID |
| RES-REQ-031 | Proposed; not implemented | Prior attempt outcomes remain available after a new attempt |
| RES-REQ-032 | Proposed; not implemented | Uncertain effects block automatic retry; each permitted exception has explicit evidence or caller authority |

Current ReAct run_id retention does not satisfy unique attempt identity.
Review failure classification and delivery independence with seam 07, and
identity projection with seam 12. No tests ran here.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
