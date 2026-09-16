> Seam alignment review. Pending approval.

# Model integration and request preparation alignment

## Status

- Reviewed: 2026-09-15.
- Code baseline: `v3-spike`, HEAD `4ed6402f`, plus uncommitted runtime, test, example, and documentation refinement. Dependency pins are unchanged.
- Prerequisite alignments used: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Models uses native ReqLLM/LLMDB model inputs. Model.Transport owns provider requests, Model.Options merges trusted options, and Model.Messages adapts messages and reference metadata. Execution.RequestTransform still exposes ReAct-specific callback views. Direct model contracts remain native; Agent results are adapted for their storage and request contracts.

- Current owner: Models and Model.Transport, Model.Options, Model.Messages, Model.Generate; routing policy is in seam 08.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Keep trusted provider binding, deterministic option precedence, bounded streaming and repair, and advanced named request-transform stages. Do not assume a new ModelRef wrapper is needed to achieve these capabilities.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/models.ex](../../../lib/jido_ai/models.ex) | Native model resolution and identity |
| [lib/jido_ai/model/transport.ex](../../../lib/jido_ai/model/transport.ex) | Provider request boundary |
| [lib/jido_ai/model/options.ex](../../../lib/jido_ai/model/options.ex) | Option normalization |
| [lib/jido_ai/model/messages.ex](../../../lib/jido_ai/model/messages.ex) | Message/reference adaptation |
| [lib/jido_ai/execution/request_transform.ex](../../../lib/jido_ai/execution/request_transform.ex) | Current transform adapter |

### Examples and tests

