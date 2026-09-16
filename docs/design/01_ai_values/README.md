> Seam review entry point. Pending approval.

# 01 — Canonical interaction and AI values

## Briefing

Jido.Session owns a Thread of Entry values. These values are process-free and have explicit codecs. Thread.Projection adapts them for AI use; Orchestration.Transcript connects them to a selected Agent field. Turn no longer executes tools. Error uses Splode classes and a runtime envelope with type, message, details, and retryable? rather than the proposed single category/code struct.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Jido.Session, Jido.Thread, Jido.Thread.Entry, Query, Turn, Output, Usage, Error, and Thread.Projection.
- Owns: canonical interaction and ai values within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Use canonical Session/Thread values for context data. Preserve multimodal content, correlation, output validation, safe errors, and explicit portable encodings. Broader constructor uniformity and strict provider-neutral content remain decisions. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [VAL-GAP-001](alignment.md#gap-register) | Constructors have established return contracts; Session.new returns a value. The universal tagged-error proposal would be a migration. | Specify constructor families rather than silently changing them. | 01; dependencies below |
| [VAL-GAP-002](alignment.md#gap-register) | Session/Thread codecs and projection replace Context. The former gap cited output requirements as context requirements. | Use VAL-REQ-008/009/021/022 for ordering, projection, and encoding evidence. | 01; dependencies below |
| [VAL-GAP-004](alignment.md#gap-register) | Current errors use Splode and type/message/details/retryable? envelopes, not one category/code value. | Decide taxonomy and compatibility in the target. | 01; dependencies below |
| [VAL-GAP-005](alignment.md#gap-register) | Error and observation sanitizers exist; an old leak claim is not carried forward as a current defect without reproduction. | Audit all projections and match tests to VAL-REQ-020. | 01; dependencies below |
| [VAL-GAP-006](alignment.md#gap-register) | Canonical context codecs are versioned. A universal encoding contract for every public value is broader. | Define which values are encoded and which remain runtime-only. | 01; dependencies below |

## Decisions requested

Resolve tagged constructor uniformity, provider-native content acceptance, and the proposed error taxonomy without reintroducing Context or History stores.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [00 Package boundary and invariants](../00_boundary_invariants/alignment.md).
- Dependents: 02, 03, 06.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
