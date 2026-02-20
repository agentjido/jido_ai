# Package Overview (Production Map)

You want a clear map of what `jido_ai` provides before production rollout.

After this guide, you should be able to explain the package in a prioritized way and choose the right integration surface for each workload.

## Core Product Surface

`jido_ai` is an AI runtime layer for Jido agents with:

1. Agent macros with built-in reasoning strategies
2. Tool-calling orchestration over `Jido.Action` modules
3. Strategy-agnostic skills loading and registry
4. Plugin-based capability mixins for reusable runtime features
5. Action APIs for direct AI workflows outside agent macros
6. First-class observability via signals, directives, and telemetry

## Priority 1: `Jido.AI.Agent` (Default ReAct Agent)

`Jido.AI.Agent` is the anchor feature.

- It is the generic AI agent macro.
- Under the hood it uses `Jido.AI.Reasoning.ReAct.Strategy`.
- It is built for tool use through a ReAct loop (reason, call tool, continue).
- It supports request handles and async orchestration (`ask/await/ask_sync`).
- It uses standardized lifecycle and runtime contracts (`ai.request.*`, `ai.llm.*`, `ai.tool.*`).

If your production workload needs reliable tool-calling agents, this is the default entry point.

## Priority 2: Multi-Strategy Agent Macros

`jido_ai` ships specialized agent macros for different reasoning patterns:

- `Jido.AI.CoTAgent` -> `Jido.AI.Reasoning.ChainOfThought.Strategy`
- `Jido.AI.AoTAgent` -> `Jido.AI.Reasoning.AlgorithmOfThoughts.Strategy`
- `Jido.AI.ToTAgent` -> `Jido.AI.Reasoning.TreeOfThoughts.Strategy`
- `Jido.AI.GoTAgent` -> `Jido.AI.Reasoning.GraphOfThoughts.Strategy`
- `Jido.AI.TRMAgent` -> `Jido.AI.Reasoning.TRM.Strategy`
- `Jido.AI.AdaptiveAgent` -> `Jido.AI.Reasoning.Adaptive.Strategy`

Supported strategy family:

- ReAct
- Chain-of-Thought
- Algorithm-of-Thoughts
- Tree-of-Thoughts
- Graph-of-Thoughts
- TRM
- Adaptive

Use these when reasoning policy is part of the product requirement, not just a model prompt detail.

### Tree-of-Thoughts Runtime Contract (Production)

`Jido.AI.ToTAgent` now returns a structured result contract (hard switch), not a plain string:

- `best`: best-ranked candidate
- `candidates`: top-K ranked leaves
- `termination`: reason/status/depth/node-count/duration
- `tree`: traversal and search-shape metadata
- `usage`: accumulated token usage
- `diagnostics`: parser mode/retries, convergence, tool-round diagnostics

ToT flexibility controls exposed at the agent macro level:

- `top_k`, `min_depth`, `max_nodes`, `max_duration_ms`, `beam_width`
- `early_success_threshold`, `convergence_window`, `min_score_improvement`
- `max_parse_retries`
- `tools`, `tool_context`, `tool_timeout_ms`, `tool_max_retries`, `tool_retry_backoff_ms`, `max_tool_round_trips`

## Priority 3: Skills System (`SKILL.md` / skills.io-aligned workflow)

Skills are reusable instruction/capability units loaded at runtime:

- `Jido.AI.Skill.Loader` parses skill files.
- `Jido.AI.Skill.Registry` stores and resolves active skills.
- Skills are strategy-agnostic and can be injected into agent behavior/context.
- Skills are useful for domain behavior reuse without duplicating agent code.

This is the main packaging mechanism for reusable AI behavior in your system.

## Priority 4: Plugins As Capability Mixins

Plugins should represent product capabilities, not low-level runtime plumbing.

Recommended plugin set (target production surface):

1. `Jido.AI.Plugins.Chat` (anchor capability)
   - Unified conversational interface with built-in tool calling.
   - Replaces split end-user mental model of separate `LLM` + `ToolCalling` plugins.
   - Supports simple chat usage and tool-augmented chat under one contract.
2. `Jido.AI.Plugins.Planning`
   - Structured planning, decomposition, and prioritization flows.
3. Strategy invocation plugins (explicit reasoning as capabilities):
   - `Jido.AI.Plugins.Reasoning.ChainOfThought`
   - `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts`
   - `Jido.AI.Plugins.Reasoning.TreeOfThoughts`
   - `Jido.AI.Plugins.Reasoning.GraphOfThoughts`
   - `Jido.AI.Plugins.Reasoning.TRM`
   - `Jido.AI.Plugins.Reasoning.Adaptive`
   - These expose reasoning strategies as callable plugin capabilities, independent of which agent macro strategy is primary.
