# V3 AI simplification

Use `Jido.AI.Agent` + `Jido.AI.DSL` + `Jido.AI.Profile` as the main AI
authoring model. Keep each change small and commit each verified step.
This record covers `jido_ai` on `v3-spike` only.

## Current scope: 2026-09-15

`jido_ai` owns `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry`.
Keep these modules and their value contracts in this package; no transfer to
core Jido is planned. Their existing module names remain unchanged.

Authoring and example migration and tests are now approved work. Refine and
consolidate these consumers around the Agent, DSL, and Profile contracts.
Run the full package test suite after repairs. Earlier deferrals and test
counts below describe earlier checkpoints, not current permission or proof
that the full suite passes.

### Consumer migration completed

`087afb8c` updates callable examples and tests to the Profile-bound API.
Quota Flows explicitly forward the Profile. Resume and skill tests read
Configuration and History. Planning and reasoning keep separate results.
Five new authoring tests cover callable Plugins, Builder, Codec, host Registry
requirements, and invalid configuration. Detailed method and deadline matrices
stay in unit tests. Examples retain route, raw-tool, quota, transport, failure,
and cancellation proofs. Unused flat-input and label fixtures were removed.

Verification on 2026-09-15:

- Full suite: 2,857 passed, 1 existing flaky exclusion, no failures or skips;
  authoring and examples included, seed 0, warnings as errors, 126.8 seconds.
- Separate example suite: 658 passed, no failures or skips, seed 0, warnings
  as errors, 81.3 seconds. This also verifies the last context-forwarding cleanup.
- Format and forced compile with warnings as errors passed.
- Existing authoring selections: 308 passed; five new callable authoring tests
  also passed separately and in the full suite.
- Empty fixture and temporary directories were removed with `rmdir`. Build,
  dependencies, Git data, and nonempty directories were not removed.

No new runtime defect was confirmed. Failures were stale API expectations or
test setup. Nested provider transport must be bound under the inner Profile ID;
the examples and their instructions now show this. No production runtime code
or dependency version changed. Live-provider quality, load testing, and fresh
line coverage remain unverified.

## Checkpoints

1. `e5937dd4` preserves the prior example refactor, test fixtures, Session test
   correction, and ReqLLM pin `888fca022fea50785e2a54f7eabfcc47d289ae41`.
2. `5cbdf5f1` removes the execution CLI and its private support.
   It does not change the reasoning engines or request runtime.
3. `20cd98d1` puts source files at paths that match module names and
   splits mixed files. It preserves module names, contracts, and behavior.
4. `2dd33ebb` removes direct test-script dependencies from Request,
   Runtime.ModelCall, and ReAct.Runner. It preserves the public test helpers
   through an internal model-call boundary.
5. `af68e568` removes the root strategy inspection helpers. Session
   inspection reads the selected Profile and committed History. Snapshot
   fields and request execution remain the same.
6. `6736c6c4` extracts internal Profile reference resolution into
   `Jido.AI.Profile.References.resolve/2`. Profile keeps defaults, canonical
   policy validation, schema construction, and public errors. No additional
  feature is removed. Orchestration.Coordinator and dependency versions are unchanged.
7. `bf5c9785` rejects invalid scalar model inputs in Profile before
   ReqLLM model validation. Valid aliases and native model specifications keep
   their existing behavior. The ReqLLM pin is unchanged.
8. The earlier callable validation checkpoint removed the extra Profile validation in `RunStrategy` and
   two repeated context normalizations. Authoring performs canonical Profile
   validation before server startup. That checkpoint retained the old option rules.
9. `cc37525e` requires successful completion for all seven callable methods.
10. The approved breaking migration binds one resolved Profile to each callable
    request. See the implementation section below for the new API and results.

## Inventory and caller evidence

Source paths below are relative to `lib/jido_ai/` unless they start with
`lib/` or `examples/`. Proposed work is not part of this checkpoint.

