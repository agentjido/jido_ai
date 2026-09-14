# 11 — Checkpoints And Resume Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 01, 04, 05, 06, 07, 08, 09, and 10.
- Alignment state: Blocked.
- Blockers: design approval and unresolved effect idempotency.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Agent checkpoint hooks: lib/jido_ai/agent/definition.ex:507-548.
- ReAct checkpoint and token values: lib/jido_ai/reasoning/react/checkpoint.ex and lib/jido_ai/reasoning/react/token.ex.
- Session recovery: lib/jido_ai/session/runtime.ex.
- Checkpoint examples: examples/14_resume.

## Retained Baseline

- Keep core Agent checkpoint callbacks as the outer checkpoint boundary.
- Keep portable checkpoint validation and explicit type versions.
- Keep rejection of Jido.Exec, PID, Task, function, and provider runtime values.
- Keep runtime-loss recovery that marks pending requests interrupted.
- Keep restore re-resolution for external resources.
- Keep unsupported versions and uncertain state failures explicit.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| RES-GAP-001 | RES-REQ-001, RES-REQ-004, RES-REQ-006 | agent.ex and react_checkpoint.ex | Current checkpoints cover key state, but the complete target shape and all size bounds are not one approved contract. | Define the versioned checkpoint envelope and strict byte and item bounds. |
| RES-GAP-002 | RES-REQ-008, RES-REQ-010, RES-REQ-016 | current restore code | Re-resolution exists in parts, but model, skill, capability, and host service binding outcomes are not one atomic contract. | Add staged validation and atomic restore failure tests. |
| RES-GAP-003 | RES-REQ-017 | current resume tests | Current resume evidence keeps the original run ID. The target requires a new run ID linked to the original run. | Change identity semantics after approval and add linkage tests. |
| RES-GAP-004 | RES-REQ-018 | resume implementation | Restore starts new work, but proof that no live Exec continuation is reconstructed is incomplete. | Add ownership and fresh-execution tests. |
| RES-GAP-005 | RES-REQ-021, RES-REQ-022, RES-REQ-023, RES-REQ-024 | effects policy and checkpoint code | External effect identity, deduplication, uncertain-outcome handling, and host decisions are incomplete. | Define effect IDs and a host-visible uncertain-effect decision protocol. |
| RES-GAP-006 | RES-REQ-026, RES-REQ-027, RES-REQ-028 | current state, token, Thread, and Session decoders | Current formats require explicit versions and no V2 importer remains. | Keep current-version acceptance and unsupported-version rejection tests. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the checkpoint envelope, bounds, identity, and effect rules.
2. Extend encoding to all portable Agent, request, method, skill, capability, and resource reference data.
3. Add staged validation and atomic resource re-resolution.
4. Start resume with a new run ID and link it to the source run.
5. Add effect deduplication and uncertain-outcome decisions.
6. Run corruption, version, interruption, replay, and no-duplicate-effect tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| RES-REQ-001 | checkpoint hooks and values exist | Complete approved envelope | Partial |
| RES-REQ-002 | checkpoint type versions exist | Passing version tests | Proven |
| RES-REQ-003 | unsafe runtime values are rejected | Passing rejection tests | Proven |
| RES-REQ-004 | current Agent integration is blocked | Passing core checkpoint integration | Partial |
| RES-REQ-005 | typed version is encoded | Passing decode tests | Proven |
| RES-REQ-006 | some bounds exist | Complete byte and item bounds | Partial |
| RES-REQ-007 | corrupt data is rejected | Passing corruption tests | Proven |
| RES-REQ-008 | resource refs are retained | Complete binding reference schema | Partial |
| RES-REQ-009 | live handles are rejected | Passing portability tests | Proven |
| RES-REQ-010 | resources re-resolve in parts | Atomic all-resource restore tests | Partial |
| RES-REQ-011 | pending work is interrupted | Passing recovery tests | Proven |
| RES-REQ-012 | terminal work stays terminal | Passing no-replay tests | Proven |
| RES-REQ-013 | missing resource fails | Passing missing-resource tests | Proven |
| RES-REQ-014 | incompatible version fails | Passing version mismatch tests | Proven |
| RES-REQ-015 | runtime resources are rebound | Complete trusted binding tests | Partial |
| RES-REQ-016 | restore checks state in parts | Complete pre-start validation | Partial |
| RES-REQ-017 | resume keeps old run ID | New run ID with source linkage | Conflict |
| RES-REQ-018 | fresh work is started | Direct no-Exec-reconstruction proof | Partial |
| RES-REQ-019 | tool execution is not replayed in examples | Complete no-replay proof | Proven |
| RES-REQ-020 | completed model output is retained | Passing no-repeat model tests | Proven |
| RES-REQ-021 | effects policy exists | Stable effect identity tests | Partial |
| RES-REQ-022 | no complete effect deduplication | Deduplication store and replay tests | Missing |
| RES-REQ-023 | no uncertain-effect protocol | Host-visible uncertain outcome decision | Missing |
| RES-REQ-024 | uncertain tool state can fail | Explicit host decision contract | Partial |
| RES-REQ-025 | delivery limits are documented | Complete delivery tests | Partial |
| RES-REQ-026 | failures normalize | Passing safe error tests | Proven |
| RES-REQ-027 | restored state is inspected | Passing inspection tests | Proven |
| RES-REQ-028 | V2 importer is absent | Source scan and current-version tests | Proven |
| RES-REQ-029 | checkpoint examples exist | Passing package-wide restore suite | Proven |

## Version policy

- Accept only the current ReAct state and checkpoint versions.
- Do not silently reinterpret or import old data.
- Preserve request IDs where required, but start every resumed execution with a new run ID.
- Never recreate a PID, Task, stream, provider client, or Jido.Exec state from checkpoint data.

## Assumptions And Blockers

- Core Agent checkpoint hooks remain the outer persistence API.
- Host applications own durable checkpoint and effect-deduplication storage.
- Package compilation and checkpoint examples must stay green.

## Completion Criteria

- Checkpoints are versioned, bounded, portable, and free of live runtime values.
- Restore is atomic and re-resolves all external resources before work starts.
- Resume uses a new linked run ID and never replays completed work.
- External effects have stable identity, deduplication, and an explicit uncertain-outcome path.
