# Current public API map

The live request API is `Jido.AI.Orchestration`. `Jido.Session` remains the
portable value. See [ownership and migration](orchestration-layout.md) for the
file layout, Coordinator boundary, and future delegation constraints.

Conversation consolidation is complete. `Jido.AI.Thread.Projection` provides
canonical Session/Thread message projection. Runtime history now stores Session
values, with no second Session in Plugin lane state. Standalone ReAct and
conversation controls use canonical Threads. The old Context value and
reverse-order history replacement API are removed. Verification is recorded in
[the consolidation audit](conversation-consolidation.md).

Checked against the source on 2026-09-15 after canonical conversation consolidation.
This map describes the current V3 branch, not a released V3 package.
The [source inventory](api-inventory.json) records declarations; an exported
function in that inventory is not, by itself, a supported application API.
The [feature map](feature-map.md) groups the behavior and test evidence.
The [old migration map](public-api-map-history.md) is historical evidence only.

## Conversation ownership

`Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry` are the retained values.
`Jido.AI.Thread.Projection` interprets AI entries; it does not own state.
Thread controls and operation encoding live under `Jido.AI.Thread`.
The top-level `Conversation` and `History` modules are removed. Internal
`Orchestration.Transcript` owns Agent field access and commits. Internal
`Model.Messages` owns provider-message normalization and private metadata.
No forwarding compatibility modules remain.

## Main authoring contract

Use **Agent + DSL + Profile** for new AI agents. Other entry points reuse this
contract; they are not separate authoring models.

| Surface | Current contract | Source and acceptance tests |
| --- | --- | --- |
| `Jido.AI.Agent`, `Jido.AI.DSL` | Declare AI Profiles on a core Agent, bind routes to Profiles, and declare result/history fields. Core owns Agent construction and route execution. | [Agent](../../lib/jido_ai/agent.ex), [DSL](../../lib/jido_ai/dsl.ex), [authoring tests](../../test/authoring/agents/authoring_test.exs) |
| `Jido.AI.Profile.new/1,2`, `new!/1,2`, `validate/1` | Validate model, reasoning, request, result, memory, tool, and control policy. `Jido.AI.profile/1,2` and `profile!/1,2` are short entry points to the same validator. | [Profile](../../lib/jido_ai/profile.ex), [validation tests](../../test/jido_ai/authoring/profile_validation_test.exs), [model tests](../../test/jido_ai/profile/model_input_test.exs) |
| `Jido.AI.Authoring.ai/1`, `lower/2` | Bind a declared Profile or lower a neutral Agent definition through canonical Profile validation. Core Builder remains in core Jido; there is no `Jido.AI.Builder` module. | [Authoring](../../lib/jido_ai/authoring.ex), [parity tests](../../test/jido_ai/authoring/full_spec_parity_test.exs) |
| `Jido.AI.inspect/1,2`, `preflight/2,3`, `export/2,3`, `import/1,2` | Portable inspection, preflight, and map/JSON/YAML exchange. Registry references are explicit. In-memory model support does not imply that every native model value can be exported. | [Portable](../../lib/jido_ai/portable.ex), [Codec](../../lib/jido_ai/authoring/codec.ex), [portable tests](../../test/jido_ai/authoring/portable_test.exs) |

## Requests and state

`Runtime.State` defines the internal, temporary execution map. Its schema is
checked at preparation and the model/decision/tool-batch boundaries. It holds
working messages, counters, deadlines, and proposed effects; it is not a
second Session or Thread. Optional method and phase fields remain absent until
needed. This map is not an application import/export contract.

`Runtime.Checkpoint` owns shared capture, restore, deadline and effect checks,
and pause delivery. The internal `Reasoning.ReAct.Checkpoint` adapter owns
ReAct State projection, code/configuration fingerprints, and token encoding.
This separation does not add resume support to other reasoning methods.

