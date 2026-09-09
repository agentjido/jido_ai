# Root package checkpoint — 2026-09-07

The root Mix project now uses local Jido v3, Action beta and Signal beta.
Every production source file remains under `lib`. The acceptance project now
uses the root package as a path dependency. It compiles only its examples and
a compatibility entry for the shared MockLLM. The server implementation now
lives in `lib/jido_ai/test/mock_llm.ex`. No production directories are excluded.

| Checkpoint | Result |
| --- | --- |
| 1. Full production compile, warnings as errors | Passed; 231 files |
| 2. Complete root test result | First: 1,763/2,418 passed; 655 failed. Latest: 2,070/2,430 passed; 360 failed. One existing exclusion in each run |
| 3. Root behavior and acceptance on the same package | Latest: 1,192/1,196 passed in 159.1 seconds; four ReqLLM usage failures. The prior core shutdown timing failure remains in the dependency record. Root fixes are in progress |
| Retained Directive, reasoning Action and task supervisor checks | 87 passed |
| Fresh-VM checkpoint checks after application warmup fix | 17 passed |

The first full acceptance run passed 1,120 of 1,121 cases. The fresh-VM script
needed to load the root application's modules before safe ETF decoding. The
script now includes `:jido_ai`; the targeted and full repeat runs pass.

The first complete root run used `mix test --seed 0` and finished in 19.9
seconds. It passed all four doctests and 1,759 of 2,414 ordinary tests. It
reported 655 failures and one existing `:flaky` exclusion. No new exclusions
were added. Earlier runs stopped during compilation and are not full results.

Task-list updates now use native Agent state and tool-result effects. Weather
examples use request transforms. Fixture schemas, model inputs, Agent fields
and Instruction targets now allow the complete suite to compile. Old StateOp
assertions keep their type and field checks as match patterns. They fail at
runtime until their behavior moves to the v3 API; no removed core structs were
recreated and no tests were skipped to produce the count.

The largest failure groups use removed Strategy callbacks, old Plugin mount
callbacks, tuple-returning Agent constructors, and obsolete fake-server
messages. The run also found a real public test-helper defect: registered
scripts could fall through to a provider. The fix binds scripts before runtime startup and uses the shared HTTP/SSE
mock for their model calls. Script storage is local to the calling process;
Task callers can inherit it through their caller chain. It no longer uses
a shared group-leader registry. Model tasks own mock-server cleanup. Binding
does not change the standalone checkpoint configuration fingerprint.

### Second checkpoint

The complete repeat root run finished in 26.8 seconds: 1,814/2,425 passed,
611 failed and one excluded. It retains every prior root case and adds seven
regression tests. This fixes 44 first-run failures. All four doctests pass.
The remaining failures are still required migration work.

- Request transport, tool API and public script helpers: 49 passed.
- Native task-list/weather examples with request/helper checks: 43 passed.
- Agent authoring checks now use the native definition, profile and constructor.
  Old lifecycle and skill-state callers remain in the failure inventory.
- The test helper uses the same HTTP/SSE server as acceptance. Its new cases
  cover token usage, concurrent caller isolation, checkpoint fingerprints and
  server cleanup. Text/tool scripts still use real ReqLLM and tools.
- The shared mock move first exposed six acceptance failures: five option-shape
  cases and one child-spec identity case. Both causes were corrected. All 63
  affected acceptance checks pass. The complete repeat run passes all 1,121
  cases in 148.6 seconds, with integration and pending-DSL tags included.
- The task-list test follows add/start/complete calls and reads committed tasks
  in a later request. Weather tests check reuse within one request, a fresh
  fetch in the next request, and error propagation.

The forced root compile passes for all 229 files. Selected formatting and
`git diff --check` pass. The API baseline SHA-256 remains
`032d8b1e3bb8d69def2f1d2451d5c8e0aa2d886fcadfd6b540617460b8812357`.

Core advanced independently to `9add32f4` and has uncommitted default-instance
helper additions in `lib/jido.ex`, with related tests and guides. The final AI
checks use that working checkout. This task did not edit it. These changes and
the existing core test failures remain part of the dependency release gate.
The observed SHA-256 of core `lib/jido.ex` is
`b9480777357c258e5e439905f406b4e32f91193edd2724df245a269ecf1add3f`.

Logs: `/tmp/jido-ai-v3-root-test-18.log`,
`/tmp/jido-ai-v3-root-compile-checkpoint-02.log`,
`/tmp/jido-ai-v3-root-request-fixture-test-03.log`,
`/tmp/jido-ai-v3-root-native-example-test-02.log`, and
`/tmp/jido-ai-v3-acceptance-root-shared-mock-final.log`.

### Third checkpoint: CoT, CoD and AoT

All 70 cases in six retained root files now use native Agent, Action, Flow and
Session boundaries. The root case count is unchanged. Every old case has a
replacement in the [CoT/CoD map](linear-test-transfer.md) or
[AoT map](aot-test-transfer.md). Test names were checked against the pinned HEAD
baseline. The files use the same HTTP/SSE mock as the integration examples.

The first CoT/CoD run exposed a missing complete-content-part callback. Model
image bytes reached ReqLLM but were absent from caller events. The shared model
operation now emits those parts. Session inspection keeps them in the trace
without joining them as text. Two new integration examples prove CoT and CoD
image streams, event identity, typed Signal delivery, and stored rich results.
This preserves part of PR 340's generated-media contract. The full history
case remains open for its other variants.

| Check | Result |
| --- | --- |
| CoT and CoD root cases | 52 passed in 6.6 seconds |
| AoT root cases | 18 passed in 2.5 seconds |
| Complete root suite | 1,867/2,425 passed in 22.2 seconds; 558 failed; one existing exclusion |
| Complete v3 example suite | 1,123 passed in 141.7 seconds; integration and pending-DSL tags included |
| Forced full production compile, warnings as errors | 229 files passed |

Compared with the second checkpoint, 53 failed cases now pass. The failure
inventory has no new failing case. All four doctests pass. Remaining failures
still include the other Strategy callers, old StateOp helpers, old Plugin and
lifecycle callers, and standalone runner cases. Their behavior transfer remains
required; the migration is not complete.

Core independently committed its helper additions as `77966b1a` and is clean.
The root and acceptance builds both compiled that revision. The observed
`lib/jido.ex` SHA-256 is
`ea2f9f5853d025b6bfa9ff2da144d37240990df3f47df3adf71a4448da40dce9`.
This task did not edit core. Its previously recorded full-suite failures remain
an open dependency gate. No new core full-suite result is claimed.