| Decision | Surface | Caller evidence and scope |
| --- | --- | --- |
| Keep | `Jido.AI.Agent`, DSL, Profile | `agent/definition.ex` installs the DSL and request helpers. `dsl.ex` lowers declarations through `Authoring` and Profile. This is the main authoring path. |
| Keep | `Authoring.lower/2`, Portable, Codec | DSL, import/export, `RunStrategy`, and standalone ReAct use these paths. They share Profile validation; they are not CLI-only builders. |
| Separate; complete | Profile reference resolution | `Profile.new/2` is the only caller of `Profile.References.resolve/2`. It resolves explicit references before defaults and policy validation. ToolSource still validates separated source declarations. |
| Keep | Request, Session, runtime Plugins | `agent/interface.ex` submits requests and waits for results. `session/inspection.ex` builds the public snapshot. Request, stream, cancellation, and reasoning unit tests cover these paths. |
| Separate; complete | Test script selection and model calls | `Test.ReActScript` owns script options, prompt matching, errors, and HTTP replies. Request and ReAct.Runner capture generic call options before they start work in another process. Runtime.ModelCall uses ReqLLM by default. |
| Keep | Eight reasoning methods and their data APIs | `reasoning.ex` dispatches Profile methods. `reasoning/*` parsers, machines, results, and inspection helpers serve the native runtime and method tests. Removing a CLI adapter does not remove its method. |
| Keep | Standalone ReAct Config, State, Token, Runner and Actions | `reasoning/react.ex` provides run, stream, resume, collect, and cancel. `reasoning/react/authoring.ex` lowers Config to a native Agent. `examples/14_resume` and ReAct unit tests call these APIs. |
| Keep | Capability Plugins, planning, retrieval, quota, skills | `plugins/*` supplies core Agent composition. Examples in groups 07, 08, 13, 16, and 18 use it. `RunStrategy` is also a callable tool in 09_14 and 09_16. |
| Replace; complete | Callable configuration | `RunStrategy` takes only prompt input and a host-bound resolved Profile. Seven fixed-method Plugins use `[profile: profile]`. The Action validates the binding; Authoring also validates it when it lowers the private Agent. |
| Keep; owned by `jido_ai` | Session/Thread values and AI Context | This `jido_ai` repository owns `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry`. They were in `lib/jido_session.ex` and `lib/jido_thread.ex`; they now use `lib/jido_session.ex`, `lib/jido_thread.ex`, and `lib/jido_thread/entry.ex`. The prior claim that core Jido owns them was incorrect. AI history, initial-state conversion, and unit tests use these values. No module moves to another repository and no value API is removed here. |
| Keep | Install, skill, and quality Mix tasks | These configure applications, manage skills, or run quality checks. They have separate unit tests and no dependency on `Mix.Tasks.JidoAi` or its adapters. |
| Remove; complete | `mix jido_ai` and `Mix.Tasks.JidoAi` | The execution task was the CLI entry point. Its option parsing, stdin batches, output formatting, and telemetry display have no other runtime caller. |
| Remove; complete | `Jido.AI.CLI.Adapter`, `Jido.AI.CLI.EphemeralAgent`, eight `CLIAdapter` modules | Adapter resolution and temporary module creation were called only by the task, adapters, and CLI tests. No retained source, example, or authoring fixture calls them. |
| Remove; complete | `Jido.AI.Tools.Arithmetic` and Add, Subtract, Multiply, Divide, Square | ReAct's CLI adapter was the only runtime caller. The CLI task documentation was the only other use outside that implementation. Examples already have their own Actions. |
| Remove; complete | `Jido.AI.get_strategy_config/1,2` and `get_strategy_context/1,2` | `Session.Inspection` now reads Profile and History directly. Four unit test files now use supported Agent, Profile, Session, and History behavior. Two example test files still need migration; their exact paths are recorded below. |
| Simplify; proposed | Generated `ask`, `ask_sync`, `ask_stream`, `await`, `cancel`, `steer` helpers | `agent/definition.ex` generates them; `agent/interface.ex` resolves routes. Native Agent unit tests and examples still call them. Review overlap with route `define` helpers as a separate change. |
| Move; proposed | Historical API and CLI obligations | Old audit files still describe the CLI as retained work. Keep historical evidence separate from the current supported API inventory. This record supersedes their CLI retention decision. |
| Move; proposed | Any future execution shell or arithmetic demonstration | Put application-specific command behavior in a consumer application, and teaching Actions in examples. There is no retained caller that requires a replacement package now. |

## Removed API details

- `Mix.Tasks.JidoAi`: `run/1`, `prepare_invocation/1`, `supported_types/0`,
  `option_parser_config/0`, `build_config/1`, `validate_format/1`,
  `validate_invocation/2`, `format_error/1`, and `handle_trace_event/4`.
- `Jido.AI.CLI.Adapter`: behaviour callbacks, `resolve/2`, `supported_types/0`,
  `status/1`, and the optional caller convention `cli_adapter/0`.
- `Jido.AI.CLI.EphemeralAgent.create/2`.
- `Jido.AI.Reasoning.{ReAct,AlgorithmOfThoughts,ChainOfDraft,ChainOfThought,
  TreeOfThoughts,GraphOfThoughts,TRM,Adaptive}.CLIAdapter`, including
  `start_agent/3`, `submit/3`, `await/3`, `stop/1`, and
  `create_ephemeral_agent/1`.
- `Jido.AI.Tools.Arithmetic` and its five Action modules.
- `Jido.AI.get_strategy_config/1,2` and `Jido.AI.get_strategy_context/1,2`.

Use a declared AI Agent and its request API for application execution.
No replacement command or compatibility adapter is added. No dependency was
used only by the CLI, so this removal does not change the dependency list.

## Source organization result

- Root public helpers now have root files: Authoring, Capability, Portable,
  PluginConfig, ReasoningCapability, ToolSource, Configuration, Control,
  History, Instructions, ModelRouter, ToolCatalog, and ToolContext.
  `authoring/` now contains only `Authoring.Codec`.
- Plugins use `plugins/`. Their Agent and AgentServer modules have separate
  files, as the Runtime and Session Plugin modules already do.
- The DSL uses `dsl.ex` and `dsl/` for Entities, Macros, Compiler, and
  StateSizeTransformer. Small nested entity values stay in `dsl/entities.ex`.
