> Seam review entry point. Pending approval.

# 90 — Migration and delivery

## Briefing

The execution CLI is removed. Install, skill, and quality Mix tasks and consumer test helpers remain. The package is version 2.3.0 using V3 beta Hex dependencies and a pinned ReqLLM Git source. Current guides/examples use V3 authoring. The preceding full verification passed 2,809 tests with one existing exclusion; it is not a complete stable-release rehearsal.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Package metadata, guides, examples, public test helpers, Mix tasks, and release evidence.
- Owns: migration and delivery within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve the complete capability/disposition inventory, migrations, compatibility decisions, deterministic consumer support, and release/security/performance/operational gates. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [DEL-GAP-001](alignment.md#gap-register) | Current API and feature inventories exist; complete approved V2 disposition and target acceptance coverage remains. | Preserve every capability until disposition is explicit. | 90; dependencies below |
| [DEL-GAP-002](alignment.md#gap-register) | V3 beta Hex dependencies replace the old sibling-path assumption. Version and package description still need release decisions. | Review source policy, version matrix, and metadata. | 90; dependencies below |
| [DEL-GAP-003](alignment.md#gap-register) | Full code tests previously passed; documentation generation, packaging, security, load, and release rehearsal are separate gates. | Keep a complete release evidence ledger. | 90; dependencies below |
| [DEL-GAP-005](alignment.md#gap-register) | The execution CLI is removed while DEL-REQ-025/026 and DEL-DEC-003 describe a CLI target. | Retain the proposal for explicit disposition; do not restore a CLI from docs alone. | 90; dependencies below |
| [DEL-GAP-006](alignment.md#gap-register) | A complete approved performance/security/operational readiness package is not established by unit tests. | Retain budgets, threat checks, load tests, and rollback gates. | 90; dependencies below |
| [DEL-GAP-007](alignment.md#gap-register) | Local verification is not a clean multi-package release rehearsal. | Keep dependency-order release verification and external package ownership explicit. | 90; dependencies below |

## Decisions requested

Reconcile old CLI and reduced-method release recommendations explicitly. Separate current tested functionality from an approved stable release surface.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [12 Observation and diagnostics](../12_observation_diagnostics/alignment.md).
- Dependents: None.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
