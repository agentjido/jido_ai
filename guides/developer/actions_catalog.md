# Actions Catalog

This guide is the quick inventory of built-in `Jido.AI.Actions.*` modules and what each one is for.

## Production Baseline (Standalone Surface)

For direct app integration (`Jido.Exec`-driven), this is the primary standalone action surface:

1. Core generation:
   - `Jido.AI.Actions.LLM.Chat`
   - `Jido.AI.Actions.LLM.GenerateObject`
   - `Jido.AI.Actions.LLM.Embed`
2. Tool orchestration:
   - `Jido.AI.Actions.ToolCalling.CallWithTools`
   - `Jido.AI.Actions.ToolCalling.ExecuteTool`
   - `Jido.AI.Actions.ToolCalling.ListTools`
3. Planning templates:
   - `Jido.AI.Actions.Planning.Plan`
   - `Jido.AI.Actions.Planning.Decompose`
   - `Jido.AI.Actions.Planning.Prioritize`
4. Retrieval memory operations:
   - `Jido.AI.Actions.Retrieval.UpsertMemory`
   - `Jido.AI.Actions.Retrieval.RecallMemory`
   - `Jido.AI.Actions.Retrieval.ClearMemory`
5. Quota operations:
   - `Jido.AI.Actions.Quota.GetStatus`
   - `Jido.AI.Actions.Quota.Reset`
6. Reasoning templates (optional):
   - `Jido.AI.Actions.Reasoning.Analyze`
   - `Jido.AI.Actions.Reasoning.Infer`
   - `Jido.AI.Actions.Reasoning.Explain`
7. Dedicated strategy orchestration:
   - `Jido.AI.Actions.Reasoning.RunStrategy`
8. Compatibility convenience:
   - `Jido.AI.Actions.LLM.Complete`

## LLM Actions

- `Jido.AI.Actions.LLM.Chat`
  - Use when you need single-turn conversational output with optional system prompt and chat/plugin defaults.
  - Runnable example: [`lib/examples/scripts/demo/actions_llm_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_llm_runtime_demo.exs)
- `Jido.AI.Actions.LLM.Complete`
  - Use when you want compatibility-style prompt completion without object constraints.
  - Runnable example: [`lib/examples/scripts/demo/actions_llm_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_llm_runtime_demo.exs)
- `Jido.AI.Actions.LLM.Embed`
  - Use when you need vector embeddings for retrieval, semantic search, or similarity tasks.
  - Runnable example: [`lib/examples/scripts/demo/actions_llm_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_llm_runtime_demo.exs)
- `Jido.AI.Actions.LLM.GenerateObject`
  - Use when downstream code expects schema-constrained structured output.
  - Runnable example: [`lib/examples/scripts/demo/actions_llm_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_llm_runtime_demo.exs)

## Tool Calling Actions

- `Jido.AI.Actions.ToolCalling.CallWithTools`
  - Use when the model should decide whether to call tools, with optional `auto_execute` loop continuation.
  - Runnable example: [`lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs)
- `Jido.AI.Actions.ToolCalling.ExecuteTool`
  - Use when your app already selected the tool and arguments and needs deterministic direct execution.
  - Runnable example: [`lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs)
- `Jido.AI.Actions.ToolCalling.ListTools`
  - Use when you need tool discovery, optional schema projection, and sensitive-name filtering.
  - Runnable example: [`lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_tool_calling_runtime_demo.exs)

## Planning Actions

- `Jido.AI.Actions.Planning.Plan`
  - Use when you need a sequential execution plan from one goal.
  - Runnable example: [`lib/examples/scripts/demo/actions_planning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_planning_runtime_demo.exs)
- `Jido.AI.Actions.Planning.Decompose`
  - Use when the goal is too large and should be split into hierarchical sub-goals.
  - Runnable example: [`lib/examples/scripts/demo/actions_planning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_planning_runtime_demo.exs)
- `Jido.AI.Actions.Planning.Prioritize`
  - Use when you already have a task list and need ranked execution order.
  - Runnable example: [`lib/examples/scripts/demo/actions_planning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_planning_runtime_demo.exs)

## Retrieval Actions

- `Jido.AI.Actions.Retrieval.UpsertMemory`
  - Use when you need to persist a memory snippet into the in-process retrieval namespace.
  - Required params: `text`. Optional params: `id`, `metadata`, `namespace`.
  - Output contract: `%{retrieval: %{namespace, last_upsert}}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs)
- `Jido.AI.Actions.Retrieval.RecallMemory`
  - Use when you need top-k memory recall for a query from a namespace.
  - Required params: `query`. Optional params: `top_k` (default `3`), `namespace`.
  - Output contract: `%{retrieval: %{namespace, query, memories, count}}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs)
