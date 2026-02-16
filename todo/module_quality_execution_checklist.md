# Module Quality Execution Checklist

## Phase 0 - Plan and Tracking
- [x] Add `MODULE_QUALITY_PLAN.md`
- [x] Add this execution checklist
- [x] Add namespace migration matrix
- [x] Add skipped-test replacement matrix
Evidence:
- `MODULE_QUALITY_PLAN.md`
- `todo/module_namespace_breaking_changes.md`
- `todo/module_test_unskip_matrix.md`

## Phase 1 - Lifecycle Parity
- [x] Preserve `request_id` correlation on all strategies
- [x] Add request-error actions/routes for CoT/ToT/GoT/TRM/Adaptive
- [x] Mark rejected requests failed in all non-ReAct agent macros
- [x] Validate second concurrent request is rejected deterministically for all strategies
Evidence:
- `lib/jido_ai/strategies/chain_of_thought.ex`
- `lib/jido_ai/strategies/tree_of_thoughts.ex`
- `lib/jido_ai/strategies/graph_of_thoughts.ex`
- `lib/jido_ai/strategies/trm.ex`
- `lib/jido_ai/strategies/adaptive.ex`
- `lib/jido_ai/agents/strategies/cot_agent.ex`
- `lib/jido_ai/agents/strategies/tot_agent.ex`
- `lib/jido_ai/agents/strategies/got_agent.ex`
- `lib/jido_ai/agents/strategies/trm_agent.ex`
- `lib/jido_ai/agents/strategies/adaptive_agent.ex`
- `test/jido_ai/integration/request_lifecycle_parity_test.exs`
- `test/jido_ai/integration/request_await_rejection_test.exs`

## Phase 2 - Hard Namespace Migration
- [x] Add centralized namespace constants
- [x] Migrate signal types and route maps to `ai.*`
- [x] Migrate request emission signal types in all agents/orchestrator
- [x] Rename ReAct action atoms and action-spec names to `ai_react_*` / `ai.react.*`
- [x] Migrate tool registration APIs to `ai.react.register_tool` / `ai.react.unregister_tool`
Evidence:
- `lib/jido_ai/namespaces.ex`
- `lib/jido_ai/signal.ex`
- `lib/jido_ai/directive.ex`
- `lib/jido_ai/strategies/react.ex`
- `lib/jido_ai/agents/strategies/react_agent.ex`
- `lib/jido_ai/agents/orchestration/orchestrator_agent.ex`
- `lib/jido_ai.ex`
- `test/jido_ai/integration/jido_v2_migration_test.exs`

## Phase 3 - Observability Generalization
- [x] Add observability events/emitter modules
- [x] Migrate telemetry event names to `[:jido, :ai, :request|llm|tool, ...]`
- [x] Update directive and machine emission call sites
- [x] Replace ReAct-only event spec with AI-wide event spec
Evidence:
- `lib/jido_ai/observability/events.ex`
- `lib/jido_ai/observability/emitter.ex`
- `lib/jido_ai/directive.ex`
- `lib/jido_ai/strategies/react/machine.ex`
- `todo/ai_observability_event_spec.md`

## Phase 4 - Action Quality Sweep
- [x] Standardize model parameter schema/runtime behavior for alias atoms
- [x] Consolidate usage extraction with `total_tokens` fallback behavior
- [x] Fix tool-calling multi-turn option preservation and deterministic terminal shape
- [x] Harden planning prioritize score parsing
- [x] Implement real streaming lifecycle + registry
- [x] Enforce structured streaming errors (no raises for missing supervisor)
- [x] Make `auto_process: false` truly deferred to `ProcessTokens`
Evidence:
- `lib/jido_ai/actions/planning/plan.ex`
- `lib/jido_ai/actions/planning/decompose.ex`
- `lib/jido_ai/actions/planning/prioritize.ex`
- `lib/jido_ai/actions/reasoning/analyze.ex`
- `lib/jido_ai/actions/reasoning/explain.ex`
- `lib/jido_ai/actions/reasoning/infer.ex`
- `lib/jido_ai/actions/helpers.ex`
- `lib/jido_ai/actions/tool_calling/call_with_tools.ex`
- `lib/jido_ai/actions/streaming/start_stream.ex`
- `lib/jido_ai/actions/streaming/process_tokens.ex`
- `lib/jido_ai/actions/streaming/end_stream.ex`
- `lib/jido_ai/streaming/registry.ex`
- `test/jido_ai/skills/tool_calling/actions/call_with_tools_test.exs`
- `test/jido_ai/skills/streaming/actions/start_stream_test.exs`
- `test/jido_ai/skills/streaming/actions/process_tokens_test.exs`
- `test/jido_ai/skills/streaming/actions/end_stream_test.exs`

## Phase 5 - Deterministic Testing and De-Skips
- [x] Add LLM client boundary and ReqLLM implementation module
- [x] Route action/directive LLM calls through LLM client boundary
- [x] Add test doubles/helpers under `test/support`
- [x] Remove all `@tag :skip` tests
- [x] Add missing CoT/GoT/TRM/Adaptive macro tests
- [x] Rewrite v2 migration integration test for strict 2.0-beta names
Evidence:
- `lib/jido_ai/actions/llm/chat.ex`
- `lib/jido_ai/directive.ex`
- `test/support/fake_req_llm.ex`
- `test/jido_ai/cot_agent_test.exs`
- `test/jido_ai/got_agent_test.exs`
- `test/jido_ai/trm_agent_test.exs`
- `test/jido_ai/adaptive_agent_test.exs`
- `test/jido_ai/integration/jido_v2_migration_test.exs`
- `rg -n "@tag :skip" test` -> zero matches

## Phase 6 - Docs and Examples
- [x] Migrate README/guides/examples to new namespace contracts
- [x] Add namespace migration guide
- [x] Mark `REACT_QUALITY_PLAN.md` as superseded
Evidence:
- `README.md`
- `guides/developer/02_strategies.md`
- `guides/developer/04_directives.md`
- `guides/developer/05_signals.md`
- `guides/developer/09_namespace_migration.md`
- `lib/jido_ai/agents/examples/issue_triage_agent.ex`
- `lib/jido_ai/agents/examples/task_list_agent.ex`
- `REACT_QUALITY_PLAN.md`

## Phase 7 - Quality Gates
- [x] `mix test`
- [x] `mix quality`
- [x] `mix docs`
- [x] `mix coveralls`
- [x] grep gates for removed names and skipped tests
Evidence:
- `mix test` -> `30 doctests, 1608 tests, 0 failures (2 excluded)`
- `mix quality` -> pass (credo + dialyzer)
- `mix docs` -> pass
- `mix coveralls` -> pass
- `rg -n "@tag :skip" test` -> zero matches
- `rg -n "react\\.(llm|tool|request|embed|usage|input|cancel|register_tool|unregister_tool|set_tool_context)" lib test guides examples README.md` -> only intentional `ai.react.*` and strict-break assertions