Logs: `/tmp/jido-ai-v3-linear-root-test-03.log`,
`/tmp/jido-ai-v3-aot-root-test-01.log`, `/tmp/jido-ai-v3-root-test-20.log`,
`/tmp/jido-ai-v3-root-compile-checkpoint-04.log`, and
`/tmp/jido-ai-v3-acceptance-linear-transfer.log`.
The latest failure data is `/tmp/jido-ai-v3-root-checkpoint-03-failures.json`.

### Fourth checkpoint: StateOp behavior transfer

The two old state test files had 76 failing cases. They now contain 39 native
cases: 25 candidate-state checks and 14 live Agent checks. Repeated checks of
removed struct names were consolidated. The root count therefore falls by 37.
This is not a claim that 76 separate tests passed. Every old case is mapped in
the [state transfer table](state-test-transfer.md) and its
[structured map](state-test-transfer.json).

The candidate cases check field and nested changes, explicit absent paths,
list order, deletion, reset, value types, composition, conflicts, immutability,
schema failure and Plugin protection. Live cases use the shared HTTP/SSE mock
for request state, iteration, pending tool IDs, text accumulation, usage reset,
configuration views, tool execution, history, cancellation and state commit.
No new runtime or StateOp compatibility implementation was added.

The first run passed 35/38. It found a real ReAct completion metadata gap and
two test-input errors. Successful ReAct completion now stores `:final_answer`
when no method or limit supplied a reason. Four added metadata integration
cases check streamed/non-streamed calls, with/without a tool round. Existing
limit and method cases retain their reasons. The state coverage review added
an absent nested-path case. All 39 state cases pass.

| Check | Result |
| --- | --- |
| Final state transfer group | 39 passed in 3.0 seconds |
| Complete root suite | 1,906/2,388 passed in 23.2 seconds; 482 failed; one existing exclusion |
| Complete v3 example suite | 1,127 passed in 143.4 seconds; integration and pending-DSL tags included |
| Forced full production compile, warnings as errors | 229 files passed |
| Formatting and whitespace checks | Passed for the changed code |

The new failure inventory contains no additional failing case. The 76 removed
entries are exactly the two transferred files. All four doctests still pass.
Remaining groups include ReAct, TRM, Adaptive, ToT, GoT, standalone runner,
Plugin, lifecycle and direct Action callers. Their remaining behavior and
release gates are still required.

Core advanced independently to `ca3cebea`, which changes documentation only.
Its production `lib` tree is unchanged from `77966b1a`:
`06fe6e5ce1582ea2dde4f0f603307b0422dbb448`. The core checkout is clean.
This pass did not change core or rerun its full suite. The dependency gate
remains open. The AI API baseline and all history source-review fields are
unchanged. No history row was closed.

Logs: `/tmp/jido-ai-v3-state-transfer-test-03.log`,
`/tmp/jido-ai-v3-root-test-22.log`,
`/tmp/jido-ai-v3-root-compile-checkpoint-05.log`, and
`/tmp/jido-ai-v3-acceptance-state-transfer.log`.
Latest failure data: `/tmp/jido-ai-v3-root-checkpoint-04-failures.json`.

### First root failure inventory

These are failing test counts by file, not estimates of missing features.
Several old files check the same behavior through removed APIs. Transfer each
behavior before replacing its old check.

