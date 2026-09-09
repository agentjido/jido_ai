# 00 — Boundary Invariants Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: none. This seam sets the rules for all other seams.
- Alignment state: Blocked.
- Blockers: design approval and a package compile failure in context_operations.ex.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Package boundary and dependencies: mix.exs:4-6 and mix.exs:56-67.
- Neutral Agent construction and Flow construction: lib/jido_ai/authoring/authoring.ex:43-57 and lib/jido_ai/authoring/authoring.ex:231-243.
- Runtime execution boundary: lib/jido_ai/operations/runtime.ex:106, lib/jido_ai/operations/runtime.ex:405, and lib/jido_ai/operations/runtime.ex:798-846.
- Signal boundary: lib/jido_ai/signals/definition.ex and lib/jido_ai/signals/signal.ex.
- Host-owned stores: lib/jido_ai/shared/retrieval/store.ex:1-18 and lib/jido_ai/shared/quota/store.ex:1-20.
- Current parity evidence: examples/v3/test/examples/01_authoring/01_06_ai_extension_test.exs:14-89.
- Current compile evidence: mix compile --warnings-as-errors fails because Jido.Thread and Jido.Thread.Entry are not available to context_operations.ex.
- Historical input only: docs/v3-spike. It is not proof of current behavior.

## Retained Baseline

- Keep jido_action as the owner of Action, Instruction, Jido.Exec, and Flow.
- Keep jido_signal as the owner of Signal transport and dispatch.
- Keep jido as the owner of Agent, AgentServer, Plugin, directives, and OTP runtime.
- Keep jido_ai as the owner of AI values, model and tool bridges, AI policies, and AI request behavior.
- Keep jido_browser as the owner of browser automation.
- Keep the Jido.Agent.Extension authoring path and the current V3 parity examples.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| BND-GAP-001 | BND-REQ-001, BND-REQ-003 | mix.exs:4-6 | The version is 2.3.0 and the package description still claims ownership of Actions and Workflows. | Update release metadata after the design is approved. |
| BND-GAP-002 | BND-REQ-002, BND-REQ-005 | operations/runtime.ex:405, 798, 846 | Model and tool Actions use Jido.Exec, but tool retry uses Process.sleep inside the worker. | Move retry delay to a scheduler-visible execution boundary. |
| BND-GAP-003 | BND-REQ-002, BND-REQ-011 | operations/react_runner.ex:43-44 | The compatibility runner can start a private Task process. | Remove or isolate this path before it can become a public runtime owner. |
| BND-GAP-004 | BND-REQ-006, BND-REQ-007, BND-REQ-009 | authoring/authoring.ex:43-243 | The extension path is present, but the complete ownership and lowering contract is not proved across all public APIs. | Add boundary tests for every public entry point. |
| BND-GAP-005 | BND-REQ-012 | current design and package guides | Rollback, idempotency, and side-effect ownership are not one enforced package contract. | Define the contract in the owning seam and add failure-path tests. |
| BND-GAP-006 | BND-REQ-014, BND-REQ-016 | checkpoint guards and compile output | Exec internals are rejected from portable state, but the package does not compile against the current sibling Jido API. | Align the Jido.Thread dependency contract before any release gate. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the package ownership table and public dependency direction.
2. Correct package metadata and name the allowed Jido.Exec and Flow call sites.
3. Remove private scheduling and retry waits from public runtime paths.
4. Define side-effect, rollback, and idempotency ownership.
5. Add boundary tests for authoring, execution, signals, stores, checkpoints, and browser separation.
6. Run the lower-level package tests, then compile and test jido_ai with sibling V3 paths.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| BND-REQ-001 | mix.exs and module layout | Approved ownership inventory and corrected metadata | Partial |
| BND-REQ-002 | Jido.Exec and Flow call sites | No private execution owner or scheduler bypass | Conflict |
| BND-REQ-003 | mix.exs path dependencies | Release-safe V3 dependency matrix | Partial |
| BND-REQ-004 | signals use Jido.Signal | Passing signal construction and dispatch tests | Proven |
| BND-REQ-005 | model and tool work use Jido.Exec | Scheduler-visible retry and cancellation | Partial |
| BND-REQ-006 | Jido.Agent.Extension implementation | Full extension route and state proof | Partial |
| BND-REQ-007 | neutral base Agent construction | Public entry-point boundary tests | Partial |
| BND-REQ-008 | no browser runtime code found | Ownership inventory test or check | Proven |
| BND-REQ-009 | Profile and extension lowering | Proof that AI policy remains outside core | Partial |
| BND-REQ-010 | retrieval and quota stores are host-owned | Lifecycle tests for all stores | Proven |
| BND-REQ-011 | main runtime uses core directives | Removal or strict isolation of private runner | Partial |
| BND-REQ-012 | scattered effect policy support | One rollback and idempotency contract | Missing |
| BND-REQ-013 | V3 parity example | Full compatibility acceptance set | Proven |
| BND-REQ-014 | checkpoint guards reject Exec state | Current migration guide and passing restore tests | Partial |
| BND-REQ-015 | seam documents name owners | Automated dependency and ownership checks | Partial |
| BND-REQ-016 | sibling paths use V3 branches | Successful compile and package-wide test run | Partial |

## Migration And Compatibility

- Keep current Jido.Agent.Extension authoring calls while the ownership corrections land.
- Treat operations/react_runner.ex as compatibility code. Do not add new callers.
- Do not persist Jido.Exec state. Continue to reject it at checkpoint boundaries.
- Restore Hex constraints before release unless a path or Git dependency is an approved release input.

## Assumptions And Blockers

- The target design is not approved.
- The current sibling Jido Plugin refactor is active and outside this task.
- The missing Jido.Thread API blocks compile and package-wide verification.
- Existing V2 guides do not change V3 ownership.

## Completion Criteria

- Every boundary requirement is Proven with source and test evidence.
- No public AI runtime path owns an undeclared process or uses a hidden scheduler.
- Package metadata and dependencies match the approved V3 release contract.
- jido_action, jido_signal, jido, and jido_ai compile and pass tests in dependency order.
