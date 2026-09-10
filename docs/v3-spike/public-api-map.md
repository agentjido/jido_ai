# Public API migration map

Status: preparation map. No production API is ported by this document.
Checked on 2026-09-06 at `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.

Use this map with the [feature map](feature-map.md) and the
[history audit](history-audit.md). The feature map defines the required
capabilities. The history audit preserves later fixes and PR decisions. This
map identifies the call surfaces that must still serve those capabilities.

The [source inventory](api-inventory.json) covers all 175 files under `lib`.
It records file hashes, literal function names and arities, source locations,
callbacks, structs, protocol implementations and `use` declarations. Each file
has a port group, baseline test paths, an API case and pending v3 evidence.
Default arguments and quoted Agent/Signal templates are included.

This is a parsed source inventory. No source macro was evaluated. Macros from
Jido, Zoi, Splode and ExUnit can supply other exports. Conditional declarations
are retained, including both installer branches. Quoted functions identify the
macro that defines them, not an expanded consumer module. A documented callback
or an exported helper is not proof of a permanent application API.

At each port, compile an actual consumer and verify its supported exports,
schemas, options and results. Do not use the inventory count as a compatibility
score. A `use Jido.Action` module with only `run/2` in its literal source still
has generated Action metadata and validation to preserve.

## Facade and direct tool management

The source is [Jido.AI](../../lib/jido_ai.ex). Default-argument arities are
listed in the inventory. Keep tagged errors and each public result shape.

| Surface | Contract and required acceptance |
| --- | --- |
| `model_aliases/0`, `llm_defaults/0,1`, `resolve_model/1`, `model_label/1` | `API/model-facade`: built-in defaults, application configuration and explicit call options select the actual model and provider request. Preserve supported strings, tuples, maps and model structs. Test invalid aliases and invalid default kinds. Pair this with HIST-01 and the stream-header case. |
| `generate_text/1,2`, `generate_object/2,3`, `stream_text/1,2` | Preserve the ReqLLM response/stream boundary, object schema and pass-through provider options. The object facade is not the Agent output/repair loop. Test defaults separately for text, object and stream, using the actual transport. |
| `ask/1,2` | This facade returns extracted text in `{:ok, text}`. It is distinct from a generated Agent's request-handle API. Test both through the same mock and preserve their different results. |
| `register_tool/2,3`, `unregister_tool/2,3`, `set_system_prompt/2,3` | `API/tool-contracts`: live calls return the supported tagged Agent result. Validate a real loadable tool, actual next-turn schema/prompt and unknown server/error handling. Preserve documented validation and timeout options. |
| `register_tool_direct/2,3`, `unregister_tool_direct/2`, `set_system_prompt_direct/2` | Direct registration/removal return tagged Agent results; direct prompt update returns an Agent. Prove no Server self-call when invoked during real work. Preserve supported behavior through complete candidate-state assembly. |
| `list_tools/1`, `has_tool?/2` | Struct input returns a plain list/boolean. Server input returns a tagged result. Test both, plus a change during active work and the catalog boundary before the next tool round. |
| `get_strategy_config/1`, `get_strategy_context/1`, `update_context_entries/2` | The configuration getter reads the effective profile. The v2 context helpers used active private `run_context`; v3 reads and changes declared committed history. Active work keeps its admitted history. The [02_21 cases](../../examples/02_requests/02_21_context_views/README.md) cover idle, active, absent and reconstructed history. Full old-state conversion remains required. |
| `steer/2,3`, `inject/2,3` | These delegate to ReAct control. Preserve queued/rejected results and expected request IDs through the real request owner. A successful control call is not proof that the model consumed the input. |

The existing anchors include [facade tests](../../test/jido_ai/jido_ai_core_test.exs),
[tool API tests](../../test/jido_ai/tool_api_test.exs), and the full tool/history
reviews. Pure extraction checks in `text_test.exs` supplement actual transport
tests; they cannot replace them.

## Generated Agent entry points

`API/agent-wrappers` requires a consumer module for each supported macro. Use
the same bounded mock script, but check each method's actual result. Preserve
its own prompt defaults, accepted input types, options and error behavior.
Core-generated construction and command functions need consumer compilation.

| Macro source | Application functions declared by its template |
| --- | --- |
| [Agent](../../lib/jido_ai/authoring/agent.ex) | `ask/2,3`, `ask_stream/2,3`, `await/1,2`, `ask_sync/2,3`, `cancel/1,2`, `steer/2,3`, `inject/2,3`; tool callbacks; checkpoint/restore integration |
| [CoDAgent](../../lib/jido_ai/authoring/cod_agent.ex) | `draft/2,3`, `draft_sync/2,3`, `await/1,2`, `strategy_opts/0` |
| [CoTAgent](../../lib/jido_ai/authoring/cot_agent.ex) | `think/2,3`, `think_sync/2,3`, `await/1,2`, `strategy_opts/0` |
| [AoTAgent](../../lib/jido_ai/authoring/aot_agent.ex) | `explore/2,3`, `explore_sync/2,3`, `await/1,2`, `strategy_opts/0`, `answer/1` |
| [ToTAgent](../../lib/jido_ai/authoring/tot_agent.ex) | `explore/2,3`, `explore_sync/2,3`, `await/1,2`, `strategy_opts/0`, `best_answer/1`, `top_candidates/1,2`, `result_summary/1` |
| [GoTAgent](../../lib/jido_ai/authoring/got_agent.ex) | `explore/2,3`, `explore_sync/2,3`, `await/1,2`, `strategy_opts/0` |
| [TRMAgent](../../lib/jido_ai/authoring/trm_agent.ex) | `reason/2,3`, `reason_sync/2,3`, `await/1,2`, `strategy_opts/0` |
| [AdaptiveAgent](../../lib/jido_ai/authoring/adaptive_agent.ex) | `ask/2,3`, `ask_sync/2,3`, `await/1,2`, `strategy_opts/0` |

The templates also declare old command hooks. Replace their runtime roles with
the common v3 service and Plugin/Flow contracts. Do not add hooks back to core.
Do not assume that every convenience macro supplies streaming, cancellation,
multimodal input or all ReAct controls. The declared source and current tests
define the retained surface; any broader common wrapper is a named v3 change.

`await_many/1,2` belongs to `Jido.AI.Request`. It is not generated by these
Agent templates. The new DSL can share one request implementation while
compatibility wrappers retain the supported method names.

The [02_03 public Agent example](../../examples/02_requests/02_03_public_agent/README.md)
now tests the actual generated helpers on v3. It retains the documented handle,
stream map, steering result and cancellation reason shapes. Core `new/1` now
returns a tagged result; `new!/1` supplies the direct Agent value. Convenience
state has a pure compatibility projection, with typed output in `last_result`.
Remaining advanced options, command hooks, strategy macros and the full facade remain open.
This is partial execution evidence, not completion of this API map.

The [02_12 callback example](../../examples/02_requests/02_12_tool_callbacks/README.md)
now ports the optional Agent tool callbacks through core Exec. It proves the
long-key alias workflow, before-validation order, real retries, final errors,
parallel batch/result order, effect policy and trusted runtime context. Native
DSL, source data, Builder and source JSON use an explicit callback module.
The [09_05 example](../../examples/09_reasoning/09_05_tot_api/README.md) now extends
this evidence to ToT. Standalone AI helpers and pending-work replay remain open.

The [02_13 example](../../examples/02_requests/02_13_tool_limits/README.md) ports the
transient `context.__tool_guardrail_callback__` through core Exec. Prepared
arguments keep their original shape, with validated arguments in an added
field. A rejection or interruption stops the whole batch. The same example
proves real Action/Flow attempt timeouts, the total request deadline, declared
retry bounds and more than 31 seconds of actual tool execution. Direct core
Exec is covered; legacy `Turn.execute_module` and Directive entry points still
need their port. Core timeouts retain their explicit non-retryable result.
Legacy error-map retry inputs still need a compatibility case.

The [02_14 activity example](../../examples/02_requests/02_14_stream_activity/README.md)
ports public `stream_timeout_ms`, `stream_receive_timeout_ms` and
`tool_heartbeat_ms` options. Public ask, sync and stream helpers use one
request conversion. Canonical keepalives preserve both runtime and enumerable
idle limits during real tools. Provider fragments reset only internal activity.
The example proves request overrides, sequence order, deadline and timer cleanup,
and current interruption after owner failure. Standalone Start/Continue/Collect,
token compatibility and durable sink/sequence recovery remain open.

The [02_15 early-activity example](../../examples/02_requests/02_15_early_tool_activity/README.md)
adds named `:tool_call` deltas before complete argument input. It verifies real
document I/O only after admission, empty and unnamed fragments, blocked/unknown
tools, cancellation and disconnected input. Native and public Agents now share
the existing `emit_llm_deltas?` capture flag, with complete results and internal
activity retained when capture is off. This proves the public request envelope;
live `ai.llm.delta` Signal projection and other reasoning methods remain open.

The [02_11 completion example](../../examples/02_requests/02_11_completion/README.md)
adds observed failure commits, state-limit handling and real storage failures.
Await success proves the answer commit, before post-commit Directive dispatch.
`completion_uncommitted` reports an owner-observed failure with a pending stored
record; `completion_uncertain` does not claim a known storage outcome. A stopped
Agent PID still returns `agent_server_unavailable`. Full durable sink delivery
and state conversion remain open.

The [02_05 example](../../examples/02_requests/02_05_request_transform/README.md) adds
request transformers and configured repair callbacks through the public macro
and native DSL. It also executes direct `Output.repair/5` overrides and callback
references decoded from source JSON. Full standalone ReAct, token compatibility,
tool callbacks in other reasoning methods and command callbacks remain open.

## Requests and standalone execution

| Surface | Required acceptance |
| --- | --- |
| [Request](../../lib/jido_ai/request.ex): `create_and_send/3`, `send_and_await/3`, `await/1,2`, `await_many/1,2` | `API/request-handles`: accepted and rejected work, request correlation, errors and caller timeout. Await requests from independent Agents with reversed completion order; results keep input order, including a failure and timeout. No caller timeout implicitly cancels work. |
| `Request.Handle.new/3`, `complete/2`, `fail/2`; request inspection/state helpers | Preserve handle fields and result/error meaning. A caller-owned handle can contain a live Server reference. It must not be copied into portable Agent state without conversion. Validate request retention and unknown IDs. |
| [Request.Stream](../../lib/jido_ai/request/stream.ex): `events/1,2`, sink normalization, message/terminal helpers | Real PID sink delivery, stream enumeration, exactly one terminal event, receiver exit and worker cleanup. Preserve event shape and accepted partial content rules. |
| [ReAct](../../lib/jido_ai/reasoning/react.ex): `stream/2,3`, `stream_from_state/2,3`, `run/2,3`, `collect_stream/1` | `API/standalone-react`: stream is an Enumerable; `run` and `collect_stream` return aggregate maps. Prove actual tools and ordered events, not just a final mock answer. Preserve result, usage, trace and termination meaning. |
| ReAct `start/2,3`, `continue/2,3`, `collect/3`, `cancel/2,3`, `build_config/1` | Start/continue return tagged runtime maps. `collect/3` accepts an event stream or a token. Test `run_until_terminal?: false` without model work. Token cancellation returns a replacement token; it is separate from live Agent cancellation. Test invalid, incompatible and restored tokens. |
| [ReAct Actions](../../lib/jido_ai/operations/react_actions/start.ex): Start, Continue, Collect, Cancel | Run each public Action through v3 Exec. Preserve schemas, defaults, context configuration, tagged results and resource ownership. Keep one implementation behind Actions and direct functions. |

Use the [request tests](../../test/jido_ai/request_test.exs),
[standalone API tests](../../test/jido_ai/react/public_api_test.exs), and
[runtime Action tests](../../test/jido_ai/react/actions/runtime_actions_test.exs)
as anchors. The new live cases must use real v3 Agents; the old fake Server
tests establish result conversion, not v3 runtime compatibility.

## Shared operations and capability APIs

Each API case below is a set of tests within the existing example families.
The inventory supplies exact file/function lists and baseline test paths.
The linked history variants remain required alongside these API checks.

| API case | Surface to retain or explicitly migrate | Evidence needed on v3 |
| --- | --- | --- |
| `API/generation-actions` | LLM Chat, Complete, GenerateObject and Embed; Action name/schema/metadata and `run/2` | All four work through Exec and ordinary Agent routes. Check actual provider input, output keys, errors and usage. Preserve Complete as supported convenience even where it shares Chat implementation. |
| `API/tool-contracts` | ToolAdapter conversion/lookup/validation; Turn response/content/result projection and tool execution; CallWithTools, ExecuteTool, ListTools; ToolInterceptor callbacks | Real Action and Flow tools, strict/open schemas, catalog lookup and conflict, canonical results, before/after order, interruption, timeouts and known versus unknown side effects. Direct management return differences above remain required. |
| `API/content-projection` | Query schemas/file references; Context and Entry constructors, append/clear/coerce/projection/inspection; PromptBuilder | User, assistant and tool content round trips; typed and JSON-decoded input; thinking, refs, MIME and bytes at the actual provider. Bound debug output and keep pure projection usable outside an Agent. |
| `API/output-contracts` | Output construction, validation, parsing, schema/instructions, repair, fingerprint and metadata | Zoi and imported JSON schemas, defaults, invalid output, raw bypass, bounded repair, callback failures and fresh request bindings. The typed result reaches every supported reasoning method. |
| `API/reasoning-contracts` | Seven reasoning entrypoint modules; prompt/parser/ID helpers; Machines and Results; Analyze, Infer, Explain and RunStrategy | Preserve algorithms and each result shape. Check all supported methods, selector/fallback behavior, parser errors, traversal limits and direct/capability use. ToT and AoT result helpers cannot be reduced to plain text. |
| `API/planning-actions` | Plan, Decompose, Prioritize | Retain schemas and structured planning results with normal, malformed and provider-failure responses. Use the same Actions behind the Planning capability. |
| `API/retrieval` | Retrieval capability; Store ensure/upsert/recall/clear/namespace inspection; UpsertMemory, RecallMemory, ClearMemory | Namespace isolation, stored record shape, ranking/limits, request enrichment, invalid input and clear. Define store ownership and restore; use real embedding transport where invoked. |
| `API/quota` | Quota capability; Store add/get/reset/status; GetStatus and Reset | Scope, limits, admitted/rejected work, usage fallback, failed/cancelled work and duplicate records. A failed Agent commit cannot erase model cost. |
| `API/plugin-capabilities` | PluginStack; Chat, Planning, seven reasoning Plugins, ModelRouting and Policy | Supported configuration, ordinary routes, callable capabilities, model precedence, validation and enforce/monitor behavior. Preserve each signal namespace and public result. Replace v2 mount/result-transform internals with current v3 ownership. |
| `API/skill-contracts` | Skill macro/accessors; Spec, Loader, Discovery, Diagnostics, Registry, Activation and Prompt; resource policy/provider/filesystem helpers; LoadSkill and LoadResource | Retain documented module/name/Spec forms, strict/lenient diagnostics, lazy catalogs, session ownership, exact limits, opaque IDs, callbacks and binary transport. Registry registration is not authorization to expose another tenant's resource. |
| `API/events-and-signals` | Runtime.Event and ReAct.Event; Observe and Usage helpers; ten canonical typed AI Signals and Signal.Helpers | Public event kinds, generated constructors/schema metadata, fixed type and validated data, result conversion, usage and bounded/redacted observation. Do not restore already removed Signal aliases. |
| `API/error-and-validation` | Error classes and normalization/display helpers; Validation limits and callback wrappers | Tagged results, raw failure terms, structured model errors, bounded display strings, retry decisions and exact input/callback limits. Keep provider failure separate from a successful blank response. |
| `API/effect-policy` | Effects facade; Policy and Applier normalization/intersection/filter/application | Preserve allowed-effect decisions and canonical tool results. Replace StateOps with explicit domain updates and complete candidate assembly. Check parallel conflicts and completed external work followed by failure. |
| `API/checkpoint-conversion` | Checkpoint sanitization/rehydration and generated Agent checkpoint/restore | Valid old payload conversion, malformed/unsupported version rejection, interrupted-request policy and no runtime handles in stored state. Test fresh runtime reconstruction. Standalone tokens have separate acceptance. |
| `API/runtime-replacement` | Old Directive structs/DirectiveExec implementations, StateOps helpers, worker Strategies and TaskSupervisor plumbing | Their model/tool/error/request behavior survives through Actions, Flows and current Plugin callbacks. Record a migration path for a consumer that constructed a documented old directive. Do not preserve removed core protocols solely to retain the old implementation. |
| `API/consumer-cli` | CLI.Adapter callbacks and eight adapters; `mix jido_ai`, install and skill commands | Non-interactive input, method selection, generated v3 code, formatter composition, optional installer branches, exit codes and errors in a fresh consumer on the runtime floor. |
| `API/quality-tools` | Quality.Checkpoint helpers and `mix jido_ai.quality` | Command construction, timing/failure reports and story/commit coverage. These are package checks; no model call is required. |
| `API/test-helpers` | TestCase; Test script/assertion helpers; ReActScript | Preserve supported script syntax, request-scoped progress, repeated and concurrent requests, strict mismatches, unused steps and real tool execution over one mock server. |

## Migration decisions exposed by this check

1. Preserve supported facade and wrapper result shapes when the execution owner
   changes. A shared runtime does not require one result type for every API.
2. Keep configuration and history access through a small public projection of
   AI-owned data. The proposed compatibility wrappers can keep their old names
   during the port. They must not return the removed Strategy state container.
   Document changed fields and prove active versus committed history semantics.
3. The seven `strategy_module/0` helpers explicitly return v2 Strategy modules,
   and existing tests assert those module names. Their purpose moves to recipe
   selection/introspection. Define and document the corresponding v3 entry point
   with the first reasoning port. CoT/CoD now use `method/0` and namespace result
   getters; their old modules are loadable read-only adapters. The other methods
   still need this mapping. Do not return a nonexistent Strategy or silently
   remove the ability to select and inspect a method. Pure prompt, parser and
   ID helpers can keep their existing behavior.
4. `strategy_opts/0`, old command hooks, documented directive constructors and
   state helpers need a named source-to-v3 mapping. An internal replacement can
   change structure while preserving behavior. Removing public behavior still
   requires the user decision specified in the migration plan.
5. Public request handles and private runtime resources have different owners.
   A caller's live handle is valid; a serialized Agent checkpoint containing its
   PID is not. Do not apply a blanket ban to the public Handle type.

These are proposed migration rules. They do not claim that new introspection
names or compatibility wrappers already exist. Resolve the exact names with
their acceptance examples before closing the corresponding milestone.

## Acceptance and inventory checks

Keep API and historical evidence separate from source indexing. One test can
prove both an API contract and a historical regression. Link its exact name,
command, dependency revisions and result into the port evidence when it passes.
Do not create one artificial test per source function or duplicate an existing
historical scenario under a second name.

The source check verified the complete file set and hashes at the pinned HEAD.
It parsed 1,466 literal definition clauses into 1,000 module/scope/kind/name
records, covering 1,212 declared name/arity combinations. Those totals include
quoted templates and protocol implementations. They are not counts of public
features or expanded exports. Every source file has a mapped port group.

The 22 port groups here are API work groups, not extra example families or the
22 historical scenario families. They use the existing 18 example families.
Baseline test paths exist. All inventory v3 statuses and test evidence are
pending. No runtime tests or production edits were performed for this check.

## Effect API execution checkpoint

The [02_10 example](../../examples/02_requests/02_10_tool_effects/README.md) and the
retained Policy/Applier tests now exercise `API/effect-policy` on v3. The Effects
module names and tuple arities remain. StateOp construction becomes
`Jido.AI.Effects.state(complete_state)`. Core Plugin protection and state
validation apply. A failed proposal keeps the original Agent and returns its
error in the fourth `apply_result/3` element, with no pending Directives.

The existing Agent `effect_policy` and `strategy_effect_policy` options map to
one profile and reasoning policy. Custom Plugin loading now has a real public
Agent compile/run example. This does not close default Plugin choice, before/
after tool callbacks, every standalone entry point, all methods or recovery.
The implementation record contains current suite results and remaining gates.

## Typed Signal and Turn execution checkpoint

The [02_16 example](../../examples/02_requests/02_16_typed_signals/README.md) retains
the ten public Signal modules on static core schemas and compiles the shared
`Jido.AI.Turn` conversion/execution helpers. Constructor metadata, error classes,
timestamps, duplicate-key rules and protected type/data options have explicit
migration mappings in the example. The former AI Signal Definition macro is
removed; its internal helper now handles input compatibility and metadata only.

The 88 retained Turn, Signal and Signal.Helpers tests pass with three Signal
error assertions changed to the v3 Zoi contract. Direct tool validation and
actual timeout cleanup have new execution evidence. The old per-run logging
option is accepted but does not configure core Exec; suppression-only tests
are not evidence of full logging precedence. All legacy option shapes, direct
long-tool budgets, other methods and the full root package remain required.

The [02_17 example](../../examples/02_requests/02_17_signal_delivery/README.md) adds
automatic request Signal delivery through the owning Agent. The existing
observation map accepts `emit_signals?`. `Session.delivery_status/2` reads a
bounded transient report; `Request.await` still confirms the answer commit.
The request-start Signal accepts the same multimodal queries as the public
request API. Normal core outbound Plugins, adapters, state reductions and
persistence checks apply. No durable receiver acknowledgment or replay is
implied by a successful dispatch receipt.

## CoT and CoD execution checkpoint

The [09_01 example](../../examples/09_reasoning/09_01_linear/README.md) runs native
CoT/CoD profiles and the public `CoTAgent`/`CoDAgent` request helpers on v3.
Prompt attributes, defaults, invalid inputs, `strategy_opts/0`, think/draft
helpers, usage reset, method identity, rich results and printable state fields
have transport and Agent evidence. Output validation, structured repair,
controls, cancellation, limits and recovery use the common implementation.

The namespace prompt/parser/call-ID helpers compile from `shared`. The later
[09_02 example](../../examples/09_reasoning/09_02_method_api/README.md) adds `method/0`
for profile selection and namespace result getters with optional request IDs.
The old Strategy names remain loadable read-only getter adapters. Their core
execution callbacks map to normal Agent/Flow/Session APIs. `strategy_module/0`
is deprecated and no longer selects an executor.

The retained CoT Machine now compiles on v3 with direct finite transitions;
27 retained tests pass. It still emits telemetry and model-work data, but owns
no runtime. The profile maps direct CoD empty-prompt behavior explicitly.
Worker APIs, CLI, capability Plugins and state conversion remain open. This
checkpoint does not close `API/reasoning-contracts` or change the pinned
inventory and its original source paths.


## AoT execution checkpoint

The [09_03 example](../../examples/09_reasoning/09_03_aot/README.md) ports the AoT
profile, public explore helpers, namespace helpers and Machine/Result data
APIs through the existing Flow. The structured result survives direct Flow,
ordinary Agent and Session paths. Native options, profile prompt variants,
public compatibility conversion, typed-answer repair, error causes and usage
have actual transport evidence. Seven retained Machine tests run unchanged.

`AlgorithmOfThoughts.method/0` selects the method. `get_result/1,2` reads the
latest or specified retained request. The old Strategy module has only its
deprecated result getter; old callbacks and action atoms map to Agent routes
and Session APIs. Result.answer can hold a declared typed value. The example
lists exact prompt, schema, error and observation mappings. CLI, capability
APIs, full partial-transport capture, state conversion and package gates remain
open. The pinned inventory is unchanged.

## Native ToT checkpoint

The [09_04 example](../../examples/09_reasoning/09_04_tot/README.md) selects ToT through
a native AI profile and proves its shared Flow. Machine and Result retain their
namespace and data APIs; 18 retained tests pass. String status values remain
part of the result contract. The finite transition implementation no longer
requires Fsmx. Native completion metadata retains nodes and the solution path.

At this native checkpoint, public ToT calls and the PR 347 alias workflow were
still pending. The following checkpoint adds their execution evidence. Typed
result and media input remain explicit gaps.

## Public ToT checkpoint

The [09_05 example](../../examples/09_reasoning/09_05_tot_api/README.md) runs the actual
public macro, explore helpers, generation options and retained tree getters.
It maps the old Strategy to four deprecated inspection functions. Use namespace
`method/0` for selection; Agent routes, core Flow and the shared request API
replace old Strategy action atoms and execution callbacks. No second executor
is retained. The pinned source inventory remains unchanged.

The public wrapper preserves search defaults and the per-call duration timeout.
Its derived model-call budget and explicit `max_tool_calls` permit bounded
multi-phase searches. The profile lists exact limits and option precedence.
Public context uses the state snapshot before admission, with permitted staged
effects. Failed search records retain explored nodes and structured causes.

PR 347 now has actual ToT alias/state, raw retry-result, callback failure and
ordinary-turn evidence. Typed Signals observe the core-owned tool result; old
inbound tool-result Signals no longer act as a separate executor. Getters read
retained records, not an active frontier. Live inspection/resume, full legacy
model/state overrides, typed results, rich input, command-hook migration,
standalone, CLI/capability and root package checks remain required.

## Native GoT checkpoint

The [09_06 example](../../examples/09_reasoning/09_06_got/README.md) executes native
GoT profiles and retains the Machine data API on v3. The 41 original Machine
tests pass unchanged. Additional examples verify legacy telemetry, nested usage
totals and the PR 314 graph traversal change. Native request success is still
text; its metadata retains the graph. Failures include graph and usage evidence.

This does not port `GoTAgent`, namespace/Strategy inspection helpers, old command
callbacks or CLI/capability entry points. Source inventory locations and hashes
remain pinned. Active graph inspection and runtime state overrides need their
own mapping. The profile also names the difference between retaining the
aggregation-mode option and implementing distinct voting/weighted execution.

## Public GoT checkpoint

The [09_07 example](../../examples/09_reasoning/09_07_got_api/README.md) now ports
`GoTAgent`, namespace result/graph inspection and the five old Strategy getters.
The wrapper and common Agent both run the existing GoT profile. Helpers retain
successful text and failed error-pair inspection; printable `last_result` does
not duplicate the full failed graph. Explicit request IDs can inspect an older
completed graph while the latest request is pending.

The profile maps old command hooks, action atoms, `__strategy__` state and core
construction. The execution roles move to Agent/Flow/Session. Strategy callback
exports are removed. Its name stays loadable only for deprecated getters.
Path inspection now skips cyclic parent chains. Native/public request helpers
return a consistent `:busy` error and rejected-stream reason.

Full custom command-hook mapping, CLI/capability APIs, runtime model/state
overrides, typed/rich contracts, active graph inspection, admission-failure
method identity and durable recovery remain required. The pinned source
inventory is unchanged.

## Native TRM checkpoint

The [09_08 example](../../examples/09_reasoning/09_08_trm/README.md) ports the native
TRM profile and shared Flow. Machine, ACT, Reasoning, Supervision and Helpers
retain their names; their 204 existing tests pass on v3 dependencies. The
Machine now uses finite transitions and the shared nested usage merge. Native
requests suppress its duplicate telemetry while direct callers retain events.

This step does not port TRMAgent, namespace/Strategy inspection, old command
hooks, CLI/capability entry points or runtime state overrides. The result
contract distinguishes the selected scored answer, the latest improvement and
the printable legacy error from its canonical cause. Public wrapper budgets
must permit three calls per supervision cycle. The pinned source inventory
remains unchanged.

## Public TRM checkpoint

The [09_09 example](../../examples/09_reasoning/09_09_trm_api/README.md) now ports
TRMAgent, its reason/sync/await helpers, declared settings, and six retained-data
getters through the common Agent/Flow/Session. The namespace retains call-ID
and prompt helpers; Strategy supplies deprecated getter/prompt delegates only.
A real default-alias request and a full five-cycle request verify model selection
and the derived 15-call budget. Explicit limits and generation options remain
in effect. Public streaming and cancellation use the common request path.

The current answer can differ from the selected scored answer. Failed requests
keep canonical causes and printable method results separate. Pending requests
clear convenience state while older completed records remain inspectable by ID.
Custom command hooks, legacy phase-input and state conversion, runtime overrides,
CLI/capability APIs, active inspection and durable recovery remain required.
The source inventory stays pinned to the original release-history target.

## Native Adaptive checkpoint

The [09_10 example](../../examples/09_reasoning/09_10_adaptive/README.md) executes
all seven method choices through a shared native profile. The old analysis
algorithm now lives in one shared selector; its Strategy helper delegates to
that module. Sixteen transferred analysis tests preserve the existing rules.
Native profiles validate available sets, overrides, thresholds and method
options before dispatch. Selected methods retain their result and output rules.

This step does not port AdaptiveAgent or its namespace/Strategy inspection
APIs. Public printable failures from PR 234, custom hooks, legacy phase-input
and state conversion, runtime overrides, active inspection, CLI/capability
entry points and durable recovery remain required. The baseline stores
`default_strategy` without using it to select a method; native options omit
that field and the public mapping remains open. The source inventory is pinned.

## Public Adaptive checkpoint

The [09_11 example](../../examples/09_reasoning/09_11_adaptive_api/README.md) ports
AdaptiveAgent ask/sync/await, declared settings and binary guards. Its namespace
keeps analysis and gains request-ID forms of the two old Strategy getters. The
Strategy name stays loadable for deprecated analysis/getter delegates only.
Execution callbacks and action atoms are removed.

Canonical text, typed objects and AoT/ToT result maps remain separate from the
printable last_result field. Actual HTTP and method failures keep structured
causes. Selection resets on new pending work; older retained records remain
inspectable by ID. Public tool callbacks, streams and cancellation use the
common runtime. Active inspection, custom command hooks, old state/phase-input
conversion, runtime overrides, CLI/capability APIs and durable recovery remain
required. The baseline API inventory remains unchanged.

## Selected method control refinement

The [09_12 refinement](../../examples/09_reasoning/09_12_method_controls/README.md)
replaces Adaptive's combined default budget with per-method counts. The public
wrapper and common Agent resolve omitted counts after selection. Explicit Agent
and request limits retain precedence. Typed repair uses the selected iteration
count plus its repair allowance. The ten-call ReAct and fifteen-call TRM defaults
now coexist on one Agent without a separate runtime.

## Active Adaptive selection

The [09_13 cases](../../examples/09_reasoning/09_13_active_selection/README.md) restore
active Adaptive selection and complexity getters. Public selected_strategy and
canonical request metadata agree before the first model call. Input rejection
keeps selection absent. Older records remain available by ID. Owner recovery
retains committed selection and interrupts the old method. Active method phase
inspection, state/command conversion and the package gates remain required.

## RunStrategy port: 2026-09-07

The [production Action](../../lib/jido_ai/operations/run_strategy.ex) keeps
`run/2`, its input schema and the result envelope. Category, tags and contract
version remain explicit catalog accessors. The
[09_14 example](../../examples/09_reasoning/09_14_callable_reasoning/README.md) proves
seven methods, structured results, caller defaults, cancellation and usage.
`context.jido` can select an existing host. Omission uses a standalone core Agent;
the Action no longer creates an implicit `Jido.AI.InternalReasoningRunner`.

The seven internal `Actions.Reasoning.Runner.*` modules are removed. Their
replacement is the common validated source-profile factory inside RunStrategy.
The public Action remains the call surface. The compatibility `snapshot_*`
diagnostic keys now describe committed request records and method data. No v2
Strategy callback or snapshot type is restored. Capability/CLI integration, all
legacy option/metadata forms and the full package gate remain required. Baseline
source paths and hashes in the inventory stay unchanged.

## Reasoning Plugin API checkpoint — 2026-09-07

All seven `Jido.AI.Plugins.Reasoning.*` modules now use the v3 Plugin contract.
They retain their public Signal namespaces, callable Action catalog and static
metadata. Sources moved to `lib/jido_ai/authoring/plugins/reasoning`; immutable
baseline inventory paths and hashes have not changed.

[16_01's API table](../../examples/16_capabilities/16_01_reasoning/README.md)
records the callback changes. `state_spec/1` replaces mount state initialization.
Preparation plus the explicit `RunCapability` route Action replaces the v2
Signal override/result-transform hooks. `signal_routes/1` remains a source-map
helper, with a target that returns the whole Agent state. Generated v2 manifests
are replaced by core declarations. Plugin configuration is a keyword list.
The old callback tests now check native state creation, configured restore and
state ownership; actual routed work has 17 excluded-by-default integration
cases. This does not close full capability, PluginStack or default-Plugin API
migration.

## Planning API checkpoint — 2026-09-07

The three Planning Actions retain their names, catalog metadata and result maps.
They moved to `lib/jido_ai/operations/planning`. `Jido.AI.Plugins.Planning` moved
to `authoring/plugins/planning.ex` and now uses v3 state and preparation callbacks.
Its three Signal names and callable catalog remain. Explicit routes use an
Action that projects the result into a declared domain field.

[08_01's mapping](../../examples/08_planning/08_01_planning/README.md) lists the removed
v2 manifest/mount/Signal/result callbacks and their replacements. Direct calls
retain their result maps; missing/empty input validation runs before provider
work. Model resolution and provider calls use the shared helpers. The original
prompt-guided `max_steps`, bounded decomposition depth and permissive parser
fallback remain explicit. This does not claim output-plan validation or task
execution. The Action defaults, Plugin defaults, explicit request values and
trusted caller defaults have separate wire tests.

The old live Action tests now use the unified mock integration example. Native
schema and Plugin contract tests remain under the existing root test paths.
The source inventory and its baseline hashes remain unchanged.

## Chat and validation API disposition: 2026-09-07

The seven LLM/ToolCalling Action module names and their `run/2`, schema and
catalog functions remain. Files moved into `operations/llm` and
`operations/tool_calling`. Action metadata fields removed from core `use`
options remain explicit public functions.

Chat Plugin catalog helpers remain. Map config becomes keyword config.
`state_spec/1` and `prepare/2` replace v2 mount/override/result callbacks.
`signal_routes/1` now returns the bound `Actions.Chat.RunCapability` route
target; callers must declare those routes. The chosen domain field defaults
to `:result`. [The example contract](../../examples/16_capabilities/16_02_chat/README.md)
records each result shape and the removed v2 callbacks.

Helpers and Validation keep their names and public functions in `shared`.
Validation's implicit global supervisor becomes core Exec. Explicit
`task_supervisor` options retain their Task behavior. `ToolAdapter.from_action/2`
adds a `:name` option so registered aliases reach provider schemas. No legacy
API inventory hash or source path was rewritten. Root test transfer, every
legacy option and complete consumer verification remain required.

## ModelRouting and Policy API changes: 2026-09-07

Both public Plugin names, catalog functions, state keys and schemas remain.
Files moved to `authoring/plugins`. Keyword config and `state_spec/1` replace
map config and `mount/2`. Core `prepare/2` replaces `handle_signal/2`; Agent
declarations replace generated `plugin_spec/1`. Neither Plugin adds routes.
Eleven tests under the retained root paths now check native Command preparation.

[Example 16_03](../../examples/16_capabilities/16_03_routing_policy/README.md) records the
exact model and rejection rules. In particular, Policy now returns a structured
error instead of changing the Signal to an error route. Consumers must handle
that error. Native Turn and session requests share per-request primary model
selection, using the fixed profile ID from the declared core route. Canonical
atom Action keys win over duplicate string keys.

These examples use direct core calls. They do not close all public request
option forms, runtime provider changes or the default PluginStack contract.
The baseline API inventory paths and hashes remain unchanged. State conversion,
root test transfer and the full package/consumer checks remain required.

## Retrieval API and ownership: 2026-09-07

The Store and three Action module names and original call arities remain.
Sources moved to `shared/retrieval` and `operations/retrieval`; the Plugin moved
to `authoring/plugins`. Store calls require an explicitly supervised owner.
`ensure_table!/0` now checks readiness. Additional store arguments, recall's
`store:` option and direct Action `context.retrieval_store` select an owner.
The default registered owner is `Jido.AI.Retrieval.Store`.

The Plugin uses keyword config, `state_spec/1`, live `admit/3` and pure
`prepare/2`. Its three route helpers target the shared capability wrapper and
put the public Action result in a declared domain field. Catalog functions and
schemas remain. The old mount, Signal hook and manifest require the documented
replacement. Missing Plugin namespace now resolves at the request boundary.

[Example 07_01](../../examples/07_retrieval/07_01_memory/README.md) records exact result,
ranking, context, lifetime and error rules. Root Store/Action tests now start
the supervised owner; six Plugin tests use current Commands and admission.
Unknown string keys cannot suppress valid memory fields or create atoms. A
completed memory write remains after a failed Agent commit. The immutable API
inventory remains unchanged; full import, recovery and consumer gates stay open.

## Quota API evidence: 2026-09-07

[13_01](../../examples/13_policy/13_01_quota/README.md) supplies 28 integration cases
for `API/quota`, plus 15 retained Store/Action and updated Plugin tests. Original
Store arities and Action result envelopes remain. Store readiness now requires
explicit supervision. Keyword configuration and core Plugin callbacks replace
mount and Signal rewriting. Route results use a declared domain field. New
ledger/import APIs expose unknown work and preserve valid v2 aggregate rows.

The profile records changed counter semantics, generation limits, zero-usage
ambiguity and conversion steps. It also records a separate `API/tool-contracts`
gap in raw RunStrategy JSON schema export. The later
[09_16](../../examples/09_reasoning/09_16_reasoning_tool/README.md) example closes that
gap with the raw Action and unchanged direct input schema. The narrower core
Flow remains a valid composition example.
Default PluginStack, durable conversion, root package and full API gates remain.

## Default Plugin API evidence: 2026-09-07

[16_04](../../examples/16_capabilities/16_04_plugin_stack/README.md) ports
`PluginStack.default_plugins/1` to v3 declarations and integrates public macro
options, optional routes and result fields. It retains map/keyword input,
explicit configuration, ordinary static routes and module-attribute route
tables. Private RunStrategy work also retains default Policy. The profile
records the TaskSupervisor replacement and the old core `default_plugins`
conversion boundary. `API/plugin-capabilities` and `API/runtime-replacement`
remain partial until their remaining state and consumer gates pass.

## Request API refinement: 2026-09-07

[02_18](../../examples/02_requests/02_18_admission/README.md) retains raw admission
errors and request correlation while correcting method identity. Standalone
synthetic-event helpers retain their default method and now honor an explicit
method. Duplicate IDs do not terminate the original request stream.

[02_19](../../examples/02_requests/02_19_model_options/README.md) adds public `model`
forwarding through the native runtime binding. Existing `llm_opts` keyword/map
forms use shared selected-model normalization; invalid outer containers reject
before admission. HTTP callbacks remain runtime resources. The original model
resolver and three/four-argument Config merge functions remain in use. The
immutable API inventory is unchanged. Full facade, transport, worker, state
conversion, root package and consumer checks remain required.

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

## Standalone trace and repeated-call contracts: 2026-09-07

[14_06](../../examples/14_resume/14_06_trace_and_cycles/README.md) proves the flat
Config observation options through the shared native runtime. Stream text and
thinking accumulate and reset per model call; checkpoints retain completed
stream data. The thinking/message flags retain their legacy no-op behavior.
Tool-start events expose prepared arguments with optional sensitive-key
redaction. They do not replace or redact the actual execution inputs.

`State.prev_tool_signature` remains available. Its internal representation is
now a digest of full arguments and public tool names. Compare it only for
identity; do not parse it. Call order and IDs do not change the signature.
The warning and signature survive tool checkpoints and later model failure.
Full current State compatibility and old progressed-state conversion are still
open; this is not a general State migration claim.

## Standalone input queue binding: 2026-09-07

[14_07](../../examples/14_resume/14_07_standalone_input/README.md) ports the existing
flat Config `pending_input_server` option. Native Session consumes that same
queue; direct enqueue and public steering share it. Borrowed queues are sealed
and remain owned by the caller. Internally created queues still stop at cleanup.
The old queue API and bounds are retained, with real failure and closure cases.

Queue addresses are live resources, not token or Agent state. Resume can bind a
fresh queue while retaining consumed history. Undrained input is not in the
checkpoint. `ReAct.steer/3` retains its Agent return value; `Session.steer/3`
retains its acknowledgement. Query append and old State conversion remain open.

## Native query append and State counters: 2026-09-07

[14_08](../../examples/14_resume/14_08_query_append/README.md) ports the `query:`
option on `continue/3` and `stream_from_state/3` for initial State and native
checkpoints. It retains conversation, identity, sequence, usage, domain state
and remaining budgets. Saved tools finish before appended input reaches the
model. Nil, empty-string and unsupported option values do not append input.

New successful terminal State retains a native checkpoint with no pending
effects. Checkpoint data version 2 separates reasoning iteration from model
calls and accepts earlier native version-1 data. Token prefix/payload and outer
State versions remain unchanged. See the example for the precise counter map.
Model repair does not advance reasoning iteration. Appended queries consume the
same finite run budget as queued input. Old v2 State and failure/cancellation
conversion remain open; this is not complete State compatibility.

## Standalone State conversion: 2026-09-07

`ReAct.State.migrate/3` is an explicit new public data-conversion function.
[14_09](../../examples/14_resume/14_09_state_migration/README.md) proves released
State-format-v3 maps and old `rt2` payloads can enter the native checkpoint path
with caller-supplied phase, counts, domain and remaining time. It checks saved
history, tool identity and pending work. Completed/failed/cancelled result replay
and new-query continuation retain identity and budgets. The old API inventory
is unchanged. This addition does not replace Agent/Strategy state conversion,
automatic failure counter projection, persistence or package acceptance.

## Reasoning position on terminal failure: 2026-09-07

[14_10](../../examples/14_resume/14_10_failure_position/README.md) adds the explicit
`reasoning_iteration` value to native request, model-start and checkpoint
events and request metadata. Stream chunks keep their existing fields.
`State.iteration` reads this reasoning position on failure/cancellation instead
of the model-operation counter in Event `iteration`. Repair can therefore add a
model call while State stays on the same reasoning step. Successful and resumed
paths use the same meaning. The existing transformer view shares the model-step
position function. No new public execution function or checkpoint format is
introduced. Parent/active inspection, persisted recovery and root package gates
remain open.


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


## Parent ReAct Strategy exit map

The old `Jido.AI.Reasoning.ReAct.Strategy` callbacks have been removed. Its
remaining `list_tools/1` helper delegates to the public tool view. All production
files now compile in the root package, which is also the acceptance dependency.
The following replacements define required caller and test migration. This
table does not mark the old root tests as passing.

| Old boundary | V3 destination |
| --- | --- |
| `start_action/0` and start instructions | Public Agent `ask` and native request routes; request admission is owned by Session. |
| `register_tool_action/0`, `unregister_tool_action/0`, `set_system_prompt_action/0` | Public live/direct helpers and the existing Configuration Plugin. Legacy Signal names are retained. |
| `set_tool_context_action/0` | `Jido.AI.set_tool_context/3`, its direct helper and `ai.react.set_tool_context`; [03_02](../../examples/03_tools/03_02_tool_context/README.md) supplies executable evidence. |
| `cancel_action/0`, `steer_action/0`, `inject_action/0` | Native Request/Session ownership and the retained public control helpers. Active work uses one request/run identity. |
| `context_modify_action/0` | `Session.modify_context/3` and the retained context Signal; [02_23](../../examples/02_requests/02_23_context_operations/README.md). |
| `snapshot/2` and `list_tools/1` | `Session.snapshot/2` for a live request, and the public configuration/context/tool views for an Agent value; [02_22](../../examples/02_requests/02_22_request_inspection/README.md). |
| `init/2`, `cmd/3`, `signal_routes/1`, `action_spec/1` | Core definition/instantiation and command APIs, `Module.agent().routes`, and schemas on the routed Actions. Old Strategy state and instruction tuples require explicit caller changes. |
| Legacy result/delta/runtime-event action identifiers | These were no-ops in the delegated v2 Strategy. Native events and request records supply their observation contract. Do not create a second event executor to preserve an identifier. |
| Worker event/start/exit handlers | The existing core-owned Session runtime and worker lifecycle examples. No old child Strategy is required. |
| Arbitrary Action fallback in `cmd/3` | Core routed command execution. Transfer the old fallback tests before package acceptance. |

Standalone skill continuation remains an open feature check. Transfer tests
that call the old callbacks directly, and record caller/state migration. The
Directive compatibility entry is now `Jido.AI.Directive.Execution.exec/3`; it
is explicit caller-owned execution, not a native v3 Directive protocol. CLI
polling now reads Session views. Full root behavior checks remain required.
See the [root package checkpoint](root-package-checkpoint.md).


## CoT, CoD and AoT root caller transfer

The six old Strategy/wrapper test files now execute through native Agent,
Action, Flow and Session APIs. All 70 behavior cases remain. The
[CoT/CoD case map](linear-test-transfer.md) and [AoT case map](aot-test-transfer.md)
record each old case and its replacement. Both maps state the busy-admission,
worker-error, Action-schema, profile-selection and state-inspection changes.
These files accounted for 53 failures in the prior root run; all now pass.

The transfer found and fixed missing complete image-part events. The shared
model callback emits them; Session inspection only joins binary text. Two
[linear integration cases](../../examples/09_reasoning/09_01_linear/README.md) check
real SSE image bytes, ordered event identity and full stored results. This is
partial HIST-04 evidence for PR 340, not closure of its replay/capture variants.
The API inventory and source-review fields remain unchanged.


## StateOp helper retirement and native state proof

The [state transfer map](state-test-transfer.md) accounts for all 76 old helper
and Strategy state cases. The two files now execute 39 native checks. Repeated
constructor-shape checks were consolidated; the count change is explicit.
Complete domain state uses `Effects.state/1`. Map/list edits are ordinary Elixir
operations. Session owns request counters, pending tools, IDs, usage and text.
Configuration and Context APIs own their respective state. The map records
which setters are removed, how callers migrate, and which stored diagnostic
values survive after live work clears.

The transfer fixed missing ReAct termination metadata. Four more response
examples check `:final_answer` across normal/streamed and tool/no-tool calls.
The existing non-default termination cases still pass. All required API,
state-conversion, consumer and release gates remain open. The immutable
inventory and source-review fields are unchanged.


### Tool inspection transfer

The [two-case ReAct transfer](react-inspection-test-transfer.md) uses
`Session.snapshot/2`. Active tool calls retain prepared provider arguments and
include a nil result. Completed records retain validated arguments, result,
attempts and duration. Typed Action failures keep their type, message and retry
hint; error details include tool identity. Repeated completion observations
cannot change an active model phase or duplicate completed results. Terminal
and subsequent requests retain separate result sets. Empty tool collections
are lists. This replaces the private Strategy snapshot shape; it does not
restore its core type. Initial Agent state conversion and other unmapped
Strategy tests remain open.


### Initial conversation state import

[`Jido.AI.Agent.from_initial_state/3`](../../lib/jido_ai/authoring/agent.ex)
accepts a module or neutral definition, application initial state, and optional
`:id`/`:profile`. It replaces conversation-only `initial_state: %{context: ...}`
startup. It uses core instantiation plus shared history preparation and portable
prompt overrides. The selected profile receives complete history and saved or
configured instructions; other declared fields retain normal validation.

The [four-case source transfer](react-initial-state-test-transfer.md) preserves
all 78 ReAct cases, with 72 passing at that checkpoint. Nine boundary cases and seven
[14_11 examples](../../examples/14_resume/14_11_initial_state/README.md) cover required
history fields, source/option validation, typed content and refs, whole tool
exchanges, profile separation, native reconstruction and size limits. The v3
Context projection uses Agent/profile identity. It does not restore a prior
Context ID or core Thread revision. Completed historical tools do not rerun.

Old `__strategy__`, request records and Plugin-owned state are not accepted as
application initial state. `API/checkpoint-conversion` remains open for full old
Agent payloads, active request policy and fresh-runtime conversion. Standalone
State conversion remains a separate API. No checkpoint gate or history row is
closed by the initial conversation import.


### Terminal checkpoint, usage and error transfer

The [six-case transfer](react-terminal-test-transfer.md) completes the retained
78-case ReAct file. Native Agent checkpoints preserve terminal request records
through core `checkpoint/1` and `restore/2`; standalone ReAct retains signed
tokens. The two formats are not interchangeable. Restoring a completed native
Agent leaves it idle and retains result, usage, errors, tool history and trace.
A later request keeps a separate record and does not replay a completed tool.
Six [14_12 cases](../../examples/14_resume/14_12_terminal_state/README.md) prove this
through buffered and SSE provider calls.

Use `Session.snapshot/2` for request inspection. Failed records have the raw
error in `view.request.error` and nil result. `Request.await/1` returns
`{:error, raw_error}`. The public ReAct collector retains the raw error as its
result. The exact tuple/map cases use an output control after real model work.
The separate provider case records the current SDK's `:error` decoding of
an incomplete Chat finish reason. Existing wrapper-envelope root failures
remain required; this mapping does not silently change those assertions.

Real multi-call usage and empty final model usage are verified at the request
boundary. Nested arbitrary usage and empty terminal usage are verified through
public event collection. Four numeric-string SSE failures remain required SDK
work. Full v2 Agent/Plugin payload conversion, active recovery and the other
reasoning Strategy callers remain open. The immutable inventory and all history
source-review fields are unchanged.