| File | Failed tests |
| --- | ---: |
| [test/jido_ai/strategy/react_test.exs](../../test/jido_ai/strategy/react_test.exs) | 78 |
| [test/jido_ai/strategy/state_ops_helpers_test.exs](../../test/jido_ai/strategy/state_ops_helpers_test.exs) | 42 |
| [test/jido_ai/strategy/trm_test.exs](../../test/jido_ai/strategy/trm_test.exs) | 41 |
| [test/jido_ai/react/runtime_runner_test.exs](../../test/jido_ai/react/runtime_runner_test.exs) | 41 |
| [test/jido_ai/strategy/adaptive_test.exs](../../test/jido_ai/strategy/adaptive_test.exs) | 37 |
| [test/jido_ai/strategy/tree_of_thoughts_test.exs](../../test/jido_ai/strategy/tree_of_thoughts_test.exs) | 37 |
| [test/jido_ai/strategy/stateops_integration_test.exs](../../test/jido_ai/strategy/stateops_integration_test.exs) | 34 |
| [test/jido_ai/agent_test.exs](../../test/jido_ai/agent_test.exs) | 30 |
| [test/jido_ai/strategy/graph_of_thoughts_test.exs](../../test/jido_ai/strategy/graph_of_thoughts_test.exs) | 29 |
| [test/jido_ai/integration/strategies_phase4_test.exs](../../test/jido_ai/integration/strategies_phase4_test.exs) | 26 |
| [test/jido_ai/strategy/chain_of_thought_test.exs](../../test/jido_ai/strategy/chain_of_thought_test.exs) | 25 |
| [test/jido_ai/integration/request_lifecycle_parity_test.exs](../../test/jido_ai/integration/request_lifecycle_parity_test.exs) | 19 |
| [test/jido_ai/integration/trm_phase4b_test.exs](../../test/jido_ai/integration/trm_phase4b_test.exs) | 19 |
| [test/jido_ai/executor_test.exs](../../test/jido_ai/executor_test.exs) | 13 |
| [test/jido_ai/integration/jido_v2_migration_test.exs](../../test/jido_ai/integration/jido_v2_migration_test.exs) | 12 |
| [test/jido_ai/strategy/algorithm_of_thoughts_test.exs](../../test/jido_ai/strategy/algorithm_of_thoughts_test.exs) | 11 |
| [test/jido_ai/tot_agent_test.exs](../../test/jido_ai/tot_agent_test.exs) | 11 |
| [test/jido_ai/skills/lifecycle_integration_test.exs](../../test/jido_ai/skills/lifecycle_integration_test.exs) | 11 |
| [test/jido_ai/skills/llm/llm_skill_test.exs](../../test/jido_ai/skills/llm/llm_skill_test.exs) | 10 |
| [test/jido_ai/adaptive_agent_test.exs](../../test/jido_ai/adaptive_agent_test.exs) | 8 |
| [test/jido_ai/skills/tool_calling/tool_calling_skill_test.exs](../../test/jido_ai/skills/tool_calling/tool_calling_skill_test.exs) | 8 |
| [test/jido_ai/integration/tools_phase2_test.exs](../../test/jido_ai/integration/tools_phase2_test.exs) | 7 |
| [test/jido_ai/cot_agent_test.exs](../../test/jido_ai/cot_agent_test.exs) | 6 |
| [test/jido_ai/got_agent_test.exs](../../test/jido_ai/got_agent_test.exs) | 6 |
| [test/jido_ai/request_test.exs](../../test/jido_ai/request_test.exs) | 6 |
| [test/jido_ai/strategy/chain_of_draft_test.exs](../../test/jido_ai/strategy/chain_of_draft_test.exs) | 6 |
| [test/jido_ai/integration/strategy_module_action_fallback_test.exs](../../test/jido_ai/integration/strategy_module_action_fallback_test.exs) | 6 |
| [test/jido_ai/jido_ai_core_test.exs](../../test/jido_ai/jido_ai_core_test.exs) | 6 |
| [test/jido_ai/test_helpers_test.exs](../../test/jido_ai/test_helpers_test.exs) | 6 |
| [test/jido_ai/tool_api_test.exs](../../test/jido_ai/tool_api_test.exs) | 5 |
| [test/jido_ai/checkpoint_test.exs](../../test/jido_ai/checkpoint_test.exs) | 5 |
| [test/jido_ai/integration/react_incomplete_response_test.exs](../../test/jido_ai/integration/react_incomplete_response_test.exs) | 5 |
| [test/jido_ai/integration/request_await_rejection_test.exs](../../test/jido_ai/integration/request_await_rejection_test.exs) | 5 |
| [test/jido_ai/skills/reasoning/reasoning_skill_test.exs](../../test/jido_ai/skills/reasoning/reasoning_skill_test.exs) | 4 |
| [test/jido_ai/skills/llm/actions/embed_action_test.exs](../../test/jido_ai/skills/llm/actions/embed_action_test.exs) | 4 |
| [test/jido_ai/integration/skills_phase5_test.exs](../../test/jido_ai/integration/skills_phase5_test.exs) | 4 |
| [test/jido_ai/aot_agent_test.exs](../../test/jido_ai/aot_agent_test.exs) | 3 |
| [test/jido_ai/reasoning/helpers_test.exs](../../test/jido_ai/reasoning/helpers_test.exs) | 3 |
| [test/jido_ai_test.exs](../../test/jido_ai_test.exs) | 3 |
| [test/jido_ai/cli/adapters/react_test.exs](../../test/jido_ai/cli/adapters/react_test.exs) | 2 |
| [test/jido_ai/react_agent_test.exs](../../test/jido_ai/react_agent_test.exs) | 2 |
| [test/jido_ai/reasoning/request_lifecycle_test.exs](../../test/jido_ai/reasoning/request_lifecycle_test.exs) | 2 |
| [test/jido_ai/cod_agent_test.exs](../../test/jido_ai/cod_agent_test.exs) | 2 |
| [test/jido_ai/skills/tool_calling/actions/call_with_tools_test.exs](../../test/jido_ai/skills/tool_calling/actions/call_with_tools_test.exs) | 2 |
| [test/jido_ai/trm_agent_test.exs](../../test/jido_ai/trm_agent_test.exs) | 2 |
| [test/jido_ai/examples/weather_agent_test.exs](../../test/jido_ai/examples/weather_agent_test.exs) | 2 |
| [test/jido_ai/skills/reasoning/actions/run_strategy_action_test.exs](../../test/jido_ai/skills/reasoning/actions/run_strategy_action_test.exs) | 2 |
| [test/jido_ai/integration/raw_error_propagation_test.exs](../../test/jido_ai/integration/raw_error_propagation_test.exs) | 1 |
| [test/jido_ai/skills/tool_calling/actions/list_tools_test.exs](../../test/jido_ai/skills/tool_calling/actions/list_tools_test.exs) | 1 |
| [test/jido_ai/skills/llm/actions/generate_object_action_test.exs](../../test/jido_ai/skills/llm/actions/generate_object_action_test.exs) | 1 |
| [test/jido_ai/tool_adapter_test.exs](../../test/jido_ai/tool_adapter_test.exs) | 1 |
| [test/jido_ai/integration/react_steering_integration_test.exs](../../test/jido_ai/integration/react_steering_integration_test.exs) | 1 |
| [test/jido_ai/integration/react_context_lifecycle_integration_test.exs](../../test/jido_ai/integration/react_context_lifecycle_integration_test.exs) | 1 |
| [test/jido_ai/skills/reasoning/actions/run_strategy_action_fast_test.exs](../../test/jido_ai/skills/reasoning/actions/run_strategy_action_fast_test.exs) | 1 |

The old AI Directive records have an explicit AI-owned compatibility entry:
`Jido.AI.Directive.Execution.exec/3`. A caller supplies the task supervisor and
result recipient. These records are not native v3 Agent directives. Native
requests use Actions, Flow and Session. Consolidation of the old per-kind
execution helpers remains open. The old parent ReAct Strategy callbacks have
been removed; their direct root callers and tests still require migration.

Logs: `/tmp/jido-ai-v3-root-compile-final.log`,
`/tmp/jido-ai-v3-root-test-*.log`,
`/tmp/jido-ai-v3-root-directive-action-test-02.log`, and
`/tmp/jido-ai-v3-acceptance-root-test-final.log`.

The immutable API inventory is unchanged. No history row was closed in this
checkpoint. Full feature, API, state conversion, dependency, supported runtime,
consumer, migration and rollback checks remain required. The goal stays active.

### Fifth checkpoint: Tool inputs and exception logs

The [tool repair](tool-input-repair.md) restores numeric conversion for model
tool arguments and server logs for Action exceptions caught by core Exec.
The same adapter serves direct Turn execution and Session tool admission.
Strict non-tool validation remains unchanged. Existing timeout execution and
telemetry pass once valid numeric arguments reach core Exec.

All 32 original direct tool cases remain. Eight new cases cover nested fields,
invalid integers, unknown keys, atom-key precedence and strict non-tool input.
The 40-case direct tool file passes. The full root run also fixes seven existing
tool integration cases. No tests were removed, merged or skipped in this pass.
The failure comparison has 20 resolved entries and no additional failure.

