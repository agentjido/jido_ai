> Seam review entry point. Pending approval.

# 11 — Checkpoints and resume

## Briefing

Execution.Checkpoint owns shared capture/restore, portable field selection, and deadlines. ReAct.Checkpoint owns adapter encoding and fingerprints. ReAct.State and Token retain the standalone format and run identity. Orchestration owns process recovery; restored pending work is not a live saved task. Canonical Session/Thread codecs are separate from runtime snapshots.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Execution.Checkpoint, standalone ReAct Checkpoint/State/Token, and Orchestration recovery integration.
- Owns: checkpoints and resume within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve advanced atomic resource restoration, linked resume identity, no-repeat completed work, bounded codecs, and uncertain-effect decisions. Storage and durable deduplication services remain host concerns. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [RES-GAP-001](alignment.md#gap-register) | Shared snapshot schema and standalone codecs exist; complete target envelope and every bound still need comparison. | Keep portable-only snapshot rules and method-specific scope. | 11; dependencies below |
| [RES-GAP-002](alignment.md#gap-register) | Trusted data is rebound and deadlines are limited. Full atomic model/skill/capability/host-resource resolution is broader. | Retain staged all-resource restore acceptance. | 11; dependencies below |
| [RES-GAP-003](alignment.md#gap-register) | Standalone resume retains run_id; the target requires a new linked run. | Treat identity change as a compatibility decision with 07/12. | 11; dependencies below |
| [RES-GAP-004](alignment.md#gap-register) | Fresh Agent/runtime work receives selected portable snapshot data; no live Exec state is encoded. | Extend no-runtime-reconstruction proof to the full target matrix. | 11; dependencies below |
| [RES-GAP-005](alignment.md#gap-register) | General durable deduplication and explicit uncertain-effect host decisions are not a complete current protocol. | Retain stable effect identity and blocked-resume decisions; host owns durable storage. | 11; dependencies below |
| [RES-GAP-006](alignment.md#gap-register) | Current-version guards exist. The preceding suite covers recovery, but every target version/rejection boundary needs mapping. | Keep explicit version rejection; do not infer V2 import support. | 11; dependencies below |

## Decisions requested

Decide new-run lineage, effect identity, and atomic binding restoration without assuming exactly-once effects or extending resume to all methods automatically.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [04 Shared AI execution](../04_ai_execution/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md), [09 Skills and resources](../09_skills_resources/alignment.md).
- Dependents: 12.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
