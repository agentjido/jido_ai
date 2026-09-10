# 08 — Capabilities And Policy Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00, 01, 04, 06, and 07.
- Alignment state: Blocked.
- Blockers: design approval and the package compile failure.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Plugin stack composition: lib/jido_ai/authoring/plugin_stack.ex.
- Capability Action execution: lib/jido_ai/authoring/capability.ex:10-36.
- Policy, model routing, retrieval, and quota plugins: lib/jido_ai/authoring/plugins.
- Retrieval store: lib/jido_ai/retrieval/store.ex.
- Quota store and reservation logic: lib/jido_ai/quota/store.ex:141-177.
- Runtime capability dispatch: lib/jido_ai/operations/runtime.ex:1-120.
- Relevant V3 authoring and request examples under examples/v3/test/examples.

## Retained Baseline

- Keep Policy and ModelRouting as default AI plugins.
- Keep deterministic plugin stack composition and duplicate rejection.
- Keep capabilities as Jido Actions executed through Jido.Exec.
- Keep retrieval and quota services host-supervised.
- Keep atomic quota reservation and duplicate request protection.
- Keep portable plugin configuration separate from live services.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| CAP-GAP-001 | CAP-REQ-001, CAP-REQ-002 | authoring/plugin_stack.ex | Plugins compose capabilities, but there is no formal capability contribution descriptor and constructor contract. | Define one portable contribution value and validation result. |
| CAP-GAP-002 | CAP-REQ-003, CAP-REQ-004, CAP-REQ-006 | plugin stack validation | Duplicate plugin modules are rejected, but cross-plugin state, route, directive, and dependency conflicts are not fully proved. | Add dependency ordering and collision tests with core Plugin rules. |
| CAP-GAP-003 | CAP-REQ-008, CAP-REQ-009 | runtime RunCapability route | Capability work uses the shared runtime, but one capability execution and result contract is not explicit. | Define the boundary and add ownership tests. |
| CAP-GAP-004 | CAP-REQ-010 | model routing plugin | Routing returns useful choices, but full selected identity and reason metadata are not uniform. | Use the Model Gateway selection result. |
| CAP-GAP-005 | CAP-REQ-015, CAP-REQ-018 | retrieval store and plugin | Retrieval works, but store behavior, result byte bounds, and enrichment limits are not one formal contract. | Add a store behavior and strict result bounds. |
| CAP-GAP-006 | CAP-REQ-026 | policy and quota state | Compatibility exists in current examples, but portable versioning and migrations are incomplete. | Add versioned plugin state and fixtures. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the capability contribution, dependency, and execution contracts.
2. Validate plugin dependency order and all collision classes.
3. Route capability execution through the approved shared runtime boundary.
4. Reuse Model Gateway selection metadata.
5. Formalize retrieval and quota store behaviors, limits, and lifecycle.
6. Add versioned state migration and capability conformance tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| CAP-REQ-001 | no formal contribution value | Approved capability descriptor | Missing |
| CAP-REQ-002 | plugin config is inert | Portable constructor and validation tests | Partial |
| CAP-REQ-003 | stack composition is deterministic | Explicit dependency order tests | Partial |
| CAP-REQ-004 | duplicate plugins rejected | Full state, route, and directive collision proof | Partial |
| CAP-REQ-005 | default plugins are deterministic | Passing default stack tests | Proven |
| CAP-REQ-006 | no complete dependency graph | Missing and cyclic dependency tests | Partial |
| CAP-REQ-007 | TaskSupervisor is rejected | Passing private-owner rejection test | Proven |
| CAP-REQ-008 | shared RunCapability route exists | One public execution contract | Partial |
| CAP-REQ-009 | capability results normalize in parts | Stable common result tests | Partial |
| CAP-REQ-010 | model routing returns choices | Full identity and reason metadata | Partial |
| CAP-REQ-011 | Actions use Jido.Exec | Passing ownership tests | Proven |
| CAP-REQ-012 | policy plugin exists | Complete policy decision tests | Partial |
| CAP-REQ-013 | deny decisions are enforced | Passing denied-work tests | Proven |
| CAP-REQ-014 | retrieval is host-supervised | Passing lifecycle tests | Proven |
| CAP-REQ-015 | concrete retrieval store exists | Approved store behavior | Partial |
| CAP-REQ-016 | retrieval CRUD is bounded | Passing access and failure tests | Proven |
| CAP-REQ-017 | retrieval results normalize | Passing result-shape tests | Proven |
| CAP-REQ-018 | enrichment limits exist in parts | Strict item and byte bounds | Partial |
| CAP-REQ-019 | quota is host-supervised | Passing lifecycle tests | Proven |
| CAP-REQ-020 | quota reservation is atomic | Passing concurrency tests | Proven |
| CAP-REQ-021 | duplicate request protection exists | Passing deduplication tests | Proven |
| CAP-REQ-022 | quota denial blocks work | Passing no-work-after-denial tests | Proven |
| CAP-REQ-023 | quota state is inspected | Passing safe inspection tests | Proven |
| CAP-REQ-024 | live services stay outside Agent state | Passing portability tests | Proven |
| CAP-REQ-025 | service failures normalize | Passing store failure tests | Proven |
| CAP-REQ-026 | current state is partly portable | Versioned migration fixtures | Partial |
| CAP-REQ-027 | plugin stack examples exist | Passing combined capability tests | Proven |

## Migration And Compatibility

- Keep current plugin modules and configuration keys through contribution adapters.
- Add defaults for new descriptor and version fields.
- Keep retrieval and quota store process references outside Agent state.
- Map current routing results to the approved Model Gateway result.

## Assumptions And Blockers

- Core Plugin owns state, route, and directive collision validation.
- Host applications supervise retrieval and quota services.
- Package compile failure blocks final combined plugin tests.

## Completion Criteria

- Every capability has a portable descriptor, explicit dependencies, and one execution contract.
- All collisions and invalid dependency graphs fail before work starts.
- Retrieval and quota services have formal bounded store contracts.
- Plugin state is versioned, portable, and migration-tested.