| Check | Result |
| --- | --- |
| Direct tool group | 40 passed in 0.4 seconds |
| New native Action and Flow examples | 4 passed in 2.1 seconds |
| Complete root suite | 1,934/2,396 passed in 22.9 seconds; 462 failed; one existing exclusion |
| Complete v3 example suite | 1,131 passed in 143.6 seconds; integration and pending-DSL tags included |
| Forced full production compile, warnings as errors | 229 files passed |
| Selected formatting and whitespace checks | Passed |

The four new [03_03 examples](../../examples/03_tools/03_03_numeric_inputs/README.md)
use the shared HTTP mock. Each tool form has a successful numeric round trip and
a malformed second call that prevents the complete batch from starting. The
tests check real tool inputs, correlated model JSON, stored results and terminal
Session state.

Core remains clean at `ca3cebea`. This pass did not edit core or rerun its full
suite. The dependency release gate remains open. The API inventory hash remains
`032d8b1e3bb8d69def2f1d2451d5c8e0aa2d886fcadfd6b540617460b8812357`.
All 126 release-history commits remain in the audit. No history source-review
fields were changed or rows closed. Remaining root behavior, full quality,
state conversion, consumer, runtime floor, guides and rollback gates are open.

Logs: `/tmp/jido-ai-v3-tool-input-test-03.log`,
`/tmp/jido-ai-v3-tool-input-examples-02.log`,
`/tmp/jido-ai-v3-root-test-23.log`,
`/tmp/jido-ai-v3-root-compile-checkpoint-06.log`, and
`/tmp/jido-ai-v3-acceptance-tool-input.log`.
The latest failure inventory is
`/tmp/jido-ai-v3-root-checkpoint-05-failures.json`.

### Sixth checkpoint: Standalone callbacks and output repair

The [runner case map](runner-test-transfer.md) records 14 retained tests moved
to the shared HTTP/SSE mock. All 58 original runner test names remain. One
separate HTTP credential case raises that file to 59 tests. No case was
removed, combined or skipped. The full root comparison resolves 13 previous
failures and has no new failing case.

Shared production fixes bind standalone tool callbacks, record request-transform
failure types and continue output repair after a provider error when an attempt
remains. The existing core Flow owns retries and deadlines. Saved provider
errors use the shared portable error conversion. The actual 503 fixture exposed
improper lists in raw SDK errors during checkpoint creation; the same case now
completes and produces a portable token without its API key.

Eight new integration cases prove callback order and arguments, real tool JSON,
transform failure, invalid repair messages, repair recovery and exhaustion,
model-call accounting, output metadata and terminal tokens. The retained
one-attempt repair case now selects that budget explicitly and keeps all its
assertions. Two new Agent cases prove a two-attempt budget.

The root run passes 1,948/2,397 cases in 22.2 seconds, with 449 failures and one
existing exclusion. All four doctests pass. Numeric-string usage and AWS
credential options remain required runner failures. An intermediate test
rewrite changed those two requirements; review restored their original cases.
The final root result replaces the earlier 1,949/2,396 count. The separate
API-key HTTP test is not AWS proof.

The forced production compile passes for all 229 AI files with warnings as
errors. Dependencies emitted warnings during their separate compilation.
Selected formatting passes after one new assertion was formatted. The immutable
API inventory hash is unchanged. No history source-review fields were edited
or rows closed.

Core advanced independently to `37ee96d6880954b5df1dad9c6ad859c432800630`.
Its production tree is `1be985dbcf801da9af2e4cc2b558f047fc16566e`. The latest root
run and production build use that checkout. During validation, another task
modified core test and documentation files; its production files remained
unchanged. This task did not edit core or rerun its full suite. The dependency
release gate remains open.

The first full example run at this AI source revision passed 1,139 cases in
149.4 seconds. The repeat against the new core passed 1,138/1,139 in 147.8
seconds. Its single failure was a local ToT test timer received after the
default 100 ms assertion timeout. The test still uses a 20 ms search limit
and checks the recorded termination duration. Its message wait now allows
2,000 ms; no behavior assertion or production limit changed. The complete
repeat run then passed all 1,139 cases in 149.1 seconds, with integration and
pending-DSL tags included. No test was excluded in this run.

Core later advanced to `c602788398eedd122a049d6e7b85e62f59c18444` while
the final checks ran. Its production tree is still
`1be985dbcf801da9af2e4cc2b558f047fc16566e`, with no uncommitted production
changes. The tested production code is unchanged.

Logs: `/tmp/jido-ai-v3-root-test-26.log`,
`/tmp/jido-ai-v3-root-compile-checkpoint-07.log`,
`/tmp/jido-ai-v3-standalone-repair-examples-01.log`,
`/tmp/jido-ai-v3-acceptance-runner-repair.log`, and
`/tmp/jido-ai-v3-acceptance-runner-repair-final.log`, and
`/tmp/jido-ai-v3-acceptance-runner-repair-final-02.log`.
The current failure inventory is
`/tmp/jido-ai-v3-root-checkpoint-06-failures.json`.

The goal remains active. Remaining root behavior, full package quality, state
conversion, minimum runtime, fresh consumer, migration and rollback checks
remain required.

### Seventh checkpoint: Stream usage source rules

The [stream usage port](stream-usage-port.md) restores the retained runner
fallback test without changing its input or assertions. The source order is
processed response, stream metadata, then captured chunks. A processed zero
keeps priority. Chunk counters use independent maxima; separate calls still
add through the existing shared Usage helper. Metadata is read before ReqLLM
closes its handle. Temporary state is removed after success and failure.

All 12 new boundary tests pass. The full root result is 1,961/2,409 passed in
27.1 seconds, with 448 failures and one existing exclusion. All four doctests
pass. The failure comparison resolves exactly one previous case and has no
new failing root case. The full production compile passes for 230 files with
warnings as errors. No old root case was removed, combined or skipped.

The [02_24 examples](../../examples/02_requests/02_24_stream_usage/README.md) add eight
required integration cases. Native Agent DSL and standalone requests prove
explicit zero and cumulative accounting across real tool rounds. Four new
cases send complete usage fields as strings. ReqLLM 1.22 raises `:badarith`
inside its stream server before AI receives the chunk. These cases remain
failing and required. They are not skipped, and the passing decoded-boundary
case does not replace their wire-format proof.

The OpenAI decoder has a separate incomplete-map limitation: omitting total
usage produces a nonempty zero map. The fallback keeps source priority; it
does not replace an authoritative zero with another record. A dependency fix
must address numeric-string arithmetic and preserve source availability and
explicit-zero behavior. The current dependency remains unchanged.

