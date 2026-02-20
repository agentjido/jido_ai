# Plugins And Actions Composition

You need a reliable way to compose mountable capabilities (plugins) with executable primitives (actions) without coupling to strategy internals.

After this guide, you can choose the right extension surface for each requirement.

## Public Plugin Surface (v3)

Public capability plugins:

- `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.Planning`
- `Jido.AI.Plugins.Reasoning.ChainOfDraft`
- `Jido.AI.Plugins.Reasoning.ChainOfThought`
- `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Plugins.Reasoning.TreeOfThoughts`
- `Jido.AI.Plugins.Reasoning.GraphOfThoughts`
- `Jido.AI.Plugins.Reasoning.TRM`
- `Jido.AI.Plugins.Reasoning.Adaptive`

Internal runtime plugin:

- `Jido.AI.Plugins.TaskSupervisor` (infrastructure, not a public capability recommendation)

Removed public plugins:

- `Jido.AI.Plugins.LLM`
- `Jido.AI.Plugins.ToolCalling`
- `Jido.AI.Plugins.Reasoning`

## Compose In Agent Definition

```elixir
defmodule MyApp.Assistant do
  use Jido.Agent,
    name: "assistant",
    plugins: [
      {Jido.AI.Plugins.Chat, %{default_model: :capable, auto_execute: true}},
      {Jido.AI.Plugins.Planning, %{}},
      {Jido.AI.Plugins.Reasoning.ChainOfThought, %{default_model: :reasoning}}
    ]
end
```

## Plugin Signal Contracts

- `Jido.AI.Plugins.Chat`
  - `chat.message` -> tool-aware chat (`CallWithTools`) with auto-execute defaulting to `true`
  - `chat.simple` -> direct chat generation
  - `chat.complete` -> completion convenience path
  - `chat.embed` -> embedding generation
  - `chat.generate_object` -> schema-constrained structured output
  - `chat.execute_tool` -> direct tool execution by tool name
  - `chat.list_tools` -> tool inventory for the active chat capability
- `Jido.AI.Plugins.Planning`
  - `planning.plan` -> structured plan generation (`Jido.AI.Actions.Planning.Plan`)
  - `planning.decompose` -> goal decomposition (`Jido.AI.Actions.Planning.Decompose`)
  - `planning.prioritize` -> task ordering (`Jido.AI.Actions.Planning.Prioritize`)
- `Jido.AI.Plugins.Reasoning.*`
  - `reasoning.cod.run`
  - `reasoning.cot.run`
  - `reasoning.aot.run`
  - `reasoning.tot.run`
  - `reasoning.got.run`
  - `reasoning.trm.run`
  - `reasoning.adaptive.run`
  - All route to `Jido.AI.Actions.Reasoning.RunStrategy` with fixed strategy identity.

### CoD Plugin Handoff (`reasoning.cod.run`)

```elixir
defmodule MyApp.CoDPluginAgent do
  use Jido.AI.Agent,
    name: "cod_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfDraft,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.cod.run",
    %{
      prompt: "Give me a terse plan with one backup.",
      strategy: :cot
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.cod.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.ChainOfDraft.handle_signal/2` overrides payload strategy to `strategy: :cod`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.

### CoT Plugin Handoff (`reasoning.cot.run`)

```elixir
defmodule MyApp.CoTPluginAgent do
  use Jido.AI.Agent,
    name: "cot_plugin_agent",
    plugins: [
      {Jido.AI.Plugins.Reasoning.ChainOfThought,
       %{
         default_model: :reasoning,
         timeout: 30_000,
         options: %{llm_timeout_ms: 20_000}
       }}
    ]
end

signal =
  Jido.Signal.new!(
    "reasoning.cot.run",
    %{
      prompt: "Lay out the reasoning steps and one fallback.",
      strategy: :cod
    },
    source: "/cli"
  )
```

Execution handoff:

- Route dispatch maps `reasoning.cot.run` to `Jido.AI.Actions.Reasoning.RunStrategy`.
- `Jido.AI.Plugins.Reasoning.ChainOfThought.handle_signal/2` overrides payload strategy to `strategy: :cot`.
- `RunStrategy` applies plugin defaults (`default_model`, `timeout`, `options`) from plugin state when omitted by caller params.

## Chat Plugin Defaults Contract

`Jido.AI.Plugins.Chat` mounts the following defaults unless overridden in plugin config:

- `default_model: :capable`
- `default_max_tokens: 4096`
- `default_temperature: 0.7`
- `default_system_prompt: nil`
- `auto_execute: true`
- `max_turns: 10`
- `tool_policy: :allow_all`
- `tools: %{}` (normalized from configured tool modules)
- `available_tools: []`

## Planning Plugin Defaults Contract

`Jido.AI.Plugins.Planning` mounts the following defaults unless overridden in plugin config:

- `default_model: :planning`
- `default_max_tokens: 4096`
- `default_temperature: 0.7`

Planning actions consume these plugin defaults when the caller omits those params.
Action-specific fields remain action-owned:

- `Plan` owns `goal`, optional `constraints`/`resources`, and `max_steps`
- `Decompose` owns `goal`, optional `max_depth`, and optional `context`
- `Prioritize` owns `tasks`, optional `criteria`, and optional `context`

## Reasoning CoT Plugin Defaults Contract

`Jido.AI.Plugins.Reasoning.ChainOfThought` mounts the following defaults unless overridden in plugin config:

- `strategy: :cot`
- `default_model: :reasoning`
- `timeout: 30_000`
- `options: %{}`

## Action Context Contract (Plugin -> Action)

When plugin-routed actions execute, the action context contract includes:

- `state`
- `agent`
- `plugin_state`
- `provided_params`

Actions should read defaults from explicit params first, then context/plugin state fallback.

## Strategy Runtime Compatibility

All built-in reasoning strategies now support module-action fallback execution for non-strategy commands. This means plugin-routed `Jido.Action` modules execute on strategy agents instead of silently no-oping.

## When To Use Plugins vs Actions

Use plugins when:

- capability should be mountable and reusable across many agents
- you need lifecycle hooks and capability-level defaults
- you want stable signal contracts for app/runtime integration

Use actions directly when:

- you are building one-off pipelines or background jobs
- you need low-level composition via `Jido.Exec`
- you do not need plugin lifecycle behavior

## Failure Mode: Defaults Not Being Applied

Symptom:

- execution succeeds but model/tool defaults are ignored

Fix:

- verify plugin state keys and `mount/2` shape match plugin schema and action fallback readers
- ensure caller does not override defaults with empty explicit params

## Next

- [Actions Catalog](actions_catalog.md)
- [Package Overview (Production Map)](../user/package_overview.md)
- [Migration Guide: Plugins And Signals (v2 -> v3)](../user/migration_plugins_and_signals_v3.md)
