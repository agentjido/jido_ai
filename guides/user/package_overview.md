# Package Overview (Production Map)

You want a clear map of what `jido_ai` provides before production rollout.

After this guide, you should be able to explain the package in a prioritized way and choose the right integration surface for each workload.

## Core Product Surface

`jido_ai` is an AI runtime layer for Jido agents with:

1. One Agent DSL with built-in reasoning methods
2. Tool-calling orchestration over `Jido.Action` modules
3. Strategy-agnostic skills loading and registry
4. Plugin-based capability mixins for reusable runtime features
5. Action APIs for direct AI workflows outside `Jido.AI.Agent`
6. First-class observability via runtime events, signals, and telemetry
7. Public ExUnit helpers for deterministic ReAct tests without ReqLLM stubs

## Portable Interaction Values

`Jido.Thread` is an append-only interaction log. `Jido.Session` owns one
Thread and adds a portable lifecycle and metadata value. These modules do not
own a process, runtime server, storage adapter, or live model request.

`Jido.Session` is separate from `Jido.AI.Orchestration`. The first is portable data.
The second is the live request API for an AI agent process.

## Priority 1: `Jido.AI.Agent`

`Jido.AI.Agent` is the anchor feature.

- It adds the Spark-based Jido AI DSL to a core Agent.
- It lowers each `ai` block into an inert `Jido.AI.Profile`.
- It supports all built-in reasoning methods through one authoring form.
- It supports request handles and async orchestration (`ask/await/ask_sync`).
- ReAct requests can narrow tools per run with `allowed_tools` or fully override them with `tools`.
- It uses standardized lifecycle and runtime contracts (`ai.request.*`, `ai.llm.*`, `ai.tool.*`).

This is the only public AI Agent authoring macro.

## Priority 2: Reasoning Methods

Select a method in the Agent's `reasoning` DSL block:

- `:react`
- `:chain_of_draft`
- `:chain_of_thought`
- `:algorithm_of_thoughts`
- `:tree_of_thoughts`
- `:graph_of_thoughts`
- `:trm`
- `:adaptive`

```elixir
ai :assistant do
  models do
    model(:answer, :fast)
  end

  reasoning :tree_of_thoughts do
    model(:answer)
    options(branching_factor: 3, max_depth: 4, top_k: 3)
  end

  requests do
    mode(:session)
  end

  result(nil, into: :answer)
end
```

Tree of Thoughts returns a structured result with `best`, `candidates`,
`termination`, `tree`, `usage`, and `diagnostics` fields. Configure method
options in the reasoning block. Configure shared limits in the `controls`
block.

## Priority 3: Skills System (`SKILL.md` / skills.io-aligned workflow)

Skills are reusable instruction/capability units loaded at runtime:

- `Jido.AI.Skill.Loader` parses skill files.
- `Jido.AI.Skill.Registry` stores specs and session-scoped activations.
- The `skills` DSL block accepts skill modules and bounded discovery sources.
- Agents receive a compact catalog and load full instructions only when needed.
- Runtime specs can use a host `resource_provider` callback for fresh, policy-bounded resources.
- Activated skill content is retained across ReAct context compaction.
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
   - `Jido.AI.Plugins.Reasoning.ChainOfDraft`
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

Where plugins fit:

- Strategies decide control flow and reasoning mechanics.
- Plugins package reusable capabilities and policy.
- Actions remain the executable units behind both plugins and direct workflows.

Signal namespace contract for this plugin surface:

- `chat.message`
- `reasoning.cod.run`
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
5. Skill orchestration
   - `Jido.AI.Actions.Skill.LoadSkill` (lazy skill body loading from a compact prompt index)
   - `Jido.AI.Actions.Skill.LoadResource` (bounded text loading from an activated skill)
6. Dedicated strategy orchestration
   - `Jido.AI.Actions.Reasoning.RunStrategy` (isolated strategy execution for `:cod | :cot | :aot | :tot | :got | :trm | :adaptive`)
7. Text generation convenience
   - `Jido.AI.Actions.LLM.Complete` for a simple completion request

Not part of standalone action surface:

- Strategy-internal command actions (`*_start`, `*_llm_result`, `*_llm_partial`, worker lifecycle events).
- These are orchestration internals for ReAct/CoD/CoT/AoT/ToT/GoT/TRM/Adaptive strategies, not reusable app-level primitives.

Pragmatically:

- `Jido.AI.Agent` is the primary authoring surface for long-lived agent orchestration.
- Direct actions are the flexible lower-level surface for pipelines, jobs, and custom runtime composition.

## Testing Surface

`Jido.AI.TestCase` and `Jido.AI.Test` provide deterministic ReAct scripts for consumer tests:

- `expect_react` scripts user prompts, model tool calls, final answers, and model failures.
- `react_opts(script)` passes a script through agent request options.
- `react_llm_opts(script)` passes a script through standalone ReAct config `:llm_opts`.
- `assert_tool_called`, `assert_final_answer`, and `assert_no_runtime_failure` assert against canonical runtime events.

These helpers replace only the model decision boundary. The application still executes its own tools, runtime lifecycle, event projection, and domain assertions.

## Runtime Map (End-To-End)

```text
User/App Query
  -> Jido.AI.Agent route and Profile
  -> Jido.AI.Orchestration admission
  -> Reasoning Flow and Actions
  -> ReqLLM and Jido.Exec
  -> Session events and public Signals
  -> validated Agent candidate
  -> request completion and await result
```

## Observability Guarantees

Observability is a core part of the package, not an add-on:

- Typed signal contracts for lifecycle, LLM, tool, and usage events
- Action and Session execution boundaries
- Telemetry events for request, LLM, and tool phases
- Request IDs and run IDs for correlation across async boundaries

## Production Positioning Summary

When describing `jido_ai` for production, the concise version is:

1. A ReAct-first AI agent framework (`Jido.AI.Agent`) with built-in tool calling.
2. A multi-strategy reasoning platform (CoD, CoT, AoT, ToT, GoT, TRM, Adaptive, ReAct).
3. A reusable skills layer for domain behavior packaging.
4. A plugin layer for mountable capability mixins and policy controls.
5. A lower-level actions API for strategy-independent AI workflows.
6. Full runtime observability through events, signals, and telemetry.

## Next

- [First Agent](first_react_agent.md)
- [Request Lifecycle And Concurrency](request_lifecycle_and_concurrency.md)
- [Strategy Selection Playbook](strategy_selection_playbook.md)
- [Migration Guide: Plugins And Signals (v2 -> v3)](migration_plugins_and_signals_v3.md)
- [Architecture And Runtime Flow](../developer/architecture_and_runtime_flow.md)