Root log: `/tmp/jido-ai-v3-root-test-27.log`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-08.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-07-failures.json`.
The immutable API baseline and all history source-review fields are unchanged.
No history row was closed. Remaining behavior and release gates remain open.

The complete example run passes 1,143/1,147 cases in 145.5 seconds, with four
failures and no exclusions. The only failures are the four new numeric-string
cases in 02_24. All prior 1,139 cases still pass. Integration and pending-DSL
tags are included. Log: `/tmp/jido-ai-v3-acceptance-usage-source.log`.
The full forced compile passes for 230 production files.

Core's final observed HEAD is `8b6e86075686a423c03d44ea46d574516fd5a67c`.
Its production tree remains `1be985dbcf801da9af2e4cc2b558f047fc16566e`, with no
uncommitted production changes. The tested dependency code is unchanged.
This pass did not edit core or rerun its full suite. The dependency gate remains
open. Selected formatting, whitespace and 296 local document links pass.
The stream transform API used by the adapter is present since Elixir 1.14;
the required fresh Elixir 1.18 / OTP 27 package check remains open.

### Eighth checkpoint: Provider changes and response context

The [provider transfer](provider-test-transfer.md) moves four retained runner
cases to real HTTP. Three previous failures are fixed. The shared response
adapter also fixes six unchanged state, checkpoint and heartbeat cases. All
58 original runner names remain, plus the previously added credential case.
The runner now passes 41/59 cases. No old case was removed, combined or skipped.

The shared mock serves Anthropic text, tools and objects in buffered and SSE
forms. Two new mock contracts prove actual ReqLLM decoding. Four new native
Agent and standalone cases change OpenAI → Anthropic → OpenAI, with real tools
between calls. They check paths, options, model labels, usage and saved state.

The Anthropic stream builder adds an empty text part to the response message
after it saves the assistant in the response context. The two representations
then differ, which prevents the next tool exchange. The AI adapter aligns
only that exact difference. Three boundary tests prove the fix and preserve
rejection for different unresolved tool IDs or arguments. No SDK files changed.

The full root result is 1,973/2,412 passed in 24.8 seconds, with 439 failures
and one existing exclusion. All four doctests pass. The failure comparison
resolves nine cases and has no new failure. All 230 production files compile
with warnings as errors. Root log: `/tmp/jido-ai-v3-root-test-28.log`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-09.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-08-failures.json`.

Core advanced independently to `7d0aaa0e5b636ac34be1c03c86b87dc4b9147c7c`.
Its production tree remains `1be985dbcf801da9af2e4cc2b558f047fc16566e`.
This pass did not edit core. The full dependency and package gates remain open.

The first full acceptance run at this checkpoint passes 1,148/1,153 cases in
146.6 seconds, with five failures and no exclusions. Four are the retained
numeric-string usage failures in ReqLLM. A standalone callback case also
failed in core shutdown: `Jido.Agent.Turn.Outcome` rejected a finish time five
milliseconds before its start time. Both timestamps came from core. The
exception occurred through `Jido.Telemetry.Agent.interrupted/2` during Agent
termination. No AI assertion or test limit was changed. This adds evidence to
the open dependency gate. The full repeat result is recorded below.

Acceptance log: `/tmp/jido-ai-v3-acceptance-provider-switch.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-provider-switch-failures.json`.

The core source uses `ID.extract_timestamp(active.turn_id)` for `started_at`
and `System.system_time(:millisecond)` for `finished_at`. It measures duration
separately with the monotonic clock. The captured shutdown error is therefore
a comparison of the ID timestamp with current wall time. This source check
does not establish why those two values differed. Core production files remain
unchanged by this task. Selected formatting, whitespace, all 1,097 local links
in the plan/profile documents, and the immutable API inventory hash pass.
All 58 original runner names remain.

The complete repeat passes 1,149/1,153 cases in 145.2 seconds, with four
failures and no exclusions. Only the required ReqLLM numeric-string cases
fail. The core shutdown timing error did not repeat. Its captured failure
remains part of the dependency gate; this repeat does not prove a core fix.
All six added mock/provider cases pass. Log:
`/tmp/jido-ai-v3-acceptance-provider-switch-repeat.log`.

### Ninth checkpoint: Blank failures and partial content

The [incomplete response port](incomplete-response-port.md) adds 16 integration
cases through native Agent DSL and standalone requests. The shared terminal
check now records `error_type: :llm_response` for a failed blank response. It
uses the existing `Turn.result/1` projection so a partial image remains usable,
as partial text already was. Blank successful `stop` remains accepted.

The retained blank-response runner test passes without changes to its input
or assertions. It checks the exact cause, usage, failure type, terminal token
and absence of successful assistant history and model events. The runner now
passes 42/59 cases. The complete root result is 1,974/2,412 passed in 24.8
seconds, with 438 failures and one existing exclusion. All four doctests pass.
The comparison resolves one failure and adds none. The root case count is
unchanged. No retained case was removed, combined or skipped.

The HTTP examples state ReqLLM's Chat mapping: unrecognized finish strings
become `:error`; `length` and `content_filter` retain their known reasons.
The examples do not prove exact Responses status handling. Five legacy
wrapper-envelope tests also remain required failures and were not changed.
Typed partial-output and remaining failed-transport cases remain open.

Root log: `/tmp/jido-ai-v3-root-test-29.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-09-failures.json`.
All 230 production files compile with warnings as errors. Compile log:
`/tmp/jido-ai-v3-root-compile-checkpoint-10.log`. The complete acceptance result is recorded below. Selected formatting, whitespace and 1,105 local document links
pass. The immutable API inventory hash is unchanged. All 126 history rows
remain, with no source-review edit or newly closed row. Core remains at
`7d0aaa0e5b636ac34be1c03c86b87dc4b9147c7c`, production tree
`1be985dbcf801da9af2e4cc2b558f047fc16566e`, with no uncommitted production
changes. No dependency code changed in this pass.

The final complete acceptance run passes 1,165/1,169 cases in 147.4 seconds,
with four failures and no exclusions. Only the retained numeric-string usage
cases in 02_24 fail inside ReqLLM. All 16 new response cases and the prior
1,149 passing cases pass together. The core shutdown timing error did not
repeat in this run; its earlier failure remains in the dependency record.
Integration and pending-DSL tags are included.

