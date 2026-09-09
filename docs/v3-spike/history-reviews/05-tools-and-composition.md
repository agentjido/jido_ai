# History review 05: tools, callbacks and Agent composition

Reviewed on 2026-09-06 against `fc5bc1434ddb69493fe8a68443f03bc6a198c5a2`.
This pass completes seven more source reviews. The total is 48 of 126.
All v3 port checks remain pending. This pass changes documents only.
No tests ran during this pass.

The review read each full commit diff, its tests and documentation, the
associated PR discussions, and issue 280. Two linked MCP records supply the
reported use case. Their code is outside the Jido AI commit range.

## Commit dispositions

| Commit | Final requirement to retain | Required cases |
| --- | --- | --- |
| `508bcf76` / PR 263 | AI authoring preserves the host's Plugin choices. The baseline permits disabling or replacing a core default Plugin. | HIST-17: plugin choices |
| `d567bdbc` / PR 267 | Direct tool registration changes the Agent value without a Server self-call. Keep the tool list, lookup and model schemas consistent. | HIST-17: direct catalog, registration from work, catalog conflict |
| `da16089d` / PR 268 | A compiled but unloaded Action reached through a Plugin route executes on its first call. | HIST-05: unloaded route |
| `058b4108` / PR 281 | Ordinary Signal routes coexist with AI requests. Retain static parameters and caller module-attribute routes. | HIST-17: ordinary routes |
| `323327c0` / PR 341 | Effective tool strictness reaches schema conversion and the provider payload. Non-strict tools retain explicitly open nested objects. | HIST-05: open schema, converter contract |
| `e623c2ae` / PR 290 | Prompt validation accepts the reported multiline code and JSON without losing the existing single-line detection cases. | HIST-02: multiline validation |
| `8defee92` / PR 347 | Agent tool callbacks transform arguments and canonical results. Keep immutable call identity, callback order, controlled failures and effect filtering. Ordinary Action execution stays independent. | HIST-09: alias round trip, direct Action, callback order, identity, failures, effects, result projection, pending work |

## One Agent combines ordinary routes and dynamic tools

Use the mixed AI/ordinary Agent from catalog 01 and 16. Give it a domain route
that changes a case status, an ordinary Plugin, and a route that adds or removes
a tool from its allowed catalog. The next model request must advertise the
committed catalog. The selected real Action must execute through core Exec.
The shared mock supplies model messages and checks the actual HTTP request.

