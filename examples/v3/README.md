# Jido AI v3 acceptance foundation

This temporary Mix project depends on the complete root `jido_ai` package.
Both use the local Jido, Jido Action and Jido Signal projects. The root compiles
all production files under `lib`; this project compiles only its own examples
and the compatibility entry for the shared mock server. The first five
examples retain core foundation checks.

Start with the [migration plan](../../docs/v3-spike/migration-plan.md) and
[unified DSL plan](../../docs/v3-spike/agent-dsl.md). The full package port is
still pending. Keep this project temporary. Transfer the fixtures and shared
example cases into the root suite when the production port is ready. The mock
server implementation is already shared from the root package.

## Run

Run these commands in `jido_ai/examples/v3`:

```sh
mix deps.get
mix test
mix test --include integration
```

The first test command runs the mock server contracts and the retained AoT
lifecycle case. The second also
runs the foundation and production AI examples. Integration examples are excluded by
default. They use local model responses and real ReqLLM, Actions, Flows,
Agents, and AgentServer commits. No provider credentials are required.

To run only the new production AI acceptance cases:

```sh
mix test test/examples/01_authoring/01_06_ai_extension_test.exs test/examples/01_authoring/01_07_ai_runtime_test.exs --include integration
```

The former pending AI tests now run as integration tests. No expected missing
module or excluded case counts as proof.

The nested lockfile pins external dependencies. Local path dependencies use
the current working trees, including uncommitted changes. Builds and downloaded
dependencies go into `jido_ai/_build/v3_acceptance`, outside the root formatter's
recursive example paths. The root dependencies have now switched to local v3 projects. See the
[root package checkpoint](../../docs/v3-spike/root-package-checkpoint.md).

## Examples

Source, test, and profile names use matching IDs, as in the core example suite.

