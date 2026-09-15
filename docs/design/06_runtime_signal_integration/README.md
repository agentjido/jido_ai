> Seam review entry point. Pending approval.

# 06 — Core runtime and Signal integration

## Briefing

Runtime and Orchestration Plugins use separate core Agent and AgentServer facets. Orchestration owns AI request coordination above core commit. Canonical Session/Thread values are local to jido_ai. Signal types and existing internal wire names were preserved during the module rename.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Runtime.Plugin and Orchestration.Plugin Agent/AgentServer facets, route/directive adapters, and typed Signal data.
- Owns: core runtime and signal integration within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Use only public core Plugin, Agent, Flow, and Signal contracts. Preserve route validation, trusted runtime binding, post-commit work, event transport, and topology integration. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [INT-GAP-001](alignment.md#gap-register) | Core route validation and boundary tests are present; complete route reachability/collision proof is not inferred. | Review INT-REQ-006 and facet ownership. | 06; dependencies below |
| [INT-GAP-002](alignment.md#gap-register) | Static authoring and runtime binding are separated. Every optional Plugin callback still needs a purity audit for the full target. | Keep runtime services out of static preparation. | 06; dependencies below |
| [INT-GAP-004](alignment.md#gap-register) | Typed Signal modules exist; complete field-by-field correlation across all events remains a separate matrix. | Align with seam 12. | 06; dependencies below |
| [INT-GAP-005](alignment.md#gap-register) | Current delivery behavior must be compared with the no-hidden-self-routing proposal, not changed by documentation. | Review explicit dispatcher and loop-prevention cases. | 06; dependencies below |

## Decisions requested

Review delivery defaults and callback purity against current core contracts. AI delegation must not introduce a second topology owner.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md), [01 Canonical interaction and AI values](../01_ai_values/alignment.md), [04 Shared AI execution](../04_ai_execution/alignment.md).
- Dependents: 07, 09.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