- ReAct Runner, Authoring, and Actions use `reasoning/react/`.
- Actions use `actions/` and runtime modules use `runtime/`. The old
  `operations/runtime.ex` is split by module. `operations/` now contains
  only `generate.ex`, which matches the retained
  `Jido.AI.Operations.Generate` name. It is no longer a general source folder.
- Session, Skill, and Signal use `session.ex`, `skill.ex`, and `signal.ex`.
  Signal children use `signal/`. Context operations use `context/operations/`
  and `context/operations.ex`.
- Session actions, history support, and delivery support have separate files.
  Configuration, tool-calling flows, ToolInterception/ToolHook,
  Effects.State/Candidate, and Thread/Entry are also split by module.
  Small error classes and values remain grouped in their existing error files.
- At the source organization checkpoint, all 266 top-level module bodies matched the prior source after removal of
  whitespace between modules. No function implementation, module name, or
  contract changed at that checkpoint. Profile reference resolution is now
  extracted as described below. Orchestration.Coordinator internals remain unchanged.
- One unit source-layout check covers AI module paths. It allows the two
  existing groups of small error values and the established ReAct spelling.

## Model-call boundary

- `Runtime.ModelCall` accepts one internal `:jido_ai_model_call` option. Its
  callback receives the call data and the default ReqLLM function. Call data
  contains kind, model, input, options, and schema. The boundary removes its
  own option before it calls the callback or ReqLLM. No provider framework or
  application configuration is added.
- An optional process-local binder converts options before Request sends its
  signal and before Runner creates its lazy stream. It can use the current
  process or its Task callers. Explicit call options take precedence. The
  captured options travel with the request and work after the binder owner
  exits. Runner stores them in live model context; it does not change Config
  or the checkpoint fingerprint.
- `Test.ReActScript` installs the binder when it registers a script.
  `TestCase` also installs it, including support for malformed legacy script
  options. The public `expect_react`, `react_opts`, `react_llm_opts`, reset,
  and assertion helpers remain. Explicit helper options carry the callback
  and work in processes without a script registry. Only test modules know
  the script format and select scripted replies.
- Scripted text and stream calls still use `Test.MockLLM` and real ReqLLM
  HTTP/SSE code. Script errors retain their tagged results. The callback runs
  in the existing Exec lifetime and quota scope. Quota, cancellation, Session,
  and structured output implementation are unchanged.
- With no callback, ModelCall still calls ReqLLM for text, objects, embeddings,
  text streams, and object streams. Tests exercise all five paths through the
  local HTTP server. No live provider request was needed for these checks.

## Strategy inspection removal

- `Session.Inspection` resolves the current Profile once through
  `Configuration.profile/2`. Its private configuration projection retains the
  same keys and merge order: method options, model generation options, then
  shared Profile fields. Tool targets, names, and ReqLLM definitions retain
  their order. The root helpers have no replacement root API.
- Conversation messages come from `History.read/2` on the committed Agent
  state. Context still projects those entries to message maps. It retains
  system prompts, chronological order, content parts, tool calls, and refs.
  Live inspection does not supply private conversation state.
- Snapshot selection still uses the selected request's profile. An idle Agent
  selects `:assistant`, or its only profile. An idle Agent with multiple
  profiles and no `:assistant` returns empty configuration and conversation.
  An Agent without AI profiles also returns an empty idle view.
- Before a lane switch, empty configured history has the `"default"` context
  reference.
  A profile without history has no context reference or conversation, even
  if it has instructions. Nil instructions add no system message. Empty text
  adds an explicit empty system message. Existing lane references and pending
  context operations retain their meaning.
- Snapshot configuration and conversation reflect current committed state,
  including for a retained request. Already-started work keeps its admission
  configuration. The request record, live sample, events, and completion
  behavior are unchanged.

Migration paths:

| Prior use | Supported path |
| --- | --- |
| Declared configuration before startup | `Jido.AI.Agent.profile(source, id)` or `profiles/1` returns declared Profile values. This does not include runtime overrides. |
| Current configuration on an Agent value | `Jido.AI.Configuration.profile(agent, id)` returns a tagged current Profile, including committed overrides. Read `instructions`, `models[reasoning.model].generation`, `tools`, `controls`, and `requests` as needed. |
| Running Agent inspection | `Jido.AI.Orchestration.snapshot(server, request_id: id)` returns `details.config` and `details.conversation`. Omit `request_id` for the normal selection. |
| Committed history for one profile | Select the Profile, then call `Jido.AI.History.read(agent.state, profile)`. The result contains chronological entry maps. The system prompt is `profile.instructions`. |
| Old Context entry comparison | Compare History entries with `context.entries \|> Enum.reverse() \|> Enum.map(&Map.from_struct/1)`. History returns maps, not Context.Entry structs. |
| Synthetic Context identity | Assert the Agent ID and selected Profile ID. The removed helper's `agent_id:profile_id` Context ID is no longer an inspection contract. |

The affected unit files retain their runtime and state assertions:

- `test/jido_ai/operations/initial_state_test.exs`
- `test/jido_ai/strategy/react_test.exs`
- `test/jido_ai/strategy/stateops_integration_test.exs`
- `test/jido_ai/integration/react_context_lifecycle_integration_test.exs`

