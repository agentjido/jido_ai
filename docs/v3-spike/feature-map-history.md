# Historical feature port map

Archived on 2026-09-15. This is a migration record, not the current feature set.
Use the [current feature map](feature-map.md). Source paths, counts, and pending
work below describe earlier checkpoints and can be obsolete.

Status: draft destination map based on `jido_ai@fc5bc143`. No row is implemented
or verified against v3. Example IDs refer to [the proposed catalog](examples.md).

Paths below are relative to the `jido_ai` repository unless stated otherwise.
The map covers public feature families and the main internal contracts they
depend on. Before implementation, link each row to its exact acceptance tests.
The [commit and PR audit](history-audit.md) adds the detailed behavior changes
after v2.0.0. Its evidence is required alongside this family-level map.
The [historical public API map](public-api-map-history.md) adds declared functions, generated
wrapper differences and API acceptance cases. Its source inventory covers all
175 production source files. Actual v3 test links remain pending.

## Agent, runtime, and reasoning

| Current feature and source | Proposed v3 destination | Examples |
| --- | --- | --- |
| `Agent`; seven convenience agents under `agents/strategies` | AI DSL profiles plus ordinary Agent routes; optional thin wrappers for old entry points | 01, 09–11, 16 |
| ReAct Strategy and worker Strategy | Bounded ReAct Flow; explicit session runtime where several Turns are needed; remove dependency on core Strategy | 03–06 |
| CoD and CoT strategies | Separate reasoning recipes using shared generation/validation operations; preserve prompts, parsing, output, and termination rules | 09 |
| AoT machine, Strategy, and structured Result | Preserve algorithm state and result contract; move execution to bounded Flow steps | 09 |
| ToT machine/Result and GoT machine | Explicit frontier/graph data with bounded expansion and evaluation; use Map and reductions without changing traversal rules | 10 |
| TRM reasoning, supervision, ACT, helpers, machine | Retain refinement and halt algorithms; express execution rounds as a bounded Flow | 11 |
| Adaptive Strategy | Explicit method selection and fallback; invoke the same method implementations used by direct calls | 11 |
| `Actions.Reasoning.RunStrategy` and runner agents | Callable reasoning Flow/Action interface; use a child Agent only when lifecycle isolation is required | 09–11, 17 |
| `Request` including `await_many`, `Request.Stream`, generated ask/await/ask_sync/ask_stream | AI request service over public core APIs; portable request records; explicit admission and completion; preserve which helpers each macro actually supplies | 05 |
| `PendingInputServer`, steer/inject, expected request correlation | One bounded input owner; preserve ReAct busy/idle rules, queued versus consumed input, atomic closure and cleanup | 05; H07 / HIST-21 |
| Standalone ReAct run/stream/start/continue/collect/cancel and tokens | Retain standalone surface; run shared operations and keep a separate versioned AI checkpoint contract | 14 |
| `Checkpoint`, worker/stream cleanup, restore callbacks | Portable state at every commit; transient resource reconstruction; explicit old-state conversion and interrupted-request policy | 06, 14 |

The current ReAct runner already supplies a useful model/tool boundary and
deterministic events. Reuse that knowledge, but do not wrap its complete task
scheduler in one Action and call the Flow port finished. Conversely, do not
rewrite pure parsers and search algorithms only to change their names.

## Model, tools, context, and data

| Current feature and source | Proposed v3 destination | Examples |
| --- | --- | --- |
| `Jido.AI` text/object/stream/ask facade; `ModelAliases`; ReqLLM options | Shared provider boundary; keep aliases, explicit model forms, defaults, provider options, and structured errors | 01–02, 13 |
| ReAct Responses continuation and optional WebSocket reuse | Preserve effective-model routing; scope continuation and session reuse to provider/endpoint/runtime identity; retain caller-owned session lifetime and runner cleanup | 01, 04–05, 13; H14 / HIST-15 |
| `Actions.LLM.Chat`, `Complete`, `GenerateObject`, `Embed` | Reusable Actions callable through `Jido.Exec`; adapt context and complete-state assembly at Agent routes | 01–02, 07 |
| `Output`: Zoi/imported JSON validation, parsing, repair callbacks and metadata | Shared validation operations and bounded repair Flow; keep output behavior across reasoning methods | 02, 09–11 |
| `Query`: content parts and file references | Preserve multimodal input and provider attachment projection; validate transient versus stored data | 02, 06, 12 |
| `Turn`, `ToolAdapter`, `ToolSelection`; tool list/execute/call-with-tools Actions | Trusted tool catalog; normalized input and result envelopes; same tool execution primitive for direct and Agent use | 03–04 |
| `ToolInterceptor` before/after callbacks | AI tool-operation boundary; preserve identity restrictions, error handling, retry placement, interrupt result, and policy filtering | 03, 15 |
| Tool timeouts, retries, concurrent execution, call ordering | Exec owns execution and worker cleanup; AI owns retry policy and ordered model transcript | 03–04 |
| `Effects.Policy`, `Effects.Applier`, allowed StateOps | Keep permission intersection/filtering; replace state operations with explicit domain data and state assembly; retain typed post-commit directives | 03–04, 13 |
| Dynamic tool register/unregister/list/has-tool; system prompt changes | Validated command Actions and portable catalog IDs/configuration; define effect on active requests | 03, 16 |
| Request transformer and per-request model/tool/context overrides | Shared per-call preparation with final authorization checks and fresh runtime state input | 03, 13 |
| `Context`, Thread projection, `PromptBuilder`, summaries/compaction | Agent-owned portable history and pure projection helpers; Flow-local request context; no `Jido.Thread.Agent` integration | 06 |
| `Usage`, `Observe`, sanitized errors, typed Signals, runtime Events | Retain AI event meaning; correlate with core Turn/commit/directive observation; preserve redaction and bounded payloads; distinguish chunk, call and terminal usage rules | 05, 13, 18 |
| `Signal.Definition` and ten typed AI Signal constructors | Static core Signal schemas with explicit input/error/metadata compatibility; fixed type and validated data; retire duplicate envelope/validation code after parity checks | 05, 13, 18; HIST-20 |

