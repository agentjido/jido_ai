> Seam alignment review. Pending approval.

# Capabilities and policy alignment

## Status

- Reviewed: 2026-09-15.
- Code for the example audit: `v3-spike`, HEAD `7bb011e98349af8bf580e7b93afa60990972beae`, plus uncommitted example, test, formatter, and documentation changes. No `lib/` or dependency changes.
- Prerequisite alignments used: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Alignment state: Draft. Current ownership is mapped; target decisions and full acceptance proof remain.
- Verification: the example-driven review below adds fresh MockLLM runs to the earlier source review. Earlier statements that no tests ran refer to that prior review, not this follow-up.

## Current architecture

Optional Plugins compose chat, reasoning, planning, routing, policy, retrieval, and quota. Capability.run accepts either a Profile-bound reasoning input or defaults-bound capability input. Stores and policies remain distinct from core Agent ownership; there is no second AI Agent authoring model.

- Current owner: Capability, ReasoningCapability, optional Plugins, ModelRouter, Quota, Retrieval.Store, and capability Actions.
- Cross-package ownership: core Jido owns Agent commit and topology; Flow/Exec and Signal internals remain in their respective packages.
- Overall placement: [architecture overview](../ARCHITECTURE.md).
- Full target: [design](design.md). Preserve advanced capability composition, contribution validation, deterministic ordering, bounded retrieval, routing diagnostics, and quota policy. Use core Plugin contracts rather than a parallel Plugin framework.

## Inputs and evidence

### Canonical code

| Source | Evidence scope |
| --- | --- |
| [lib/jido_ai/capability.ex](../../../lib/jido_ai/capability.ex) | Two current capability bindings |
| [lib/jido_ai/plugins/model_routing.ex](../../../lib/jido_ai/plugins/model_routing.ex) | Routing policy |
| [lib/jido_ai/plugins/retrieval.ex](../../../lib/jido_ai/plugins/retrieval.ex) | Retrieval integration |
| [lib/jido_ai/retrieval/store.ex](../../../lib/jido_ai/retrieval/store.ex) | Store implementation |
| [lib/jido_ai/quota/store.ex](../../../lib/jido_ai/quota/store.ex) | Quota storage |

### Examples and tests

- [Example briefing](../../../examples/16_capabilities/16_03_routing_policy/README.md): public behavior and documented limits.
- [Matching example tests](../../../test/examples/16_capabilities/16_03_routing_policy): deterministic example evidence.
- [test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs): detailed boundary evidence.
- [test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs): detailed boundary evidence.

These are evidence entry points, not blanket acceptance claims. The requirement
matrix below separates target decisions from implemented behavior whose full
proof is still incomplete. Inert declaration support is not runtime support.

## Retained baseline

Preserve advanced capability composition, contribution validation, deterministic ordering, bounded retrieval, routing diagnostics, and quota policy. Use core Plugin contracts rather than a parallel Plugin framework.

Preserve current public behavior unless an approved decision includes a
migration. This follow-up changes examples and their tests, not runtime implementation.
Advanced requirements remain in the target even when they are not implemented.

## Gap register

Existing gap IDs remain stable. Superseded rows identify resolved historical
findings, not removed target requirements. Old acceptance labels and erroneous
requirement associations are not carried forward as proof.

| Gap | Requirement or proposal | Current evidence or difference | State | Required outcome and owner |
| --- | --- | --- | --- | --- |
| `CAP-GAP-001` | `CAP-REQ-001`, `CAP-REQ-002`, `CAP-REQ-003` | Plugins and bindings exist; there is no universal contribution value matching the proposal. | Decision required | Evaluate the descriptor against existing core Plugin contracts. |
| `CAP-GAP-002` | `CAP-REQ-004`, `CAP-REQ-005`, `CAP-REQ-006` | Core composition and field/route checks exist. The full cross-capability dependency and collision matrix remains broader. | Implemented; evidence incomplete | Retain composition acceptance work. |
| `CAP-GAP-003` | `CAP-REQ-008`, `CAP-REQ-009`, CAP-DEC-005 | Capability.run has Profile-bound and defaults-bound forms. | Partially implemented | Keep distinct inputs behind one internal preparation result; do not require Profiles for simple non-model capabilities. |
| `CAP-GAP-004` | `CAP-REQ-010` | Routing changes model selection. Uniform selection reasons and observations require cross-seam proof. | Implemented; evidence incomplete | Align with 02/12. |
| `CAP-GAP-005` | `CAP-REQ-015`, `CAP-REQ-016`, `CAP-REQ-017`, `CAP-REQ-018`, `CAP-REQ-019` | Retrieval Store and integration exist. General adapter behavior and strict enrichment bounds need review. | Partially implemented | Retain the advanced store and result-limit contract. |
| `CAP-GAP-006` | Capability state-version proposal; resource failure is CAP-REQ-026 | Current policy/quota state works; universal versioned capability state migration is not established. | Partially implemented | Keep explicit codec and migration work; do not imply durable accounting. |

## Decisions and dependency gates