`test/jido_ai/orchestration/inspection_test.exs` adds ten snapshot tests. They cover
nil, empty, and saved prompts before the first request; absent history;
no profiles; method and generation fields; default and explicit profile
selection; current overrides during active work; retained request selection;
and imported content parts, tool messages, refs, and context lane switches.
Existing tests still cover pending tools, stream text, cancellation, failure,
recovery, deferred context replacement, checkpoints, and trace truncation.

## Profile reference resolution

- `profile/references.ex` contains the former private resolution group with
  one internal `resolve/2` entry. It calls Profile's existing field, traversal,
  and error helpers. Control input conversion retains its original error paths;
  control defaults and policy checks stay in Profile.
- Explicit map registries retain atom or string namespace keys. Core
  `Codec.Registry` retains Action, Flow, alias, and error behavior, including
  its existing rejection of schema, router, and control references here.
  Nested instruction, tool, schema, repair Action, router, and control
  references retain their order and normalization. Explicit tool sources
  precede inline sources; ToolSource still owns their validation and references.
- Twelve selected unit tests cover these contracts, invalid containers and
  fields, Flow values, defaults, and inert construction. Eleven passed against
  the original implementation before extraction. Action, router, and control
  test callbacks raise if construction executes them.
- The root `AGENTS.md` now records the main V3 authoring model, current release
  state, bounded checks, and deferred suites. Broader documentation remains
  deferred. This step adds no public authoring API or execution framework.

## Callable reasoning review before approval

- Before: `RunStrategy` called `Profile.new/1`, then `Authoring.lower/2`
  called `Profile.source/1`, which called `Profile.new/1` again. After: the
  Action passes the source map directly to the existing lowerer. This removes
  one full pre-lowering policy validation per valid callable request. It does
  not remove validation of runtime overrides, selected methods, or core Agent
  configuration. No new module, schema, or execution layer is added.
- Context normalization now occurs once at `run/2`. The two private callers
  receive that normalized map directly. Source changes remove three redundant
  calls and the direct Profile alias. This is a small runtime reduction, not
  a new common configuration API.
- Seven regression tests cover canonical Profiles for all seven callable
  methods, deferred method limits, top-level and nested option precedence,
  atom and string keys, false and nil option values, default sources, explicit
  caller presence, ignored options, and validation error order before server
  startup. They also require successful tool execution and successful core
  Plugin composition with model routing, a fixed method, and a selected result
  field. The seven tests passed before the reduction and after it. The Plugin
  test also checks the model and prompt sent to the isolated Agent.
- Tests use explicit scripted model options for the tool worker. Process-local
  script discovery does not reach that worker through `Turn.execute/4`.
  Explicit caller context under `ai.assistant.options` works across the
  boundary. The final success checks use the local HTTP fixture.
- At the callable validation checkpoint, the seven-method execution matrix
  accepted success or failure. The completion checkpoint below replaces that
  matrix with required successful results for every callable method.

The review found real contract differences that prevent a larger compatible
merge:

| Surface | Prior callable contract |
| --- | --- |
| `RunStrategy` | Seven short strategy IDs; direct default model `:fast`; request timeout 30 seconds; method-derived count limits. It is itself callable as a tool. |
| `ReasoningCapability` and seven `Plugins.Reasoning` modules | Core-owned defaults use model `:reasoning`. The Plugin fixes the method and result field. Routing and retrieval can supply input before the Action runs. Schema validation checks the defaults container; method policy is validated during execution. |
| Flat and nested Action options | The existing per-method key list is narrower than Profile. For example, callable ToT ignores `max_nodes`, and count-limit keys are ignored. Removing the key list would change accepted input and errors. |
| Model generation options | Callable AoT converts generation fields to a keyword list. Profile's direct model fields perform stricter checks. Replacing this conversion can change validation and error precedence. |
| Method wrappers | They expose method identity, prompts, parsers, and stored result inspection. They no longer build another runtime configuration. Retained unit tests and examples call them. |
| ReAct | Standalone Config/Runner and native Profile execution remain. `RunStrategy` still rejects `strategy: :react`; this checkpoint does not add an eighth callable strategy. All eight reasoning methods remain supported through their current APIs. |

That earlier reduction required no caller migration. The user has now approved
the replacement of flat options and Plugin default containers with Profile
configuration. The implemented changes and required migrations are below.
Generated Agent helpers and Session/Thread values are unchanged.

## Callable completion coverage

The unit matrix and the fast callable test now require successful completion
through `Jido.Exec.run(RunStrategy, ...)`. They use the real private Agent,
Session, Request, and ReqLLM HTTP/SSE path. The local `Jido.AI.Test.MockLLM`
supplies finite response scripts through its public model and option helpers.
No provider or runtime function is stubbed. No live provider is used.

- All seven callable IDs complete: `cod`, `cot`, `tot`, `got`, `trm`, `aot`,
  and `adaptive`. Tests check exact answers, usage, method and termination
  metadata, completed snapshots, and exact HTTP call counts. ToT retains ranked
  candidates and tree bounds; AoT retains its explicit answer and backtracking
  data. Plugin timeout and instruction defaults reach a successful call and
  the actual HTTP request.