Tool output data and Agent candidate state are different contracts. A tool can
return `%{stock: 3}` without replacing the Agent with that map. A terminal
assembler decides which domain fields change, then validates the complete
state. With parallel tools, define a deterministic reducer or reject conflicting
state changes. Do not use implicit last-writer-wins behavior.

The old tool context uses `context[:state]`; core v3 supplies
`context.agent_state`. Decide whether the AI adapter provides the old read-only
alias temporarily. The value must come from the current validated execution
state and must not be replaced by untrusted request data.

## Plugins, skills, and application support

| Current feature and source | Proposed v3 destination | Examples |
| --- | --- | --- |
| `PluginStack`; Chat and Planning Plugins | Capability configuration plus explicit routes/Flows; use v3 Plugin callbacks only for their defined preparation/state/runtime roles | 08, 16 |
| Seven `Plugins.Reasoning.*` modules | Named callable reasoning capabilities; same implementations as direct reasoning | 09–11, 16 |
| `Plugins.ModelRouting` | Resolve the model in explicit preparation; preserve exact/wildcard precedence and explicit model overrides | 01, 13 |
| `Plugins.Policy`, Validation, error normalization | Explicit request validation and enforce/monitor policy; reject through a structured result rather than relying on Signal type rewrites | 13 |
| Retrieval Plugin, memory Actions, `Retrieval.Store` | Explicit retrieval Flow and state/runtime store ownership; keep namespace, enrichment, and CRUD behavior | 07 |
| Quota Plugin, get/reset Actions, `Quota.Store` | Admission checks and owned accounting; preserve usage fallback rules and scope; test failures, cancellation, and duplicate accounting | 13 |
| Planning Plan/Decompose/Prioritize; reasoning Analyze/Infer/Explain | Reusable typed Actions or small Flows; preserve standalone use and schemas | 08–11 |
| `Plugins.TaskSupervisor` | Replace old mount/checkpoint plumbing with supported Exec supervisor routing or an owned Plugin runtime | 04–05 |
| Skill Loader/Spec/Registry/Discovery/Diagnostics | Preserve trusted catalog, lazy activation, strict/lenient validation, bounds, registry lifecycle, and session isolation | 12 |
| Skill activation/prompt and LoadSkill | Keep compact discovery and lazy body loading; preserve active instructions through compaction | 06, 12 |
| ResourcePolicy/Resources/ResourceProvider and LoadResource | Preserve bounded listings and reads, opaque provider IDs, path rules, runtime context, binary policy, and attachments | 12 |
| Quality checkpoint and quality Mix task | Keep development checks, story-to-commit coverage, command timing, and failure reports; these are build checks, not model quality scores | 18 |
| CLI adapters, `mix jido_ai`, installer, skill Mix task | Project the new request/result/event contracts; generated code must use valid v3 authoring | 18 |
| `Jido.AI.Test`, `TestCase`, `ReActScript`, smoke and integration suites | Public script syntax over the unified mock server; explicit test/request progress, history isolation and strict diagnostics; canonical assertions plus actual tool output | 03, 05, 18; HIST-22 |
| Weather strategy suite; browser, task, triage, and release-note demos | Preserve representative application behavior; port core examples first and track external package dependencies separately | 18 |

## Important design risks

**Plugin state ownership.** Core protects a Plugin's state key from Action
writes. Put conversation and request domain data in declared Agent fields, or
define an owned Plugin update protocol. Do not assume a Flow can write both.
Current v3 Plugins use `prepare`, `admit`, `state_spec`, `update_state`, and
`dispatch`, plus directive validation, `prepare_dispatch`, and `await_ready`.
The pending core design uses different callbacks. Recheck the implemented
contract before each runtime port.

**Accounting after failed work.** A model call can incur cost even if its Agent
Turn does not commit. Quota must not count only successful state commits.
Choose a usage ledger or correlated accounting protocol and test late and
duplicate records. Durable exactly-once accounting would be a new guarantee.

**Side effects and retry.** State preservation does not roll back network calls,
tools, or resource reads. Flow timeout and cancellation do not establish that
an external service cancelled the request. Prove local cleanup and record any
unknown external outcome.

**Restore.** Current Agent checkpoints fail interrupted streams and reset ReAct
workers. Standalone AI tokens support a different resume path. Core Flow Codec
serializes definitions; Exec execution state does not supply durable resume.
Keep these three contracts distinct. Old Agent checkpoints need a named data
conversion or an explicit rejection policy.

**Recent features.** The branch includes the eight latest skill commits, including
runtime resource providers and binary attachments. A port based only on the old
package overview or the prior local checkout would omit current behavior.

The [skill history review](history-reviews/16-skill-discovery-and-lazy-loading.md)
links the first two commits to their user reports and final contract. A rendered
index alone does not bind a loader. Retain one selected catalog, stable session
identity and actual instruction content through compaction. Registry bookkeeping,
catalog removal and conversation state have separate migration rules.