- `Jido.AI.Actions.Retrieval.ClearMemory`
  - Use when you need to clear all in-process retrieval memory entries in one namespace.
  - Required params: none. Optional params: `namespace`.
  - Output contract: `%{retrieval: %{namespace, cleared}}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_retrieval_runtime_demo.exs)

## Quota Actions

- `Jido.AI.Actions.Quota.GetStatus`
  - Use when you need the current rolling quota snapshot for one scope.
  - Required params: none. Optional params: `scope`.
  - Scope resolution when `scope` is omitted: `context[:plugin_state][:quota][:scope]` -> `context[:state][:quota][:scope]` -> `context[:agent][:id]` -> `"default"`.
  - Output contract: `%{quota: %{scope, window_ms, usage, limits, remaining, over_budget?}}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_quota_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_quota_runtime_demo.exs)
- `Jido.AI.Actions.Quota.Reset`
  - Use when you need to clear rolling quota counters for one scope.
  - Required params: none. Optional params: `scope`.
  - Scope resolution when `scope` is omitted: `context[:plugin_state][:quota][:scope]` -> `context[:state][:quota][:scope]` -> `context[:agent][:id]` -> `"default"`.
  - Output contract: `%{quota: %{scope, reset}}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_quota_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_quota_runtime_demo.exs)

## Reasoning Actions

- `Jido.AI.Actions.Reasoning.Analyze`
  - Use when you need structured analysis (`:sentiment | :topics | :entities | :summary | :custom`) over one input.
  - Output contract: `%{result, analysis_type, model, usage}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs)
- `Jido.AI.Actions.Reasoning.Infer`
  - Use when you have explicit premises and need an inference for a specific question.
  - Output contract: `%{result, reasoning, model, usage}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs)
- `Jido.AI.Actions.Reasoning.Explain`
  - Use when you need audience-aware explanation depth (`:basic | :intermediate | :advanced`).
  - Output contract: `%{result, detail_level, model, usage}`.
  - Runnable example: [`lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs)
- `Jido.AI.Actions.Reasoning.RunStrategy`
  - Use when you need explicit strategy execution independent of host agent strategy.
  - Required parameters: `strategy` (`:cod | :cot | :tot | :got | :trm | :aot | :adaptive`) and `prompt`.
  - Strategy tuning parameters can be passed at top-level or inside `options`; top-level keys win when both are set.
  - Output contract: `%{strategy, status, output, usage, diagnostics}` where `diagnostics` includes timeout, options, snapshot status, and sanitized errors.
  - Runnable example: [`lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs`](https://github.com/agentjido/jido_ai/blob/v2.0.0-rc.0/lib/examples/scripts/demo/actions_reasoning_runtime_demo.exs)

## Shared Helpers

- `Jido.AI.Actions.Helpers`
  - model resolution, security/input checks, response text/usage extraction.

## Not Standalone: Strategy Internals

Reasoning strategy command atoms and lifecycle/event handlers are intentionally not standalone actions:

- `:cod_start`, `:ai_react_start`, `:cot_start`, `:aot_start`, `:tot_start`, `:got_start`, `:trm_start`, `:adaptive_start`
- `*_llm_result`, `*_llm_partial`, request error lifecycle handlers, worker event handlers

These belong to strategy orchestration and are not app-level AI primitives.

## Selection Heuristic

- Need chat/completion/embed/object output: use LLM actions.
- Need model-directed tool use: use Tool Calling actions.
- Need structured planning templates: use Planning actions.
- Need in-process memory upsert/recall/clear primitives: use Retrieval actions.
- Need rolling quota status or a quota counter reset operation: use Quota actions.
- Need explicit reasoning strategy execution as a callable capability: use `RunStrategy`.

## Failure Mode: Action Used Outside Expected Context

Symptom:

- runtime errors due to missing tool context or model/provider config

Fix:

- pass required context explicitly
- verify model/provider config and tool maps before execution
- for plugin-routed calls, ensure plugin state keys match mounted capability

## Next

- [Plugins And Actions Composition](plugins_and_actions_composition.md)
- [Tool Calling With Actions](../user/tool_calling_with_actions.md)
- [Migration Guide: Plugins And Signals (v2 -> v3)](../user/migration_plugins_and_signals_v3.md)
