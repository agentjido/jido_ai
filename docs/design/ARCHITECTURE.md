# Jido AI architecture

> High-level current-state map and target reconciliation guide.
> Review status: Pending approval. Source review: 2026-09-15, `v3-spike`, HEAD `c4e57c8d`.
> The reviewed worktree includes the uncommitted Orchestration rename.
> This document does not certify the complete target requirement set.

## 1. How to read this map

Code is the current baseline. Examples and their tests show specific behavior.
Designs preserve the complete target, including advanced work.

The [design index](README.md) maps the existing folders and owns document
approval. Each seam's alignment file owns detailed evidence and gaps. This
overview explains the connections; it does not create another public API.

Module names below use the `Jido.AI.` prefix unless written in full.

## Selected direction, not yet implemented

[Complete the runtime split](04_ai_execution/design.md#selected-direction-complete-the-runtime-split):
Runtime owns common execution, limits, usage, and output validation/repair.
Reasoning remains one Profile-selected internal dispatcher with method-owned
validated state and diagnostics. ReAct conversion and tokens stay in the
standalone adapter. Shared transformers move to a common execution view and
Profile; callback compatibility is open. No new registry or execution framework
is selected. The current-state map below does not claim this work is complete.

## Data-focused foundation

The [selected direction](00_boundary_invariants/design.md#selected-direction-data-focused-foundation)
places validated data, stable identity, explicit order, and explicit state
changes before process and adapter structure. The proposed private request
boundary uses [batches and receipts](01_ai_values/design.md#proposed-entry-batch-and-receipt-values),
not another conversation store. [Orchestration](07_request_sessions/design.md#proposed-data-boundary)
owns lifetime and ordered commit coordination; core validates and commits.
Detailed adapter, duplicate, and recovery contracts remain proposals.

## Selected conversation commit policy

[Retain evidence; promote only on success](07_request_sessions/design.md#selected-conversation-commit-policy).
The canonical log retains admitted input, consumed steering, and committed
intermediate work. Default model context advances only after successful
settlement. Failure and cancellation do not advance it; unresolved tool
exchanges stay out. Parent Coordinator accepts delegated results once while
the parent request is active. This policy is selected but not fully implemented.

## Selected capability policy

[Required stages are explicit](08_capabilities_policy/design.md#selected-policy-stage-direction).
Shared preparation validates declarations, applies required stages only, and
rejects unavailable stages without an implicit fallback. Profile-bound and
defaults-bound inputs remain distinct behind one internal preparation result.
Detailed stage order still needs core callback review.

## Selected request and attempt policy

[Logical request identity survives retry/resume](07_request_sessions/design.md#selected-request-and-attempt-meanings).
Each restarted or resumed execution gets a new attempt identity, with prior
outcomes retained. Execution, commit, and delivery failures have distinct
meanings. Uncertain effects block automatic retry without evidence, supported
deduplication, or explicit caller authority. Cancellation is not proof that
effects stopped. Data representation remains open.

## Selected content permissions

[Destination-specific permissions](12_observation_diagnostics/design.md#selected-content-permissions)
default off for rich content, reasoning, and diagnostics. Stream permission
does not permit storage. Reasoning permissions are separately trusted.
Diagnostics needs trusted access and explicit content permission. Telemetry
never includes content. Permitted paths still remove credentials and enforce
size limits; native execution data is unchanged.

## Selected runtime resource ownership

[One AI resource owner per AgentServer](06_runtime_signal_integration/design.md#selected-ai-runtime-resource-ownership)
uses core Plugin supervision and explicit worker bindings. Request workers use
the selected Jido Task Supervisor; Coordinator keeps cancellation and commits.
[Activations are Session-scoped](09_skills_resources/design.md#selected-resource-and-activation-ownership),
not request-scoped. Restart survival remains open. MockLLM uses explicit
request options through the same runtime path.

## 2. Package boundary

| Owner | Responsibility |
| --- | --- |
| `jido_ai` | AI authoring, model integration, tools, reasoning, request orchestration, AI policy, and canonical Session/Thread values |
| Core `jido` | Agent values, AgentServer, Plugin contracts, state validation and commit, directives, Agent lifecycle and topology |
| `jido_action` | Actions, Instructions, Flow graphs, and in-memory Exec |
| `jido_signal` | Signal envelope, routing, dispatch, and local bus |
| ReqLLM / LLMDB | Native provider and model contracts |
| Host application | Durable stores, credentials, external services, business policy, and deployment |

AI orchestration uses core commit and lifecycle contracts. It does not replace
AgentServer, introduce a generic job scheduler, or promise durable workflow
execution. A module named `Plugin` can be required integration, not an optional
feature.

Source: [package overview](../../lib/jido_ai.ex),
[authoring lowering](../../lib/jido_ai/authoring.ex),
[shared execution](../../lib/jido_ai/runtime/flow.ex).

## 3. Main values and state owners

| Value or state | Meaning | Owner |
| --- | --- | --- |
| `Profile` | Validated model, tool, method, limit, result, and memory configuration | Authoring, seam 10 |
| `Jido.Session` | Portable interaction value that owns one Thread | Values, seam 01 |
| `Jido.Thread` / `Jido.Thread.Entry` | Ordered interaction log and its entries | Values, seam 01 |
| `Query`, `Turn`, `Output`, `Usage` | AI input, normalized response, output contract, and usage | Values, seam 01 |
| `Request.Handle` / `Request.Stream` | Local access to admitted work and its events | Orchestration, seam 07 |
| `Orchestration.Record` | Validated request map retained in Agent state; pending/completed/failed status | Orchestration, seam 07 |
| `Runtime.State` | Temporary validated execution map, including ReqLLM context | Execution, seam 04 |
| `Reasoning.ReAct.State` / `Token` | Standalone adapter state and resume encoding | Recovery, seam 11 |

Not all runtime values are portable. A Request handle can contain a server
reference. Runtime.State can contain provider values. Neither is another
conversation store. The checkpoint layer selects portable data explicitly.

`Turn` does not execute tools. `Thread.Projection` adapts canonical entries
to AI messages. `Orchestration.Transcript` reads the selected Agent field and
coordinates entry commits. These are different operations on the same
conversation values.

Source: [Session](../../lib/jido_session.ex),
[Thread](../../lib/jido_thread.ex), [Entry](../../lib/jido_thread/entry.ex),
[Profile](../../lib/jido_ai/profile.ex),
[execution state](../../lib/jido_ai/runtime/state.ex),
[projection](../../lib/jido_ai/thread/projection.ex),
[transcript integration](../../lib/jido_ai/orchestration/transcript.ex).

## 4. Request execution and commit

The main authored Agent path has these roles:

```text
Agent + DSL + Profile
        |
        v
Authoring lowers configuration to core Agent routes and Plugins
        |
        v
AgentServer admits a request through AI/core integration
        |
        v
Orchestration coordinates active work and its result
        |
        v
Runtime prepares and executes the reasoning/model/tool Flow
        |
        +--> Model.Transport --> ReqLLM
        |
        +--> Tools.Executor --> Jido.Exec --> Action
        |
        v
Orchestration produces settlement through core Agent APIs
        |
        v
Core validates and commits Agent state; delivery follows its contracts
```

This is an ownership view, not a complete state machine. The exact path depends
on the Profile request mode. Session-mode work has admission and later
settlement; turn-mode work completes within its owning Turn. Standalone ReAct
uses an Agent and the shared runtime rather than a separate model/tool engine.

`Orchestration.Coordinator` keeps worker lifetime, pending completion, recovery,
and ordered commit coordination together. `Runtime` owns the execution steps,
not the final Agent commit. Active-input and delivery helpers do not define
durable queues.

Source: [request API](../../lib/jido_ai/request.ex),
[orchestration API](../../lib/jido_ai/orchestration.ex),
[Coordinator](../../lib/jido_ai/orchestration/coordinator.ex),
[start](../../lib/jido_ai/orchestration/start.ex),
[settle](../../lib/jido_ai/orchestration/settle.ex),
[standalone runner](../../lib/jido_ai/reasoning/react/runner.ex).

## 5. Existing design folders and module families

Folders organize contracts, not one-to-one source namespaces. One public
feature can have a value, an Action adapter, and a Plugin adapter. Its owning
seam defines the feature; seam 06 defines how it connects to core Jido.

| Design seam | Current module families | Boundary |
| --- | --- | --- |
| [00 Boundary](00_boundary_invariants/README.md) | `Jido.AI`, package metadata; cross-seam ownership rules | Package duties, not a runtime subsystem |
| [01 Values](01_ai_values/README.md) | `Jido.Session`, `Jido.Thread.*`, `Query`, `Turn.*`, `Output`, `Usage.*`, `Error.*`, `Thread.Projection` | Values, normalization, and AI projection; no workers |
| [02 Models](02_model_gateway/README.md) | `Models`, `Model.{Transport,Options,Messages,Generate}`, `PromptBuilder`, `Actions.LLM.*` | ReqLLM integration and request preparation |
| [03 Tools](03_tool_bridge/README.md) | `ToolAdapter`, `ToolCatalog`, `ToolSource`, `ToolContext`, `ToolInterceptor`, `ToolResult`, `Tools.Executor`, `Effects.*`, `Actions.ToolCalling.*` | Tool contracts, one execution boundary, effect policy |
| [04 Execution](04_ai_execution/README.md) | `Runtime.{State,Prepare,Run,Flow,ReasonFlow,CallModel,Decide,Continue,NextBatch,ToolsFlow,ToolCycle,ToolAttempt,OutputState}` and execution helpers | Temporary state, progression, limits, retries, and repair |
| [05 Reasoning](05_reasoning_planning/README.md) | `Reasoning.*`, method machines/results, `Actions.Reasoning.*`, `Actions.Planning.*` | Method algorithms and planning semantics, not a generic Flow engine |
| [06 Core integration](06_runtime_signal_integration/README.md) | `Runtime.Plugin.*`, `Orchestration.Plugin.*`, `Signal.*`, route and directive adapters | Core Plugin facets, trusted context, routes, candidate and directive contracts |
| [07 Orchestration](07_request_sessions/README.md) | `Request.*`, `Orchestration.*`, `PendingInputServer`, `Thread.Control.*`, `Thread.Operation` | Live work, input controls, completion, delivery, and commit coordination |
| [08 Capabilities](08_capabilities_policy/README.md) | `Capability`, `ReasoningCapability`, `PluginConfig`, optional `Plugins.*`, `ModelRouter`, `Quota.*`, `Retrieval.Store`, capability Actions | Optional composition and policy; not another Agent model |
| [09 Skills](09_skills_resources/README.md) | `Skill.*`, `Actions.Skill.*` | Discovery, loading, activation, prompts, tools, resources, and trust policy |
| [10 Authoring](10_authoring_definitions/README.md) | `Agent.*`, `DSL.*`, `Profile.*`, `Authoring.*`, `Portable`, `Configuration.*`, `Instructions`, `Control`, input validation helpers | One authoring model, portable definitions, and validated configuration |
| [11 Recovery](11_checkpoints_resume/README.md) | `Runtime.Checkpoint`, `Reasoning.ReAct.{Checkpoint,State,Token}`; orchestration recovery integration | Portable snapshots and standalone resume, not durable storage |
| [12 Observation](12_observation_diagnostics/README.md) | `Observe.*`, `Runtime.{Event,Telemetry}`, `Signal.*`, `Orchestration.Inspection`, request metadata | Safe projections and correlation, not execution ownership |
| [90 Delivery](90_migration_delivery/README.md) | `Test.*`, `TestCase`, `Quality.Checkpoint`, `Mix.Tasks.JidoAi.*`, package metadata | Consumer support, evidence, migration, and release |

Shared entries are deliberate interfaces. For example, seam 08 owns routing
policy while seam 02 owns native model resolution. Seam 03 owns tool policy
while seam 04 applies that policy within execution. Seam 11 owns snapshot
meaning while seam 07 owns recovery process lifetime.

## 6. Physical source layout

```text
lib/
├── jido_ai.ex
├── jido_session.ex              Jido.Session
├── jido_thread.ex               Jido.Thread
├── jido_thread/entry.ex         Jido.Thread.Entry
├── jido_ai/
│   ├── agent/ + dsl/ + profile/ authoring and validation
│   ├── orchestration/          live request ownership
│   ├── runtime/                shared execution
│   ├── thread/                 AI projection and controls
│   ├── model/                  provider integration
│   ├── tools/                  shared executor
│   ├── reasoning/              methods and standalone ReAct adapter
│   ├── actions/ + plugins/     callable and core integration adapters
│   ├── skill/                  optional resources and skills
│   └── ...                     values, policy, observation, and support
└── mix/tasks/                  package development tools
```

This is a selected tree, not an exhaustive file list. Tool modules still span
root files and `tools/`. Standalone ReAct adapter code still shares the method
directory. These are visible organization questions, not proof of duplicate
execution engines.

## 7. Current state versus retained target

These are review findings, not approvals to change runtime behavior.

| Seam | Current fact | Alignment question or retained advanced work |
| --- | --- | --- |
| 00 | Uses core Agent, Plugin, Flow, and Exec; metadata still says version 2.3.0 | Complete ownership wording and release requirements |
| 01 | Session/Thread replace the old Context store; Turn execution was removed | Reconcile old Context signatures with canonical values; decide remaining codec and error guarantees |
| 02 | Native ReqLLM/LLMDB values; transport/options/messages have separate owners | ModelRef and fully provider-neutral public wrappers remain proposals in tension with the current contract; named transform stages need review |
| 03 | Shared executor, effects, interception, and inert source declarations exist | Dynamic discovery, catalog snapshots, approvals, and replay-safe effects need explicit evidence and scope; declarations do not prove execution |
| 04 | Internal validated Runtime.State and shared Flows exist | Public portable Execution values differ from current state; ToolAttempt still sleeps for bounded retry delay |
| 05 | ReAct, CoT, CoD, AoT, ToT, GoT, TRM, and Adaptive remain | Trusted custom-method registration, common method results, and portable executable Plan proposals remain |
| 06 | Runtime and Orchestration Plugins use Agent and AgentServer facets | Revalidate the full route, purity, delivery, and correlation matrices; old Thread compile blockers are stale |
| 07 | Orchestration owns the live API; Session is a value | Replace old live-Session names in detailed documents; specify linked delegation and cancellation policies |
| 08 | Capabilities use Profile-bound and defaults-bound adapters | Decide whether one contribution contract is needed; keep routing, retrieval, quota, and state-version proposals |
| 09 | Skill discovery/resources exist; Registry supports lazy startup | Explicit resource ownership, dependency/collision rules, and atomic resource restoration remain under review |
| 10 | Agent + DSL + Profile, portable definitions, and authoring tests exist | Reconcile illustrative target structs with actual schema; distinguish declaration parity from executable feature support |
| 11 | Shared checkpoint boundary with ReAct encoding; resume retains its adapter run identity | New-run lineage, all-resource atomic restore, deduplication, and uncertain-effect decisions remain target work |
| 12 | Sanitization, typed Signals, telemetry, and bounded inspection exist | A common versioned event contract, stricter rich-content policy, and cross-projection conformance remain under review |
| 90 | Execution CLI removed; install/skill/quality Mix tasks remain; V3 beta dependencies used | Reconcile CLI requirements explicitly; complete release version, migration, performance, security, and operational evidence |

Source checks for specific differences:
[retry delay](../../lib/jido_ai/runtime/tool_attempt.ex),
[model contracts](../../lib/jido_ai/models.ex),
[request transforms](../../lib/jido_ai/runtime/request_transform.ex),
[capability inputs](../../lib/jido_ai/capability.ex),
[registry startup](../../lib/jido_ai/skill/registry.ex),
[resume adapter](../../lib/jido_ai/reasoning/react/checkpoint.ex),
[package metadata](../../mix.exs).

A gap can mean missing evidence, a deliberate current limit, or a future target.
None of these meanings automatically requires feature removal.

## 8. Delegation and topology

Current `ToolSource` accepts inert `:subagent` and `:handoff` declarations.
This is authoring data, not proof of an executable delegation protocol.
Callable reasoning also does not by itself prove child/peer delegation.

The proposed ownership split is:

| Concern | Design owner |
| --- | --- |
| Target Agent identity, child lifecycle, peer placement, topology | Core Jido; AI integration reviewed in 06 |
| Linked request identity, delivery, cancellation, and parent commit policy | 07 |
| Model-facing delegation tool and input/output adaptation | 03 |
| Context selection and portable interaction values | 01, consumed by 07 |
| Resume, late results, duplicate effects, uncertain outcomes | 11 with 07 |
| Request lineage and tool/delegation observation | 12 |

The target needs explicit decisions for context transfer, fan-out and result
collection, depth and budget limits, cancellation propagation, target failure,
handoff authority, and late-result handling. A peer can perform delegated work
without becoming a supervised child. Cancelling that work must not be assumed
to stop the peer.

These are retained design questions. No new delegation module, process owner,
or transport API is claimed by this document.

Source: [source declarations](../../lib/jido_ai/tool_source.ex),
[callable reasoning](../../lib/jido_ai/actions/reasoning/run_strategy.ex).

## 9. Example and test entry points

These links identify evidence to review. They are not blanket conformance
claims for all target requirements.

| Boundary | Example | Direct test entry point |
| --- | --- | --- |
| Authoring | [Authoring forms](../../examples/01_authoring/01_01_authoring_formats/README.md) | [Authoring suite](../../test/authoring/agents/authoring_test.exs) |
| Model/tool cycle | [Dependent tool rounds](../../examples/01_authoring/01_02_tool_flow/README.md) | [MockLLM multi-round test](../../test/examples/01_authoring/01_02_tool_flow/multi_round_test.exs) |
| Canonical values | [Thread and Session](../../examples/02_requests/02_27_thread_session_values/README.md) | [Value tests](../../test/jido_ai/thread_value_test.exs) |
| Requests and observation | [Request inspection](../../examples/02_requests/02_22_request_inspection/README.md) | [Inspection tests](../../test/jido_ai/orchestration/inspection_test.exs) |
| Execution state | [AI runtime](../../examples/01_authoring/01_07_ai_runtime/README.md) | [State contract](../../test/jido_ai/runtime/state_test.exs) |
| Tool boundary | [Tool examples](../../examples/03_tools/README.md) | [Executor boundary](../../test/jido_ai/tools/executor_boundary_test.exs) |
| Core integration | [AI extension](../../examples/01_authoring/01_06_ai_extension/README.md) | [Plugin facets](../../test/jido_ai/plugin_facets_test.exs) |
| Reasoning | [Method examples](../../examples/09_reasoning/README.md) | [Callable profiles](../../test/authoring/agents/callable_profiles_test.exs) |
| Planning | [Planning](../../examples/08_planning/08_01_planning/README.md) | [Planning example test](../../test/examples/08_planning/08_01_planning/08_01_planning_test.exs) |
| Capabilities | [Composition](../../examples/16_capabilities/README.md) | [Routing and policy](../../test/examples/16_capabilities/16_03_routing_policy/16_03_routing_policy_test.exs) |
| Skills | [Skills](../../examples/18_skills/README.md) | [Skill authoring](../../test/examples/18_skills/18_02_skill_authoring/18_02_skill_authoring_test.exs) |
| Recovery | [Checkpoint resume](../../examples/14_resume/14_03_checkpoint_resume/README.md) | [Shared checkpoint boundary](../../test/jido_ai/runtime/checkpoint_test.exs) |
| Safe projections | [Stream usage](../../examples/02_requests/02_24_stream_usage/README.md) | [Observation tests](../../test/jido_ai/observe_test.exs) |

The preceding code-change verification reported 2,809 passing tests and one
existing exclusion, including authoring and MockLLM examples. This
documentation task does not rerun that suite. The earlier live Haiku result
proves one dependent-tool example, not all providers or all examples.

## 10. Reconciliation sequence

1. Reconcile the value and ownership contracts in 00/01, including the meaning
   of Session versus Orchestration and temporary execution state.
2. Review model and tool contracts in 02/03 without discarding advanced sources
   or introducing wrappers solely to satisfy old pseudocode.
3. Align shared execution and all methods in 04/05.
4. Review integration and request behavior in 06/07, including delegation.
5. Align optional capabilities and resources in 08/09.
6. Reconcile complete authoring and recovery requirements in 10/11.
7. Complete observation and delivery evidence in 12/90.

For every requirement, record current code, example/test evidence, the exact
difference, the decision owner, and the acceptance evidence still needed.
Preserve existing requirement IDs. The seam documents now include current
ownership and gap reviews, with acceptance rows rebuilt from the target
requirements. Incomplete evidence stays explicit; this is not a claim that all
target requirements pass. Proposed delegation requirements live in seam 07
and depend on the tool, core integration, recovery, and observation seams.
