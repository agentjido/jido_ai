# 05 — Reasoning And Planning Alignment

> Seam alignment plan. This document and its design are pending approval.

## Status

- Design reviewed: 2026-09-09 for alignment only.
- Code reviewed: 17c97ca04d97b26a1c7017250c90053ad674f33f.
- Prerequisites: seams 00 through 04.
- Alignment state: Blocked.
- Blockers: design approval, package compile failure, and missing public method and plan contracts.

Proven means that current source and a direct executable test assertion exist. It does not mean that the current package test suite passes.

## Inputs And Evidence

- Target design: design.md.
- Method selection and options: lib/jido_ai/reasoning.ex and lib/jido_ai/reasoning/adaptive/selection.ex.
- Shared Flow lowering: lib/jido_ai/authoring/authoring.ex:231-243.
- Current method implementations: lib/jido_ai/reasoning.
- Planning Actions: lib/jido_ai/planning.
- Method examples: examples/v3/test/examples/09_reasoning.
- Tree-of-thought evidence: examples/v3/test/examples/09_reasoning/09_04_tot_test.exs:28-430.
- Historical input only: docs/v3-spike.

## Retained Baseline

- Keep the current built-in reasoning method names and bounded options.
- Keep method work inside shared Flow and Jido.Exec execution.
- Keep stable candidate IDs, deterministic ranking order, and usage aggregation.
- Keep bounded parser repair and tool call order.
- Keep planning operations as Jido Actions.

## Gap Register

| Gap | Requirement | Current evidence | Difference | Disposition |
| --- | --- | --- | --- | --- |
| RSN-GAP-001 | RSN-REQ-001, RSN-REQ-002 | shared/reasoning.ex | There is no formal public method behavior, descriptor, or trusted registration contract. | Define the method contract and a trusted static registry. |
| RSN-GAP-002 | RSN-REQ-004, RSN-REQ-013 | method modules and options | Methods work, but not every method is proved as the same bounded Flow shape with approved hard maxima. | Add shared lowering and limit conformance tests. |
| RSN-GAP-003 | RSN-REQ-009, RSN-REQ-010 | tree-of-thought ranking tests | Ranking is stable in examples, but tie behavior and pruning rules are not one public contract. | Define deterministic tie and prune rules. |
| RSN-GAP-004 | RSN-REQ-015, RSN-REQ-016 | method-specific result maps | There is no common method result. Thinking data can remain in public results and metadata. | Add a common result and a safe thinking projection policy. |
| RSN-GAP-005 | RSN-REQ-017, RSN-REQ-022 | current reasoning modules | Extension and method lookup are not based on one trusted registry contract. | Add trusted registration, collision checks, and lookup tests. |
| RSN-GAP-006 | RSN-REQ-018, RSN-REQ-019, RSN-REQ-020, RSN-REQ-021 | planning Actions | No stable Plan value, validation contract, or deterministic lowering to executable work exists. | Define Plan and separate planning data from execution. |

## High-Level Work Sequence

This sequence defines outcomes and gates. Detailed implementation planning comes after design approval.

1. Approve the method behavior, descriptor, registry, common result, and Plan value.
2. Adapt built-in methods to the shared method contract.
3. Define deterministic ranking, tie, prune, and termination rules.
4. Apply finite maxima to every method and planning operation.
5. Add safe thinking projections.
6. Add Plan validation and deterministic lowering tests without making Plan an execution owner.

## Acceptance Matrix

| Requirement | Current evidence | Required evidence | State |
| --- | --- | --- | --- |
| RSN-REQ-001 | no formal public behavior | Approved method callback contract | Missing |
| RSN-REQ-002 | built-in selection map exists | Trusted descriptors and registration tests | Partial |
| RSN-REQ-003 | adaptive selection exists | Passing deterministic selection tests | Proven |
| RSN-REQ-004 | methods use shared runtime | Uniform public Flow lowering proof | Partial |
| RSN-REQ-005 | no private method worker found | Direct ownership and scheduler tests | Proven |
| RSN-REQ-006 | ReAct examples exist | Passing termination and tool tests | Proven |
| RSN-REQ-007 | chain methods have ordered steps | Passing ordered-step tests | Proven |
| RSN-REQ-008 | candidate IDs are stable | Passing candidate identity tests | Proven |
| RSN-REQ-009 | ranked candidates are tested | Explicit deterministic tie rule | Partial |
| RSN-REQ-010 | pruning is implemented | Approved stable pruning contract | Partial |
| RSN-REQ-011 | parser repair is bounded | Passing parse failure tests | Proven |
| RSN-REQ-012 | usage aggregation exists | Passing multi-step usage tests | Proven |
| RSN-REQ-013 | max values are finite | Approved hard maxima for every method | Partial |
| RSN-REQ-014 | tool order is retained | Complete multi-method tool tests | Partial |
| RSN-REQ-015 | method result shapes differ | One common result value | Partial |
| RSN-REQ-016 | thinking can be public | Default-safe thinking projection | Conflict |
| RSN-REQ-017 | extension points are informal | Trusted extension contract | Missing |
| RSN-REQ-018 | no stable Plan value | Versioned Plan struct and codec | Missing |
| RSN-REQ-019 | planning Actions return data | Plan validation and dependency tests | Partial |
| RSN-REQ-020 | no canonical lowering | Deterministic Plan-to-work lowering | Missing |
| RSN-REQ-021 | planning and execution are partly separate | Explicit no-execution-owner tests | Partial |
| RSN-REQ-022 | no trusted registry | Collision-safe trusted method registry | Missing |
| RSN-REQ-023 | stable IDs and profile codec exist | Complete portability fixtures | Partial |

## Migration And Compatibility

- Keep current method names and option keys through descriptor aliases.
- Convert method-specific result maps to the common result at the public boundary.
- Keep old Plan-like maps as legacy inputs only after validation.
- Do not store functions, processes, tasks, provider structs, or Jido.Exec state in method or plan values.

## Assumptions And Blockers

- The design must decide whether third-party method registration is compile-time or host-owned.
- Planning remains data production. Execution remains in Flow and Jido.Exec.
- Package compile failure blocks final conformance tests.

## Completion Criteria

- Every method implements one trusted, bounded, deterministic contract.
- All method results use one portable public value with safe thinking projections.
- Plan is versioned, validated, deterministic, and separate from execution.
- Built-in method and planning acceptance tests pass.
