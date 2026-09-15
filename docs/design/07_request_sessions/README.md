> Seam review entry point. Pending approval.

# 07 — Request orchestration and active input

## Briefing

Orchestration owns the live API; Jido.Session is a separate portable value. Record is a validated internal map with pending/completed/failed statuses. Cancellation and interruption are failure outcomes rather than distinct record status atoms. Coordinator owns active workers, completion, recovery, and ordered commit coordination. Request streams are best-effort views, not durable logs.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Request, Orchestration and Coordinator, PendingInputServer, Thread.Control, and core Plugin integration.
- Owns: request orchestration and active input within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Define one request contract across authored and standalone paths, plus advanced linked delegation, handoff, bounded active input, and explicit delivery/cancellation guarantees. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [SES-GAP-001](alignment.md#gap-register) | Request.await_many exists; the prior row incorrectly linked it to the stream-sink requirement. | Keep ordering/timeout/cleanup proof as an API evidence item, separate from SES-REQ-022. | 07; dependencies below |
| [SES-GAP-002](alignment.md#gap-register) | Start/settle/cancel transitions and failure retention exist. Proposed statuses and replies differ from Record and current APIs. | Resolve record vocabulary, reply compatibility, and rollback limits. | 07; dependencies below |
| [SES-GAP-003](alignment.md#gap-register) | Steering, injection, source references, and bounded input exist. Queued input is not proof of model consumption. | Complete malformed/stale/queued/applied acceptance cases. | 07; dependencies below |
| [SES-GAP-004](alignment.md#gap-register) | Coordinator and streams have lifecycle policies. A full sink/caller/owner loss matrix is still required. | Do not conflate caller exit with cancellation of shared work. | 07; dependencies below |
| [SES-GAP-006](alignment.md#gap-register) | Subagent/handoff declarations do not implement linked requests, context transfer, fan-out, or peer cancellation. | Retain delegation requirements with 03/06/11/12; core owns topology. | 07; dependencies below |

## Decisions requested

Resolve record/error semantics and cancellation replies before changing current API shapes. Define child/peer delegation as linked work above core topology, not a new Agent model.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [06 Core runtime and Signal integration](../06_runtime_signal_integration/alignment.md).
- Dependents: 08, 09, 11.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
