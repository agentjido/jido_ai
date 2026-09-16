# V3 callable reasoning contract

Status: approved and implemented on `v3-spike`, after `cc37525e`.
The user approved the breaking callable input and Plugin configuration changes.
Read with `docs/v3-spike/simplification.md`. Paths are repository-relative.

## Public contract

Use `Jido.AI.Agent` + DSL + `Jido.AI.Profile` for authoring and native AI routes for application
requests. Keep `Actions.Reasoning.RunStrategy` for isolated, finite Action/tool/Flow calls. Bind one
Profile; remove configuration from input data.

```elixir
Zoi.object(%{prompt: Zoi.string() |> Zoi.min(1)},
  coerce: true, unrecognized_keys: :error)
```

Accept one nonempty string under `:prompt` or JSON key `"prompt"`. Before work, reject duplicate key
forms, unknown fields, and missing/invalid input, including direct `run/2` calls. Do not trim or
convert the prompt. Bind `%Profile{}` at the host-context key `:jido_ai_callable_profile`:

```elixir
profile = Jido.AI.Agent.profile(MyAgent, :review)
Jido.Exec.run(Jido.AI.Actions.Reasoning.RunStrategy, %{prompt: "Review this"},
  %{jido_ai_callable_profile: profile}, timeout: 65_000)
```

Require a supported callable method, `result.into`. Missing binding
returns `{:error, :reasoning_profile_not_bound}`; invalid binding returns a Profile validation
error. Keep the Profile ID unchanged. Use `Agent.profile/2` for declared policy, or
`Configuration.profile(agent, id)` for committed overrides. The host selects an explicit ID and
freezes one value for the call. Do not search caller state for defaults.

## Tool and Plugin boundaries

Expose a named Action or Flow with the prompt schema; its trusted code binds a fixed Profile. A raw
RunStrategy tool can receive that binding through an explicit `forward_context` field list. Do not
put the binding in Signal data, tool arguments, or static `tool_context`. The `jido_ai_` prefix has
protection in `lib/jido_ai/tool_context.ex`. Models must not select Profile IDs, models, provider
options, limits, tools, or policy through parameters. Hosts can expose several named bound tools.
Adaptive uses its bound policy.

Keep the seven `Plugins.Reasoning.*` modules as small, fixed-method bindings for core Agent
composition. Their configuration is `[profile: profile]` only. Validate the Profile/method
at Agent construction. Keep explicit routes and core ownership. `RunCapability` requires the
selected prepared Plugin input; arbitrary caller context cannot forge that input. Use
`profile.result.into` as the host destination; remove the Plugin `into` copy. On success, replace
only that declared domain field with the result envelope and return complete domain state. Failure
preserves prior state. The field must accept the envelope; native routes store raw output. Preserve
Plugin state and independent results for multiple capabilities.

Retrieval can supply prompt content. ModelRouting applies its trusted choice to the Profile model
role and validates it; it must not insert a flat model parameter. Keep Profile routers, quota scope,
effect controls, and explicit context projection. Provider call options remain host-only at
`context.ai[profile.id].options`. Use `Session.caller_context/1` before private admission; forward
quota explicitly. Do not copy parent request/state/event bindings or the callable binding into child
tools.

## Defaults, methods, and migration

Profile is the only default and validation authority. Keep its current defaults: configured
`agent_defaults.model` or `:fast`, configured instructions or nil; limits 8 iterations, 12 model
calls, 16 tool calls, and 60,000 ms; requests reject busy work, retain 100 records,
streaming/steering false; tools empty, no history, no result schema, and zero repairs. ID and result
field are required. Explicitly select the method; do not rewrite the host Profile. Keep
method option/generation defaults from `lib/jido_ai/reasoning.ex` and its validators.