- [Example briefing](../../../examples/01_authoring/01_08_model_helpers/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/01_authoring/01_08_model_helpers): deterministic example evidence.
- [test/authoring/agents/transport_test.exs](../../../test/authoring/agents/transport_test.exs): detailed boundary evidence.
- [test/jido_ai/model/options_test.exs](../../../test/jido_ai/model/options_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Keep trusted provider binding, deterministic option precedence, bounded streaming and repair, and advanced named request-transform stages. Do not assume a new ModelRef wrapper is needed to achieve these capabilities.

Preserve current public behavior unless an approved decision includes a
migration. The initial audit changed examples and tests. The implementation follow-up also changes the runtime; see the current evidence below.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `MDL-GAP-001` | `MDL-REQ-004` | Native model inputs are intentional; portable encoding is a separate constraint. ModelRef is not an implemented type. | Decision required | Retain reference safety while deciding whether any wrapper adds value. |
| `MDL-GAP-002` | `MDL-REQ-002` | Resolution and routing exist; complete routing-reason and identity projection evidence is not established by one example. | Implemented; evidence incomplete | Review MDL-REQ-002 with seams 08/12. |
| `MDL-GAP-003` | `MDL-REQ-007`, `MDL-REQ-008` | The current transformer is not the full named portable stage contract and retains ReAct views. | Decision required | Define the advanced stage contract and its compatibility. |
| `MDL-GAP-004` | `MDL-REQ-016`, `MDL-REQ-017`, `MDL-REQ-021` | MDL-REQ-016/017/021 already preserve native direct-call contracts. The old gap demanded the opposite. | Superseded | Keep native direct results; review Agent normalization separately. |
| `MDL-GAP-005` | `MDL-REQ-018`, `MDL-REQ-019` | Runtime output repair is bounded. Uniform repair-attempt events and provider edge behavior need requirement-specific proof. | Partially implemented | Use MDL-REQ-018/019 and 04/12, not the old misnumbered row. |
| `MDL-GAP-006` | `MDL-REQ-022` | Transport has no independent retry supervisor. Execution owns bounded attempts. | Implemented; evidence incomplete | Add ownership evidence if this is a release guarantee. |

## Selected transformer direction

The ReAct callback view in Execution.RequestTransform remains an implementation
gap against [EXE-DEC-005](../04_ai_execution/design.md#selected-direction-complete-the-runtime-split).
This seam owns the common-view and callback contract review. Compatibility
for existing `transform_request/4` implementations is not decided. Evidence
for the later change includes normal requests, repairs, transformer errors,
tool selection, and option precedence. No adapter or new signature is approved
by this note; coordinate the migration gate with seam 90.

## Explicit binding alignment gap

Model.Transport currently uses Process.put, $callers, and process dictionary
lookup for option binding. The [selected direction](design.md#selected-explicit-binding-direction)
removes production dependence on that lookup. Future checks cover explicit
bindings across worker boundaries, missing bindings, isolated MockLLM requests,
and the same runtime path for mock and live providers. No code changed or tests
ran. Coordinate ownership with seam 06 and resource scope with seam 09.

## Decisions and dependency gates

Separate native direct-call APIs from portable stored data. Resolve transform stages and callback views without introducing a second provider facade.

- Prerequisites: [01 Canonical interaction and AI values](../01_ai_values/alignment.md).
- Dependents: 04, 08.
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
| `MDL-REQ-001` | Implemented; evidence incomplete | Related example evidence (partial): [rich model aliases resolve at the request boundary and text output uses the same operation](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: When a request names a profile model alias, the gateway shall resolve the alias at request start against that profile's validated model table. |
| `MDL-REQ-002` | Implemented; evidence incomplete | Related example evidence (partial): [built in routing selects actual models for Chat operations](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs). | Verify the target behavior: When model-routing policy selects a model, the gateway shall record the selected alias, concrete model identifier, and routing reason in request-local metadata. |
| `MDL-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [invalid explicit or routed native models fail before provider work](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs). | Verify the target behavior: When a model alias or concrete model cannot be resolved, the gateway shall return a validation error before a provider call starts. |
| `MDL-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [rich model aliases resolve at the request boundary and text output uses the same operation](../../../test/examples/01_authoring/01_06_ai_extension/01_06_ai_extension_test.exs). | Verify the target behavior: A model reference stored in a profile, Signal, or checkpoint shall be portable data and shall not contain a provider client or credential. |
| `MDL-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [built in routing selects actual models for Chat operations](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs); [media query, model options, refs and real tool output reach the provider](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: The gateway shall apply option precedence in the documented order and shall expose the effective safe options for diagnostics. |
| `MDL-REQ-006` | Implemented; evidence incomplete | Related example evidence (partial): [Signal data cannot replace a host profile](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: The gateway shall reject a provider or transport option that arrives through untrusted Signal data. |
| `MDL-REQ-007` | Decision required | To be implemented: named-stage transform example with two stages and a first-stage failure. Select the common portable callback contract before adding a runnable consumer. | Verify the target behavior: When request transforms are configured, the gateway shall run them in declared stage order and shall stop at the first error. |
| `MDL-REQ-008` | Decision required | To be implemented: portable transform input/context and tagged errors. Current ReAct callback views do not establish the selected shared contract. | Verify the target behavior: A request transform shall receive portable request data and explicit context and shall return `{:ok, value}` or `{:error, reason}`. |
| `MDL-REQ-009` | Implemented; evidence incomplete | Related example evidence (partial): [streamed objects use the provider schema and the common result validator](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: The gateway shall add structured-output instructions and provider schema data from the approved `Jido.AI.Output` contract. |
| `MDL-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [text generation uses the resolved alias with the native ReqLLM API](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [structured generation stays on the native ReqLLM contract](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [two tool rounds preserve options usage and one assistant message per response](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs). | Verify the target behavior: All text, object, embedding, and stream provider calls shall enter through the ReqLLM integration boundary. |
| `MDL-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [text generation uses the resolved alias with the native ReqLLM API](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [structured generation stays on the native ReqLLM contract](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [two tool rounds preserve options usage and one assistant message per response](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs). | Verify the target behavior: A model Action shall call the gateway and shall return only public Jido Action result forms. |
| `MDL-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [real SSE text and request headers precede the final commit](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: When a provider stream starts, the gateway shall assign one stable model-call identifier before it emits the first item. |
| `MDL-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [streamed tool calls execute once and event IDs follow the model rounds](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs); [real SSE text and request headers precede the final commit](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: The gateway shall preserve provider item order and shall assign a monotonic sequence number when the provider does not supply one. |
| `MDL-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [streamed objects use the provider schema and the common result validator](../../../test/examples/02_requests/02_01_session/02_01_session_test.exs). | Verify the target behavior: When a stream ends normally, the gateway shall produce the same normalized terminal Turn and Usage value as the equivalent non-stream call. |
| `MDL-REQ-015` | Implemented; evidence incomplete | Target scenario repaired: [MDL-REQ-015 target check](../../../test/examples/02_requests/02_25_incomplete_response/design_requirements_test.exs). Nonempty truncated responses fail before successful completion, including decoded objects. Full-clause and provider-matrix proof remains separate. | Verify the target behavior: When a stream fails or stops early, the gateway shall return a normalized error and shall not present partial content as a completed result. |
| `MDL-REQ-016` | Implemented; evidence incomplete | Related example evidence (partial): [text generation uses the resolved alias with the native ReqLLM API](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [structured generation stays on the native ReqLLM contract](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs); [two tool rounds preserve options usage and one assistant message per response](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs). | Verify the target behavior: Direct model calls shall keep the native ReqLLM response and usage contracts. |
| `MDL-REQ-017` | Implemented; evidence incomplete | Related example evidence (partial): [the generated command commits an answer and preserves domain data](../../../test/examples/01_authoring/01_01_authoring_formats/01_01_authoring_formats_test.exs). | Verify the target behavior: Agent runtime seams can convert ReqLLM values when an Agent contract needs a stable stored result. |
| `MDL-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [schema feedback reaches one repair before a valid object commits](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs); [repair calls share one request and token budget](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: When structured-output validation requests repair, the gateway shall perform only the bounded attempts allowed by the output contract. |
| `MDL-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [schema feedback reaches one repair before a valid object commits](../../../test/examples/01_authoring/01_03_structured_output/01_03_structured_output_test.exs); [repair calls share one request and token budget](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Each repair call shall use a new model-call identifier and shall remain correlated with the parent AI request. |
| `MDL-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [resume binds a new local transport without saving credentials or callback handles](../../../test/examples/14_resume/14_03_checkpoint_resume/14_03_checkpoint_resume_test.exs). | Verify the target behavior: When the gateway needs a provider client or credential, it shall resolve it from a trusted runtime binding supplied by the host. |
| `MDL-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [provider errors keep the native ReqLLM tagged result](../../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs). | Verify the target behavior: Direct calls shall keep ReqLLM errors. Agent runtime seams shall preserve the provider cause in a bounded internal field when they convert an error. |
| `MDL-REQ-022` | Implemented; evidence incomplete | Source check: provider retry classification versus execution-owned scheduling. A passing response alone cannot prove absence of independent workers. | Verify the target behavior: The gateway shall classify retry eligibility but shall not schedule retry delay or create an independent retry worker. |

## Migration and compatibility

Separate native direct-call APIs from portable stored data. Resolve transform stages and callback views without introducing a second provider facade.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Runtime repair follow-up

The current worktree adds runtime repairs over the audit baseline. Dependencies
are unchanged. The [audit summary](../README.md#example-driven-design-audit)
separates the repaired scenarios from the remaining advanced API gates. A passing
scenario is not complete requirement conformance.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