| ID and profile | Passing acceptance checks |
| --- | --- |
| [01_01_authoring_formats](profiles/01_01_authoring_formats.md) | Agent DSL/Builder/direct/JSON parity; Flow DSL/Builder/direct/JSON parity; direct result and live commits |
| [01_02_tool_flow](profiles/01_02_tool_flow.md) | Real Action and nested Flow tools; Map; full batch validation; exact tool IDs and follow-up messages |
| [01_03_structured_output](profiles/01_03_structured_output.md) | Requested JSON schema; invalid output feedback; bounded Iterate repair; state preservation on exhaustion |
| [01_04_controls](profiles/01_04_controls.md) | Input and output control order; no model call on denied input; no commit on denied output or provider failure |
| [01_05_streaming](profiles/01_05_streaming.md) | SSE deltas before commit; live cancellation; provider connection cleanup |
| [01_06_ai_extension](profiles/01_06_ai_extension.md) | Production AI DSL, common lowering, Builder/data/JSON execution and profile validation |
| [01_07_ai_runtime](profiles/01_07_ai_runtime.md) | Mixed routes and Plugins; real Action/Flow tools; source JSON; stable artifact IDs; control order, limits and cancellation |
| [01_08_model_helpers](profiles/01_08_model_helpers.md) | Shared public model-helper code; defaults, option precedence, HTTP/SSE headers, objects, usage and errors |
| [02_01_session](profiles/02_01_session.md) | Confirmed admission, awaits, SSE, tools/objects, usage, cancellation, partial failures, source formats and process cleanup |
| [02_02_steering](profiles/02_02_steering.md) | FIFO controls, closure, consumed history, hard limits, timeouts, repair and later-request history |
| [02_03_public_agent](profiles/02_03_public_agent.md) | Actual public Agent macro and helpers; result shapes, cancellation reasons, state fields, context, retries, headers and core checkpoint round trip |
| [02_04_request_scope](profiles/02_04_request_scope.md) | Request tool selection, actual aliased/open tool execution, raw/custom output, imported schemas and isolated iteration limits |
| [02_05_request_transform](profiles/02_05_request_transform.md) | Per-call transformation, fresh repair headers, changed models, real tool selection, callback references across source forms and bounded repair |
| [02_06_output_contract](profiles/02_06_output_contract.md) | Nested output schemas, provider schema tools, output events/metadata, repair failure and cancellation, telemetry flags across source forms |
| [02_07_response_metadata](profiles/02_07_response_metadata.md) | Decoded reasoning/thinking metadata, per-call traces, request isolation, failure/cancellation retention and snapshot source order |
| [02_08_error_contract](profiles/02_08_error_contract.md) | Structured provider/repair/control errors, killed callbacks, portable storage, JSON-safe error details and finite output error summaries |
| [02_09_tool_results](profiles/02_09_tool_results.md) | Canonical tool results, real tool and Flow errors, binary content, ordered completed outputs, retries and failure/cancellation retention |
| [02_10_tool_effects](profiles/02_10_tool_effects.md) | Complete candidate state, policy intersection, parallel conflicts, post-commit directives, direct I/O and failure/cancellation boundaries |
| [02_11_completion](profiles/02_11_completion.md) | Observed completion commits, Plugin rejection, state limits, compact failure records, post-commit failure and uncertain storage writes |
| [02_12_tool_callbacks](profiles/02_12_tool_callbacks.md) | Alias workflow, callback order/identity, retries, batch failures, policy, current state, cancellation and source-format parity |
| [02_13_tool_limits](profiles/02_13_tool_limits.md) | Batch preflight, interruption, real attempt and request timeouts, retries, and tools that run beyond 30 seconds |
| [02_14_stream_activity](profiles/02_14_stream_activity.md) | Public tool keepalives, both idle limits, provider activity, ordered parallel retries, request overrides and timer cleanup |
| [02_15_early_tool_activity](profiles/02_15_early_tool_activity.md) | Named tool activity before argument completion, shared delta capture, real document execution, rejection and interrupted input |
| [02_16_typed_signals](profiles/02_16_typed_signals.md) | Core Signal schemas, explicit runtime projection and outbound delivery, real response/embedding data, direct Turn conversion and timeout cleanup |
| [02_17_signal_delivery](profiles/02_17_signal_delivery.md) | Automatic session Signals, bounded batches, core dispatch receipts, policy flags, cancellation, stale tickets and owner cleanup |
| [02_18_admission](profiles/02_18_admission.md) | Canonical method on rejection, actual route binding, raw errors, duplicate isolation and missing bindings |
| [02_19_model_options](profiles/02_19_model_options.md) | Public model forms, request options, routing precedence, SSE labels/headers, HTTP callbacks, buffered Responses tools/objects, and OpenAI → Anthropic → OpenAI tool rounds |
| [02_20_call_counts](profiles/02_20_call_counts.md) | Failed and cancelled operation counts, HTTP retries, Quota, repair, owner loss and duplicate observations |
| [02_21_context_views](profiles/02_21_context_views.md) | Committed history, preserved thinking/timestamps/refs, active changes, invalid entries and interrupted reconstruction |
| [02_22_request_inspection](profiles/02_22_request_inspection.md) | Committed revision, live work, retained traces, cancellation races and recovery |
| [02_23_context_operations](profiles/02_23_context_operations.md) | Context lanes, deferred operations, compaction, protected Thread refs, local model refs and recovery |
| [02_24_stream_usage](profiles/02_24_stream_usage.md) | Explicit zero and cumulative tool-round counts pass; four numeric-string provider cases remain failing |
| [02_25_incomplete_response](profiles/02_25_incomplete_response.md) | Blank canonical Chat errors, failure type, usage/history, terminal tokens, partial text/images and blank successful stop |
| [02_26_request_setup](profiles/02_26_request_setup.md) | Declared/runtime HTTP options, empty overrides, next-request defaults, deferred aliases and model option maps in Session and Turn modes |
| [03_01_dynamic_catalog](profiles/03_01_dynamic_catalog.md) | Public tool/prompt updates, direct Action use, protected state, active request identity, profile scope and reconstruction |
| [03_02_tool_context](profiles/03_02_tool_context.md) | Static defaults, live base replacement, request overrides, active snapshots, native/data/JSON forms and restore |
| [03_03_numeric_inputs](profiles/03_03_numeric_inputs.md) | Numeric model arguments, nested Action and Flow inputs, correlated results and batch validation |
| 08_01 | [Planning Actions and capability](profiles/08_01_planning.md) | Direct/Exec/Agent results, prompt and parser contracts, defaults, mixed capabilities, errors and cancellation |
| [09_01_linear](profiles/09_01_linear.md) | CoT/CoD in the shared Flow; public helpers, prompt defaults, parsing, rich results, output repair, method events, budgets and recovery |
| [09_02_method_api](profiles/09_02_method_api.md) | Public method selection, separate stored results, legacy getters and retained Machine data/telemetry APIs |
| [09_03_aot](profiles/09_03_aot.md) | AoT search prompts, full result maps, typed final answers, repair, public helpers, measured lifecycle and retained Machine APIs |
| [09_04_tot](profiles/09_04_tot.md) | Native tree search, phase calls, ranked candidates, parser repair, bounded tools and retained Machine/Result APIs |
| [09_05_tot_api](profiles/09_05_tot_api.md) | Public search helpers, retained tree inspection, alias callbacks, raw retry results, failed effects, search budgets and provider timeout |
| [09_06_got](profiles/09_06_got.md) | Native graph generation, connections, synthesis, traversal, phase events, bounds and retained Machine APIs |
| [09_07_got_api](profiles/09_07_got_api.md) | Public graph helpers, retained request inspection, printable failures, call budgets, bounded path inspection and consistent busy rejection |
| [09_08_trm](profiles/09_08_trm.md) | Native reasoning, supervision and improvement; scored answer selection, ACT and step limits, phase failures, interruption and retained data APIs |
| [09_09_trm_api](profiles/09_09_trm_api.md) | Public reason helpers, retained review inspection, scored/current answer differences, default call budgets, provider options, streams and cancellation |
| [09_10_adaptive](profiles/09_10_adaptive.md) | Native selection of all seven methods, typed repair, selected tools, phase metadata, ordinary Actions, limits and interruption |
| 09_11 | [Public Adaptive API](profiles/09_11_adaptive_api.md) | All seven methods, declared options, retained selection, printable results, tools, repair and cancellation |
| 09_12 | [Method control defaults](profiles/09_12_method_controls.md) | Selected limits, explicit overrides, tool bounds, typed repair and source-format parity |
| 09_13 | [Active Adaptive selection](profiles/09_13_active_selection.md) | Input controls, committed selection, one-use grants, host policy and owner loss |
| 09_14 | [Callable reasoning](profiles/09_14_callable_reasoning.md) | Seven methods through Exec and Agent calls, isolated ownership, defaults, failure usage and cancellation |
| [09_15_prompt_policy](profiles/09_15_prompt_policy.md) | Adaptive method defaults, public empty values, native instructions, source formats and typed output |
| [09_16_reasoning_tool](profiles/09_16_reasoning_tool.md) | Raw RunStrategy model calls, JSON atom labels, all seven methods, source formats, shared Quota and nested cancellation |
| [14_01_standalone_authoring](profiles/14_01_standalone_authoring.md) | Standalone Config lowering, runtime-only options, aliased tools, core effects, typed repair and portable token checks |
| [14_02_standalone_runtime](profiles/14_02_standalone_runtime.md) | Public standalone Agent/Session adapter, lazy streams, tool work, terminal tokens, callbacks, bounded repair and ownership |
| [14_03_checkpoint_resume](profiles/14_03_checkpoint_resume.md) | Model and tool checkpoints, new-VM resume, saved repair state, code and permission checks, remaining time and token expiry |
| [14_04_standalone_actions](profiles/14_04_standalone_actions.md) | Start, Continue, Collect and Cancel through Exec, Flow and an Agent; live stream ownership, runtime resources, limits and input normalization |
| [14_05_worker_lifecycle](profiles/14_05_worker_lifecycle.md) | ReAct and CoT task failure, owner recovery, parent shutdown, stale messages and uploaded file IDs through native Sessions |
| [14_06_trace_and_cycles](profiles/14_06_trace_and_cycles.md) | Tool argument redaction, captured stream fields, repeated-call warnings, complete argument comparison and checkpoint resume |
| [14_07_standalone_input](profiles/14_07_standalone_input.md) | Caller-owned queues, FIFO steering, closure, failure, cancellation, limits, output repair and queue rebinding on resume |
| [14_08_query_append](profiles/14_08_query_append.md) | Native conversation append, terminal continuation, separate State/call counters, pending-tool order, domain state and retained budgets |
| [14_09_state_migration](profiles/14_09_state_migration.md) | Explicit old State conversion, saved tool and typed answers, caller evidence, terminal restart and retained limits |
| [14_10_failure_position](profiles/14_10_failure_position.md) | Reasoning position during provider/repair failure, cancellation and worker/parent loss; retained model counts and resumed input |
| [14_11_initial_state](profiles/14_11_initial_state.md) | Initial Context import, profile prompt selection, complete tool history and later native reconstruction |
| [14_12_terminal_state](profiles/14_12_terminal_state.md) | Native terminal checkpoint restore, raw errors, retained usage and tool history, and a later independent request |
| 16_01 | [Reasoning capability Plugins](profiles/16_01_reasoning_capabilities.md) | Seven fixed methods, explicit routes, owned defaults, mixed AI profiles, complete state results and failure cleanup |

