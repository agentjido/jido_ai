# Current feature map

Checked against the source on 2026-09-15, after `a59eb23c`.
This is the current V3 branch feature map, not a migration wish list or release
announcement. See the [public API map](public-api-map.md) for entry points,
the [source inventory](api-inventory.json) for declarations, and the
[verification record](simplification.md) for test results.
The [old feature map](feature-map-history.md) remains as historical evidence.

## Supported feature families

| Feature | Current implementation and boundary | Acceptance evidence |
| --- | --- | --- |
| One AI authoring model | [Agent](../../lib/jido_ai/agent.ex), [DSL](../../lib/jido_ai/dsl.ex), and [Profile](../../lib/jido_ai/profile.ex) lower to core Agents and Flows. Native declarations, Builder composition, and portable source use the same validation. | [authoring corpus](../../test/authoring/agents/authoring_test.exs), [source variations](../../test/authoring/agents/source_variations_test.exs), [parity](../../test/jido_ai/authoring/full_spec_parity_test.exs) |
| Portable definitions | [Portable](../../lib/jido_ai/portable.ex) and [Codec](../../lib/jido_ai/authoring/codec.ex) support inspection, preflight, and map/JSON/YAML exchange with explicit references. Rich native model export is not supported. | [portable tests](../../test/jido_ai/authoring/portable_test.exs) |
| Native reasoning | [Reasoning](../../lib/jido_ai/reasoning.ex) supports ReAct, CoD, CoT, AoT, ToT, GoT, TRM, and Adaptive. Method-specific algorithms and result data remain; core Strategy coupling and old convenience Agent macros do not. | [reasoning examples](../../examples/09_reasoning), [runtime authoring](../../test/authoring/agents/execution_test.exs) |
| Callable reasoning | [RunStrategy](../../lib/jido_ai/actions/reasoning/run_strategy.ex) uses prompt-only input and a host-bound Profile. Seven fixed-method [Plugins](../../lib/jido_ai/plugins/reasoning) use the same contract. Private sessions preserve deadlines, quota, cancellation, and state isolation. | [authoring](../../test/authoring/agents/callable_profiles_test.exs), [policy](../../test/jido_ai/skills/reasoning/actions/run_strategy_policy_test.exs), [lifecycle](../../test/jido_ai/skills/reasoning/actions/run_strategy_lifecycle_test.exs) |
| Requests and streaming | [Request](../../lib/jido_ai/request.ex), [Stream](../../lib/jido_ai/request/stream.ex), and [Orchestration](../../lib/jido_ai/orchestration.ex) handle admission, progress, completion, waiting, and cancellation. Generated Agent helpers remain. | [interfaces](../../test/authoring/agents/interfaces_test.exs), [Orchestration](../../test/jido_ai/orchestration/orchestration_test.exs) |
| Steering and injection | [Control](../../lib/jido_ai/control.ex) and Orchestration keep request correlation and queued-input behavior. Accepted input is not proof that a model consumed it. | [controls](../../test/authoring/agents/plugins_controls_test.exs), [input owner](../../test/jido_ai/pending_input_server_test.exs) |
| History, recovery, and standalone ReAct | [Thread projection](../../lib/jido_ai/thread/projection.ex) reads the canonical Session/Thread values; internal Orchestration integration commits entries. [Standalone ReAct](../../lib/jido_ai/reasoning/react.ex) retains its Config, State, and Token APIs. Initial-state conversion remains explicit. | [recovery](../../test/authoring/agents/recovery_test.exs), [resume examples](../../examples/14_resume), [token tests](../../test/jido_ai/react/token_test.exs) |
| Models and provider transport | [Models](../../lib/jido_ai/models.ex) resolves aliases; ReqLLM owns native provider calls. [ModelRouting](../../lib/jido_ai/plugins/model_routing.ex) selects models within AI composition. Internal [Model.Transport](../../lib/jido_ai/model/transport.ex) separates production calls from scripted tests. | [transport](../../test/authoring/agents/transport_test.exs), [routing](../../test/jido_ai/plugins/model_routing_test.exs) |
| Structured and multimodal data | [Output](../../lib/jido_ai/output.ex) validates output; [Query](../../lib/jido_ai/query.ex) handles content and references; [Turn](../../lib/jido_ai/turn.ex) holds AI turn data. Provider support still applies. | [output](../../test/jido_ai/output_test.exs), [query](../../test/jido_ai/query_test.exs), [limits](../../test/authoring/agents/output_limits_test.exs) |
| Tools and effects | [ToolCatalog](../../lib/jido_ai/tool_catalog.ex), [ToolAdapter](../../lib/jido_ai/tool_adapter.ex), context filtering, callbacks, and [Effects](../../lib/jido_ai/effects.ex) preserve trusted execution and state assembly. Root tool/prompt configuration helpers remain. | [tool API](../../test/jido_ai/tool_api_test.exs), [boundaries](../../test/authoring/agents/boundaries_test.exs), [tool examples](../../examples/03_tools) |
| Composable capabilities | [Plugins](../../lib/jido_ai/plugins) support Chat, Planning, Retrieval, Policy, ModelRouting, Quota, and callable reasoning through core Plugin facets. These remain distinct capabilities, not competing Agent authoring models. | [Plugin facets](../../test/jido_ai/plugin_facets_test.exs), [combinations](../../test/authoring/agents/combinations_test.exs) |
| Skills and resources | [Skill](../../lib/jido_ai/skill.ex) and its registry, discovery, resource, and runtime modules support explicit skill loading and policy. | [conformance](../../test/jido_ai/skill/conformance_test.exs), [runtime contracts](../../test/jido_ai/skill/runtime_contracts_test.exs) |
| Observation and testing | [Observe](../../lib/jido_ai/observe.ex), [Usage](../../lib/jido_ai/usage.ex), typed [Signals](../../lib/jido_ai/signal), and public [test helpers](../../lib/jido_ai/test.ex) remain. | [signal tests](../../test/jido_ai/signal), [authoring transport](../../test/authoring/agents/transport_test.exs) |