Acceptance log: `/tmp/jido-ai-v3-acceptance-incomplete-response.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-incomplete-response-failures.json`.
The goal remains active. Root behavior, exact provider status and transport
contracts, legacy result shapes, core dependency fixes and all remaining
package, consumer, minimum-runtime, migration and rollback gates remain open.

### Tenth checkpoint: ReAct setup and option preparation

The [ReAct setup case map](react-setup-test-transfer.md) accounts for all 78
original cases. Twenty-four now test native definition validation, route
binding, owned request work, prepared limits/options and tool selection.
Fifty-four cases remain required and failing. No case was removed, combined
or skipped. The model-control cases deliberately stop after option capture;
they are configuration proof, not substitute provider responses.

Shared fixes accept model option maps, defer provider lookup until model
resolution, and merge declared, runtime and request HTTP options. One common
preparation helper serves Session and direct Turn execution. The six new
[02_26 examples](../../examples/02_requests/02_26_request_setup/README.md) prove actual
headers, buffered callbacks, model values, later defaults and portable state.
All six pass. The full root result is 1,998/2,412 passed in 24.9 seconds, with
414 failures and one existing exclusion. All four doctests pass. The comparison
resolves exactly the 24 mapped setup cases and has no new failure. All 54
unported ReAct cases still fail and remain required. Root log:
`/tmp/jido-ai-v3-root-test-30.log`. Failure inventory:
`/tmp/jido-ai-v3-root-checkpoint-10-failures.json`.
The full forced production compile passes for all 230 files with warnings as
errors. Log: `/tmp/jido-ai-v3-root-compile-checkpoint-11.log`. Selected formatting,
whitespace, the 78-case map and 1,117 local document links pass. The immutable
API inventory hash and all 126 history source-review rows are unchanged. No
history row was closed. The complete acceptance result is recorded below.

The complete acceptance run passes 1,171/1,175 cases in 149.4 seconds, with
four failures and no exclusions. The six new setup examples and all prior
1,165 passing cases pass together. Only the retained ReqLLM numeric-string
usage cases fail. Integration and pending-DSL tags are included. The earlier
core shutdown timing failure did not repeat and remains in the dependency
record. The tested core production tree is unchanged.

Acceptance log: `/tmp/jido-ai-v3-acceptance-request-setup.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-request-setup-failures.json`.
The goal remains active. The remaining 414 root failures, four provider usage
failures, dependency fixes and all other release gates remain required.

### Eleventh checkpoint: ReAct lifecycle and real tool context

The [lifecycle transfer](react-lifecycle-test-transfer.md) moves 24 more retained
ReAct cases to native APIs. The full 78-case map now records 24 setup cases,
24 lifecycle cases and 30 required unported cases. No case was removed,
combined or skipped. Real HTTP/SSE tests cover request ownership, controls,
failure, cancellation, history, telemetry and live configuration. The trace-cap
check uses explicit Session events during a held HTTP request. Its scope is
recorded separately from provider events.

The complete root result is 2,022/2,412 passed in 23.9 seconds, with 390 failures
and one existing exclusion. All four doctests pass. The complete failure
comparison resolves exactly the 24 mapped cases and adds no failing case.
All 30 unported ReAct cases still fail and remain required. The three new
[03_02 examples](../../examples/03_tools/03_02_tool_context/README.md) cover a named
native Session Agent, native Turn Agent and public Agent. All 14 focused tool
context examples pass with integration and pending-DSL tags included.

The refinement removes unused old helpers and aliases, retains explicit Action
schemas and declares native tool context projection. Core rejection of reserved
Turn command keys is asserted before successful execution. These cases do not
change the production AI implementation. They transfer retained tests to the
v3 implementation and add execution proof. The old test names and contract
changes remain in the case map and transfer document.

The local core received an independent constructor/codec fix while this pass
ran. Complete checks use core `dbb878b6d5dbcf727845d81b4b9abcf8c1b188a0`,
production tree `ec8fb62befda3d6da79033b06639a8f050a4161c`, with no uncommitted
core production edits. No core file was edited by this pass. Earlier core
failures and the shutdown timing finding remain open until separately checked.
Action and Signal revisions are unchanged.

All 230 AI production files pass forced compilation with warnings as errors.
Selected formatting, whitespace and the complete 78-name map pass. Local plan
and example document links resolve. The immutable API SHA is unchanged. All
126 history rows remain, with no source-review edit or newly closed row.

Root log: `/tmp/jido-ai-v3-root-test-31.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-11-failures.json`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-12.log`.
The complete acceptance result is recorded below. The goal remains active.

The complete acceptance run passes 1,174/1,178 cases in 146.0 seconds, with four
failures and no exclusions. It includes integration and pending-DSL tags. All
three new tool-context cases and the prior 1,171 passing cases pass together.
The failure names match the previous run: only the four required 02_24
numeric-string usage cases fail inside ReqLLM. No new failure appeared. The
prior core shutdown timing failure did not repeat; its earlier evidence remains
in the dependency record. The core production tree was rechecked and is unchanged
from the revision above.

Acceptance log: `/tmp/jido-ai-v3-acceptance-react-lifecycle.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-react-lifecycle-failures.json`.
The remaining 390 root failures, four provider failures, earlier core findings,
minimum runtime, quality checks, fresh consumer, API/state migration, recovery,
rollback and final package gates remain required. The goal remains active.

### Twelfth checkpoint: context operations and protected history refs

The [context transfer](react-context-test-transfer.md) moves 18 more retained
ReAct cases to native APIs. All 78 old names remain mapped: 24 setup, 24
lifecycle, 18 context and 12 required unported cases. No case was removed,
combined or skipped. Replacement, deferred application, lane selection,
compaction and refs now have real request/tool proof. Deferred worker loss is
checked during an actual held tool.

Two shared defects were found and fixed. Thread message entries now use the
owned request/run IDs and reject caller ID aliases. Model-message refs retain
caller correlation values through ReqLLM conversion, request transforms and
later rounds. The shared Generate boundary removes private ref metadata from
provider requests and restores it only onto an exact returned input prefix.
An unchanged no-prompt case caught the first implementation's HTTP metadata
leak. Its exact assertion passes again. Other provider metadata and unresolved
tool-context errors retain their behavior. Provider response metadata cannot
create private AI refs.

The complete root run passes 2,044/2,416 cases in 25.0 seconds, with 372 failures
and one existing exclusion. All four doctests pass. The complete comparison
resolves exactly the 18 mapped cases, adds four passing conversion/boundary
cases and adds no failing case. ReAct now passes 66/78. All 12 unported cases
remain required failures. The four new history cases and three retained
response-context cases pass together.

The [02_23 examples](../../examples/02_requests/02_23_context_operations/README.md) add
three cases through a public Agent and native buffered/streamed Agents. Real
tools, steer/inject, portable reconstruction and a later request keep owned
Thread refs, local caller refs and one copy of tool history. HTTP bodies keep
private refs out. Explicit native history, steering and context projection
replace assumptions in the first fixture. The focused group passes all 31
cases. Final callback assertions also compare request messages and runtime
state-view refs; that focused result is recorded below.

The complete acceptance run passes 1,177/1,181 cases in 145.9 seconds, with four
failures and no exclusions. Integration and pending-DSL tags are included. All
three new examples and the prior 1,174 passing cases pass together. The failure
names match the previous run: only the four required ReqLLM numeric-string usage
cases fail. No new failure appears. The prior core shutdown timing failure did
not repeat; its evidence remains in the dependency record.

All 230 production files pass forced compilation with warnings as errors.
Core remains `dbb878b6d5dbcf727845d81b4b9abcf8c1b188a0`, production tree
`ec8fb62befda3d6da79033b06639a8f050a4161c`, with no uncommitted core production
edits. No dependency code changed. The immutable API hash and all 126 history
source-review rows are unchanged; no history row was closed.

Root log: `/tmp/jido-ai-v3-root-test-32.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-12-failures.json`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-13.log`.
Acceptance log: `/tmp/jido-ai-v3-acceptance-react-context.log`.
Acceptance failures: `/tmp/jido-ai-v3-acceptance-react-context-failures.json`.
Boundary log: `/tmp/jido-ai-v3-history-boundary-02.log`.

