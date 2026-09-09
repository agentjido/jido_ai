> Seam review entry point. This document is pending approval.

# 00 — Package boundary and invariants

## Briefing

Jido AI ownership is now described in several files, and some old text still says that this package owns workflows. The target is one approved package boundary and one invariant set. The main change is to state that Jido AI owns AI behavior while Jido, Jido Action, Jido Signal, and the host own their lower-level systems.

## Why this seam exists

- Owner: Jido AI maintainers, with sibling-package owner review.
- Owns: Package ownership, stable terms, portability rules, effect timing, and boundary tests.
- Does not own: Model features, runtime features, compatibility code, or new execution systems.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Ownership | Spread across package files, migration notes, and sibling designs | One approved bright line |
| Workflow claim | Some package text says that Jido AI owns workflows | Flow definition and execution are assigned to `jido_action` |
| Runtime access | Current code uses public contracts in many paths | All AI code uses only public Jido, Exec, and Signal contracts |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner seam |
| --- | --- | --- | --- |
| Stale ownership text | It can cause duplicate systems | One consistent package description | 00 |
| No local invariant set | Later seams can make conflicting choices | Stable `BND` requirements and invariants | 00 |

## Decisions requested

1. **Durable orchestration:** Approve host ownership for V3 unless a separate package is named.
   Effect: Jido AI cannot become a durable workflow engine.
2. **Workflow boundary:** Approve `Jido.Flow` and `Jido.Exec` as the only in-memory graph and execution contracts.
   Effect: Later seams can remove duplicate mechanics.

## Dependencies

- Prerequisites: None.
- Dependents: All other seams.
- Blockers: Durable orchestration ownership is not final.

## Documents

- [Target design](design.md).
- [Alignment plan](alignment.md).