The [lifecycle/conformance review](history-reviews/18-skill-lifecycle-and-conformance.md)
adds two more commits. Retain real instruction content and valid transcript
pairing through compaction. Track session cleanup separately from activation
reuse. Preserve document/file validation, namespaced file metadata, accumulated
diagnostics and explicit-file CLI checks in the package migration.

**Core proposals.** Stable Ref addressing, isolated Plugin reads/prepared input,
definition revision enforcement, and stronger runtime reconstruction are not
assumed prerequisites for basic AI examples. If a later profile needs one,
record that dependency and its acceptance case. Do not claim an unimplemented
core feature through an AI wrapper.

## Starting evidence

- [Current package surface](../../guides/user/package_overview.md)
- [Agent implementation](../../lib/jido_ai/agent/definition.ex)
- [ReAct Strategy](../../lib/jido_ai/reasoning/react/strategy.ex)
- [ReAct runner](../../lib/jido_ai/operations/react_runner.ex)
- [Request lifecycle](../../guides/user/request_lifecycle_and_concurrency.md)
- [Standalone runtime](../../guides/user/standalone_react_runtime.md)
- [Skills and resources](../../guides/developer/skills_system.md)
- [Core Agent API](../../../jido/lib/jido/agent.ex)
- [Core Plugin contract](../../../jido/guides/plugins.md)
- [Core LLM examples](../../../jido/examples/03_llm/README.md)
- [Exec execution contract](../../../jido_action/lib/jido_exec.ex)

## Native ToT progress

The [09_04 example](../../examples/09_reasoning/09_04_tot/README.md) supplies partial
evidence for the ToT row: three traversal modes, bounded candidate expansion,
ranked paths, parser repair, per-phase tool rounds and common request control.
The [09_05 example](../../examples/09_reasoning/09_05_tot_api/README.md) adds the public
facade, retained namespace getters and Strategy inspection mapping. The exact
PR 347 alias/state workflow, raw retry results, callback failures and ordinary
turns also have execution evidence. Active tree inspection, capability and CLI
paths, typed results, runtime state overrides and the remaining history cases
still need evidence. The following checkpoint adds native GoT evidence.

## Native GoT progress

The [09_06 example](../../examples/09_reasoning/09_06_got/README.md) runs generation,
connection discovery and synthesis through the shared Flow. It retains graph
metadata and proves traversal with actual model context and separate diamond,
disconnected-node and cycle cases. The 41 retained Machine tests pass on v3.
Public GoT APIs, general branching, aggregation across several leaves and
distinct voting/weighted behavior remain required. The profile records the
baseline gaps; setting retention is not algorithm acceptance.

The [09_07 example](../../examples/09_reasoning/09_07_got_api/README.md) adds the public
GoT wrapper and namespace/Strategy inspection mapping. It verifies separate
retained graphs, raw failure causes, a search beyond ten model calls and bounded
path inspection through a parent cycle. The broader graph and package gates
above remain required.

## Native TRM progress

The [09_08 example](../../examples/09_reasoning/09_08_trm/README.md) executes the existing
reason-supervise-improve method through the common Flow. It verifies all five
cycles, highest-score selection, zero-score fallback, ACT threshold/convergence,
step precedence, phase failure, prior usage, cancellation and owner cleanup.
The same definition works through DSL, data, Builder and source JSON. There
are 24 native integration cases and 204 retained support-module tests.

The public TRMAgent and namespace/Strategy APIs, CLI/capability paths, runtime
state and input conversion, complete media/output/provider cases and durable
recovery remain required. This is partial evidence for feature family 11.

The [09_09 example](../../examples/09_reasoning/09_09_trm_api/README.md) adds 12 public
TRM cases. Reason/sync/await, declared defaults, all five cycles, retained review
inspection, provider options, streams, busy rejection and cancellation use the
common Agent. The old Strategy now supplies deprecated getters and prompts
only. Active phase inspection, custom hooks, old input/state conversion, runtime
overrides, CLI/capability paths and durable recovery remain open.

## Native Adaptive progress

The [09_10 example](../../examples/09_reasoning/09_10_adaptive/README.md) runs CoD,
CoT, ReAct, AoT, ToT, GoT and TRM through automatic selection and the common
Flow. Its 28 cases cover method selection, overrides, invalid configuration,
new-request selection, selected tools, typed output and repair, ordinary
Actions, errors, limits, observation and interruption. Sixteen transferred
analysis tests preserve the original keyword/complexity rules.

Public AdaptiveAgent and inspection APIs, legacy failure strings, custom
hooks, input/state conversion, runtime overrides, active inspection, complete
provider/media and CLI/capability paths, and durable recovery remain required.
Native steering and rich selection are rejected. This is partial feature
evidence; selected-method gaps and package gates remain open.

## Public Adaptive checkpoint

The [09_11 public examples](../../examples/09_reasoning/09_11_adaptive_api/README.md)
execute all seven selected methods. They add declared option and default model
checks, a complete 15-call TRM request, explicit budgets, before/after tool
callbacks, typed repair, raw provider failures, printable public fields,
retained selection and cancellation with a different later choice. The common
Agent method selector and public wrapper use the same profile and Session.
Active state, legacy conversion, CLI/capability paths and the full package gates
remain open. No complete feature-family or history status is inferred here.

## Selected method control refinement