CAP-DEC-005 selects declared required stages and explicit rejection. The two
input forms remain distinct behind one internal preparation result. A new
public contribution descriptor is not selected. Verify the recommended stage
order against core Plugin callbacks before implementation. Keep admission in
core and quota checks at each provider call. Define store ownership and
versioning without implying durable billing or workflow guarantees.

- Prerequisites: [02 Model integration and request preparation](../02_model_gateway/alignment.md), [03 Tools, sources, and effect policy](../03_tool_bridge/alignment.md), [05 Reasoning and planning methods](../05_reasoning_planning/alignment.md), [07 Request orchestration and active input](../07_request_sessions/alignment.md).
- Dependents: 10.
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
| `CAP-REQ-001` | Decision required | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: Each capability shall have a stable ID, option schema, contribution contract, owned state, runtime needs, and dependency declaration. |
| `CAP-REQ-002` | Decision required | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: Capability construction shall be inert and shall perform no store access, process start, model call, or tool call. |
| `CAP-REQ-003` | Implemented; evidence incomplete | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: Capability contributions shall lower to public Profile, Action, Flow, route, schema, and Plugin contracts. |
| `CAP-REQ-004` | Implemented; evidence incomplete | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: When two capabilities claim the same profile field, Agent schema field, route identity, Plugin module, Plugin state key, or Directive type, lowering shall reject the conflict unless an explicit composition rule exists. |
| `CAP-REQ-005` | Implemented; evidence incomplete | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: Capability ordering shall be deterministic and visible through authoring inspection. |
| `CAP-REQ-006` | Implemented; evidence incomplete | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: A capability shall not depend on private state or callbacks from another capability. |
| `CAP-REQ-007` | Implemented; evidence incomplete | Related example evidence (partial): [two tool rounds preserve options usage and one assistant message per response](../../../test/examples/16_capabilities/16_02_chat/16_02_chat_test.exs). | Verify the target behavior: The Chat capability shall store conversation history only in the Agent domain field declared by the author. |
| `CAP-REQ-008` | Decision required | Related example evidence (partial): [Profile policy and route bindings are stable with reverse order #{reverse}](../../../test/examples/16_capabilities/16_01_reasoning/16_01_reasoning_test.exs). | Verify the target behavior: The Reasoning capability shall select and configure a registered seam 05 method and shall not implement a separate method runner. |
| `CAP-REQ-009` | Decision required | Related example evidence (partial): [planning prompts carry constraints resources depth and priority criteria](../../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs). | Verify the target behavior: The Planning capability shall create, validate, or revise plan values and shall not execute a generic plan outside Flow or a host orchestrator. |
| `CAP-REQ-010` | Implemented; evidence incomplete | Related example evidence (partial): [built in routing selects actual models for Chat operations](../../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs). | Verify the target behavior: ModelRouting shall return a portable model alias, routing reason, and safe metadata through the seam 02 selection contract. |
| `CAP-REQ-011` | Implemented; evidence incomplete | Related example evidence (partial): [missing or refused authorization prevents model work](../../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs); [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: A control shall run as a declared Action through `Jido.Exec` at one of the `:input`, `:model`, `:operation`, or `:output` stages. |
| `CAP-REQ-012` | Implemented; evidence incomplete | Related example evidence (partial): [missing or refused authorization prevents model work](../../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs); [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: A control shall return `:ok`, a normalized error, or an allowed operation-stage interrupt. |
| `CAP-REQ-013` | Implemented; evidence incomplete | Related example evidence (partial): [missing or refused authorization prevents model work](../../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs); [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: A control interrupt shall not bypass candidate validation, effect policy, or session settlement. |
| `CAP-REQ-014` | Implemented; evidence incomplete | Related example evidence (partial): [missing or refused authorization prevents model work](../../../test/examples/01_authoring/01_04_controls/01_04_controls_test.exs); [live cancellation stops owned tool work and preserves the commit](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: Controls shall share the request deadline and shall not create an unbounded independent task. |
| `CAP-REQ-015` | Implemented; evidence incomplete | Related example evidence (partial): [ranking updates and namespace isolation retain the public Store contract](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: Retrieval shall define a provider-neutral store behavior for recall, upsert, delete or clear, readiness, and error normalization. |
| `CAP-REQ-016` | Implemented; evidence incomplete | Related example evidence (partial): [the supervised store survives callers and an Agent stop](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: The host shall supervise each retrieval store process; a capability call shall not start an implicit store. |
| `CAP-REQ-017` | Implemented; evidence incomplete | Related example evidence (partial): [ranking updates and namespace isolation retain the public Store contract](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: Retrieval results shall have stable IDs, text or content, score, safe metadata, and deterministic ordering. |
| `CAP-REQ-018` | Implemented; evidence incomplete | Related example evidence (partial): [configured limits bound snippets and request opt out keeps routes available](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: Retrieval enrichment shall identify its source and shall remain within configured item and byte limits. |
| `CAP-REQ-019` | Implemented; evidence incomplete | Related example evidence (partial): [an Agent checkpoint keeps config but does not copy the external memory store](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs). | Verify the target behavior: Agent checkpoints shall not contain the external retrieval store or claim to restore it. |
| `CAP-REQ-020` | Implemented; evidence incomplete | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Quota admission shall correlate one reservation with the model-call identifier before provider invocation. |
| `CAP-REQ-021` | Implemented; evidence incomplete | Related example evidence (partial): [failed provider invocations retain unknown usage and consume a request slot](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Quota settlement shall record known usage once for the matching reservation and shall handle unknown final usage explicitly. |
| `CAP-REQ-022` | Implemented; evidence incomplete | Related example evidence (partial): [a mirrored model usage Signal cannot charge the provider call twice](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: A quota store shall reject duplicate active call identifiers and shall not double-count a repeated terminal report. |
| `CAP-REQ-023` | Implemented; evidence incomplete | Related example evidence (partial): [missing Store fails before provider use and a Store restart starts empty](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: The host shall supervise the authoritative quota store and define its durability; Jido AI shall not imply durability for an in-memory store. |
| `CAP-REQ-024` | Implemented; evidence incomplete | Related example evidence (partial): [over-budget requests fail before HTTP and reset permits later work](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: Quota policy shall return a stable allow or reject decision before the guarded provider call. |
| `CAP-REQ-025` | Implemented; evidence incomplete | Related example evidence (partial): [DSL helper executes Action and Flow tools and preserves Plugin ownership](../../../test/examples/01_authoring/01_07_ai_runtime/01_07_ai_runtime_test.exs). | Verify the target behavior: A capability Plugin shall own at most one state key and shall use an optional runtime root only for real live state. |
| `CAP-REQ-026` | Implemented; evidence incomplete | Related example evidence (partial): [store absence fails before model work and opt out still permits a request](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs); [missing Store fails before provider use and a Store restart starts empty](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: When a required capability resource is unavailable, the request shall fail with a capability-specific normalized error before dependent work starts. |
| `CAP-REQ-027` | Not revalidated | Related example evidence (partial): [store absence fails before model work and opt out still permits a request](../../../test/examples/07_retrieval/07_01_memory/07_01_memory_test.exs); [missing Store fails before provider use and a Store restart starts empty](../../../test/examples/13_policy/13_01_quota/13_01_quota_test.exs). | Verify the target behavior: A capability shall not silently disable an explicitly requested policy, retrieval, quota, or control feature. |
| `CAP-REQ-028` | Decision required | To be implemented: declare capability policy stages through an agreed public contract. | Verify the target behavior: Each capability shall declare its required policy stages. |
| `CAP-REQ-029` | Decision required | To be implemented: reject invalid required-stage declarations before model or tool work. | Verify the target behavior: Shared capability preparation shall validate the required-stage declaration. |
| `CAP-REQ-030` | Decision required | To be implemented: observe required stages in fixed semantic order through public behavior. | Verify the target behavior: Shared capability preparation shall apply required stages in the fixed semantic policy order. |
| `CAP-REQ-031` | Decision required | To be implemented: prove an unrequested stage has no effect and starts no resource. | Verify the target behavior: Shared capability preparation shall apply only the capability's required policy stages. |
| `CAP-REQ-032` | Decision required | To be implemented: missing required stage yields capability, stage, and reason without starting work. | Verify the target behavior: If a required stage is unavailable, then shared capability preparation shall return a structured error identifying the capability, stage, and reason. |
| `CAP-REQ-033` | Decision required | To be implemented: required-stage failure cannot silently select another path. | Verify the target behavior: Shared capability preparation shall reject an unavailable required stage without skipping it or choosing an implicit fallback. |

## Migration and compatibility

Decide whether a new contribution descriptor simplifies the two current input contracts. Define store ownership and versioning without implying durable billing or workflow guarantees.

Keep existing request, data, Signal, and provider contracts until a change is
approved. A documentation rename does not authorize a wire-format change.
Retained advanced proposals need their own migration and operational review.
Source paths above replace old `operations/`, `shared/`, live Session, and
`examples/v3/` references as evidence; historical paths are not current owners.

## Selected-stage acceptance additions

Current Capability.run has separate preparation paths. These rows describe
missing proof for the selected shared contract, not newly implemented code.

The [acceptance matrix](#acceptance-matrix) now contains the evidence and
remaining work for `CAP-REQ-028`, `CAP-REQ-029`, `CAP-REQ-030`, `CAP-REQ-031`, `CAP-REQ-032`, `CAP-REQ-033`.

Additional regression evidence: both input forms, a non-model capability without
a Profile, core admission rejection, per-provider-call quota checks, usage
accounting, and result placement. Exact stage schema and semantic order remain
open review items. No tests ran in this documentation task.

## Completion criteria

- [ ] All approved requirements have direct implementation and acceptance evidence.
- [ ] All material decisions have an explicit owner and resolution.
- [ ] Examples state what they prove and do not claim unsupported target features.
- [ ] Migrations and dependent seam reviews are complete.
- [ ] No previous test result is used as proof of an untested target requirement.