[Issue 280](https://github.com/agentjido/jido_ai/issues/280) reports that the AI
macro prevented users from adding Signal routes to change live Agent state.
[PR 281](https://github.com/agentjido/jido_ai/pull/281) preserves simple routes,
static route parameters and a route table defined with a module attribute.
It verifies a live Server call. A route-table inspection alone is insufficient.

| Variant | Required evidence |
| --- | --- |
| `HIST-17/ordinary-routes` | Compile the supported legacy route forms through compatibility conversion. Declare the same ordinary route beside `ai` in the new Agent DSL. A live call commits the complete domain state and preserves unrelated fields. Then run an AI request on the same Agent. |
| `HIST-17/plugin-choices` | Configure, disable and replace a supported default capability. Preserve the remaining Plugins, declared order, state namespace and mount configuration. Test the actual v3 Plugin lifecycle. Document how legacy memory/Thread choices map to AI history and current core Plugins. |
| `HIST-17/direct-catalog` | Register a valid Action on an Agent value, list it, call it, and remove it by public name. The allowed lookup and next provider tool schema agree. Re-registering the same module adds no duplicate. Missing and incomplete modules fail before a catalog commit. |
| `HIST-17/registration-from-work` | A real Action already executing for the Agent requests a catalog change. The operation completes without a Server self-call or deadlock. The next request sees the committed change. Compare the supported direct API and live route. |
| `HIST-17/catalog-conflict` | Two distinct modules expose the same public name. Reject the ambiguous catalog before commit or provider work. All previous entries remain valid. Removing a tool removes its schema and lookup together; a model cannot execute it through a stale name. |
| `HIST-17/catalog-boundary` | Hold a tool batch after preparation, then request a catalog change. Bind the prepared batch to its validated operation identity. Apply the new catalog at a documented boundary, and recheck permission before resumed approval work. A changed name mapping must not silently select another executable. |

[PR 267](https://github.com/agentjido/jido_ai/pull/267) calls the direct API a
practical fix for work already inside the Agent, including dynamic MCP sync.
The baseline rebuilds three derived tool views in one struct update. Its
adapter rejects duplicate names; the intermediate `Map.new` does not make
colliding modules a supported replacement policy. Preserve the rejection.
The `validate: false` option bypasses the initial callback check only. Schema
conversion still occurs and can fail. Define its compatibility behavior without
claiming that it accepts arbitrary executable values.

Use one validated tool catalog in the new design. Derive provider schemas and
lookup data from it. Use complete candidate state or a dedicated Plugin update
at the core boundary. Do not port mutations of the removed strategy state.
Treat catalog changes during active work as an explicit runtime policy. The
baseline direct-registration tests do not prove that concurrency contract.

[PR 263](https://github.com/agentjido/jido_ai/pull/263) tests the old canonical
memory Plugin and preserves the old Thread/Identity defaults. These names are
baseline evidence, not a demand to restore removed core v2 internals. Preserve
the user's ability to select capabilities and retain required AI history.
Give each legacy option an explicit conversion or migration-guide entry.

## HIST-05: first use must load an Action and preserve its schema

For `HIST-05/unloaded-route`, compile a real Action to a temporary BEAM file,
remove it from the loaded module set, and put its directory on the code path.
Invoke the Plugin route before any helper inspects that Action. Assert actual
execution, the committed state and module loading. Clean up the module and
path after the test. The old test uses a v2 strategy fallback; the new example
must use the current core route and Exec path.

[PR 268](https://github.com/agentjido/jido_ai/pull/268) traced a silent no-op to
`function_exported?` on an unloaded module. The linked
[MCP request](https://github.com/agentjido/jido_mcp/issues/1) asks for runtime
endpoint registration. [MCP PR 6](https://github.com/agentjido/jido_mcp/pull/6)
adds endpoint Signals, explicit readiness and tool-sync lifecycle rules.
Use that context to test dynamic AI composition. Do not add MCP endpoint
implementation or implicit endpoint auto-sync to this AI migration requirement.

[PR 341](https://github.com/agentjido/jido_ai/pull/341) reports a Fireworks
failure: a tool declared `strict: false`, but its nested parameters were closed
by schema conversion. OpenAI models did not expose the same failure.

- `HIST-05/open-schema`: use an Action with a declared nested object that has
  `additionalProperties: true`. In non-strict mode, retain that value in the
  provider payload. Return a call with non-empty dynamic parameters from the
  unified mock and assert the real Action receives them. Repeat with inferred
  strictness and both explicit overrides. Strict mode closes that object.
  Objects that omit `additionalProperties` retain the baseline closed default.
- `HIST-05/converter-contract`: use the actual supported Action Schema converter
  and load it before callback discovery. Conversion failure is visible before
  provider work; it must not silently become an empty schema. The baseline has
  arity-two conversion and an arity-one compatibility fallback. Keep only the
  fallback required by the chosen supported dependency range, with an explicit
  migration decision if the public range changes.

The open-schema example must use an OpenAI-compatible provider route with the
real ReqLLM encoder and decoder. A `ReqLLM.Tool` field assertion alone cannot
prove the wire payload. Use local responses; no paid Fireworks call is needed.

## HIST-09: preserve the reported alias workflow

The [PR 347 user report](https://github.com/agentjido/jido_ai/pull/347#issuecomment-5345440818)
describes long serialized keys that the model copies incorrectly. The user
maps each key to a short alias for AI use. Ordinary workflows still use the
original key. Build this case with two real Actions: one lists available items;
the other validates and consumes an original key.

For `HIST-09/alias-round-trip`, an after-tool callback maps the returned long
key to an alias. The next model call sees that alias. Its response selects the
second Action with the alias. A before-tool callback restores the exact long
key before schema validation and execution. Assert the final result and call
IDs through both ReAct and ToT Agent execution.

Keep the alias table in explicit request or domain data. Do not hide it in
the mock or global test state. If the alias must survive restore, prove that
portable data path and the authority to use it after restore.

For `HIST-09/direct-action`, invoke the same Actions with original keys through
an ordinary Action/Flow path. No Agent AI callback runs. Also cover supported
direct AI tool helpers. The baseline applies these hooks only to Agent-managed
ReAct and ToT work; it does not apply them to every `Exec`, `Turn`,
`CallWithTools` or `ExecuteTool` call. Keep this scope explicit in the new API.

| Variant | Required evidence |
| --- | --- |
| `HIST-09/callback-order` | Before runs once before argument validation and retries. Preflight sees the rewritten arguments. After runs once after the final attempt, including a final tool error. Count calls with a per-test process and use real retries. A rejected prepared batch starts no tool. |
| `HIST-09/identity` | Reject a change to call ID, public tool name or executable identity. Keep the original identity in events, result lookup and next model context. An unknown tool cannot gain authority through a callback. Missing callbacks are identity operations. |
| `HIST-09/failures` | Cover explicit errors, before-tool interrupt, invalid return shapes, exception, throw and exit. Return controlled failures with callback identity and reason. Before failure prevents execution. After failure prevents successful finalization but cannot undo completed external work. |
| `HIST-09/effects` | The callback returns a canonical `{:ok, value, effects}` or `{:error, reason, effects}` inside its success result. Reject malformed or two-element callback result tuples. Filter effects after transformation. A callback cannot add an effect forbidden by the active policy. |
| `HIST-09/result-projection` | ReAct completion events, stored canonical results and next model input use the transformed value. ToT receives the raw executor result, then transforms it before state, effect application and follow-up model input. Match IDs and order under reversed tool completion. |
| `HIST-09/parallel-after-failure` | Two real tools finish their external work. Make an after callback fail. Record which work occurred and return a request failure. Do not emit successful final completion or claim that no tools ran. Keep the documented commit boundary. |
| `HIST-09/runtime-context` | Callbacks receive current state, request/run IDs, Agent identity, application tool context and effect policy. Caller data cannot replace reserved runtime fields. The next round sees permitted state changes without storing live runtime handles. |
| `HIST-09/pending-work` | Preserve tool identity, arguments and attempt/result data in pending work. Restore and validate it before execution. Test whether argument preparation repeats, including a non-idempotent transform. Define the v3 replay rule; do not claim a once-only callback across restart from the old retry tests. |

The final [maintainer decision](https://github.com/agentjido/jido_ai/pull/347#issuecomment-5428496166)
clarifies a difference from the PR's proposed shared executor. The merged
implementation shares `ToolInterceptor`, but ReAct and ToT invoke it at their
own runtime boundaries. ToT's inbound `ai.tool.result` contains the raw result.
The PR body alone would incorrectly require that inbound signal to be changed.

In the baseline, ReAct collects the parallel results before it applies after
callbacks in call order. An after failure can follow completed external work
and earlier completion events. Pending work re-enters the preparation path.
These observations require the failure and replay cases above. They are not
passing v3 guarantees.

Implement one AI tool-preparation/result policy around core Action/Flow
execution. Do not add AI hooks to every ordinary Action or create a second
executor. Use stable trusted callback references in the profile. Keep legacy
module callbacks in compatibility conversion. The full alias example must
pass before a simplification removes method-specific wrappers.

## HIST-02: validate useful code without the reported false positive

For `HIST-02/multiline-validation`, send the reported multiline Elixir shape
through public prompt validation and an Agent configured to use that control.
Include `<-`, `auto_join_system_group` and `|>` on different lines. The mock
must receive the accepted content. Repeat with the accepted multiline JSON
fixture. The existing single-line XML-like and role-spoofing JSON fixtures
must still fail before a model call.

[PR 290](https://github.com/agentjido/jido_ai/pull/290) changes two character
classes to exclude newlines. It does not establish a general security guarantee
or identical handling for every multiline string. Other regex terms still
use whitespace matching. Preserve the tested input behavior and make the
validation control explicit; do not describe a prompt filter as a tool
authorization check.

## Baseline evidence and simplification checks

Source: [Agent macro](../../../lib/jido_ai/authoring/agent.ex),
[direct API](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai.ex),
[tool adapter](../../../lib/jido_ai/shared/tool_adapter.ex),
[reasoning helper](../../../lib/jido_ai/reasoning/helpers.ex),
[tool interceptor](../../../lib/jido_ai/shared/tool_interceptor.ex),
[ReAct runner](https://github.com/agentjido/jido_ai/blob/fc5bc1434ddb69493fe8a68443f03bc6a198c5a2/lib/jido_ai/reasoning/react/runner.ex),
[ToT strategy](../../../lib/jido_ai/shared/tot_strategy.ex), and
[prompt validation](../../../lib/jido_ai/shared/validation.ex).

Tests: [Agent composition](../../../test/jido_ai/agent_test.exs),
[direct API](../../../test/jido_ai/jido_ai_core_test.exs),
[unloaded routed Action](../../../test/jido_ai/integration/jido_v2_migration_test.exs),
[schema adapter](../../../test/jido_ai/tool_adapter_test.exs),
[callback contract](../../../test/jido_ai/tool_interceptor_test.exs),
[ReAct runtime](../../../test/jido_ai/react/runtime_runner_test.exs),
[ToT](../../../test/jido_ai/strategy/tree_of_thoughts_test.exs), and
[validation](../../../test/jido_ai/validation_test.exs).

At the authoring simplification pass, verify mixed core routes/Plugins and
one canonical catalog. At the live-runtime pass, verify callback counts,
rewritten preflight input, retries and the complete alias workflow. At the
recovery pass, verify pending identity, catalog changes and callback replay.
All checks use the real production operation paths after kickoff.

## Partial v3 reasoning capability evidence — 2026-09-07

[16_01](../../../examples/16_capabilities/16_01_reasoning/README.md) now runs
seven capability Plugins on core v3. It uses explicit routes, configured owned
state, and the existing callable reasoning Action. Two Plugin orders produce
the same request defaults and result field. A native AI profile shares an Agent
with a callable capability. An ordinary route commits domain state before two
capability requests; each keeps the other result and domain fields.

These cases add partial evidence to PR 263 and PR 281. They do not prove the
legacy `default_plugins` conversion, disabling/replacing a default Plugin, all
old route-table forms, dynamic catalogs, or Thread/history conversion. The
required cases and history statuses remain pending. Callback removal and the
explicit route migration are listed in the example's API table.

## Chat port evidence: 2026-09-07

[Example 16_02](../../../examples/16_capabilities/16_02_chat/README.md) supplies the
new execution evidence. The PR 290 multiline code and JSON cases now have a real Chat request example. Single-line detection remains. Chat also uses explicit core routes, consistent tool aliases and a core Flow tool. The separate dynamic catalog and caller hook requirements remain open.

## Default Plugin and ordinary-route evidence: 2026-09-07

[16_04](../../../examples/16_capabilities/16_04_plugin_stack/README.md) now runs the
public Agent with default Policy/ModelRouting, optional Retrieval/Quota and
explicit custom Plugins. Static route input and a caller module-attribute route
table reach real Actions before a later AI request. Explicit route choices
replace only the matching generated capability route. The example also checks
shared Store lifetime, request work cleanup and definition codec parity.

PR 263 and PR 281 gain partial evidence. The old core default-map option still
requires an explicit state migration. Mutable tool catalogs, the full unloaded
runtime-route case and all callback/consumer requirements remain separate gates.


## Persistent context evidence: 2026-09-07

[03_02](../../../examples/03_tools/03_02_tool_context/README.md) adds base context
replacement through the existing Configuration Plugin. The cases prove live
and direct changes, request precedence, admitted snapshots, callback context,
protected fields, separate profiles, format parity and restore. Base values
are portable; runtime/skill bindings remain host-owned. These results extend
partial history evidence. The complete feature and package gates remain open.