- The tests read the private Agent's Profile through `Configuration.profile/2`
  and resolve its method through `Reasoning.select/2`. They require numeric
  model-call and iteration limits: 1 for linear methods and AoT, 802 for the
  tested ToT policy, 40 for default GoT, 3 for one TRM cycle, 15 for default
  TRM, and 10 for Adaptive's ReAct choice. Exact observed call counts must stay
  within these limits. This does not add new callable limit options.
- Default TRM completes all five cycles and 15 model calls. It returns the
  fifth improvement with `:max_steps`. A separate case stops after one cycle
  at `:act_threshold`. Adaptive selects CoD for a simple query, ReAct for a
  tool query, and TRM for an improvement query. It falls back to available CoT
  when ReAct is absent. A fallback to TRM also completes all five cycles;
  its budget is resolved after selection.
- Separate negative cases require AoT failure without an explicit answer,
  ToT evaluation failure, and TRM supervision failure. They check retained
  method data and completed usage. `Jido.Exec` retains the Action error
  envelope under `ExecutionFailureError.details.reason`. These cases cannot
  pass as recovered success.
- `test/support/callable_reasoning_case.ex` contains focused unit support.
  The response formats follow the reviewed example fixtures, but the tests
  do not call example helpers. An HTTP barrier holds the first request while
  public Agent APIs identify the private Agent and Session. Process monitors
  verify that both owners and provider work stop. The host has no remaining
  private Agents. Every script must have no unused responses, unexpected
  requests, or held requests. The tests use no sleeps or runtime observer hooks.

The `cc37525e` checkpoint changed tests and documentation only. It found no
method defect. The user then approved the Profile-bound migration. The current
implementation and added lifecycle/composition checks are recorded below.
Authoring and example suites remain deferred.

## Approved callable Profile implementation

The breaking contract in `callable-v3-contract.md` is implemented. The old flat
configuration API is removed. Profile is the only policy/default authority.

- `RunStrategy` accepts exactly one nonempty string under `:prompt` or `"prompt"`.
  It rejects duplicate key forms, unknown fields, missing input, and invalid
  values before startup, including direct `run/2`. It does not trim the string.
  Host context binds a resolved `%Profile{}` at `:jido_ai_callable_profile`.
  Missing bindings return `:reasoning_profile_not_bound`; invalid bindings return
  Profile validation errors. The ID stays unchanged. Session mode and one of the
  seven callable methods are required. Direct callable ReAct stays unsupported.
- Removed Action interfaces: `strategy`, `model`, `timeout`, `options`, all flat
  method/generation fields, the method-specific option allowlist, context/default
  lookup, `provided_params` precedence, and Plugin/state/Agent default lookup.
  No runtime or test helper translates the old API. Method-specific configuration
  remains available in canonical Profile fields. The count and timeout defaults
  now follow Profile; tests that need method-derived budgets select
  `:method_default` explicitly.
- All seven reasoning Plugins accept only `[profile: profile]`. Construction
  validates policy and the fixed method. Plugin state is an empty core-owned
  namespace. The old `strategy/default_model/timeout/options` state and the
  Plugin `into` copy are removed. The destination comes from `profile.result.into`.
  Core keeps the state boundary; two Plugins retain independent domain results.
  Failure preserves the previous state, and the domain schema checks the envelope.
- `RunCapability` reads core-prepared selected input. It applies retrieval to the
  validated prompt and trusted ModelRouting output to the selected Profile model
  role. It forwards quota explicitly before the private Session removes parent
  runtime context. Provider options stay under `context.ai[profile.id].options`.
  Named wrapper tools can bind Profiles in code. Raw callable tools use an explicit
  context field list. Model arguments cannot choose policy.
- The private Agent declares fresh result and optional history fields. Authoring
  rejects collisions. One deadline covers readiness, both admission waits, and
  await. Expired work is not admitted. Outer Exec enforces its own shorter limit.
  Cancel, snapshot, and graceful stop each use a separate 1,000 ms cleanup limit.
  A failed graceful stop unlinks and kills the server, then checks its monitor.
  This closes the suspended-server leak. Committed-success recovery is retained.
- Public success/error envelopes, method diagnostics, partial usage, ToT/AoT
  outputs, Adaptive selection/fallback, and the TRM 15-call budget are retained.
  All eight native reasoning methods and standalone ReAct APIs are unchanged.
  No generic framework, dependency change, or generated helper removal is included.

### Contract details from the core implementation

Core rejects caller-supplied `plugin_inputs` at the Agent command boundary.
`RunCapability` requires a prepared `Jido.Plugin.Input` with matching package and
owner. It does not add a token protocol to protect against arbitrary trusted
Elixir code that fabricates the complete runtime context. Plugin callback errors
at Agent construction use core's `Jido.Error.ExecutionError` wrapper; the cause
retains the Profile or configuration error. Direct binding errors retain their
Profile field paths.