The [09_12 cases](../../examples/09_reasoning/09_12_method_controls/README.md) prove
selected default counts, explicit Agent/request overrides, full-batch tool limits
and typed repair after a per-request output change. Actual model and Action
counts verify the boundaries. The initial larger ReAct budget is fixed. Active
inspection, state conversion, capability/CLI paths and package gates stay open.

## Active Adaptive selection

The [09_13 cases](../../examples/09_reasoning/09_13_active_selection/README.md) prove
active selection before provider work, input-control order, one-use progress
grants, host policy rejection, preservation of unrelated domain changes,
cancellation and owner recovery. No selection is read from untrusted Signal
data. Runtime state stays with the existing Session and core Turn owners.

## Callable reasoning evidence: 2026-09-07

[09_14](../../examples/09_reasoning/09_14_callable_reasoning/README.md) exercises all seven
RunStrategy methods through direct Exec and an ordinary Agent. It retains AoT/ToT
results, shared controls, caller defaults, failure usage, cancellation and cleanup.
One dynamic profile factory replaces seven unused internal runner wrappers and
the implicit global Jido runtime. Capability declarations, nested AI tool budget
aggregation, complete options/metadata and root package gates remain pending.

## Reasoning capability checkpoint — 2026-09-07

[16_01](../../examples/16_capabilities/16_01_reasoning/README.md) adds all seven
reasoning Plugin entry points. Seventeen integration cases prove fixed method
identity, owned defaults, actual model requests, explicit parameter precedence,
ordinary and AI route composition, full candidate state, provider failure and
timeout cleanup. Twenty-one focused native Plugin cases replace obsolete v2
callback tests. Empty restored Plugin state now keeps its configured defaults.
This is partial capability parity. Chat/Planning and routing/policy/retrieval/
quota, complete PluginStack conversion, CLI and durable recovery remain open.

## Planning checkpoint — 2026-09-07

[08_01](../../examples/08_planning/08_01_planning/README.md) now ports Plan, Decompose,
Prioritize and `Jido.AI.Plugins.Planning`. Eighteen integration cases prove direct,
Exec and Agent results, original prompt content, defaults and explicit values,
model precedence, parser fallback and score forms, depth limits, multi-block
text, token counts, invalid inputs, headers, failure, cancellation and timeout.
Twelve native schema/catalog/Plugin cases replace old callback and provider-stub
checks. The shared candidate helper also serves reasoning capabilities.

The full AI acceptance suite passes 678 cases. This does not close validated
plan execution and repair, other capabilities, skills/resources, CLI, durable
recovery, or the package and release gates.

## Chat family implementation: 2026-09-07

[Example 16_02](../../examples/16_capabilities/16_02_chat/README.md) supplies 32 passing
integration cases for Chat, Complete, GenerateObject, Embed, CallWithTools,
ExecuteTool and ListTools. The Chat Plugin uses core owned state and explicit
routes. Shared callback validation uses core Exec by default. Alias lookup,
Flow tools, two tool rounds, continuation metadata, nested usage, input errors,
provider failure, timeout and cancellation have actual execution evidence.
Model options and default preparation now share code with Planning. Root
package, consumer, CLI, dynamic catalog and durable recovery gates remain open.

## ModelRouting and Policy: 2026-09-07

[Example 16_03](../../examples/16_capabilities/16_03_routing_policy/README.md) ports both
Plugins to core state and preparation. Twenty-one integration cases prove
actual Chat/native model selection, explicit overrides, wildcard precedence,
committed configuration, enforce/monitor behavior and observation normalization.
Native custom routes check their declared query binding. Blocked requests return
the planned structured error, make no provider call and commit no state.

The common route-binding helper serves Runtime, Session and Policy. Shared
option checks serve all ported capability families. Known Action keys now give
the canonical atom key precedence over its string form. The mock supports
forced structured-output tools through both ordinary and streamed responses.
Default PluginStack insertion, Retrieval/Quota, all public override forms,
provider switching, state conversion and root release gates remain required.

## Retrieval ownership and execution: 2026-09-07

[Example 07_01](../../examples/07_retrieval/07_01_memory/README.md) ports the Store,
three Actions and Retrieval Plugin. One supervised Store owns memory shared
across Agents. Core live admission performs enrichment; pure preparation binds
capability defaults. Explicit routes use the shared complete-state helper.
Actual model calls prove Chat/native enrichment and a real RecallMemory tool.

The example records namespace, ranking, key conversion, limits, opt-out,
concurrency, store lifetime and failure-after-write behavior. A checkpoint
contains Plugin configuration and retained results, not the external store.
Old-data import, durable backup/restore, full source formats, deployment and root
consumer checks remain required. Quota and default PluginStack remain open.

## Quota feature evidence: 2026-09-07

[13_01](../../examples/13_policy/13_01_quota/README.md) ports the Quota Plugin, Store
and two Actions. Twenty-eight cases cover native and DSL use, concurrent
admission, repair/tool/nested calls, explicit scopes/stores, status/reset, window
replacement, failed output, stream disconnect/cancellation and v2 row import.
The ledger is external to the Agent commit. Known partial tokens and unknown
calls remain visible. Duplicate call reports cannot add cost twice in one
window. Fifteen retained root tests cover counters and Action/Plugin contracts.

Normalized zero usage remains unknown when ReqLLM has removed source provenance.
Imported aggregate counters are explicit unattributed records. Window-local
accounting does not prove durable replay or a hard provider-spend cap. Raw
RunStrategy model-tool schema export, full source-format parity, deployment
conversion, default PluginStack, root package and consumer gates remain open.

## Default Plugin composition: 2026-09-07