The 372 root failures, four provider failures, earlier core findings, initial
Agent state conversion, checkpoint/recovery and all other release gates remain
required. The goal remains active.

The final focused repeat passes all 31 context cases in 4.0 seconds after adding
explicit callback-state ref comparisons. No production code changed after the
complete runs. Log: `/tmp/jido-ai-v3-context-refs-03.log`. Selected formatting,
whitespace, the 78-name source map and local document links pass.


### Thirteenth checkpoint: tool inspection and typed Action errors

The [inspection transfer](react-inspection-test-transfer.md) retains all 78
ReAct cases and moves two more to native Session inspection. ReAct now passes
68/78, with ten required failures. Real HTTP and Action execution replace the
old synthetic Strategy state. Completion replay retains one result per tool,
the active model phase, the final answer and the old request's saved results.
A later request starts with empty tool results.

Shared inspection now includes nil results for running tools. A duplicate
completion cannot change the phase when it removes no pending call. Shared
tool normalization also restores typed error maps from the exact core wrapper
for returned Action errors. It preserves timeout type, text and retry hints,
and adds actual tool identity. Exceptions and failures with extra execution
evidence retain their previous handling. Five new boundary cases pass.
Prepared arguments remain visible for active calls; completed records keep the
validated arguments sent to the Action. General error storage is unchanged.

The complete root run passes 2,051/2,421 cases in 28.5 seconds: four doctests
and 2,047 ordinary tests pass. There are 370 failures and one existing exclusion.
Comparison with checkpoint 12 shows exactly the two mapped failures resolved,
five new passing boundary cases and no new failing case. All 230 production
files pass forced compilation with warnings as errors.

The [02_22 examples](../../examples/02_requests/02_22_request_inspection/README.md)
add named buffered and streaming Agents. All 16 focused cases pass. Each new
case executes success/failure tools, replays an actual completion twice, checks
one HTTP history entry per tool, finishes and starts a later request. It checks
the actual stream flag and portable Agent state.

Core remains `dbb878b6d5dbcf727845d81b4b9abcf8c1b188a0`, production tree
`ec8fb62befda3d6da79033b06639a8f050a4161c`, with no local core production edits.
No dependency code changed. The immutable API inventory and all 126 history
source reviews remain unchanged. No history row was closed.