Profile is validated before binding/startup and again by the existing Authoring
lowerer. Routing validates its changed model. This repeated validation is kept
for correctness; no validation bypass or second authoring entry point was added.
The internal `admission_deadline` option is used only by callable requests; native
requests without it keep their current admission timeout behavior.

### Selected callable coverage

The seven successful method tests and all selected unit consumers now use
canonical Profiles. Old precedence/default-container assertions are replaced by
strict rejection coverage. The shared callable fixture accepts Profile fields;
it has no general old-to-new translation helper.

New checks cover binding type and ID, atom/string input, duplicates, legacy keys,
missing values, nil/false, field error order, method restrictions, inert refs,
static context protection, fixed-method construction, forged Plugin input,
owned state, two results, retrieval, routing, quota, and provider options.
They also cover numeric model/iteration/tool/node limits, input controls, fresh
history, explicit context projection, nested callable execution, nested cancel,
timeout, caller death, concurrent calls, lost-await committed-success recovery,
one admission deadline, exhausted readiness, and suspended-server cleanup.
HTTP scripts remain finite and deterministic. No skips or ignored failures were
added. The success matrix still requires exact answers, usage, metadata, and
call counts. Native and standalone tests remain in the selected package run.

### Compile-only example changes and deferred work

The request explicitly defers example runtime repairs. `examples/AGENTS.md` was
read before edits. Four example source files needed minimal compile changes:

| File | Compile change | Deferred runtime repair |
| --- | --- | --- |
| `examples/08_planning/08_01_planning/agent.ex` | Bind a session CoT Profile in Plugin configuration. | Remove model/policy fields from reasoning Signals and update state/default assertions. |
| `examples/09_reasoning/09_14_callable_reasoning/agent.ex` | Generated `reason` arguments now contain only `prompt`. | Hosts must bind a Profile; migrate old strategy/options tests and helper calls. |
| `examples/16_capabilities/16_01_reasoning/agent.ex` | Bind CoT and CoD Profiles with separate result fields. | Migrate flat Signals and Plugin-default/state assertions. |
| `examples/16_capabilities/16_01_reasoning/mixed_agent.ex` | Bind the callable CoT Profile. Native configuration is unchanged. | Migrate callable Signals and provider options under the bound ID. |

`examples/13_policy/13_01_quota/reasoning_flow.ex` still compiles with its old
flat parameters. A compile probe confirmed this, so the source is unchanged. Its
runtime repair must remove `strategy` and bind a Profile from host context.
`examples/09_reasoning/09_16_reasoning_tool/agent.ex` still compiles unchanged,
but its context list must include `:jido_ai_callable_profile` and its callers must
bind that Profile. Its tool-call fixtures must send only prompt. The deferred
`test/examples/support/16_03_routing_policy_fixtures.ex` still builds the old
Plugin options at runtime; it needs a Profile binding. The selected unit support
has been migrated. No example test file or deferred support file was repaired.
The existing two strategy-inspection example repairs below also remain open.
Broader guides, API inventories, authoring tests, and example tests still need
migration and fresh verification before release.

## Profile model input validation

- `Profile.model_input/1` now rejects explicit `nil`, booleans, integers, and
  floats with `{:error, %Jido.AI.Error.Validation.Invalid{field: "models"}}`.
  The message remains `models: Invalid ReqLLM model input`. An omitted model
  still uses the normal default. The earlier callable API treated `nil` as an
  omitted option. The current callable API rejects flat model fields and
  validates its bound Profile, including explicit nil/false model values.
- Defect ownership: Profile owns the tagged policy validation boundary. Its
  fallback passed these unsupported values to the pinned ReqLLM's
  `model/1` fallback (`deps/req_llm/lib/req_llm.ex:367`). That fallback calls
  `Validation.Error.exception(message: ...)`, but the error type declares
  only `tag`, `reason`, and `context` (`deps/req_llm/lib/req_llm/error.ex:100`). This caused
  `KeyError` before Profile could return its validation error. The local fix
  rejects these values; it does not change provider code or catch all errors.
- Five regression tests cover scalar values, named model entries, validation
  order, the callable Action, inert atom aliases, registered string aliases,
  native string specifications, both tuple forms, inline maps, and
  `LLMDB.Model` values. The two initial rejection tests reproduced the crash
  before the fix. Callers now receive the existing tagged error for invalid
  scalar inputs. No valid model-input migration is required.

## Released V3 dependency check

On 2026-09-15, the Hex package and release APIs reported these latest V3 betas:

