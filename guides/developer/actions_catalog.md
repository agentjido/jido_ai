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
4. Reasoning templates (optional):
   - `Jido.AI.Actions.Reasoning.Analyze`
   - `Jido.AI.Actions.Reasoning.Infer`
   - `Jido.AI.Actions.Reasoning.Explain`
5. Dedicated strategy orchestration:
   - `Jido.AI.Actions.Reasoning.RunStrategy`
6. Compatibility convenience:
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
  - Goal-to-step plan generation.
- `Jido.AI.Actions.Planning.Decompose`
  - Hierarchical goal decomposition.
- `Jido.AI.Actions.Planning.Prioritize`
  - Task prioritization under criteria/context.

## Reasoning Actions

- `Jido.AI.Actions.Reasoning.Analyze`
  - Structured analysis by analysis type.
- `Jido.AI.Actions.Reasoning.Infer`
  - Logical inference from premises and question.
- `Jido.AI.Actions.Reasoning.Explain`
  - Explanations with detail-level targeting.
- `Jido.AI.Actions.Reasoning.RunStrategy`
  - Executes a dedicated reasoning strategy runner (`:cod | :cot | :aot | :tot | :got | :trm | :adaptive`) independent of host strategy.
  - ToT strategy runs return structured payloads (best/candidates/termination/tree/usage/diagnostics).

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