| Surface | Current contract | Source and acceptance tests |
| --- | --- | --- |
| Generated `ask/2,3`, `ask_sync/2,3`, `ask_stream/2,3` | `ask` returns an answer for turn mode or a request handle for session mode. `ask_sync` waits for an answer; `ask_stream` starts a streaming session request. These are not aliases for core route helpers, which return the committed Agent. | [generated definitions](../../lib/jido_ai/agent/definition.ex), [interface](../../lib/jido_ai/agent/interface.ex), [interface tests](../../test/authoring/agents/interfaces_test.exs) |
| Generated `await/1,2`, `cancel/1,2`, `steer/2,3` | Retained convenience helpers. Generated cancellation targets the Agent server; `Orchestration.cancel` targets a handle. `inject` is not generated. | [definitions](../../lib/jido_ai/agent/definition.ex), [request tests](../../test/authoring/agents/execution_test.exs) |
| `Jido.AI.Request.await/1,2`, `await_many/1,2` | Wait for admitted requests. `await_many` belongs to Request, not the generated Agent interface. | [Request](../../lib/jido_ai/request.ex), [Session tests](../../test/jido_ai/orchestration/orchestration_test.exs) |
| `Jido.AI.Orchestration.snapshot/1,2`, `modify_context/2,3`, `cancel/1,2`, `steer/2,3`, `inject/2,3`, `skill_catalog/1,2` | Inspect or control AI requests. Inspection reads selected Profile and committed Session entries, not private strategy state. | [Orchestration](../../lib/jido_ai/orchestration.ex), [inspection tests](../../test/jido_ai/orchestration/inspection_test.exs), [recovery tests](../../test/authoring/agents/recovery_test.exs) |
| `Jido.AI.Configuration.profile/1,2`, `Jido.AI.Thread.Projection.messages/1` | Read effective configuration and the declared committed history. A request already in progress keeps its admitted input. | [Configuration](../../lib/jido_ai/configuration.ex), [Thread projection](../../lib/jido_ai/thread/projection.ex), [history tests](../../test/jido_ai/operations/history_test.exs) |
| `Jido.Session`, `Jido.Thread`, `Jido.Thread.Entry` | Value contracts owned by **jido_ai**, despite the module prefix. They remain in this package. `Jido.Session` is distinct from the AI runtime service `Jido.AI.Orchestration`. | [Session value](../../lib/jido_session.ex), [Thread](../../lib/jido_thread.ex), [Entry](../../lib/jido_thread/entry.ex), [value tests](../../test/jido_ai/thread_value_test.exs) |

## Models, tools, and capabilities

Provider transport now lives under `Model`: `Model.Transport` owns the ReqLLM
call boundary and test-option binding; `Model.Generate` owns the bounded
generation Action; `Model.Options` owns provider option normalization and
HTTP option merging; `Model.Messages` owns message metadata and response
alignment. `Models` resolves model identities. Runtime events remain in
`Runtime.Event`. The old `Runtime.ModelCall`, `Runtime.Response`, and
`Operations.Generate` modules are removed without forwarding modules.

ReAct Config no longer supplies generic model option helpers. Its standalone
configuration construction and `llm_opts/1` projection use `Model.Options`.
Internal callers pass the selected model explicitly when merging options.

`Jido.AI.Tools.Executor` owns direct tool execution (`execute`, `execute_module`,
`run_tools`, and `run_tool_calls`). Profile tool attempts use its internal
target boundary before applying Profile policy. `Jido.AI.Turn` only normalizes
response values and projects messages. Its old execution functions are removed,
not forwarded. Use `ToolAdapter.to_action_map/1` for module lookup maps and
`SchemaInput.normalize_tool/2` (schema first) for argument normalization.