| Package | Latest V3 beta | Current requirement and lock |
| --- | --- | --- |
| [jido](https://hex.pm/api/packages/jido/releases/3.0.0-beta.1) | `3.0.0-beta.1` | Matches |
| [jido_action](https://hex.pm/api/packages/jido_action/releases/3.0.0-beta.11) | `3.0.0-beta.11` | Matches |
| [jido_signal](https://hex.pm/api/packages/jido_signal/releases/3.0.0-beta.4) | `3.0.0-beta.4` | Matches |

None is retired. Core's release metadata requires these Action and Signal
betas. There is no newer compatible V3 beta to install. `mix.exs`, `mix.lock`,
the ReqLLM Git pin, and unrelated dependencies are unchanged.

## Unit coverage and verification

The unit file selection is `test/jido_ai/**/*_test.exs`, excluding
`test/jido_ai/authoring/**`, plus `test/jido_ai_test.exs`. It includes the
deterministic runtime tests under `test/jido_ai/integration`. It does not
select `test/authoring` or `test/examples`. The existing `:flaky` exclusion
also excludes the live provider test.

Run from the package in zsh:

```sh
mix format --check-formatted
mix compile --force --warnings-as-errors
unit_tests=(${(f)"$(rg --files test/jido_ai test/jido_ai_test.exs -g '*_test.exs' -g '!test/jido_ai/authoring/**' | sort)"})
mix test "${unit_tests[@]}" --warnings-as-errors --seed 0
```

Foundation result: 151 files; 1,907 passed, 1 excluded; no failures or skips.
Format, compile, and `mix deps.get` passed. The first file filter was incorrect;
that run was stopped and is not verification evidence.

Removal result: 139 files; 1,794 passed, 1 excluded; no failures or skips.
Format and compile passed. Both completed test runs used seed 0 and warnings
as errors. The foundation run took 20.2 seconds; the removal run took 16.1 seconds.

Source organization result: 140 files; 1,795 passed, 1 excluded; no failures
or skips. The run took 18.1 seconds with seed 0 and warnings as errors.
`mix format --check-formatted` and
`mix compile --force --warnings-as-errors` passed. The added test is
`test/jido_ai/source_layout_test.exs`. Authoring and example suites were not
run. No example or existing unit test source changes were needed.

Model-call boundary result: 141 files; 1,810 passed, 1 excluded; no failures
or skips. The run took 18.7 seconds with seed 0 and warnings as errors.
`mix format --check-formatted` and
`mix compile --force --warnings-as-errors` passed. The existing flaky
exclusion is unchanged. All existing unit tests remain.

Strategy inspection removal result: 142 files; 1,820 passed, 1 excluded;
no failures or skips. The full selected run took 18.9 seconds with seed 0
and warnings as errors. `mix format --check-formatted` and
`mix compile --force --warnings-as-errors` passed; the forced dev compile
compiled 336 files. The existing flaky exclusion is unchanged. All previous
unit tests remain, and ten snapshot tests were added. The focused snapshot
run also passed all ten tests with seed 0 and warnings as errors.
Authoring and example suites were not run. Their compiled source and support
needed no repair. After the checks, safe `rmdir` removed the empty
`test/fixtures/skills` and `test/jido_ai/fixtures` directories left by tests.
There were no empty source directories.

Profile reference extraction result: 143 files; 1,832 passed, 1 excluded;
no failures or skips. The selected run took 20.7 seconds with seed 0 and
warnings as errors. `mix format --check-formatted` and
`mix compile --force --warnings-as-errors` passed; the forced dev compile
compiled 337 files. Twelve focused tests were added. The first eleven also
passed before and after extraction. The existing flaky exclusion is unchanged.
Source comparison confirmed that Profile only changes the resolver call and
removes the extracted group; the moved function bodies retain their behavior.
Authoring and example suites remain deferred. Dev/test compilation needed no
example source or support repairs. After verification, `rmdir` removed the two
empty test fixture directories listed above and 160 empty directories under
`tmp/`. No build, dependency, or Git directory was touched.

Scalar model validation result: 144 files; 1,837 passed, 1 excluded; no
failures or skips. The selected run took 17.8 seconds with seed 0 and warnings
as errors. Format and forced compile with warnings as errors passed; the dev
compile compiled 337 files. Five tests were added. Authoring and example
suites remain deferred; their compiled source and support needed no repair.

Callable validation result: 145 files; 1,844 passed, 1 excluded; no failures
or skips. The selected run took 17.9 seconds with seed 0 and warnings as
errors. Format and forced compile with warnings as errors passed; the dev
compile compiled 337 files. Seven tests were added. Authoring and example
suites remain deferred; their compiled source and support needed no repair.
After the checks, `rmdir` removed the two empty test fixture directories listed
above and 77 empty directories under `tmp/`. Build, dependency, and Git
directories were not touched.

Callable completion result: 145 files; 1,853 passed, 1 excluded; no failures
or skips. The selected run took 21.0 seconds with seed 0 and warnings as
errors. Format and forced compile with warnings as errors passed; the dev
compile compiled 337 files. The focused callable run passed all 20 tests in
3.3 seconds with seed 0 and warnings as errors. Nine tests were added, and the
existing matrix, defaults test, and fast completion test now require success.
The existing flaky exclusion is unchanged. Authoring and example suites were
not run or changed; their compiled source and support needed no repair.
After verification, `rmdir` removed the two empty test fixture directories
listed above and 75 empty directories under `tmp/`. No empty source directory
remained. Build, dependency, and Git directories were not touched.

Callable Profile migration result: 148 selected files; 1,886 passed, 1 excluded;
no failures or skips. This is 33 more selected tests than `cc37525e`. The final
run took 23.5 seconds with seed 0 and warnings as errors. The same selected run
also passed before the compile-only scope check. `mix format --check-formatted`
and `mix compile --force --warnings-as-errors` passed; the forced dev compile
compiled 337 files. The focused command
`mix test test/jido_ai/skills/reasoning/actions --warnings-as-errors --seed 0`
passed all 81 tests in 5.3 seconds. The existing flaky exclusion is unchanged.
Authoring and example suites were not run. After verification, `rmdir` removed
`test/jido_ai/fixtures`, `test/fixtures/skills`, and 75 empty directories under
`tmp/`. No empty source directory remained. Build, dependency, and Git
directories were not touched.

The 15 tests added at the model-call checkpoint cover default ReqLLM calls,
callback data and delegation,
explicit option precedence, quota admission and accounting, cancellation,
binding through Task callers, use after the binder owner exits, native request
isolation, explicit helpers outside the caller tree, and plain text inputs.
Existing tests retain script errors, token usage, tool loops, concurrent
callers with the same prompt, and checkpoint fingerprints.

The 112 CLI-only tests and their mock helper are deleted with the implementation.
The obsolete smoke wiring test is deleted. The existing native Chain-of-Draft
completion test now has `:stable_smoke`. It checks the request result, retained
status, method inspection, termination metadata, and Session cleanup. Supported
request, reasoning, standalone, Plugin, and task tests remain.

## Documentation and example repair inventory

This inventory records gaps at the unit-only checkpoints. The 2026-09-15 scope
above supersedes the earlier authoring and example deferral. Verify each repair
before marking it complete.

- Source links in `public-api-map.md`, `feature-map.md`, `implementation.md`,
  `provider-test-transfer.md`, `api-inventory.json`, `history-audit.json`,
  `history-reviews/*`, `docs/design/*`, and
  `docs/jido-ai-agent-dsl-kitchen-sink.md` still use old paths. Update current
  links in the documentation step. Preserve historical evidence and use the
  source map above to locate the current implementation.
- The CLI guide and its README, skills-guide, and ExDoc entries are removed.
  No current example source or test refers to a removed CLI module.
- `public-api-map.md`, `feature-map.md`, `api-inventory.json`,
  `root-package-checkpoint.md`, `history-audit.md`, `history-audit.json`, and
  `history-reviews/*` still contain CLI obligations or removed-file links.
  Update their current-status sections in a later documentation step. Preserve
  historical evidence. Their old CLI retention requirement no longer applies.
- Authoring and example suites are deferred. Existing Mix settings still
  compile example source and test support during dev/test builds. No example
  repair was needed for these changes. Earlier results in `status.md` are prior
  evidence, not a fresh run for this checkpoint.
- The model-call boundary required no authoring or example source repairs.
  Those suites remain deferred. Broader guide and API work remains below;
  no capability, strategy helper, or other public API was removed in that
  model-call checkpoint.
- Strategy inspection removal leaves exactly two example test files to migrate:
  - `test/examples/14_resume/14_11_initial_state/14_11_initial_state_test.exs`
    calls the removed Context helper at lines 43-45 and 101. Use
    `Configuration.profile/2` and `History.read/2` for imported prompt and entry
    assertions. Compare chronological maps and assert Agent/Profile IDs.
    Keep explicit `:review` selection and unrelated history assertions.
  - `test/examples/18_skills/18_01_skill_runtime/18_01_skill_runtime_test.exs`
    calls it in `entries/1` at line 34. Read the selected Profile's History.
    Review callers that expect reverse order or Context.Entry structs; preserve
    skill refs, durable entries, compaction, and request isolation assertions.

  There are no calls in `test/authoring`, `test/jido_ai/authoring`, example
  source, or compiled example support. No compile repair was required.
  These two files are unchanged and still need the migration before their
  suites can pass. Authoring and example suites remain deferred by request.

## Recommended remaining pieces

The bounded structural work is complete. Authoring and example repairs are
now approved. Keep further changes focused on simpler supported contracts.

1. The request-helper review is complete in `callable-v3-contract.md`.
   Keep `ask_sync` for answers, `ask` plus Request APIs for lifecycle control,
   and `ask_stream` for events. Core `define` returns an Agent and does not
   replace these contracts. Removing the generated `await` and `steer` aliases
   remains an optional API decision, not a required runtime change.
2. The callable Profile migration and consumer repairs are complete and tested.
   Keep Plugin composition and all reasoning methods.
3. Orchestration.Coordinator was also reviewed. It coordinates jobs, recovery,
   completion commits, input queues, and observed events. Keep those process
   and commit boundaries together for now; no Runtime extraction is included
   in this recommendation. `jido_ai` owns `Jido.Session` and `Jido.Thread`;
   keep them in this package.
4. Current API inventories are reconciled. The public API and feature maps now
   describe current source and ownership. Their old logs and the byte-identical
   V2 JSON inventory remain separate historical evidence. The current JSON
   indexes all 250 library files, with a generator and unit drift/link checks.
   Reconciliation verification: 2,861 tests passed, 1 existing exclusion, no
   failures or skips, authoring/examples included, seed 0, warnings as errors,
   125.0 seconds. Format, forced compile, and generator drift checks passed.
   Remaining package guides, release metadata, fresh coverage, and live-provider
   verification are separate release work.
