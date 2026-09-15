> Seam review entry point. Pending approval.

# 12 — Observation and diagnostics

## Briefing

Telemetry and transport sanitizers redact and bound values differently. Typed Signal and stream projections exist. Inspection separates committed records from live samples and bounds retained traces. Current observation tests deliberately preserve some nested tool_result content; the strict content-free telemetry target is therefore not fully met.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Observe, sanitization, Runtime.Event/Telemetry, typed Signal projections, Request metadata, and Orchestration.Inspection.
- Owns: observation and diagnostics within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Preserve a complete versioned event contract, request/model/tool/delegation lineage, safe default projections, explicit rich-content policy, bounded diagnostics, and compatibility testing. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [OBS-GAP-001](alignment.md#gap-register) | Runtime.Event and typed projections exist; there is no single public Event value matching all proposed fields. | Keep event semantics and versioning work. | 12; dependencies below |
| [OBS-GAP-002](alignment.md#gap-register) | Lifecycle IDs and measurements exist. A complete finite vocabulary and correlation matrix remains. | Retain per-event schema and measurement proof. | 12; dependencies below |
| [OBS-GAP-003](alignment.md#gap-register) | ReAct run identity is retained across resume rather than replaced with linked identity. | Resolve with 11 before asserting OBS-REQ-006. | 12; dependencies below |
| [OBS-GAP-004](alignment.md#gap-register) | observe_test explicitly preserves nested tool_result payload fields after sanitization. | Review the strict no-content default against current consumers. | 12; dependencies below |
| [OBS-GAP-005](alignment.md#gap-register) | Reasoning details can remain in results/projections. A universal private-thinking exclusion is a stronger target. | Specify trusted opt-in policy with 01/05. | 12; dependencies below |
| [OBS-GAP-006](alignment.md#gap-register) | Bounds and sanitizers exist; full cross-projection/version compatibility evidence remains. | Retain golden projection, cardinality, and arbitrary-input safety tests. | 12; dependencies below |

## Decisions requested

Decide the common event representation and default rich/thinking-content policy. Observation must not become an execution or durable-event owner.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [10 Authoring and portable definitions](../10_authoring_definitions/alignment.md), [11 Checkpoints and resume](../11_checkpoints_resume/alignment.md).
- Dependents: 90.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
