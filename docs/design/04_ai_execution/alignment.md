> Seam alignment review. Pending approval.

# Shared AI execution alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

One internal validated execution map carries Profile, ReqLLM context, counters, deadlines, and optional method state. Shared Actions and Flows run the model/tool cycle. ToolAttempt uses a bounded continuation plus sleep; output repair is separate runtime logic. Orchestration owns live request lifetime and settlement, not these step modules.

- Current owner: Execution.State, Flow, ModelFlow, Prepare, CallModel, Decide, ToolsFlow, ToolAttempt, and OutputState.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Keep one bounded execution path for all authoring forms and methods. Preserve advanced streaming, cancellation, retry, and effect contracts without making temporary execution state a portable context value.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/execution/state.ex](../../../lib/jido_ai/execution/state.ex) | Validated temporary execution map |
| [lib/jido_ai/execution/flow.ex](../../../lib/jido_ai/execution/flow.ex) | Canonical Flow |
| [lib/jido_ai/execution/tools_flow.ex](../../../lib/jido_ai/execution/tools_flow.ex) | Tool Map and continuation |
| [lib/jido_ai/execution/next_batch.ex](../../../lib/jido_ai/execution/next_batch.ex) | Batch partitioning |
| [lib/jido_ai/execution/tool_attempt.ex](../../../lib/jido_ai/execution/tool_attempt.ex) | Retry policy |
| [lib/jido_ai/execution/output_state.ex](../../../lib/jido_ai/execution/output_state.ex) | Output validation and repair |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_02_tool_flow/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_02_tool_flow): deterministic example evidence.
- [test/jido_ai/execution/state_test.exs](../../../test/jido_ai/execution/state_test.exs): detailed boundary evidence.
- [test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Keep one bounded execution path for all authoring forms and methods. Preserve advanced streaming, cancellation, retry, and effect contracts without making temporary execution state a portable context value.

Preserve current public behavior unless an approved decision includes a
migration. This follow-up changes examples and their tests, not runtime implementation.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `EXE-GAP-001` | `EXE-REQ-004`, `EXE-REQ-005`, `EXE-REQ-006` | Execution.State now exists as an internal map with provider values. It is not the proposed portable public Execution.Input/State. | Decision required | Separate temporary state from portable snapshots; review the public abstraction before adding it. |
| `EXE-GAP-002` | `EXE-REQ-018`, `EXE-REQ-019`, `EXE-REQ-020` | Runtime events carry correlation, but one shared schema for all attempts and projections is not established. | Implemented; evidence incomplete | Complete correlation evidence in 12. |
| `EXE-GAP-003` | `EXE-REQ-015`, `EXE-REQ-016`, `EXE-REQ-017` | Retry uses a continuation with bounded worker sleep; output repair has its own bounded path. | Decision required | Resolve EXE-REQ-015/017 without creating a generic retry engine. |
| `EXE-GAP-004` | `EXE-REQ-023`, `EXE-REQ-024` | Coordinator owns cancellation and worker cleanup through the current integration. The target names a public Exec cancellation contract. | Decision required | Verify the exact lower-level API and cancellation races before changing ownership. |
| `EXE-GAP-005` | `EXE-REQ-019`, `EXE-REQ-021`, `EXE-REQ-022` | Stream and caller-loss paths exist, but full slow-consumer, backpressure, caller-down, and mailbox-bound guarantees need direct proof. | Implemented; evidence incomplete | Retain slow-consumer and cleanup acceptance cases with 07/12. |
| `EXE-GAP-006` | `EXE-REQ-012`, `EXE-REQ-013`, `EXE-REQ-014` | Profile and method limits exist. A uniform account of hard maxima and limit provenance remains broader than the current controls. | Partially implemented | Retain limit source and most-restrictive-bound acceptance cases. |

## Selected-direction gap

`EXE-GAP-007` — [EXE-DEC-005](design.md#selected-direction-complete-the-runtime-split)
is selected but not implemented. [RequestTransform](../../../lib/jido_ai/execution/request_transform.ex)
constructs ReAct Config/State views. [Decide](../../../lib/jido_ai/execution/decide.ex)
uses that view to obtain the repair query. Execution.State names GoT/TRM machine
types. These are remaining dependencies on method-specific state.

Required evidence for the later change: all eight methods keep their current
behavior; shared transformers use a common view; repair works without ReAct
State construction; method-state validation rejects invalid state. ReAct
adapter and token tests cover compatibility. No such checks were run here.
Seams 02, 05, 06, and 11 depend on this boundary. Callback migration is open.

## Request adapter review gap

The [boundary proposal](design.md#proposed-execution-to-orchestration-boundary)
is not implemented. Runtime uses multiple Orchestration helpers and direct
Coordinator messages. [PendingInput](../../../lib/jido_ai/execution/pending_input.ex)
reads the queue from context and calls it directly.
[Checkpoint](../../../lib/jido_ai/execution/checkpoint.ex) calls Coordinator.

Future evidence covers tagged request/run identity, stale messages, safe
boundary positions, input order, commit waits, and unknown commit results.
Resolve seam 01 batch data and seam 07 replies before implementation planning.
No generic adapter framework is needed by this proposal.

### Selected bridge refinement

The user has selected the private bridge scope in
[EXE-REQ-031/032](design.md#proposed-execution-to-orchestration-boundary) and
[SES-REQ-049 through 055](../07_request_sessions/design.md#selected-private-execution-bridge).
The current source still uses the old helper/context interface; migration is
not yet complete. Existing model/tool contracts from prerequisite seams 02/03
are preserved. No public batch/receipt or transformer API is required here.

The acceptance evidence will cover one trusted binding, progress ordering,
required commit waits, rejection versus unknown outcomes, input sealing,
checkpoint continuation, owner loss, and ownerless direct Actions. Existing
method, standalone, and MockLLM examples remain the compatibility checks.
The bridge does not implement EXE-GAP-007's method-state changes.

| Requirement | Evidence state | Required acceptance outcome |
| --- | --- | --- |
| `EXE-REQ-031` | Proposed; not implemented | Execution and model streaming use the bridge; no direct owner messages or queue access remain in execution steps. |
| `EXE-REQ-032` | Implemented; evidence incomplete | Core Exec remains the only completion path after the migration; completion/cancellation tests pass unchanged. |

## Decisions and dependency gates

Resolve portable public Execution types, explicit Map concurrency, and the exact public cancellation contract against current core APIs.

- Prerequisites: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md).
- Dependents: 05, 06, 11.
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
| `EXE-REQ-001` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: Every multi-step AI request shall execute as a validated `Jido.Flow` through the public `Jido.Exec` contract. |
| `EXE-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: A profile lowerer shall build the same semantic Flow for module DSL, direct profile, and codec authoring forms. |
| `EXE-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: Developer-authored AI Flows shall use the standard `Jido.Flow` module DSL and AI Actions; Jido AI shall not define a competing graph DSL. |
| `EXE-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: Runtime profile data shall enter Flow input or Exec context and shall not be captured as changing data in a compiled Flow module. |
| `EXE-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [nested AI syntax lowers to an ordinary Agent and Flow](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs); [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: The execution Flow shall have one declared output that is a normalized terminal result or a normalized error. |
| `EXE-REQ-006` | Decision required | Related example evidence (partial): [text generation uses the resolved alias with the native ReqLLM API](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs). | Verify the target behavior: A model-call Action shall return a normalized Turn and shall not execute a tool. |
| `EXE-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: A decision Action shall select finalization, a tool batch, another approved model operation, or a terminal error. |
| `EXE-REQ-008` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: A dynamic decision shall use `Jido.Flow.Dispatch` or an equivalent public Flow component and shall not invoke an internal workflow runner. |
| `EXE-REQ-009` | Decision required | Related example evidence (partial): [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs). | Verify the target behavior: When the model selects multiple independent tools, the execution Flow shall use `Jido.Flow.Map` with an explicit positive `max_concurrency`. |
| `EXE-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs). | Verify the target behavior: Tool results added to context shall retain the original model call order, independent of completion order. |
| `EXE-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs); [an Action and Flow supply real, correlated results to the next model call](../../../test/examples/01_authoring/01_02_tool_flow/01_02_tool_flow_test.exs). | Verify the target behavior: After a tool batch completes, a continuation Action shall add the assistant tool-call turn and all tool results to context before the next model call. |
| `EXE-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [the common model-call budget stops before a new phase and retains prior work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs); [the iteration limit prevents another model call after tool results](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: Each execution shall have positive limits for total timeout, model calls, tool calls, reasoning iterations, and Flow continuations. |
| `EXE-REQ-013` | Decision required | Related example evidence (partial): [the common model-call budget stops before a new phase and retains prior work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs); [the iteration limit prevents another model call after tool results](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: The effective limit shall be the most restrictive value from package policy, profile policy, trusted request policy, and Exec options. |
| `EXE-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [the common model-call budget stops before a new phase and retains prior work](../../../test/examples/09_reasoning/09_06_got/09_06_got_test.exs); [the iteration limit prevents another model call after tool results](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: When any limit is reached, execution shall stop with a stable resource-limit error and a partial safe usage summary. |
| `EXE-REQ-015` | Decision required | Related example evidence (partial): [explicitly retryable tools get a fresh attempt budget within the total request deadline](../../../test/examples/02_requests/02_13_tool_limits/02_13_tool_limits_test.exs). Related retry-budget example exists. Flow continuation ownership still needs source-level proof; retries alone do not prove the complete requirement. | Verify the target behavior: When model or tool policy permits another attempt, the execution Flow shall represent the attempt as a bounded continuation or Iterate step. |
| `EXE-REQ-016` | Implemented; evidence incomplete | Source check: no independent retry supervisor or live retry state. Runtime response tests alone are insufficient. | Verify the target behavior: Jido AI execution code shall not start an independent retry supervisor or persist live retry state. |
| `EXE-REQ-017` | Decision required | To be implemented: delayed retry through an approved host Action, or explicit unsupported-policy error. Do not teach bridge sleep as the target. | Verify the target behavior: When retry policy requests a delay, execution shall use an approved host Action or return an unsupported-policy error; it shall not sleep inside the tool bridge. |
| `EXE-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: One execution shall assign stable request, run, model-call, and tool-call identifiers before related events are emitted. |
| `EXE-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: The event stream shall preserve causal order for one model call and monotonic sequence order for its deltas. |
| `EXE-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [tools run in each phase with callbacks and ordered results after reverse completion](../../../test/examples/09_reasoning/09_04_tot/09_04_tot_test.exs). | Verify the target behavior: A parallel tool batch can emit completion events in completion order, but its batch result shall preserve authored call order. |
| `EXE-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [cancellation stops a held real tool and cannot stop the next request](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [real SSE text and request headers precede the final commit](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: A stream shall emit exactly one terminal item: completed, failed, cancelled, or interrupted. |
| `EXE-REQ-022` | Implemented; evidence incomplete | Related example evidence (partial): [the trace cap keeps the first 2000 events and records overflow without hiding completion](../../../test/examples/02_requests/02_22_request_inspection/02_22_request_inspection_test.exs). | Verify the target behavior: Token and progress events shall be bounded and shall use seam 12 sanitization before transport. |
| `EXE-REQ-023` | Decision required | Related example evidence (partial): [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs); [cancellation stops a held real tool and cannot stop the next request](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: When the owner cancels live execution, Jido AI shall call the public Exec cancellation contract and shall not send a private worker message. |
| `EXE-REQ-024` | Implemented; evidence incomplete | Related example evidence (partial): [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs); [cancellation stops a held real tool and cannot stop the next request](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: Cancellation shall stop pending continuations and child tool work according to Exec cleanup rules. |
| `EXE-REQ-025` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs); [provider failure after tool work leaves state unchanged](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: A terminal success shall contain the final typed value, final context update, usage, safe metadata, and proposed effects. |
| `EXE-REQ-026` | Implemented; evidence incomplete | Related example evidence (partial): [three dependent tool rounds precede the committed answer](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs); [provider failure after tool work leaves state unchanged](../../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs). | Verify the target behavior: The execution result shall not commit Agent state or dispatch post-commit Directives. |
| `EXE-REQ-027` | Implemented; evidence incomplete | Related example evidence (partial): [DSL data Builder source JSON direct Flow and ordinary turns use the same recursive contract](../../../test/examples/09_reasoning/09_08_trm/09_08_trm_test.exs). | Verify the target behavior: Asynchronous and synchronous request helpers shall use the same canonical AI Flow, model gateway, tool bridge, limits, and terminal result contract. |
| `EXE-REQ-028` | Superseded | Retired in the owning design after selection of one AI request lifecycle. | Keep the identifier; use the admission/execution/settlement requirements. |
| `EXE-REQ-029` | Implemented; evidence incomplete | Related example evidence (partial): [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: When a host stores or transports a custom AI Flow, it shall use `Jido.Flow.Codec` with a trusted Flow registry and shall not use a Jido AI-specific graph format. |
| `EXE-REQ-030` | Implemented; evidence incomplete | Related example evidence (partial): [common AI lowering composes with core data, Builder and JSON](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: When Jido AI constructs a Flow directly, it shall use public canonical Flow component constructors and the same validation as DSL, Builder, and Codec forms. |

## Migration and compatibility

Resolve portable public Execution types, explicit Map concurrency, and the exact public cancellation contract against current core APIs.

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