## Ownership and consolidation

- `jido_ai` owns model integration, AI behavior, tools, AI request orchestration,
  and AI policies. It also owns [Jido.Session](../../lib/jido_session.ex),
  [Jido.Thread](../../lib/jido_thread.ex), and
  [Jido.Thread.Entry](../../lib/jido_thread/entry.ex). Their module names do not
  imply ownership by core Jido. No package transfer is planned.
- Core Jido owns Agents, Plugins, AgentServer, state transitions, and OTP
  execution. `jido_action` owns Actions and Flows. `jido_signal` owns Signal
  envelopes and routing. AI-specific contracts stay here.
- File paths now follow module names. Orchestration Coordinator process, recovery, queue,
  and commit work stays together. Internal modules are not extra authoring APIs.
- Removed features: the execution CLI and adapters, CLI arithmetic tools, root
  strategy inspection helpers, old method-specific Agent macros, and flat
  callable configuration. Install, skill, and quality Mix tasks remain.
- Dynamic tool-source expansion remains on hold. Existing static/source
  declarations follow [ToolSource](../../lib/jido_ai/tool_source.ex).

## Verification and remaining work

The inventory reconciliation run passed **2,861 tests**, with one existing flaky
exclusion, including authoring, examples, and four inventory checks. Format,
forced compile, and inventory drift checks passed. The preceding consumer
migration also passed a separate **658-test** example run. See the
[verification record](status.md).

Examples and authoring tests are migrated, not deferred. Remaining release work
includes reconciling other guides, release metadata, and final validation.
Live-provider quality, load testing, and fresh line coverage remain unverified.
Do not use historic pending rows as a current defect list, or deterministic
example results as proof that every provider/model combination works.
