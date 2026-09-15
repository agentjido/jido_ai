# V3 AI simplification

Use `Jido.AI.Agent` + `Jido.AI.DSL` + `Jido.AI.Profile` as the main AI
authoring model. Keep each change small and commit each verified step.
This record covers `jido_ai` on `v3-spike` only.

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
5. This checkpoint removes the root strategy inspection helpers. Session
   inspection reads the selected Profile and committed History. Snapshot
   fields and request execution remain the same.

## Inventory and caller evidence

Source paths below are relative to `lib/jido_ai/` unless they start with
`lib/` or `examples/`. Proposed work is not part of this checkpoint.

| Decision | Surface | Caller evidence and scope |
| --- | --- | --- |
| Keep | `Jido.AI.Agent`, DSL, Profile | `agent/definition.ex` installs the DSL and request helpers. `dsl.ex` lowers declarations through `Authoring` and Profile. This is the main authoring path. |
| Keep | `Authoring.lower/2`, Portable, Codec | DSL, import/export, `RunStrategy`, and standalone ReAct use these paths. They share Profile validation; they are not CLI-only builders. |
| Keep | Request, Session, runtime Plugins | `agent/interface.ex` submits requests and waits for results. `session/inspection.ex` builds the public snapshot. Request, stream, cancellation, and reasoning unit tests cover these paths. |
| Separate; complete | Test script selection and model calls | `Test.ReActScript` owns script options, prompt matching, errors, and HTTP replies. Request and ReAct.Runner capture generic call options before they start work in another process. Runtime.ModelCall uses ReqLLM by default. |
| Keep | Eight reasoning methods and their data APIs | `reasoning.ex` dispatches Profile methods. `reasoning/*` parsers, machines, results, and inspection helpers serve the native runtime and method tests. Removing a CLI adapter does not remove its method. |
| Keep | Standalone ReAct Config, State, Token, Runner and Actions | `reasoning/react.ex` provides run, stream, resume, collect, and cancel. `reasoning/react/authoring.ex` lowers Config to a native Agent. `examples/14_resume` and ReAct unit tests call these APIs. |
| Keep | Capability Plugins, planning, retrieval, quota, skills | `plugins/*` supplies core Agent composition. Examples in groups 07, 08, 13, 16, and 18 use it. `RunStrategy` is also a callable tool in 09_14 and 09_16. |
| Keep; ownership unresolved | Session/Thread values and AI Context | This `jido_ai` repository defines `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry`. They were in `lib/jido_session.ex` and `lib/jido_thread.ex`; they now use `lib/jido/session.ex`, `lib/jido/thread.ex`, and `lib/jido/thread/entry.ex`. The prior claim that core Jido owns the current code was incorrect. Intended package ownership remains unresolved. AI history, initial-state conversion, and unit tests use these values. No module moves to another repository and no value API is removed here. |
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
- All 266 top-level module bodies match the prior source after removal of
  whitespace between modules. No function implementation, module name, or
  contract changed. Profile and Session.Runtime internals are unchanged.
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
| Running Agent inspection | `Jido.AI.Session.snapshot(server, request_id: id)` returns `details.config` and `details.conversation`. Omit `request_id` for the normal selection. |
| Committed history for one profile | Select the Profile, then call `Jido.AI.History.read(agent.state, profile)`. The result contains chronological entry maps. The system prompt is `profile.instructions`. |
| Old Context entry comparison | Compare History entries with `context.entries \|> Enum.reverse() \|> Enum.map(&Map.from_struct/1)`. History returns maps, not Context.Entry structs. |
| Synthetic Context identity | Assert the Agent ID and selected Profile ID. The removed helper's `agent_id:profile_id` Context ID is no longer an inspection contract. |

The affected unit files retain their runtime and state assertions:

- `test/jido_ai/operations/initial_state_test.exs`
- `test/jido_ai/strategy/react_test.exs`
- `test/jido_ai/strategy/stateops_integration_test.exs`
- `test/jido_ai/integration/react_context_lifecycle_integration_test.exs`

`test/jido_ai/session/inspection_test.exs` adds ten snapshot tests. They cover
nil, empty, and saved prompts before the first request; absent history;
no profiles; method and generation fields; default and explicit profile
selection; current overrides during active work; retained request selection;
and imported content parts, tool messages, refs, and context lane switches.
Existing tests still cover pending tools, stream text, cancellation, failure,
recovery, deferred context replacement, checkpoints, and trace truncation.

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

## Deferred documentation and example work

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

1. **Next: extract Profile reference resolution.** Move the private
   `resolve_references/2` group in `profile.ex` (currently lines 221-444) to
   an internal `Jido.AI.Profile.References` module with one `resolve/2`
   entry point. This group resolves explicit registry references for
   instructions, tools, schemas, repair Actions, model routers, and controls.
   It also separates tool-source inputs. Its only entry caller is Profile
   construction. Keep defaults, canonical validation, schema construction,
   and public errors in Profile. Preserve map and Codec.Registry behavior.
   This separates input reference resolution from policy validation with a
   bounded, inert contract. No new provider, process, or public root API is
   needed. This recommendation is not implemented here.
2. Review generated Agent request helpers against route `define` helpers.
   Choose one normal calling form. Keep request admission, stream, and cancel
   behavior covered before removing any helper.
3. Review capability and callable-reasoning defaults against Profile fields.
   Remove duplicate option translation only where callers can use the shared
   validation. Keep Plugin composition and all reasoning methods.
4. Session.Runtime was also reviewed. It coordinates jobs, recovery,
   completion commits, input queues, and observed events. Keep those process
   and commit boundaries together for now; no Runtime extraction is included
   in this recommendation. Resolve the intended ownership
   of `Jido.Session` and `Jido.Thread` before any package transfer.
5. Reconcile current guides and API inventories. Run the deferred authoring
   and example suites after the API decisions are complete.
