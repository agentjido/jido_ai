# Plugins And Actions Composition

You need a repeatable way to compose plugin lifecycle with action execution.

After this guide, you can choose plugin vs action extension points without coupling mistakes.

## Built-In Plugin Modules

- `Jido.AI.Plugins.LLM`
- `Jido.AI.Plugins.ToolCalling`
- `Jido.AI.Plugins.Reasoning`
- `Jido.AI.Plugins.Planning`
- `Jido.AI.Plugins.Streaming`
- `Jido.AI.Plugins.TaskSupervisor`
- `Jido.AI.Plugins.Policy` (default-on middleware for AI signal policy enforcement)

## Compose In Agent Definition

```elixir
defmodule MyApp.Assistant do
  use Jido.Agent,
    name: "assistant",
    plugins: [
      {Jido.AI.Plugins.TaskSupervisor, []},
      {Jido.AI.Plugins.LLM, %{default_model: :fast}},
      {Jido.AI.Plugins.ToolCalling, %{auto_execute: true}}
    ]
end
```

## Action-Level Composition

For custom behavior, write plain actions and reuse `Jido.AI.Actions.Helpers` for:
- model resolution
- option assembly
- response text/usage extraction
- input sanitization

## Failure Mode: Plugin State Shape Mismatch

Symptom:
- plugin routing works but runtime fails reading expected keys

Fix:
- keep `mount/2` return shape aligned with `schema/0`
- do not silently change plugin `state_key` semantics

## Defaults You Should Know

- plugin `handle_signal/2` default behavior is usually pass-through (`:continue`)
- `TaskSupervisor` plugin is expected by async-heavy AI flows

## When To Use / Not Use

Use plugins when:
- capability should be mountable and reusable across agents

Use actions directly when:
- behavior is one-off and does not need lifecycle hooks

## Next

- [Actions Catalog](actions_catalog.md)
- [Skills System](skills_system.md)
- [Security And Validation](security_and_validation.md)
