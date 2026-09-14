# 10 — Authoring And Definitions Alignment

> Seam alignment plan and current implementation record.

## Status

- Design approved: 2026-09-09.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00 through 09.
- Alignment state: Active. The first authoring refinement is implemented.
- Current gate: warnings-as-errors compile and the full default test suite pass.

Proven means that current source and a direct executable test assertion exist. The current package test suite also passes.

## Inputs And Evidence

- Target design: design.md.
- Profile definition and validation: lib/jido_ai/profile.ex.
- Spark extension DSL: lib/jido_ai/authoring/dsl.ex.
- Neutral Agent and Flow lowering: lib/jido_ai/authoring/authoring.ex:43-243.
- Canonical Agent macro: lib/jido_ai/agent/definition.ex.
- Profile codec and portable authoring tests: test/jido_ai/authoring.
- Full specification parity: test/jido_ai/authoring/full_spec_parity_test.exs:218-291.
- Validation examples: examples/v3/test/examples/01_authoring/01_06_ai_extension_test.exs:14-89.

## Retained Baseline

- Keep Profile as the declarative AI authoring value.
- Keep Jido.Agent.Extension as the canonical lowering point.
- Keep neutral core Agent construction followed by AI extension.
- Keep duplicate profile, field, and route validation with source locations.
- Keep Flow.Builder for reasoning Flow construction.
- Keep Jido.AI.Agent as the canonical convenience form for Jido.Agent with the AI extension.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| AUT-GAP-001 | AUT-REQ-010 | lib/jido_ai/agent/definition.ex | Resolved: V2 option authoring was removed. | Keep compile-time rejection tests. |
| AUT-GAP-002 | AUT-REQ-013 | inline Action support and core schemas | Ordinary named Actions work, but the full inline Action input, output, and context validation contract is not proved. | Add focused inline Action compile and runtime tests. |
| AUT-GAP-003 | AUT-REQ-020 | authoring validation | Local duplicate and field checks are strong, but full Plugin, directive, and route collisions depend on the active sibling core contract. | Add conformance tests after core Plugin approval. |
| AUT-GAP-004 | AUT-REQ-026, AUT-REQ-027 | generated APIs | The stable public surface still needs a final inventory. | Define the approved V3 API list. |
| AUT-GAP-005 | Compile and test gate | package compile and test output | Resolved: warnings-as-errors compile, full default tests, and selected authoring examples pass. | Keep these checks as the authoring gate. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve Profile, extension, and generated API surfaces.
2. Reject V2 option authoring.
3. Add inline Action schema and source-location tests.
4. Align collision validation with the approved core Plugin contract.
5. Compile with warnings as errors and run authoring, parity, and example tests.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| AUT-REQ-001 | Profile exists | Passing Profile constructor tests | Proven |
| AUT-REQ-002 | Profile validation exists | Passing malformed profile tests | Proven |
| AUT-REQ-003 | Profile fields are portable | Passing codec tests | Proven |
| AUT-REQ-004 | extension DSL exists | Passing DSL compile tests | Proven |
| AUT-REQ-005 | neutral Agent is built first | Passing lowerer tests | Proven |
| AUT-REQ-006 | extension applies AI state and routes | Passing extension tests | Proven |
| AUT-REQ-007 | duplicate profiles fail | Passing duplicate tests | Proven |
| AUT-REQ-008 | field conflicts fail | Passing field conflict tests | Proven |
| AUT-REQ-009 | route conflicts fail locally | Passing route tests | Proven |
| AUT-REQ-010 | V3-only Agent macro | Compile-time rejection tests | Proven |
| AUT-REQ-011 | source locations are reported | Passing compile error tests | Proven |
| AUT-REQ-012 | named Actions are supported | Passing Action authoring tests | Proven |
| AUT-REQ-013 | inline support is incomplete | Full schema validation tests | Partial |
| AUT-REQ-014 | Flow.Builder is used | Passing reasoning Flow tests | Proven |
| AUT-REQ-015 | generated request APIs exist | Passing generated API tests | Proven |
| AUT-REQ-016 | generated signal APIs exist | Passing generated API tests | Proven |
| AUT-REQ-017 | generated inspection APIs exist | Passing generated API tests | Proven |
| AUT-REQ-018 | defaults are deterministic | Passing default expansion tests | Proven |
| AUT-REQ-019 | profile codec exists | Passing version and round-trip tests | Proven |
| AUT-REQ-020 | local conflicts are tested | Full core Plugin collision matrix | Partial |
| AUT-REQ-021 | unknown options fail | Passing unknown option tests | Proven |
| AUT-REQ-022 | invalid models fail | Passing model option tests | Proven |
| AUT-REQ-023 | invalid tools fail | Passing tool option tests | Proven |
| AUT-REQ-024 | invalid limits fail | Passing finite limit tests | Proven |
| AUT-REQ-025 | full spec parity tests exist | Passing parity suite | Proven |
| AUT-REQ-026 | generated APIs exist | Approved stable API inventory | Partial |
| AUT-REQ-027 | V3 inspection exists | Approved stable API inventory | Partial |
| AUT-REQ-028 | docs and examples use extension | Passing documentation examples | Proven |
| AUT-REQ-029 | lowerer output is deterministic | Passing repeated compile tests | Proven |
| AUT-REQ-030 | extension state is portable | Passing snapshot checks | Proven |

## V3 authoring policy

- Keep Jido.AI.Agent as the canonical convenience form around the extension lowerer.
- Do not accept V2 keyword formats or reasoning-specific Agent macros.
- Keep all authoring forms inert and lower them through one Profile contract.

## Assumptions And Blockers

- Core Agent and Plugin validation remain the final authority for core-owned conflicts.
- The target public API inventory needs approval.
- Package compile failure blocks the final authoring gate.

## Completion Criteria

- One lowerer serves every V3 authoring form.
- Invalid profiles, fields, routes, Actions, models, tools, and limits fail with source locations.
- Unsupported V2 authoring forms fail instead of starting a second path.
- All authoring and parity tests pass with warnings as errors.
