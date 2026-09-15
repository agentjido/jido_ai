> Seam review entry point. Pending approval.

# 02 — Model integration and request preparation

## Briefing

Models uses native ReqLLM/LLMDB model inputs. Model.Transport owns provider requests, Model.Options merges trusted options, and Model.Messages adapts messages and reference metadata. Runtime.RequestTransform still exposes ReAct-specific callback views. Direct model contracts remain native; Agent results are adapted for their storage and request contracts.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Models and Model.Transport, Model.Options, Model.Messages, Model.Generate; routing policy is in seam 08.
- Owns: model integration and request preparation within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Keep trusted provider binding, deterministic option precedence, bounded streaming and repair, and advanced named request-transform stages. Do not assume a new ModelRef wrapper is needed to achieve these capabilities. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [MDL-GAP-001](alignment.md#gap-register) | Native model inputs are intentional; portable encoding is a separate constraint. ModelRef is not an implemented type. | Retain reference safety while deciding whether any wrapper adds value. | 02; dependencies below |
| [MDL-GAP-002](alignment.md#gap-register) | Resolution and routing exist; complete routing-reason and identity projection evidence is not established by one example. | Review MDL-REQ-002 with seams 08/12. | 02; dependencies below |
| [MDL-GAP-003](alignment.md#gap-register) | The current transformer is not the full named portable stage contract and retains ReAct views. | Define the advanced stage contract and its compatibility. | 02; dependencies below |
| [MDL-GAP-005](alignment.md#gap-register) | Runtime output repair is bounded. Uniform repair-attempt events and provider edge behavior need requirement-specific proof. | Use MDL-REQ-018/019 and 04/12, not the old misnumbered row. | 02; dependencies below |
| [MDL-GAP-006](alignment.md#gap-register) | Transport has no independent retry supervisor. Execution owns bounded attempts. | Add ownership evidence if this is a release guarantee. | 02; dependencies below |

## Decisions requested

Separate native direct-call APIs from portable stored data. Resolve transform stages and callback views without introducing a second provider facade.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Dependents: 04, 08.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
