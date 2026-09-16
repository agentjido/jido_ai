> Seam alignment review. Pending approval.

# Reasoning and planning methods alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: [04 Shared AI execution](../04_ai_execution/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

ReAct, ChainOfThought, ChainOfDraft, AlgorithmOfThoughts, TreeOfThoughts, GraphOfThoughts, TRM, and Adaptive remain. Linear, tree, graph, and recursive engines integrate with shared execution. Callable reasoning uses a prompt and host-bound Profile. Planning Actions exist; they are not a general executable Plan system.

- Current owner: Reasoning methods, shared method engines, method state/results, and planning Actions.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve all eight methods, advanced search and recursive behavior, custom-method extension, and portable plans. Keep algorithms above Flow and provider/tool boundaries.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/reasoning.ex](../../../lib/jido_ai/reasoning.ex) | Method dispatch and limits |
| [lib/jido_ai/reasoning/tree_search.ex](../../../lib/jido_ai/reasoning/tree_search.ex) | Tree search integration |
| [lib/jido_ai/reasoning/graph_search.ex](../../../lib/jido_ai/reasoning/graph_search.ex) | Graph search integration |
| [lib/jido_ai/reasoning/recursive.ex](../../../lib/jido_ai/reasoning/recursive.ex) | TRM integration |
| [lib/jido_ai/actions/reasoning/run_strategy.ex](../../../lib/jido_ai/actions/reasoning/run_strategy.ex) | Callable Profile contract |
| [lib/jido_ai/actions/planning/plan.ex](../../../lib/jido_ai/actions/planning/plan.ex) | Planning Action |

### Examples and tests

