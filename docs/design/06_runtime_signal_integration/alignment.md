# 06 — Runtime And Signal Integration Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00 through 05 and the sibling Jido Plugin facet contract.
- Alignment state: Blocked.
- Blockers: design approval, package compile failure, and downstream alignment with the new Jido Plugin facet contract.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Agent extension DSL: lib/jido_ai/authoring/dsl.ex:679-760.
- Agent lowering and routes: lib/jido_ai/authoring/authoring.ex.
- Runtime Plugin: lib/jido_ai/operations/runtime.ex:1-40.
- Session Plugin: lib/jido_ai/session/plugin.ex:1-180.
- Signal definitions and projection: lib/jido_ai/signals/definition.ex and lib/jido_ai/signals/signal.ex.
- Session calls: lib/jido_ai/session/session.ex.
- Signal delivery tests: examples/v3/test/examples/02_requests/02_17_signal_delivery_test.exs:312-345.
- Compile failure: lib/jido_ai/session/context_operations.ex:401 and 421 refer to missing Jido.Thread structs.
- Sibling Plugin evidence: jido commit c835ad5e2c08e97826e15158a5889955d551af2c split Agent, AgentServer, persistence, topology, manifest, and normalizer facets. The earlier missing Normalizer warning is resolved.

## Retained Baseline

- Keep Jido.Agent.Extension as the authoring integration point.
- Keep Plugin state under one declared key per plugin.
- Keep prepare, admit, update_state, routes, and directives in core Plugin callbacks.
- Keep typed Jido.Signal envelopes and core Emit directives.
- Keep AgentServer as the host call boundary.
- Keep portable Agent state separate from runtime resources.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| INT-GAP-001 | INT-REQ-006, INT-REQ-012 | authoring route lowering | Route and signal validation exist, but full collision and unreachable-route proof is incomplete. | Add route table conformance tests against the approved core Plugin API. |
| INT-GAP-002 | INT-REQ-009 | plugin prepare and admit callbacks | Most prepare work is pure, but purity and store access boundaries are not protected across all plugins. | Add callback-side-effect tests and keep live store calls in operational callbacks. |
| INT-GAP-003 | INT-REQ-016 | context_operations.ex:401-421 | Context integration expects Jido.Thread values that are not available in the current sibling API. | Align on the declared Agent history field and supported core type. |
| INT-GAP-004 | INT-REQ-022, INT-REQ-024 | current runtime events and signals | Typed signals exist, but not every event proves the full approved correlation metadata. | Add one projection contract and event matrix. |
| INT-GAP-005 | INT-REQ-027 | 02_17_signal_delivery_test.exs:312-345 | Current default dispatch can self-route to the host, which conflicts with the no-hidden-self-routing target. | Require an explicit route or revise the design before implementation. |
| INT-GAP-006 | Blocker: new sibling Jido Plugin facet contract | jido commit c835ad5e2c08e97826e15158a5889955d551af2c | The new core facet contract has landed, but jido_ai conformance cannot be verified while the package compile fails. | Align this seam with the approved sibling Plugin contract without changing sibling code in this task. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the sibling Jido Plugin callback, route, directive, and normalization contract.
2. Align Jido.Thread or replace it with the approved Agent history value.
3. Prove plugin state ownership, callback purity, and route collision rules.
4. Standardize event-to-Signal projection and correlation fields.
5. Decide and test explicit self-routing behavior.
6. Compile and test jido first, then jido_ai.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| INT-REQ-001 | Jido.Agent.Extension behavior | Passing extension integration tests | Proven |
| INT-REQ-002 | authoring lowers to Agent | Passing neutral Agent tests | Proven |
| INT-REQ-003 | plugins declare state specs | Passing state validation tests | Proven |
| INT-REQ-004 | plugins declare directives | Passing directive tests | Proven |
| INT-REQ-005 | routes are generated | Passing route lowering tests | Proven |
| INT-REQ-006 | route validation exists | Complete collision and reachability tests | Partial |
| INT-REQ-007 | AgentServer call paths exist | Passing host call tests | Proven |
| INT-REQ-008 | one state key per AI plugin | Passing ownership tests | Proven |
| INT-REQ-009 | prepare is mostly pure | Enforced callback purity tests | Partial |
| INT-REQ-010 | admit callback exists | Passing admission order tests | Proven |
| INT-REQ-011 | update_state callback exists | Passing state transition tests | Proven |
| INT-REQ-012 | route declarations exist | Complete route contract proof | Partial |
| INT-REQ-013 | core directives are returned | Passing directive application tests | Proven |
| INT-REQ-014 | runtime resources use context | Passing portable-state checks | Proven |
| INT-REQ-015 | session data is separated | Passing snapshot separation tests | Proven |
| INT-REQ-016 | missing Jido.Thread structs | Supported declared history field | Conflict |
| INT-REQ-017 | typed signal modules exist | Passing signal construction tests | Proven |
| INT-REQ-018 | signals use Jido.Signal | Passing envelope tests | Proven |
| INT-REQ-019 | Signal.from_event exists | Passing projection tests | Proven |
| INT-REQ-020 | Emit directives are used | Passing dispatch tests | Proven |
| INT-REQ-021 | request lifecycle signals exist | Passing lifecycle signal tests | Proven |
| INT-REQ-022 | IDs exist on main paths | Complete correlation matrix | Partial |
| INT-REQ-023 | sequence values exist | Passing ordered signal tests | Proven |
| INT-REQ-024 | event fields vary by kind | Full approved metadata on each kind | Partial |
| INT-REQ-025 | signal definitions validate | Passing malformed signal tests | Proven |
| INT-REQ-026 | safe projection exists | Passing secret and size tests | Proven |
| INT-REQ-027 | default self dispatch exists | Explicit-only self-route behavior | Conflict |

## Migration And Compatibility

- Keep current extension modules and route names through the sibling Plugin transition.
- Add a narrow compatibility adapter for old Plugin callbacks if core requires it.
- Do not write a replacement Plugin runtime in jido_ai.
- Treat current self-route behavior as frozen until the design decision is approved.

## Assumptions And Blockers

- The sibling jido worktree is clean at c835ad5e2c08e97826e15158a5889955d551af2c and remains outside this task.
- The new Plugin facets need a downstream jido_ai conformance review after the compile blocker is removed.
- Missing Jido.Thread blocks compilation and makes several runtime tests unavailable.

## Completion Criteria

- jido_ai implements the approved core Plugin contract without private substitutes.
- Agent history uses a supported declared core field and value.
- All runtime events project to typed safe Signals with complete correlation data.
- Self-routing behavior is explicit and covered by acceptance tests.