| Surface | Current contract | Source and acceptance tests |
| --- | --- | --- |
| `Jido.AI.Models.aliases/0`, `resolve/1` | Resolve aliases and native ReqLLM model inputs. Use ReqLLM directly for provider calls; there is no second root generation facade. | [Models](../../lib/jido_ai/models.ex), [model example tests](../../test/examples/01_authoring/01_08_model_helpers/01_08_model_helpers_test.exs) |
| Root tool and prompt helpers | `register_tool`, `unregister_tool`, `set_system_prompt`, `set_tool_context`, their direct variants, `list_tools`, and `has_tool?` remain. Server and direct Agent forms have different result shapes; use their documented contracts. | [root API](../../lib/jido_ai.ex), [tool API tests](../../test/jido_ai/tool_api_test.exs) |
| `Jido.AI.Actions.*` | Reusable LLM, planning, reasoning, retrieval, quota, skill, and tool Actions run through core execution. Action schemas define input; source-level helper functions are not additional user inputs. | [Actions](../../lib/jido_ai/actions), [Action tests](../../test/jido_ai/skills) |
| `Actions.Reasoning.RunStrategy` | Input is exactly one nonempty `prompt`. Host context binds a resolved Profile at `:jido_ai_callable_profile`. The Profile must use session mode and one of the seven callable methods. No flat strategy/model/options input remains. | [Action](../../lib/jido_ai/actions/reasoning/run_strategy.ex), [contract](callable-v3-contract.md), [binding tests](../../test/jido_ai/skills/reasoning/actions/run_strategy_profile_test.exs) |
| `Plugins.Reasoning.*` | Seven fixed-method Plugins accept `[profile: profile]`. Profile controls result destination and policy. A private Agent isolates callable execution. Direct callable ReAct is not provided; Adaptive can select ReAct. | [Plugins](../../lib/jido_ai/plugins/reasoning), [callable authoring tests](../../test/authoring/agents/callable_profiles_test.exs), [lifecycle tests](../../test/jido_ai/skills/reasoning/actions/run_strategy_lifecycle_test.exs) |
| Other `Jido.AI.Plugins.*` | Chat, Planning, ModelRouting, Policy, Quota, and Retrieval compose through core Plugin contracts. Their individual schemas still apply; the reasoning Plugin migration does not make all Plugin schemas identical. | [Plugins](../../lib/jido_ai/plugins), [composition tests](../../test/jido_ai/plugin_facets_test.exs) |
| `Jido.AI.Reasoning.ReAct` | Standalone `run`, `stream`, `stream_from_state`, `start`, `continue`, `collect`, and `cancel` remain, with Config, State, and Token contracts. Native Profile authoring supports all eight reasoning methods. | [ReAct](../../lib/jido_ai/reasoning/react.ex), [standalone tests](../../test/examples/14_resume/14_01_standalone_authoring/14_01_standalone_authoring_test.exs) |

## Compatibility, internal code, and removed APIs

- `Agent.from_initial_state/2,3` accepts canonical Session values or encoded
  Session maps in declared conversation fields. The special `:context` input
  is removed, as is root `update_context_entries/2`.
  These do not restore private V2 strategy state. See [import](../../lib/jido_ai/agent/initial_state.ex)
  and [boundary tests](../../test/authoring/agents/boundaries_test.exs).
- Internal implementation: `Agent.Definition`, `Agent.Interface`, DSL compiler,
  `Profile.References`, Runtime steps, and Orchestration process/commit helpers support
  the public entry points. Do not infer a stable user API from their exports.
- Public testing support remains: [Test](../../lib/jido_ai/test.ex),
  [TestCase](../../lib/jido_ai/test_case.ex), and
  [Test.ReActScript](../../lib/jido_ai/test/react_script.ex). The runtime uses an
  internal model-call boundary; it does not depend on script formats.
- Removed: execution CLI and adapters, CLI arithmetic tools, root
  `get_strategy_config` and `get_strategy_context`, old method-specific Agent
  macros, and flat callable reasoning configuration. No compatibility shim is
  promised for these surfaces.
- Not provided: rich native-model export. Dynamic tool-source expansion remains
  on hold; it is not a promised follow-up implementation. Current tool-source
  support is bounded by [ToolSource](../../lib/jido_ai/tool_source.ex) and its
  [tests](../../test/jido_ai/authoring/tool_source_test.exs).

## Evidence and limits

The JSON inventory uses schema version 2 and indexes every current `lib/**/*.ex`
file. It records hashes, source declarations, default arities, callbacks,
structs, protocol implementations, and quoted templates. It does not evaluate
macros or treat each exported helper as a supported application API. The
unchanged [schema version 1 snapshot](api-inventory-v2.json) is the V2 baseline.

Run `mix run scripts/api_inventory.exs` to regenerate it, or add `--check` to
verify it without writing. The regular unit suite checks source drift and the
local links in the current maps. Review the contract map when changing source;
automatic source indexing cannot decide API support.

The reconciliation run passed 2,861 tests with one existing flaky exclusion,
including authoring, examples, and four inventory checks. Format, forced
compile, and the inventory drift check passed. The preceding consumer
migration also ran the 658-test example suite separately. See the
[verification record](status.md) for dates and scope.
This does not establish live-provider quality, load behavior, fresh line
coverage, or release readiness. Historical maps and audits do not override
the current source and tested contracts above.