- [Example briefing](../../../examples/09_reasoning/09_14_callable_reasoning/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/09_reasoning/09_14_callable_reasoning): deterministic example evidence.
- [test/authoring/agents/callable_profiles_test.exs](../../../test/authoring/agents/callable_profiles_test.exs): detailed boundary evidence.
- [test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs](../../../test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve all eight methods, advanced search and recursive behavior, custom-method extension, and portable plans. Keep algorithms above Flow and provider/tool boundaries.

Preserve current public behavior unless an approved decision includes a
migration. This follow-up changes examples and their tests, not runtime implementation.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `RSN-GAP-001` | `RSN-REQ-001`, `RSN-REQ-002` | Built-in method IDs, options, state, and limits exist. A uniform public descriptor/Flow factory is not the current API. | Partially implemented | Preserve descriptor and custom-method work as a target. |
| `RSN-GAP-002` | `RSN-REQ-003`, `RSN-REQ-004`, `RSN-REQ-005`, `RSN-REQ-012`, `RSN-REQ-013`, `RSN-REQ-014` | All eight methods use shared execution and method limits. Complete limit conformance is not proved by one method example. | Implemented; evidence incomplete | Review method-specific construction and execution matrices. |
| `RSN-GAP-003` | `RSN-REQ-008`, `RSN-REQ-009`, `RSN-REQ-010` | Search engines implement ordering and pruning; target-wide deterministic tie/prune diagnostics need direct proof. | Implemented; evidence incomplete | Retain deterministic search contracts. |
| `RSN-GAP-004` | `RSN-REQ-015`, `RSN-REQ-016`, `RSN-REQ-017` | Results retain method-specific shapes and some reasoning metadata. The uniform result/private-thinking target needs review. | Decision required | Coordinate visibility with 01/12. |
| `RSN-GAP-005` | `RSN-REQ-022` | There is no general trusted custom-method registry matching RSN-REQ-022. | Proposed; not implemented | Retain registration, validation, and collision requirements. |
| `RSN-GAP-006` | `RSN-REQ-018`, `RSN-REQ-019`, `RSN-REQ-020`, `RSN-REQ-021` | Planning Actions do not establish a portable Plan type and deterministic executable lowering contract. | Proposed; not implemented | Retain Plan design; executable work remains Flow or host-owned. |

## Selected-direction gap

`RSN-GAP-007` — [EXE-DEC-005](../04_ai_execution/design.md#selected-direction-complete-the-runtime-split)
selects an explicit Profile-based dispatcher and method-owned validated
`method_state`. Current [Reasoning](../../../lib/jido_ai/reasoning.ex) dispatches
some transitions and diagnostics from `tree_search`, `graph_search`, or
`recursive` keys. This boundary is incomplete, not a new framework requirement.

Use the existing functions as the starting contract. Future evidence covers
all eight methods, Adaptive selection, invalid method state, transitions,
diagnostics, and common limits. `RSN-GAP-005` and `RSN-REQ-022` remain retained
extension proposals, excluded from this cleanup. The prerequisite is the
[execution boundary](../04_ai_execution/alignment.md#selected-direction-gap).
This direction does not approve this document or its other proposals.

## Decisions and dependency gates

Do not infer a reduced stable method set from the old first-release recommendation. Decide extension registration, common results, thinking visibility, and executable Plan semantics explicitly.

- Prerequisites: [04 Shared AI execution](../04_ai_execution/alignment.md).
- Dependents: 07, 08, 10.
- Blocker: approval of the affected target decisions, not a historical package compile failure.
- Assumption: the current public lower-package contracts remain the integration boundary. A proposed API in this design is not evidence of an upstream API.
- Re-review dependents when an owning contract changes. Do not infer approval from a passing test or a category rename.

## High-level work sequence

1. Resolve prerequisite ownership and the decisions above. Exit: each changed contract has an explicit decision and compatibility scope.
2. Align current public contracts and retained target requirements. Exit: current behavior and intended changes are distinct, with no fictional API presented as implemented.
3. Specify acceptance cases for each approved change, including examples, failure paths, and cleanup. Exit: each requirement has direct evidence or a named missing test outcome.
4. Review dependent seams, migrations, and release implications. Exit: no dependent document assumes an unapproved guarantee.

This is a dependency and outcome plan, not a formal implementation task list.
Implementation planning follows approval of the seam intent and requirements.

## Example-driven review

This follow-up uses the later selected decisions when older wording conflicts.
The [audit summary](../README.md#example-driven-design-audit) separates target
failures, related scenarios, API gates, and non-example release checks. All
requirements in this seam appear in the acceptance matrix below.

The new target checks extend existing example lessons. They use public APIs and
the local MockLLM transport. No target failure is skipped or changed to accept
the current behavior. Tests blocked by an unspecified public contract are
marked as a gate; no invented API is presented as an executable example.

## Acceptance matrix

Requirement IDs and target wording come from `design.md`. The evidence column
now names related example scenarios. **Related evidence is partial**, not full
requirement acceptance. A passing target check proves only its stated case.
`To be implemented — reproduced` identifies a failed target assertion, not a
failure inferred from a missing example. Source/release checks and public API
gates are separate. No row grants document approval.

| Requirement | Evidence state | Current evidence | Required acceptance outcome |
| --- | --- | --- | --- |
| `RSN-REQ-001` | Decision required | Related example evidence (partial): [invalid options tools steering typed results and rich queries fail before provider work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs); [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: Each public reasoning method shall have a stable identifier, option schema, state schema, capability declaration, Flow factory, and result contract. |
| `RSN-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [invalid options tools steering typed results and rich queries fail before provider work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs); [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: Method options and state shall be portable data and shall reject unknown fields at untrusted boundaries. |
| `RSN-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: A method shall use seam 02 for every model call and seam 03 for every local tool call. |
| `RSN-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: A method shall use public Flow components for branching, fan-out, reduction, iteration, subflows, and continuation. |
| `RSN-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: A method shall not create a worker pool, private task supervisor, graph scheduler, or direct Runic workflow. |
| `RSN-REQ-006` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: ReAct shall alternate model decisions and approved tool batches until final answer, failure, cancellation, or a limit. |
| `RSN-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: Linear methods shall preserve prompt-step order and shall return one final answer or structured result. |
| `RSN-REQ-008` | Implemented; evidence incomplete | Related example evidence (partial): [search returns ranked candidates and paths after two real model calls](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: Search methods shall assign stable candidate identifiers before concurrent evaluation. |
| `RSN-REQ-009` | Implemented; evidence incomplete | Related example evidence (partial): [search returns ranked candidates and paths after two real model calls](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: Search methods shall define deterministic score ordering and a deterministic tie-break rule. |
| `RSN-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [best-first beam retains only the configured frontier and top candidates](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: When a method prunes candidates, it shall retain the reason and score data required for safe diagnostics. |
| `RSN-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [automatic #{method} selection executes the actual method without an extra model call](../../../test/examples/09_reasoning/09_10_adaptive/09_10_adaptive_test.exs). | Verify the target behavior: An Adaptive method shall select only a declared method whose capabilities satisfy the request. |
| `RSN-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [invalid options tools steering typed results and rich queries fail before provider work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs). | Verify the target behavior: When a method does not support a requested feature, profile validation shall fail before model execution. |
| `RSN-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [the common model-call budget stops before a new phase and retains prior work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs). | Verify the target behavior: Each method shall declare finite defaults and hard maxima for its iterations, candidates, depth, breadth, and model calls as applicable. |
| `RSN-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [the common model-call budget stops before a new phase and retains prior work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs). | Verify the target behavior: The execution seam shall apply the most restrictive method, profile, request, and Exec bounds. |
| `RSN-REQ-015` | Decision required | Related example evidence (partial): [search returns ranked candidates and paths after two real model calls](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs); [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: Every terminal method result shall include method ID, status, value, termination reason, usage, and safe method metadata. |
| `RSN-REQ-016` | Decision required | Related example evidence (partial): [namespace method selection runs both profiles and reads their separate stored results](../../../test/examples/09_reasoning/09_02_method_api/09_02_method_api_test.exs). CoT/CoD request results contain conclusions rather than their steps. This does not prove privacy across every method or the explicit detail accessors. | Verify the target behavior: A method result shall not expose private chain-of-thought by default. |
| `RSN-REQ-017` | Decision required | To be implemented: retained reasoning classification with explicit private/provider-required/user-safe policy. | Verify the target behavior: When a method retains reasoning details, policy shall identify whether the data is private, provider-required, or safe for user output. |
| `RSN-REQ-018` | Proposed; not implemented | Related example evidence (partial): [planning prompts carry constraints resources depth and priority criteria](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs). | Verify the target behavior: Planning shall produce a validated portable plan value with stable step identifiers and declared dependencies. |
| `RSN-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [planning prompts carry constraints resources depth and priority criteria](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs). | Verify the target behavior: Planning shall not execute a plan unless the plan is explicitly lowered to a `Jido.Flow` or submitted to a host-owned orchestrator. |
| `RSN-REQ-020` | Proposed; not implemented | Related example evidence (partial): [planning prompts carry constraints resources depth and priority criteria](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs). | Verify the target behavior: When a plan is lowered to Flow, every executable plan step shall resolve to an approved Action or Subflow through a trusted registry. |
| `RSN-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [planning prompts carry constraints resources depth and priority criteria](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs). | Verify the target behavior: An encoded plan shall not contain anonymous functions, PIDs, provider clients, or unregistered executable targets. |
| `RSN-REQ-022` | Proposed; not implemented | Decision gate: trusted custom-method registration and validation API is not selected. Do not invent a registry in an example. | Verify the target behavior: A custom method shall register through a trusted method registry and shall pass the same option, state, capability, and Flow validation as built-in methods. |
| `RSN-REQ-023` | Implemented; evidence incomplete | Related example evidence (partial): [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: The Agent DSL and profile codec shall refer to methods by stable identifiers and portable options. |

## Migration and compatibility

Do not infer a reduced stable method set from the old first-release recommendation. Decide extension registration, common results, thinking visibility, and executable Plan semantics explicitly.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