[16_04](../../examples/16_capabilities/16_04_plugin_stack/README.md) adds Policy and
ModelRouting to public AI macros and the private callable reasoning factory.
Optional Retrieval/Quota map and keyword options work through core declarations.
All capability namespaces can coexist; generated routes use a separate domain
result field. The Session Plugin replaces the old TaskSupervisor role.

Eighteen cases cover configuration, order, scope, real requests, ordinary routes,
route attributes, first-use loading, JSON/data/Builder parity and work cleanup.
Three retained root tests check the public list helper. Core Memory/Thread
map overrides still require explicit state conversion. Default insertion does
not close all facade, catalog, skill/resource, recovery or root package gates.

## Request identity and model options: 2026-09-07

[02_18](../../examples/02_requests/02_18_admission/README.md) adds nine rejection cases
for declared method identity, custom routes, raw errors, busy admission and
duplicate isolation. [02_19](../../examples/02_requests/02_19_model_options/README.md)
adds ten cases for request model forms, native/public binding, model routing,
option conversion, SSE labels/headers and real HTTP callbacks. The common mock
now supports buffered Responses tool rounds and typed objects.

Both slices use existing core and shared AI operations. The profiles identify
the remaining live-upgrade, provider, transport, complete API and recovery gaps.
Root dependencies and all package/consumer release gates remain open.

## Failed call metadata and Adaptive prompts: 2026-09-07

[02_20](../../examples/02_requests/02_20_call_counts/README.md) retains known started
model-operation counts after failure or cancellation. HTTP attempts and Quota
charges remain separate. Recovery preserves committed data and leaves an
uncommitted count unknown. Real provider, tool and repair work proves these
boundaries; duplicate observations cannot change a completed record.

[09_15](../../examples/09_reasoning/09_15_prompt_policy/README.md) resolves the shared
ReAct default after Adaptive selection. Public empty prompt values use their
default. Native empty instructions keep their current meaning. DSL, data,
Builder, trusted source JSON, direct Flow and ordinary Turn agree. The change
uses the current profile and lowerer without an additional DSL term.

Continue with the remaining public and runtime APIs, dynamic tools/prompts,
raw RunStrategy tool-schema export, skills/resources, state conversion and
recovery. Root dependency, full package, consumer, minimum-runtime, migration
and rollback checks remain required.

## Raw reasoning tool port: 2026-09-07

[09_16](../../examples/09_reasoning/09_16_reasoning_tool/README.md) closes the raw
RunStrategy model-tool schema gap. All seven methods execute through the
existing Action, core Exec and private Agent/Session. Native and public Agent
authoring work; DSL/data/Builder/source JSON agree. Shared Quota, cancellation,
provider errors and result envelopes survive the nested call.

The refinement uses Zoi's existing traversal for JSON export. Generic atom
fields export as strings; the original direct Action schema remains intact.
Model strings resolve only to existing atoms before ordinary validation.
Unknown names cannot allocate atoms. Open objects, strict export and defaults
keep their current behavior. No additional DSL term or executor is introduced.

Continue with dynamic tools and prompts, remaining facade and worker APIs,
skills/resources, old state conversion and recovery. Root dependencies, full
package validation, fresh consumers, supported runtime versions, migration
and rollback remain open.

## Dynamic configuration and public facade: 2026-09-07

[03_01](../../examples/03_tools/03_01_dynamic_catalog/README.md) ports direct and
live tool/prompt changes through portable `jido_ai_config` state owned by the
existing Runtime Plugin. One validated catalog supplies provider schemas and
lookup. Core configuration directives commit live changes. Ordinary Actions
cannot forge the protected key. An active request keeps its admitted catalog
and prompt; later requests use the committed update.

The existing DSL needs no new block. The lowerer supplies the configuration
routes, and native profiles can be selected explicitly. Direct Agent APIs
retain their return shapes. The actual `Jido.AI` facade now compiles from
`shared/facade.ex`; generation delegates remain shared with other callers.
The profile records the new configuration/history view and the Action
migration pattern. No private v2 Strategy state is retained.

Keep the remaining public option/metadata and active-context conversion,
standalone/worker, skill/resource and durable recovery requirements. Complete
root dependencies, full package, consumer, runtime-floor, migration and
rollback gates before treating the package as migrated.

## Public context and history refinement: 2026-09-07

[02_21](../../examples/02_requests/02_21_context_views/README.md) adds nine integration
cases for the compiled public context helpers. Committed history retains
thinking, timestamps, tool IDs, reasoning details and references through reads
and real model requests. String-keyed entries use the same conversion. Invalid
roles, tool calls and live values cannot commit through the replacement helper.

A real host Action changes history while a provider call is held. The active
call uses its admitted history. Its completion appends to the new committed
history, and the next request uses that history. Plain Agents and profiles
without history retain an absent view; a neutral definition no longer crashes.
Portable v3 reconstruction retains entries and fails pending work without replay.

The shared Context now uses its existing entry conversion for message import;
the duplicate converter was removed. History replacement uses ReqLLM's message
schema and the core Agent update path. New assistant and tool entries retain
request references. No DSL term, generated route, runtime owner or mock was added.

This is an explicit mapping from the old private `run_context` helpers to
committed domain history. Use Session steering/injection for active input.
Full legacy configuration views, old-state conversion, skill activation and
compaction, standalone/workers, durable recovery, root dependency/package,
consumer, minimum-runtime, migration and rollback checks remain required.

## Standalone authoring and token foundation: 2026-09-07

