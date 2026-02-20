# Plugins And Actions Composition

You need a reliable way to compose mountable capabilities (plugins) with executable primitives (actions) without coupling to strategy internals.

After this guide, you can choose the right extension surface for each requirement.

## Public Plugin Surface (v3)

Public capability plugins:

- `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.Planning`
- `Jido.AI.Plugins.Reasoning.ChainOfThought`
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
- `Jido.AI.Plugins.Reasoning.*`
  - `reasoning.cot.run`
  - `reasoning.tot.run`
  - `reasoning.got.run`
  - `reasoning.trm.run`
  - `reasoning.adaptive.run`
  - All route to `Jido.AI.Actions.Reasoning.RunStrategy` with fixed strategy identity.

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
