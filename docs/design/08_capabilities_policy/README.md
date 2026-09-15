> Seam review entry point. Pending approval.

# 08 — Capabilities and policy

## Briefing

Optional Plugins compose chat, reasoning, planning, routing, policy, retrieval, and quota. Capability.run accepts either a Profile-bound reasoning input or defaults-bound capability input. Stores and policies remain distinct from core Agent ownership; there is no second AI Agent authoring model.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Capability, ReasoningCapability, optional Plugins, ModelRouter, Quota, Retrieval.Store, and capability Actions.
- Owns: capabilities and policy within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve advanced capability composition, contribution validation, deterministic ordering, bounded retrieval, routing diagnostics, and quota policy. Use core Plugin contracts rather than a parallel Plugin framework. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [CAP-GAP-001](alignment.md#gap-register) | Plugins and bindings exist; there is no universal contribution value matching the proposal. | Evaluate the descriptor against existing core Plugin contracts. | 08; dependencies below |
| [CAP-GAP-002](alignment.md#gap-register) | Core composition and field/route checks exist. The full cross-capability dependency and collision matrix remains broader. | Retain composition acceptance work. | 08; dependencies below |
| [CAP-GAP-003](alignment.md#gap-register) | Capability.run has Profile-bound and defaults-bound forms. | Choose a shared contract or document the deliberate distinction. | 08; dependencies below |
| [CAP-GAP-004](alignment.md#gap-register) | Routing changes model selection. Uniform selection reasons and observations require cross-seam proof. | Align with 02/12. | 08; dependencies below |
| [CAP-GAP-005](alignment.md#gap-register) | Retrieval Store and integration exist. General adapter behavior and strict enrichment bounds need review. | Retain the advanced store and result-limit contract. | 08; dependencies below |
| [CAP-GAP-006](alignment.md#gap-register) | Current policy/quota state works; universal versioned capability state migration is not established. | Keep explicit codec and migration work; do not imply durable accounting. | 08; dependencies below |

## Decisions requested

Decide whether a new contribution descriptor simplifies the two current input contracts. Define store ownership and versioning without implying durable billing or workflow guarantees.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Dependents: 10.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