[14_01](../../examples/14_resume/14_01_standalone_authoring/README.md) starts the
standalone port with 12 integration cases. An existing ReAct Config lowers
through the same Profile, ToolCatalog, Agent and Flow path. Tests execute real
aliased tools, state effects, request transforms, typed repair, streaming,
limits and cancellation. Provider options and callbacks remain in live context.
Builder and Codec forms run the same definition. Config provider tool schemas
now retain public aliases, including two names for one Action.

The internal stream owner must supply explicit native request-time and total
tool-call limits; the old Config has neither field. This step does not change
the old public Runner's default limits or claim that its replacement is complete.
The next runtime step must preserve long tools and the legacy iteration result.

The actual Token and deprecated Event modules now compile from shared source.
Valid `rt2` data retains signing, expiry, fingerprint, compression and
cancellation semantics. Issuance and decoding reject live state, and decoding
checks request/run identity against the saved State. A different process can
restore valid data without any model request. This is not fresh-VM resume.

Core Exec's paused Execution is a live value with guards and references. It
must not be serialized as a token. The pending public run/stream/start/continue/
collect adapter must rebuild the common Flow from AI state. After-model,
after-tools and terminal checkpoints, pending tool recovery, sequence/identity,
queue ownership, trace filters, redaction and cycle handling remain required.
The current examples execute the lowerer's native Agent, not the old Runner.

Full standalone Actions/workers, skills/resources, legacy state conversion,
durable recovery, root dependency/package, consumer, runtime-floor, migration
and rollback checks remain open. No second executor or mock was added.


## Standalone runtime progress: 2026-09-07

[14_02](../../examples/14_resume/14_02_standalone_runtime/README.md) adds 18 integration
cases through the actual public ReAct API. The adapter owns a private v3 Agent
and uses the shared Session/Flow for all model and tool work. The old private
model/tool loop is removed. Lazy start, run identity, real tools, state effects,
typed repair, usage, terminal tokens and stream ownership have focused evidence.

Terminal continuation and cancellation-token paths work without model replay.
An untouched initial token starts through the same native runtime. The optional
State termination reason preserves iteration-limit meaning. Failed and cancelled
collections retain terminal usage. The focused run passed 41 checks.

Intermediate model/tool checkpoints are not yet emitted. Progressed state, query
append on resume and external queue binding are refused before provider work.
Their full port remains required. The profile records finite native default
limits and explicit overrides, remaining trace/redaction/cycle/provider behavior,
and the difference between token data and durable Agent recovery. Standalone
Actions, workers, skills/resources, state migration and the root package gates
remain open. Root Mix files still select v2. All history statuses remain pending.


## Native checkpoint resume: 2026-09-07

[14_03](../../examples/14_resume/14_03_checkpoint_resume/README.md) adds 17 integration cases through the actual public ReAct API.
The common Flow now pauses after a model response or a complete tool round.
The next stream pull releases it. Stopping at that boundary cancels the private
Agent before the next operation. Resume rebuilds an Agent and Session from AI
data and enters the existing native decision or model step.

Saved data retains pending calls, completed tool history, proposed domain state,
usage, counts, output repair state, identity, sequence and remaining execution
time. Current limits and tool permission apply again. Contract and module code
hashes reject changed targets or code. Provider options and credentials must be
supplied again. One example resumes in a new operating-system VM and confirms
that the completed tool does not run again. Core Exec values are never saved.

The focused run passed 60 checks, including 13 retained root token/pending-call
cases. Expiry prevents later continuation; it does not stop current execution.
The saved execution budget excludes offline storage time. Full quality results
are recorded in the [implementation record](implementation.md).

These tokens remain caller-owned and replayable. Partial tool batches, durable
single-consumer records, old progressed-state conversion, query append and
external queue binding remain open. This is not evidence for the Agent
persistence API or durable backup/restore. Trace/redaction, cycles, standalone
Actions/workers, skills/resources, root dependency/package, consumer,
minimum-runtime, migration and rollback checks remain required. All history
statuses remain pending. Root Mix files still select v2.


## Standalone Action port: 2026-09-07

[14_04](../../examples/14_resume/14_04_standalone_actions/README.md) adds 13 integration
cases for the actual Start, Continue, Collect and Cancel Actions. They execute
through v3 Exec. A portable Flow connects Start and Collect, and an Agent route
commits the aggregate result. The live stream stays in execution context.

The Actions retain public metadata functions and use the shared schema input
normalizer. Start now delegates to the public start function. One runner option
builder carries runtime resources and native limits for Start, Continue and
Collect. This fixes lost runtime context during token collection. The old
AgentServer State dependency is removed; transient nested context maps remain
supported. Cancellation stops the tool, private Agent and stream owner.

The focused run passed 28 checks, including 15 retained root helper tests.
A real multimodal Action request is linked to PR 278 in the history ledger.
No shape-only or mocked ReAct call is counted as live feature evidence.

Query append, old progressed-state conversion, complete trace/redaction/cycle
and provider behavior, workers and skills/resources remain required. Token
replay, durable Agent recovery, root dependency/package, consumer,
minimum-runtime, migration and rollback gates remain open. Root Mix files still
select v2. Full validation is recorded in [implementation](implementation.md).


## Native worker lifetime and failure: 2026-09-07

[14_05](../../examples/14_resume/14_05_worker_lifecycle/README.md) adds nine integration
cases through the public ReAct and CoT Agents. Task loss stops held work,
preserves observed usage and commits one failure. Later work succeeds, and late
old task data cannot finish the next request. Session-owner loss interrupts
stored requests; parent shutdown stops the complete owned process tree.
Wrong-run observations and old worker Signals cannot publish a result.