| Old callable input/configuration | Profile replacement |
| --- | --- |
| `strategy: :cot / :cod / :aot` | `reasoning.method: :chain_of_thought / :chain_of_draft / :algorithm_of_thoughts` |
| `strategy: :tot / :got / :trm / :adaptive` | `reasoning.method: :tree_of_thoughts / :graph_of_thoughts / :trm / :adaptive` |
| `model`, Plugin/context `default_model` | `models[role].model`, selected by `reasoning.model` |
| `timeout`, context timeout | `controls.timeout`; Exec/tool timeout remains an outer execution limit |
| `system_prompt`, `llm_timeout_ms` | `instructions`, `models[role].timeout` |
| `request_policy` | Removed; all Agent requests reject concurrent work with `:busy` |
| `temperature`, `max_tokens` | `models[role].temperature`, `models[role].max_tokens` |
| `branching_factor`, `max_depth`, `traversal_strategy`, `generation_prompt`, `evaluation_prompt` | Applicable `reasoning.options` fields |
| `max_nodes`, `aggregation_strategy`, `connection_prompt`, `aggregation_prompt` | Applicable `reasoning.options` fields |
| `max_supervision_steps`, `act_threshold` | TRM `reasoning.options` fields |
| AoT `profile`, `search_style`, `examples`, `require_explicit_answer` | AoT `reasoning.options` fields; `profile` here means the in-context example preset |
| `available_strategies`, `complexity_thresholds` | Adaptive `reasoning.options` fields |
| Action/context/Plugin `options`, `provided_params`, `reasoning_*` defaults | Remove containers and precedence rules; migrate each recognized value to its Profile field |
| Plugin `into` | `result.into` |

To retain old callable behavior, explicitly set timeout 30,000, streaming true, and all three count
limits to `:method_default`. Set model `:reasoning` for old Plugin defaults; direct calls previously
used `:fast`. Explicit numeric limits win. Resolve method defaults after Adaptive selection,
including fallback. Generic 8/12 limits can stop TRM before five cycles; preserve its 15-call budget
on migration. Keep ToT bounds, parser retries, tool rounds, and output repair budgets.

Unknown Profile keys now fail instead of being ignored by the callable key list. ToT `max_nodes` and
count limits previously ignored by that list now work at their Profile paths. Nil/false, generation
validation, and error order follow Profile rules; old nil fallback and top-level-over-nested
precedence are removed. These are breaking behavior changes. All configuration remains available to
hosts; model-directed policy changes are intentionally removed. Removing methods, rich results, or
execution controls would be capability loss, not safe simplification. Keep seven callable methods.
Direct callable ReAct stays unsupported; native `reasoning: :react` and standalone `Reasoning.ReAct`
remain supported. Keep ReAct run/stream/start/continue/collect/cancel, State, Config, and Token
APIs. Adaptive can still select ReAct. Preserve method tool/schema restrictions in Profile.

## Results, lifetime, and reference handling

Keep `{:ok, %{strategy: short_id, status: status, output: term, usage: map, diagnostics: map}}` and
the same envelope under `{:error, envelope}` after execution. `status` is the last snapshot status
(`:success`, `:failure`, or `:running`); the tuple states the call outcome. Preserve ToT/AoT
structured outputs, partial usage, method diagnostics, and sanitized errors. Validation and startup
failures remain `{:error, reason}`; Profile errors retain their structured field paths. Do not
serialize the bound Profile or provider options into diagnostics.

Keep one linked private Agent/Session per call, no global runner, and guaranteed cleanup on success,
failure, timeout, caller death, and outer Exec cancellation. Use one deadline for readiness,
admission, and await, bounded by Profile and outer execution limits; do not restart the full timeout
for each wait. Cancel before teardown on timeout. Keep committed-success race recovery and
concurrent isolation. Private result/history fields start fresh and end with the call. Do not merge
them into the parent. Use native sessions for retained history and lifecycle access.

Validate static Plugin Profiles before startup; runtime hosts validate before binding. Explicit refs
resolve through `Profile.new/2` and `profile/references.ex`. RunStrategy accepts the resolved value,
not registry names or selector callbacks. Construction performs no model/tool/router/control
execution. Atom model aliases resolve at request start; native model specs can be checked during
construction. Use an already compiled definition or construct the shared Profile before binding; do
not call a generated accessor on the module still being compiled.

## Request helpers and implementation order

