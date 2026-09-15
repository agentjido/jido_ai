> Seam review entry point. Pending approval.

# 00 — Package boundary and invariants

## Briefing

Jido AI lowers Profiles into core Agent routes and Plugins and uses Flow/Exec for execution. Session and Thread values belong to this package. Orchestration owns AI live-work coordination while core Jido owns Agent commit and topology. The package version remains 2.3.0 with V3 beta dependencies and a pinned ReqLLM Git source.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Jido.AI package boundary; core Jido, jido_action, jido_signal, and host interfaces.
- Owns: package boundary and invariants within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve the complete AI capability set above public lower-package contracts. Separate in-memory coordination from host-owned durability and external-effect guarantees. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [BND-GAP-001](alignment.md#gap-register) | Release metadata still uses 2.3.0 and an Actions/Workflows description. V3 dependency selection is present; a release version is not. | Review release wording and version policy in 90. | 00; dependencies below |
| [BND-GAP-002](alignment.md#gap-register) | ToolAttempt returns a continuation after a bounded Process.sleep. The no-sleep target is not implemented. | Decide execution-delay ownership with 03/04; do not add a generic scheduler here. | 00; dependencies below |
| [BND-GAP-004](alignment.md#gap-register) | Boundary tests reject invalid routes, fields, managed Plugins, and initialized hosts. This is not a proof of every public path. | Complete per-entry-point ownership evidence. | 00; dependencies below |
| [BND-GAP-005](alignment.md#gap-register) | Candidate/effect separation exists. External effects are not rolled back by an Agent commit failure. | Retain idempotency and uncertain-outcome design work in 03/11. | 00; dependencies below |

## Decisions requested

Confirm the retry-delay boundary and the external-effect contract before changing execution mechanics. Release metadata is separate delivery work.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: None.
- Dependents: 01, 06.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