| [18_01_skill_runtime](profiles/18_01_skill_runtime.md) | Real activation, approved instruction history, compaction, closed catalogues, fresh bounded resources, image/PDF transport and owner cleanup/restore |
| [18_02_skill_authoring](profiles/18_02_skill_authoring.md) | Public/native skill sources, lazy runtime discovery, shared index and tools, static format parity, live changes and restore |

These examples establish authoring, bounded ReAct, CoT/CoD, AoT, native/public ToT,
native/public GoT and TRM, native Adaptive selection and the request session.
Complete public API parity, approval, durable recovery, all reasoning methods, and
full historical feature parity remain required. See the
[implementation record](../../docs/v3-spike/implementation.md).

[16_02 Chat](profiles/16_02_chat.md) adds all seven capability routes, core Flow tool rounds, structured objects, embeddings and callback execution.

[16_03 ModelRouting and Policy](profiles/16_03_routing_policy.md) adds actual
model selection, request overrides, structured policy rejection, custom AI
routes and typed observation preparation.

[07_01 Retrieval](profiles/07_01_memory.md) adds supervised shared memory,
namespace and ranking contracts, native/Chat enrichment, explicit store lifetime
and complete results through Agent routes.

[13_01 Quota](profiles/13_01_quota.md) adds atomic shared admission, per-call
usage, partial failure accounting, nested budgets and v2 counter import.