`agent/interface.ex` makes `ask` return a Request Handle for every Profile; `ask_sync` waits for the answer; `ask_stream` returns `%{request: handle, events: enumerable}`
and checks streaming permission. Core `define` calls return `{:ok, committed_agent}`; its Signal
helpers only build Signals (`deps/jido/lib/jido/agent/interface.ex`,
`deps/jido/lib/jido/agent/dsl/generator.ex`). Use `ask_sync` as the main answer path, `ask` plus
`Request.await` for session control, and `ask_stream` for events. Keep all three; none duplicates
`define`. Generated `await` and `steer` are exact Request/root delegates; only remove these aliases
after checking callers and overrides. Generated cancel casts, whereas `Session.cancel(handle)`
confirms via a call. Keep both lifecycle semantics. Wait timeout does not cancel native work. Do not
remove Request/Session APIs.

1. Approval is complete. The implementation removes the old callable configuration API.
2. Implement binding/validation. Test strict input, inert refs, unknown IDs, fixed methods, legacy field paths, nil/false, and compile/runtime errors.
3. Migrate Plugins/tools. Test forged input, domain ownership, two capabilities, retrieval/routing, quota, provider options, and nested cancellation.
4. Require seven successful methods, Adaptive fallback, TRM 15 calls, ToT/AoT failure data, explicit limits, timeout cleanup, and concurrent calls.
5. Keep helper return/stream/cancel tests. Run bounded package gates and migrate callable consumers before removal. The selected unit matrix requires success for all seven callable methods.

Source evidence: `actions/reasoning/{run_strategy,run_capability}.ex`, `reasoning_capability.ex`,
`capability.ex`, `plugins/reasoning/*.ex`, `profile.ex`, `authoring.ex`,
`agent/{definition,interface}.ex`, `session.ex`, and `runtime/{prepare,tool_attempt}.ex`, all under
`lib/jido_ai/`. Consumers: examples 08_01, 09_14, 09_16, 13_01, 16_01 and the 16_03 routing fixture.
Tests: `test/jido_ai/skills/reasoning/actions/run_strategy_{action,profile}_test.exs`,
`test/jido_ai/plugins/reasoning/*_test.exs`, schema/Plugin-facet tests. Stronger success/lifecycle
fixtures: `test/examples/09_reasoning/` (09_14, 09_16),
`test/examples/16_capabilities/16_01_reasoning/`, and `test/authoring/agents/interfaces_test.exs`;
those suites were deferred during implementation. Their migration and execution
are now in scope (2026-09-15).

## Implementation notes

- `RunStrategy` validates its input before binding or startup. It keeps the Profile
  ID and creates fresh result and optional history fields. Authoring rejects a
  history/result collision. It still checks the Profile when it lowers the Agent.
- Reasoning Plugins keep an empty core-owned state namespace. Their Profile stays
  in configuration and selected prepared input. They no longer store policy
  defaults or a second result destination in Plugin state.
- Core rejects caller `plugin_inputs` before preparation. `RunCapability` reads
  the selected `%Jido.Plugin.Input{}` and verifies that the package and owner
  match. This uses the core trust boundary; it is not an unforgeable token for
  arbitrary direct Elixir calls with fabricated runtime structures.
- `Session.submit/4` accepts an internal admission deadline. Callable readiness,
  both admission calls, and await use the time left on one deadline. Outer Exec
  limits remain enforced by Exec's process owner; core does not expose that
  deadline as Action context. Cleanup has a separate short allowance: cancel,
  snapshot, and graceful stop each have a 1,000 ms limit. A failed graceful stop
  unlinks and kills the private server, then waits up to 1,000 ms for its monitor.
- Named model roles, host provider options, Profile routers, tool context,
  controls, result schemas, quota, and method limits use the existing runtime.
  The selected unit tests cover nested callable tools and parent cancellation.
- Authoring/example suites were deferred at this implementation checkpoint.
  Their migration and execution are now in scope. See `simplification.md` for
  the earlier compile-only changes and test results; these are historical evidence.
- `jido_ai` owns `Jido.Session`, `Jido.Thread`, and `Jido.Thread.Entry`.
  Keep these value modules in this package with their existing names.
