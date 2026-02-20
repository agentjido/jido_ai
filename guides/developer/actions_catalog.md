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
5. Reasoning templates (optional):
   - `Jido.AI.Actions.Reasoning.Analyze`
   - `Jido.AI.Actions.Reasoning.Infer`
   - `Jido.AI.Actions.Reasoning.Explain`
6. Dedicated strategy orchestration:
   - `Jido.AI.Actions.Reasoning.RunStrategy`
7. Compatibility convenience:
   - `Jido.AI.Actions.LLM.Complete`

## LLM Actions

- `Jido.AI.Actions.LLM.Chat`
  - Use when you need single-turn conversational output with optional system prompt and chat/plugin defaults.
  - Example snippet: [`lib/examples/actions/llm_actions.md#chat-action`](../../lib/examples/actions/llm_actions.md#chat-action)
- `Jido.AI.Actions.LLM.Complete`
  - Use when you want compatibility-style prompt completion without object constraints.
  - Example snippet: [`lib/examples/actions/llm_actions.md#complete-action`](../../lib/examples/actions/llm_actions.md#complete-action)
- `Jido.AI.Actions.LLM.Embed`
  - Use when you need vector embeddings for retrieval, semantic search, or similarity tasks.
  - Example snippet: [`lib/examples/actions/llm_actions.md#embed-action`](../../lib/examples/actions/llm_actions.md#embed-action)
- `Jido.AI.Actions.LLM.GenerateObject`
  - Use when downstream code expects schema-constrained structured output.
  - Example snippet: [`lib/examples/actions/llm_actions.md#generateobject-action`](../../lib/examples/actions/llm_actions.md#generateobject-action)

## Tool Calling Actions

- `Jido.AI.Actions.ToolCalling.CallWithTools`
  - Use when the model should decide whether to call tools, with optional `auto_execute` loop continuation.
  - Example snippet: [`lib/examples/actions/tool_calling_actions.md#callwithtools-one-shot`](../../lib/examples/actions/tool_calling_actions.md#callwithtools-one-shot)
  - Example snippet: [`lib/examples/actions/tool_calling_actions.md#callwithtools-auto-execute`](../../lib/examples/actions/tool_calling_actions.md#callwithtools-auto-execute)
- `Jido.AI.Actions.ToolCalling.ExecuteTool`
  - Use when your app already selected the tool and arguments and needs deterministic direct execution.
  - Example snippet: [`lib/examples/actions/tool_calling_actions.md#executetool-direct`](../../lib/examples/actions/tool_calling_actions.md#executetool-direct)
- `Jido.AI.Actions.ToolCalling.ListTools`
  - Use when you need tool discovery, optional schema projection, and sensitive-name filtering.
  - Example snippet: [`lib/examples/actions/tool_calling_actions.md#listtools-discovery-and-security-filtering`](../../lib/examples/actions/tool_calling_actions.md#listtools-discovery-and-security-filtering)

## Planning Actions

- `Jido.AI.Actions.Planning.Plan`
  - Use when you need a sequential execution plan from one goal.
  - Example snippet: [`lib/examples/actions/planning_actions.md#plan-action`](../../lib/examples/actions/planning_actions.md#plan-action)
- `Jido.AI.Actions.Planning.Decompose`
  - Use when the goal is too large and should be split into hierarchical sub-goals.
  - Example snippet: [`lib/examples/actions/planning_actions.md#decompose-action`](../../lib/examples/actions/planning_actions.md#decompose-action)
- `Jido.AI.Actions.Planning.Prioritize`
  - Use when you already have a task list and need ranked execution order.
  - Example snippet: [`lib/examples/actions/planning_actions.md#prioritize-action`](../../lib/examples/actions/planning_actions.md#prioritize-action)
  - Workflow snippet: [`lib/examples/actions/planning_actions.md#planning-workflow-with-task-decomposition`](../../lib/examples/actions/planning_actions.md#planning-workflow-with-task-decomposition)

## Retrieval Actions

- `Jido.AI.Actions.Retrieval.UpsertMemory`
  - Use when you need to persist a memory snippet into the in-process retrieval namespace.
  - Required params: `text`. Optional params: `id`, `metadata`, `namespace`.
  - Output contract: `%{retrieval: %{namespace, last_upsert}}`.
  - Example snippet: [`lib/examples/actions/retrieval_actions.md#upsertmemory-action`](../../lib/examples/actions/retrieval_actions.md#upsertmemory-action)
- `Jido.AI.Actions.Retrieval.RecallMemory`
  - Use when you need top-k memory recall for a query from a namespace.
  - Required params: `query`. Optional params: `top_k` (default `3`), `namespace`.
  - Output contract: `%{retrieval: %{namespace, query, memories, count}}`.
  - Example snippet: [`lib/examples/actions/retrieval_actions.md#recallmemory-action`](../../lib/examples/actions/retrieval_actions.md#recallmemory-action)
- `Jido.AI.Actions.Retrieval.ClearMemory`
  - Use when you need to clear all in-process retrieval memory entries in one namespace.
  - Required params: none. Optional params: `namespace`.
  - Output contract: `%{retrieval: %{namespace, cleared}}`.
  - Example snippet: [`lib/examples/actions/retrieval_actions.md#clearmemory-action`](../../lib/examples/actions/retrieval_actions.md#clearmemory-action)

## Reasoning Actions

- `Jido.AI.Actions.Reasoning.Analyze`
  - Use when you need structured analysis (`:sentiment | :topics | :entities | :summary | :custom`) over one input.
  - Output contract: `%{result, analysis_type, model, usage}`.
  - Example snippet: [`lib/examples/actions/reasoning_actions.md#analyze-action`](../../lib/examples/actions/reasoning_actions.md#analyze-action)
- `Jido.AI.Actions.Reasoning.Infer`
  - Use when you have explicit premises and need an inference for a specific question.
  - Output contract: `%{result, reasoning, model, usage}`.
  - Example snippet: [`lib/examples/actions/reasoning_actions.md#infer-action`](../../lib/examples/actions/reasoning_actions.md#infer-action)
- `Jido.AI.Actions.Reasoning.Explain`
  - Use when you need audience-aware explanation depth (`:basic | :intermediate | :advanced`).
  - Output contract: `%{result, detail_level, model, usage}`.
  - Example snippet: [`lib/examples/actions/reasoning_actions.md#explain-action`](../../lib/examples/actions/reasoning_actions.md#explain-action)
- `Jido.AI.Actions.Reasoning.RunStrategy`
  - Use when you need explicit strategy execution independent of host agent strategy.
  - Required parameters: `strategy` (`:cod | :cot | :tot | :got | :trm | :aot | :adaptive`) and `prompt`.
  - Strategy tuning parameters can be passed at top-level or inside `options`; top-level keys win when both are set.
  - Output contract: `%{strategy, status, output, usage, diagnostics}` where `diagnostics` includes timeout, options, snapshot status, and sanitized errors.
  - Example snippet: [`lib/examples/actions/reasoning_actions.md#runstrategy-action`](../../lib/examples/actions/reasoning_actions.md#runstrategy-action)
  - Coverage split guidance: fast-smoke subset lives in `test/jido_ai/skills/reasoning/actions/run_strategy_action_fast_test.exs`; full checkpoint matrix lives in `test/jido_ai/skills/reasoning/actions/run_strategy_action_test.exs`.

## Shared Helper

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