Task failure retains `:worker_crash` and now also records a portable exit reason
and `:worker_task` error type. A public ReAct file-ID request reaches the model
boundary, which is linked to PR 304. The focused lifecycle set passes 84 checks.
The shared mock changes only model responses; real tools and core tasks execute.

Four internal Worker Agent/Strategy modules and the obsolete callback-only
worker test are removed. Native Session task ownership replaces that separate
execution layer. The old parent ReAct Strategy remains unported and still has
old worker references. Its trace, inspection, context lane/compaction, skills,
resources and state conversion must be mapped before its retirement. Existing
root callback tests must also be transferred. This is not a root package pass.

Session-owner recovery does not restore the old volatile stream sink. Durable
terminal delivery, Agent persistence, full standalone behavior, root dependency,
package, consumer, minimum-runtime, migration and rollback gates remain open.
Root Mix files still select v2. All history statuses remain pending. See the
[implementation record](implementation.md) for full validation results.

## Trace and repeated-call port: 2026-09-07

[14_06](../../examples/14_resume/14_06_trace_and_cycles/README.md) adds 13 real
integration cases. They cover tool-start redaction, unchanged tool inputs,
stream capture settings, model-field reset, saved stream fields, repeated
calls, distinct long arguments, public tool aliases and two checkpoint resumes.
The common Flow owns the repeated-call check; no second execution loop is added.

The check predates v2.0.0 (PR 188). The full argument digest corrects truncated
comparison. The warning no longer claims equal results. Parent Strategy trace
retention, context lanes/compaction, inspection, old-state conversion and the
remaining package gates stay open.

## Standalone queued input: 2026-09-07

[14_07](../../examples/14_resume/14_07_standalone_input/README.md) adds 13 integration
cases for caller-supplied queues through the common Flow. They cover FIFO input,
refs, lower-level bounds, real tool steering, final-answer continuation, atomic
closure, queue loss, cancellation and ownership. Iteration limits still apply,
and the queue closes before output repair. Resume binds a fresh queue without
saving process handles or repeating its saved tool.

These cases extend the active-input feature from PR 225 and the shared public
control path from PR 235. Queued input remains volatile. Query append, old State
conversion, parent context/inspection, skills/resources and package gates remain
required.

## Native conversation continuation: 2026-09-07

[14_08](../../examples/14_resume/14_08_query_append/README.md) adds 15 cases for native
query append, terminal history/domain state, pending-tool ordering, separate
repair and reasoning counters, rich input and saved limits. One checkpoint
format serves active and completed native runs. Committed effects are not
reapplied. Earlier native checkpoint data version 1 still resumes.

Append consumes remaining reasoning, model, tool and time limits. The old path
could reuse the same iteration or skip pending tools after changing status;
these behaviors have explicit v3 corrections. General old State conversion,
failed/cancelled restart, parent context and inspection, skills/resources and
full package gates remain required.

## Explicit standalone State migration: 2026-09-07

[14_09](../../examples/14_resume/14_09_state_migration/README.md) adds 22 cases for
State conversion before/after a model, after tools and at terminal status. A
real failed model call after tools restarts without repeating the completed tool.
Rich input/refs, typed saved output, terminal errors, call and time bounds remain.
Old tokens need external evidence for phase, counters and domain state. Uncertain
tool work returns a reconciliation error. Agent persistence and automatic native
failure counter capture remain separate requirements; this is not full recovery.

## Failure and cancellation position: 2026-09-07

[14_10](../../examples/14_resume/14_10_failure_position/README.md) adds 18 integration
cases for reasoning position across provider, transformer, typed-output and
repair failures; cancellation; worker failure; parent shutdown; and resumed or
queued input. Model calls remain separate. The standalone State and terminal
request metadata retain the correct reasoning position. Lost owner metadata and
uncertain tool outcomes still require their separate recovery work.


## Native parent inspection and trace prefixes: 2026-09-07

[02_22](../../examples/02_requests/02_22_request_inspection/README.md) adds the common
`Session.snapshot/2` API and 14 integration examples. The envelope distinguishes
the committed Agent/revision/request from a later live Session sample. It keeps
request/run IDs, phase, model counts, reasoning position, usage, output,
text/thinking, tool progress/results, raw failure and retained request selection.
It reuses the existing configuration and committed Context views.

Portable request records now retain bounded trace prefixes. The first 2,000
events are kept; overflow sets the truncation flag. History commits store the
current prefix and metadata. Completion stores the sampled prefix plus the
normal terminal record. State-size pressure can omit trace details. Recovery
retains the last committed prefix and fails interrupted work without replay.
A real durable lost-reply case restores a completed answer and trace.

The simplification pass removed terminal event construction from the pure
outcome Turn. Cancellation can race with later events before commit. A saved
trace therefore declares `scope: :observed_prefix` and its last sampled `seq`.
The canonical stream continues through the existing publisher and emits its
terminal event after commit. This is not a complete durable event journal or
proof of Signal delivery. Events since the last history commit can be lost;
profiles without history save their trace at completion only.

No old Strategy callback, core Snapshot type, new executor, queue or runtime
owner was introduced. Context replace/switch, operation IDs, trusted skill
compaction, skills/resources and active method-specific tree/graph views remain
required before the parent Strategy can retire. Root dependency, old Agent
conversion, full package/consumer/runtime-floor/migration/rollback gates remain
open. The migration goal stays active.


## Native context operations: 2026-09-07