4. Cross-cutting policy plugins (production hardening):
   - model routing/fallback
   - guardrails and safety policy
   - memory/retrieval enrichment
   - cost/quota/rate limiting

Non-goal for public plugin surface:

- `TaskSupervisor` should not be treated as a primary user-facing capability plugin.
- Async execution infrastructure should be handled by Jido runtime/Jido.Exec primitives and internal runtime wiring.

Where plugins fit:

- Strategies decide control flow and reasoning mechanics.
- Plugins package reusable capabilities and policy.
- Actions remain the executable units behind both plugins and direct workflows.

Signal namespace contract for this plugin surface:

- `chat.message`
- `reasoning.cot.run`
- `reasoning.aot.run`
- `reasoning.tot.run`
- `reasoning.got.run`
- `reasoning.trm.run`
- `reasoning.adaptive.run`

## Priority 5: Actions As Independent Integration Surface

Standalone actions are the strategy-independent integration path for adding AI behavior directly to Jido apps via `Jido.Exec`.

Finalized standalone action set (recommended):

1. Core generation primitives
   - `Jido.AI.Actions.LLM.Chat` (single-turn conversational generation)
   - `Jido.AI.Actions.LLM.GenerateObject` (schema-constrained structured output)
   - `Jido.AI.Actions.LLM.Embed` (embedding generation for retrieval/search)
2. Tool orchestration primitives
   - `Jido.AI.Actions.ToolCalling.CallWithTools` (LLM + tool schema + optional auto-execution loop)
   - `Jido.AI.Actions.ToolCalling.ExecuteTool` (direct tool execution by name)
   - `Jido.AI.Actions.ToolCalling.ListTools` (tool discovery and schema inspection)
3. Planning domain templates
   - `Jido.AI.Actions.Planning.Plan`
   - `Jido.AI.Actions.Planning.Decompose`
   - `Jido.AI.Actions.Planning.Prioritize`
4. Reasoning domain templates (optional, useful outside full strategy orchestration)
   - `Jido.AI.Actions.Reasoning.Analyze`
   - `Jido.AI.Actions.Reasoning.Infer`
   - `Jido.AI.Actions.Reasoning.Explain`
5. Dedicated strategy orchestration
   - `Jido.AI.Actions.Reasoning.RunStrategy` (isolated strategy execution for `:cot | :aot | :tot | :got | :trm | :adaptive`)
6. Compatibility convenience
   - `Jido.AI.Actions.LLM.Complete` (simple completion path; overlaps with `Chat` and can remain as convenience)

Not part of standalone action surface:

- Strategy-internal command actions (`*_start`, `*_llm_result`, `*_llm_partial`, worker lifecycle events).
- These are orchestration internals for ReAct/CoT/AoT/ToT/GoT/TRM/Adaptive strategies, not reusable app-level primitives.

Pragmatically:

- Agent macros are the primary production surface for long-lived agent orchestration.
- Direct actions are the flexible lower-level surface for pipelines, jobs, and custom runtime composition.

## Runtime Map (End-To-End)

```text
User/App Query
  -> Agent Macro (Jido.AI.Agent or strategy-specific agent)
  -> Strategy (ReAct/CoT/AoT/ToT/GoT/TRM/Adaptive)
  -> Directives (LLM, tool, control intents)
  -> Runtime Execution (ReqLLM + tool execution)
  -> Signals (ai.request.*, ai.llm.*, ai.tool.*, ai.usage)
  -> Strategy state updates
  -> Request completion/await result
```

## Observability Guarantees

Observability is a core part of the package, not an add-on:

- Typed signal contracts for lifecycle, LLM, tool, and usage events
- Directive-level execution boundaries
- Telemetry events for request, LLM, and tool phases
- Request IDs and run IDs for correlation across async boundaries

## Production Positioning Summary

When describing `jido_ai` for production, the concise version is:

1. A ReAct-first AI agent framework (`Jido.AI.Agent`) with built-in tool calling.
2. A multi-strategy reasoning platform (CoT, AoT, ToT, GoT, TRM, Adaptive, ReAct).
3. A reusable skills layer for domain behavior packaging.
4. A plugin layer for mountable capability mixins and policy controls.
5. A lower-level actions API for strategy-independent AI workflows.
6. Full runtime observability through directives, signals, and telemetry.

## Next

- [First Agent](first_react_agent.md)
- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Strategy Selection Playbook](strategy_selection_playbook.md)
- [Migration Guide: Plugins And Signals (v2 -> v3)](migration_plugins_and_signals_v3.md)
- [Architecture And Runtime Flow](../developer/architecture_and_runtime_flow.md)
