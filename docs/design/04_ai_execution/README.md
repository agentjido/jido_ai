> Seam review entry point. Pending approval.

# 04 — Shared AI execution

## Briefing

One internal validated execution map carries Profile, ReqLLM context, counters, deadlines, and optional method state. Shared Actions and Flows run the model/tool cycle. ToolAttempt uses a bounded continuation plus sleep; output repair is separate runtime logic. Orchestration owns live request lifetime and settlement, not these step modules.

This seam retains the complete target, not only current functionality. Detailed
current evidence and gaps are in [alignment](alignment.md); proposed contracts
and stable requirement IDs are in [design](design.md).

## Why this seam exists

- Owner: Runtime.State, Flow, ReasonFlow, Prepare, CallModel, Decide, ToolsFlow, ToolAttempt, and OutputState.
- Owns: shared ai execution within [the package architecture](../ARCHITECTURE.md).
- Does not own: contracts assigned to other seams or private lower-package internals.

## Current and target state

| Area | Current | Target |
| --- | --- | --- |
| Architecture | The module and state ownership above is the code baseline | Keep one bounded execution path for all authoring forms and methods. Preserve advanced streaming, cancellation, retry, and effect contracts without making temporary execution state a portable conversation value. |
| Evidence | Linked example and boundary tests cover specific cases | Direct requirement-level acceptance, including advanced paths |
| Compatibility | Current APIs remain authoritative | Explicit migration for approved contract changes |

## Major gaps and work remaining

| Gap | Why it matters | Required outcome | Owner |
| --- | --- | --- | --- |
| [EXE-GAP-001](alignment.md#gap-register) | Runtime.State now exists as an internal map with provider values. It is not the proposed portable public Execution.Input/State. | Separate temporary state from portable snapshots; review the public abstraction before adding it. | 04; dependencies below |
| [EXE-GAP-002](alignment.md#gap-register) | Runtime events carry correlation, but one shared schema for all attempts and projections is not established. | Complete correlation evidence in 12. | 04; dependencies below |
| [EXE-GAP-003](alignment.md#gap-register) | Retry uses a continuation with bounded worker sleep; output repair has its own bounded path. | Resolve EXE-REQ-015/017 without creating a generic retry engine. | 04; dependencies below |
| [EXE-GAP-004](alignment.md#gap-register) | Coordinator owns cancellation and worker cleanup through the current integration. The target names a public Exec cancellation contract. | Verify the exact lower-level API and cancellation races before changing ownership. | 04; dependencies below |
| [EXE-GAP-005](alignment.md#gap-register) | Stream and caller-loss paths exist, but full slow-consumer, backpressure, caller-down, and mailbox-bound guarantees need direct proof. | Retain slow-consumer and cleanup acceptance cases with 07/12. | 04; dependencies below |
| [EXE-GAP-006](alignment.md#gap-register) | Profile and method limits exist. A uniform account of hard maxima and limit provenance remains broader than the current controls. | Retain limit source and most-restrictive-bound acceptance cases. | 04; dependencies below |

## Decisions requested

Resolve portable public Execution types, explicit Map concurrency, and the exact public cancellation contract against current core APIs.

The [target design decisions](design.md#open-design-decisions) remain pending.
No advanced capability is removed by this reconciliation.

## Dependencies

- Prerequisites: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md).
- Dependents: 05, 06, 11.
- Blockers: unresolved target and prerequisite decisions. Current implementation can be inspected without treating proposed contracts as approved.

## Documents

- [Target design](design.md).
- [Current evidence and alignment](alignment.md).
- [Overall architecture](../ARCHITECTURE.md).