[02_23](../../examples/02_requests/02_23_context_operations/README.md) adds 28 integration
cases and `Session.modify_context/3`. The common lowerer adds context routes
and a pure state Plugin for profiles with history. It stores active lane refs,
one deferred operation, the last 128 applied IDs and a portable `Jido.Session`
with one `Jido.Thread` per profile. Request admission/history and terminal completion use the existing
commit paths. No runtime owner, queue or executor was added.

Replacement and switch apply while idle or in the terminal commit after active
work. The current request keeps its admitted context. Success, failure, cancel,
task loss and Session recovery apply the pending operation; later pending input
replaces the previous operation. Nil prompt keeps the configured prompt. New
lanes are empty; switching back restores the selected history and prompt.
Invalid native input fails; the retained legacy Signal keeps invalid no-op
semantics. Direct history changes are reconciled before later lane operations.

Compaction retains accepted skill tool/assistant pairs and removes conflicting
replacement copies. A regression test exposed the old assistant-ID-only check;
v3 now keeps the original call name and arguments with the result. Typed and
string-keyed tool calls work. These are host-imported accepted-history cases;
actual LoadSkill provenance, callbacks, catalog scope and resources remain open.
A real durable lost-reply test proves the request answer, replacement, prompt
and applied ID are in the same saved terminal commit.

Public configuration/Context getters now accept a profile ID, and request
inspection uses it. Private standalone checkpoints exclude the owned context
field from their application domain, with resume checks through a new VM.
The root dependencies remain v2. Local core advanced independently to
`c845eed9` (`3.0.0-beta.1`); this AI slice uses that current checkout. Core was
not edited here, and its full suite was not rerun here. Skill/resource ports,
parent Strategy retirement, old Agent conversion and root package/consumer/
runtime-floor/migration/rollback gates remain required. The goal stays active.


## Native skill runtime and resources: 2026-09-07

[18_01](../../examples/18_skills/18_01_skill_runtime/README.md) adds 27 integration
cases for real `LoadSkill`/`LoadResource`, approved instruction history, context
compaction, closed catalogues, fresh resource reads, image/PDF transport and
owner cleanup/restore. A separate v3 command passes 293 retained skill/resource
checks. `Jido.AI.Skill` now lives in `lib/jido_ai/skill/skill.ex`.

The current path uses an explicit host-prepared catalogue in trusted context.
Request `tool_context` cannot replace reserved catalogue/provider/policy fields.
A native skill session belongs to the Session owner, profile and host binding.
Activation survives requests and model failure; owner exit or explicit cleanup
removes its resource access. Restore retains instructions and requires fresh
activation. Runtime handles stay outside portable state. There is no additional
execution owner, model server or skill compiler.

The legacy `agent_skills` option, automatic prompt/tools setup, declarative skill
source forms and standalone continuation still need their authoring port.
Installed-application resource tests, CLI, complete conversion/recovery and all
root package/consumer/runtime-floor/migration/rollback gates remain open. The
root dependency files still use v2. History statuses remain pending.


## Automatic skill authoring: 2026-09-07

[18_02](../../examples/18_skills/18_02_skill_authoring/README.md) adds 21 integration
cases. Public `agent_skills`, the native `skills` block, source data, Builder
and JSON use one static source and the existing Session/Flow runtime. Live
startup prepares the catalogue; compilation and static construction do not
read skill files. Selected Specs supply the prompt index, loading context and
automatic Actions. File bodies are strictly loaded only on selection.

Cases prove runtime-directory resolution, trust and discovery limits, source
precedence and diagnostics, separate profiles, current-file activation,
restore, and live tool/prompt changes. A refinement fix preserves automatic
tools during live registration. Public timeout/retry defaults apply to the
automatic entries. All 21 cases and 293 retained skill/resource tests pass.

`Session.skill_catalog/2` returns live Specs, index and diagnostics. Pure config
getters show declared values and portable overrides. Automatic skills require
a live ReAct Session; static callbacks use MFA. Native module Plugins stay
explicit Agent declarations. The manual host binding remains available.

The ledger has 787 exact test references and 66 rows with partial evidence;
all 126 row statuses remain pending. Standalone skill continuation, installed
resources/CLI, old parent Strategy retirement, complete Agent conversion and
recovery, root dependency/package, consumer, minimum-runtime and rollback gates
remain open. See the [implementation record](implementation.md) for full checks.


## Persistent tool context: 2026-09-07

[03_02](../../examples/03_tools/03_02_tool_context/README.md) adds the base context
replacement API to the existing Configuration Plugin. Public `tool_context`,
native DSL and source data now store defaults in `Profile.tool_context`.
`set_tool_context/3`, `set_tool_context_direct/3` and the retained
`ai.react.set_tool_context` Signal replace that map. Invalid or nonportable
values leave the committed Agent unchanged. No new runtime owner was added.

The public wrapper no longer inserts old defaults into every request. The
merge order for application fields is host, base, then explicit request values.
Active requests retain their admission context. Request values remain transient.
Native tool projection and protected runtime/skill fields still apply. The
compatibility config view now includes `base_tool_context`. The 11 cases cover
live/direct calls, Signals, callbacks, native Turn/Session profiles, Builder,
both JSON forms, profile isolation and restore.

This completes one remaining parent Strategy behavior. Standalone skill
continuation, parent Strategy retirement, the other uncompiled production files,
complete Agent conversion/recovery and package/consumer/minimum-runtime/migration/
rollback checks remain required. See the [implementation record](implementation.md)
for the current full-suite evidence.