Root log: `/tmp/jido-ai-v3-root-test-34.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-13-final-failures.json`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-15.log`.
Focused examples: `/tmp/jido-ai-v3-inspection-examples-final.log`.
Boundary cases: `/tmp/jido-ai-v3-tool-result-boundary-02.log`.

The remaining ReAct cases cover initial Agent context, checkpoint retention,
usage and saved raw errors. Parent Agent conversion is still separate from
standalone State conversion. The four required ReqLLM cases, earlier core
findings, the other root failures and all release gates remain open. The goal
remains active.


The first complete acceptance run passed 1,178/1,183 checks and failed five.
Four failures were the known ReqLLM usage cases. The added failure was the
unchanged skill-authoring case for a file changed after catalogue setup.
Restored typed error data exposed a retry-hint lookup that used Access syntax
on a nested exception. Map field lookup fixes that failure without changing
error storage. The new boundary case covers both atom and string detail keys.
All 37 skill/inspection cases and all 26 boundary/error-model cases pass.
First acceptance log: `/tmp/jido-ai-v3-acceptance-react-inspection.log`.
Its inventory: `/tmp/jido-ai-v3-acceptance-react-inspection-failures.json`.
Focused repeat: `/tmp/jido-ai-v3-inspection-skills-02.log`.


The final complete acceptance run passes 1,179/1,183 checks in 148.1 seconds,
with no exclusions. The only four failures are the same required ReqLLM
numeric-string usage cases from checkpoint 12. Both new examples and all prior
1,177 passing cases pass. The skill regression is resolved. The earlier core
timing finding did not repeat and remains open until its separate check.
Final acceptance log: `/tmp/jido-ai-v3-acceptance-react-inspection-02.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-react-inspection-02-failures.json`.

No production code changed after the final complete root and acceptance runs.
Forced production compile, selected formatting and whitespace checks pass.
The source map still accounts for all 78 ReAct cases. The API inventory hash is
unchanged, and all 126 history source reviews retain their prior status.


### Fourteenth checkpoint: initial conversation state import

The [initial-state transfer](react-initial-state-test-transfer.md) adds
`Jido.AI.Agent.from_initial_state/3`. It imports application state and optional
Context into a selected v3 profile before Server startup. Saved history and
prompts use existing AI state fields. Core instantiation still validates domain
fields, defaults, Plugin ownership and final state size. The constructor does
not start a model, tool or old worker. Full v2 Agent checkpoint and Plugin-state
conversion remain separate required work.

All 78 root ReAct cases remain. Four more use the new API and pass; the file
now passes 72/78. Nine new boundary cases cover required fields, defaults,
profiles, malformed/unknown/live data, complete tool exchanges, decoded Context
maps and size limits. History preparation is shared with normal replacement.
Standalone State conversion now uses the same tool-history ordering check.
The source map retains every original and current test name.

The complete root run passes 2,064/2,430 cases in 25.9 seconds: all four doctests
and 2,060 ordinary tests pass. It has 366 failures and one existing exclusion.
Compared with checkpoint 13, exactly the four mapped failures are resolved,
nine new tests pass and no failing case is added.
Root log: `/tmp/jido-ai-v3-root-test-35.log`.
Failure inventory: `/tmp/jido-ai-v3-root-checkpoint-14-failures.json`.

The [14_11 examples](../../examples/14_resume/14_11_initial_state/README.md) add seven
integration cases. Four public/native buffered/streamed Agents import image and
completed tool history, make real model requests, save native state and restart
without tool replay. Two selected-profile cases prove prompt and history
separation at the provider. One rejection case starts no model work.
The complete acceptance run passes 1,186/1,190 checks in 147.7 seconds, with no
exclusions. Its only failures are the same four required ReqLLM numeric-string
usage cases. All seven new examples and all prior 1,179 passing examples pass.
The earlier core timing finding did not repeat and remains open.
Acceptance log: `/tmp/jido-ai-v3-acceptance-initial-state.log`.
Failure inventory: `/tmp/jido-ai-v3-acceptance-initial-state-failures.json`.

Forced production compilation found a warning about separated `context/2`
clauses. They were moved together without changing their expressions or order
relative to each other. Final compile and focused results are recorded below.
Core remains `dbb878b6d5dbcf727845d81b4b9abcf8c1b188a0`, production tree
`ec8fb62befda3d6da79033b06639a8f050a4161c`, with no local core production edits.
No dependency source changed. The immutable API hash and all 126 history source
reviews remain unchanged, and no history row was closed.

The six remaining ReAct cases cover usage, checkpoint tokens and raw errors.
Full old Agent conversion, Plugin state, active recovery and all remaining
feature/dependency/package/runtime-floor/consumer/release gates stay required.
The goal remains active.


Final forced compile passes for all 231 production files with warnings treated
as errors. The clause grouping change also passes the 13 initial-state/history
boundary cases and all 60 initial-state, standalone-conversion and context
examples. Selected formatting, whitespace and all 1,532 checked local document
links pass. No test was excluded or removed in this pass.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-17.log`.
Boundary log: `/tmp/jido-ai-v3-initial-state-boundary-final.log`.
Focused examples: `/tmp/jido-ai-v3-initial-state-examples-final.log`.


### Fifteenth checkpoint: terminal ReAct state

The [terminal-state transfer](react-terminal-test-transfer.md) moves the final
six retained ReAct cases to native Agent checkpoints, standalone signed tokens,
and public request/collector APIs. All 78 now pass. The JSON map matches every
original and current name, with no removed, combined or skipped case. It records
24 setup, 24 lifecycle, 18 context, two inspection, four initial-state and six
terminal cases. The old private Strategy runtime calls are gone from this file.

The [14_12 examples](../../examples/14_resume/14_12_terminal_state/README.md) add six
checks for native buffered/SSE success and two raw error forms. Each proves
real model/tool work, empty final usage, portable checkpoint copy, retained
request and trace, no restored active work, no tool replay and a later request
with separate usage. Failed request records keep raw errors in their error
field; the public event collector keeps them as its result. Native Agent
checkpoints and standalone signed tokens remain separate formats.

The nested usage assertions are collector-boundary checks. The provider case
records the SDK's actual decoding of an incomplete Chat finish reason to
`:error`. A control after real model work supplies the exact incomplete tuple
and raw map. This does not claim different provider decoding or close the
existing wrapper-envelope failures. Full v2 Agent and Plugin-state conversion
remains required. No production file changed during this pass.

| Check | Result |
| --- | --- |
| Retained ReAct file | 78/78 passed in 9.1 seconds |
| Initial focused integration group | 54/54 passed in 9.1 seconds |
| Complete root suite | 2,070/2,430 passed in 32.6 seconds; 360 failed; one existing exclusion |
| Complete acceptance suite | 1,192/1,196 passed in 159.1 seconds; four required failures; no exclusions |
| Forced production compile with warnings as errors | All 231 files passed |

The root comparison resolves exactly the six mapped failures and adds no
failing case. All four doctests and 2,066 ordinary cases pass. Acceptance keeps
all 1,186 prior passing cases and adds six passes. Its four failure names are
unchanged: native/standalone numeric-string usage with capture on/off. The SDK
fails in arithmetic before AI receives the usage chunk. No failure was hidden.
The initial focused run had constant-branch test warnings. One expectation
helper removes those warnings; the final full suite verifies the change.

Selected formatting, whitespace and local document links pass. The API
inventory hash remains `032d8b1e3bb8d69def2f1d2451d5c8e0aa2d886fcadfd6b540617460b8812357`.
All 126 history rows remain source-reviewed and pending. No history row was
closed. Core remains `dbb878b6d5dbcf727845d81b4b9abcf8c1b188a0`, with production
tree `ec8fb62befda3d6da79033b06639a8f050a4161c` and no uncommitted lib change.
This task did not edit core or dependencies. Earlier core suite failures and
the shutdown timing finding remain in the dependency gate.

Root log: `/tmp/jido-ai-v3-root-test-36.log`. Failure inventory:
`/tmp/jido-ai-v3-root-checkpoint-15-failures.json`.
Acceptance log: `/tmp/jido-ai-v3-acceptance-terminal-state.log`. Failure inventory:
`/tmp/jido-ai-v3-acceptance-terminal-state-failures.json`.
Compile log: `/tmp/jido-ai-v3-root-compile-checkpoint-18.log`.

The largest remaining root groups use TRM, Adaptive, ToT and GoT Strategy APIs,
followed by old integration/Plugin callers and standalone runner cases. Their
behavior transfer, package quality, consumer and runtime-floor checks, full
checkpoint conversion, API/history closure and migration/rollback guides all
remain required. The migration goal is active.
