> Seam alignment review. Pending approval.

# Package boundary and invariants alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: None.
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Jido AI lowers Profiles into core Agent routes and Plugins and uses Flow/Exec for execution. Session and Thread values belong to this package. Orchestration owns AI live-work coordination while core Jido owns Agent commit and topology. The package version remains 2.3.0 with V3 beta dependencies and a pinned ReqLLM Git source.

- Current owner: Jido.AI package boundary; core Jido, jido_action, jido_signal, and host interfaces.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve the complete AI capability set above public lower-package contracts. Separate in-memory coordination from host-owned durability and external-effect guarantees.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai.ex](../../../lib/jido_ai.ex) | Public package boundary |
| [lib/jido_ai/authoring.ex](../../../lib/jido_ai/authoring.ex) | Lowering to Agent routes and Plugins |
| [lib/jido_ai/execution/tool_attempt.ex](../../../lib/jido_ai/execution/tool_attempt.ex) | Bounded retry still sleeps inside the worker |
| [mix.exs](../../../mix.exs) | Actual version and dependency sources |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_07_ai_runtime/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_07_ai_runtime): deterministic example evidence.
- [test/authoring/agents/boundaries_test.exs](../../../test/authoring/agents/boundaries_test.exs): detailed boundary evidence.
- [test/jido_ai/execution/checkpoint_test.exs](../../../test/jido_ai/execution/checkpoint_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve the complete AI capability set above public lower-package contracts. Separate in-memory coordination from host-owned durability and external-effect guarantees.

Preserve current public behavior unless an approved decision includes a
migration. This follow-up changes examples and their tests, not runtime implementation.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `BND-GAP-001` | `BND-REQ-001`, `BND-REQ-003` | Release metadata still uses 2.3.0 and an Actions/Workflows description. V3 dependency selection is present; a release version is not. | Decision required | Review release wording and version policy in 90. |
| `BND-GAP-002` | `BND-REQ-002` | ToolAttempt returns a continuation after a bounded Process.sleep. The no-sleep target is not implemented. | Decision required | Decide execution-delay ownership with 03/04; do not add a generic scheduler here. |
| `BND-GAP-003` | `BND-REQ-003`, `BND-REQ-011` | The old operations/react_runner path is removed. The standalone adapter uses an Agent and the shared runtime. | Superseded | Retain lifecycle and cleanup coverage; no second runner is required. |
| `BND-GAP-004` | `BND-REQ-006`, `BND-REQ-007`, `BND-REQ-009` | Boundary tests reject invalid routes, fields, managed Plugins, and initialized hosts. This is not a proof of every public path. | Implemented; evidence incomplete | Complete per-entry-point ownership evidence. |
| `BND-GAP-005` | `BND-REQ-012` | Candidate/effect separation exists. External effects are not rolled back by an Agent commit failure. | Partially implemented | Retain idempotency and uncertain-outcome design work in 03/11. |
| `BND-GAP-006` | `BND-REQ-014`, `BND-REQ-016` | The old missing-Thread compile blocker is resolved by package-owned canonical values. | Superseded | Use current package checks, not the old sibling failure, as the gate. |

## Decisions and dependency gates

Confirm the retry-delay boundary and the external-effect contract before changing execution mechanics. Release metadata is separate delivery work.

- Prerequisites: None.
- Dependents: 01, 06.
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
| `BND-REQ-001` | Decision required | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs); [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: The Jido AI package shall own only model-provider integration, AI data, AI reasoning, AI tool policy, AI request policy, AI capability policy, AI skill behavior, AI resume data, and AI observation semantics. |
| `BND-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs); [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: The Jido AI package shall use `Jido.Action`, `Jido.Instruction`, `Jido.Flow`, and `Jido.Exec` as the only public computation and in-memory execution contracts. |
| `BND-REQ-003` | Decision required | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs); [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: The Jido AI package shall use core `Jido.Agent`, Turn, Plugin, Directive, commit, AgentServer, checkpoint, and OTP runtime contracts without a competing implementation. |
| `BND-REQ-004` | Not revalidated | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs); [all ten public Signal definitions validate and pass through real core outbound delivery](../../../test/examples/02_requests/02_16_typed_signals/02_16_typed_signals_test.exs). | Verify the target behavior: The Jido AI package shall use `Jido.Signal` as the only Signal envelope and shall use public Signal routing, dispatch, and bus contracts. |
| `BND-REQ-005` | Decision required | Source check: confirm browser execution stays in jido_browser Actions/adapters. A consumer example cannot prove package ownership. | Verify the target behavior: The Jido AI package shall consume browser functions only as Actions or explicit adapters owned by `jido_browser`. |
| `BND-REQ-006` | Implemented; evidence incomplete | Related example evidence (partial): [the supervised store survives callers and an Agent stop](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs); [resume binds a new local transport without saving credentials or callback handles](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs). | Verify the target behavior: The host application shall own credentials, provider-client supervision, application stores, durable queues, deployment, distribution, domain tools, and product policy. |
| `BND-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs); [restored request records reject runtime resources and mismatched IDs](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: When Jido AI accepts static definition data, it shall reject a process, port, reference, task, monitor, anonymous function, or other nonportable runtime value unless the public contract explicitly identifies a local-only field. |
| `BND-REQ-008` | Not revalidated | Related example evidence (partial): [resume binds a new local transport without saving credentials or callback handles](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs); [declared sources own their catalogue provider and resource policy](../../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs). | Verify the target behavior: When Jido AI needs a runtime resource, it shall resolve that resource from the caller context, Plugin runtime, or an explicit host registry after definition validation. |
| `BND-REQ-009` | Implemented; evidence incomplete | Related example evidence (partial): [versioned documents round-trip and reject runtime data](../../../test/examples/02_requests/02_27_thread_session_values/02_27_thread_session_values_test.exs); [restored request records reject runtime resources and mismatched IDs](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Jido AI shall not store credentials or live runtime handles in Agent domain state, Plugin state, Signals, codecs, or checkpoints. |
| `BND-REQ-010` | Not revalidated | Related example evidence (partial): [the generated command commits an answer and preserves domain data](../../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs); [DSL helper executes Action and Flow tools and preserves Plugin ownership](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: When AI work runs as a core Turn, it shall return a complete candidate Agent and validated Directives through the public Turn result contract. |
| `BND-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [a refused durable completion stops the Agent without another write or Directive dispatch](../../../test/examples/02_requests/02_11_completion/02_11_completion_test.exs). | Verify the target behavior: Jido AI shall not mutate private AgentServer state or dispatch post-commit work before core commit succeeds. |
| `BND-REQ-012` | Decision required | Related example evidence (partial): [a failed Agent result commit does not undo the external memory write](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: When an Action or Flow performs external I/O before commit, the public contract shall state that rollback is not available and shall identify any idempotency requirement. |
| `BND-REQ-013` | Not revalidated | Related example evidence (partial): [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: When the same admitted command uses direct and live core execution, Jido AI shall preserve the same AI validation, Flow, candidate, and Directive semantics, except for behavior that requires an explicitly declared live runtime. |
| `BND-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [after-tools checkpoint preserves completed tool history and does not repeat its side effect](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs). | Verify the target behavior: Jido AI shall not describe `Jido.Exec` state, Flow step state, or an AI session process as a durable checkpoint. |
| `BND-REQ-015` | Not revalidated | Related example evidence (partial): [after-tools checkpoint preserves completed tool history and does not repeat its side effect](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs). | Verify the target behavior: When durable orchestration is required, Jido AI shall expose portable commands, results, events, and resume data for a host-owned or separately owned orchestrator. |
| `BND-REQ-016` | Implemented; evidence incomplete | Release check: inspect the resolved dependency graph and run the compatible V3 matrix. | Verify the target behavior: V3 integration tests shall use compatible V3 package versions unless a test explicitly verifies V2 migration or compatibility. |

## Migration and compatibility

Confirm the retry-delay boundary and the external-effect contract before changing execution mechanics. Release metadata is separate delivery work.

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
