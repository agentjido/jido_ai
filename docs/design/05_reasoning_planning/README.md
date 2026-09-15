> Seam review entry point. Pending approval.

# 05 — Reasoning and planning methods

## Briefing

ReAct, ChainOfThought, ChainOfDraft, AlgorithmOfThoughts, TreeOfThoughts, GraphOfThoughts, TRM, and Adaptive remain. Linear, tree, graph, and recursive engines integrate with shared execution. Callable reasoning uses a prompt and host-bound Profile. Planning Actions exist; they are not a general executable Plan system.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Reasoning methods, shared method engines, method state/results, and planning Actions.
- Owns: reasoning and planning methods within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve all eight methods, advanced search and recursive behavior, custom-method extension, and portable plans. Keep algorithms above Flow and provider/tool boundaries. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [RSN-GAP-001](alignment.md#gap-register) | Built-in method IDs, options, state, and limits exist. A uniform public descriptor/Flow factory is not the current API. | Preserve descriptor and custom-method work as a target. | 05; dependencies below |
| [RSN-GAP-002](alignment.md#gap-register) | All eight methods use shared execution and method limits. Complete limit conformance is not proved by one method example. | Review method-specific construction and execution matrices. | 05; dependencies below |
| [RSN-GAP-003](alignment.md#gap-register) | Search engines implement ordering and pruning; target-wide deterministic tie/prune diagnostics need direct proof. | Retain deterministic search contracts. | 05; dependencies below |
| [RSN-GAP-004](alignment.md#gap-register) | Results retain method-specific shapes and some reasoning metadata. The uniform result/private-thinking target needs review. | Coordinate visibility with 01/12. | 05; dependencies below |
| [RSN-GAP-005](alignment.md#gap-register) | There is no general trusted custom-method registry matching RSN-REQ-022. | Retain registration, validation, and collision requirements. | 05; dependencies below |
| [RSN-GAP-006](alignment.md#gap-register) | Planning Actions do not establish a portable Plan type and deterministic executable lowering contract. | Retain Plan design; executable work remains Flow or host-owned. | 05; dependencies below |

## Decisions requested

Do not infer a reduced stable method set from the old first-release recommendation. Decide extension registration, common results, thinking visibility, and executable Plan semantics explicitly.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [04 Shared AI execution](../04_ai_execution/alignment.md).
- Dependents: 07, 08, 10.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