[16_04 Default Plugins](profiles/16_04_plugin_stack.md) adds public Agent
composition, optional capability routes, separate results, route attributes
and shared Store ownership.

## One mock model server

[MockLLM](support/mock_llm.ex) delegates to the [shared server](../../lib/jido_ai/test/mock_llm.ex). It starts one loopback HTTP server per test on a
free port. Each server accepts concurrent connections. Test processes own its
lifetime. All examples use this implementation.

Scripts match decoded request paths, normalized HTTP headers and body fields. Maps match the stated
fields recursively; lists and scalar values match exactly. The first remaining
matching entry is consumed. Independent model lanes can therefore run without
an arrival-order assumption. Unmatched calls return an error and are recorded.
`report/1` lists all requests, unused entries, unexpected input, barriers, and
connection workers. Tests assert that expected scripts are consumed.

```elixir
script = [
  %{match: %{path: "/v1/chat/completions"},
    reply: {:tools, [%{id: "call-1", name: "multiply", arguments: %{a: 2, b: 3}}]}},
  %{reply: {:text, "The answer is 6"}}
]
```

Supported replies are text, objects, tool batches, embeddings, HTTP errors,
raw provider envelopes, disconnections, and SSE delta sequences. SSE tool
arguments arrive in fragments. `{:usage, map}` supplies an intermediate
nonterminal usage event. Standard responses include final usage. Use a raw
envelope for custom non-streamed usage or provider fields. Barriers use
`{:wait, tag, reply}` or `{:wait, tag}` within an SSE sequence. Release them
with `MockLLM.release/2`. Tests use messages and process monitors, not sleeps.

`{:from_request, fun}` builds a reply from the decoded provider request body.
The function runs in the connection worker and returns an ordinary scripted
reply. GoT uses it to refer to actual node IDs supplied to the model. A default
contract test verifies text and streamed object replies through ReqLLM.

Object scripts also answer forced structured-output tool calls. A default test
checks both streamed and non-streamed decoding, requested tool names and usage.

The server implements OpenAI Chat Completions, its SSE form, embeddings,
buffered Responses replies, and Anthropic Messages in buffered and SSE forms.
`{:anthropic, reply}` scripts text, tools or objects. `{:sse, events}` sends named
provider events. `MockLLM.options(server, :anthropic)` supplies the correct base
URL for the SDK. The mock contracts check actual decoding through ReqLLM.
`MockLLM.model/1` selects OpenAI Chat explicitly. The test Finch configuration
leaves enough HTTP/1 connections for held and concurrent requests.

The mock changes only provider responses. Tool outputs come from real Jido
Actions and Flows. It does not bypass Agent validation or invent committed
state. Model behavior, provider dialect coverage, and real external cancellation
remain separate checks.

## Current checks: 2026-09-07

The root package compiles all 231 production files on local v3 dependencies,
with warnings treated as errors. Its latest complete test result is
2,070/2,430 passed, with 360 failures and one existing exclusion. Acceptance
runs against that same package: 1,192/1,196 passed in 159.1 seconds, with four
required ReqLLM numeric-string failures and no exclusions. An earlier run also
hit a core shutdown timing error. It did not repeat, but remains in the open
dependency record. All required cases remain included.
Core is the local v3 checkout at `dbb878b6`, which adds constructor and codec
contract fixes; Action
is beta.7 and Signal is beta.4. ReqLLM is 1.22.0. The local runtime is
Elixir 1.20.3 / OTP 29. The minimum Elixir 1.18 / OTP 27 remains a release check.

See the [implementation record](../../docs/v3-spike/implementation.md) for the
latest test counts, core checks, package limits and next steps. Earlier planning
runs had three pending DSL examples. Those examples now execute successfully.
No pending test is counted as a pass.
