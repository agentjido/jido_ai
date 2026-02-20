# Migration Guide: Plugins And Signals (v2 -> v3)

This guide maps the removed v2 public plugin surface to the v3 replacement.

## Breaking Change Summary

Removed public plugins:

- `Jido.AI.Plugins.LLM`
- `Jido.AI.Plugins.ToolCalling`
- `Jido.AI.Plugins.Reasoning`

New public plugins:

- `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.Planning`
- `Jido.AI.Plugins.Reasoning.ChainOfThought`
- `Jido.AI.Plugins.Reasoning.AlgorithmOfThoughts`
- `Jido.AI.Plugins.Reasoning.TreeOfThoughts`
- `Jido.AI.Plugins.Reasoning.GraphOfThoughts`
- `Jido.AI.Plugins.Reasoning.TRM`
- `Jido.AI.Plugins.Reasoning.Adaptive`

`Jido.AI.Plugins.TaskSupervisor` remains internal runtime infrastructure, not a recommended public capability plugin.

## Plugin Module Mapping

- `Jido.AI.Plugins.LLM` -> `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.ToolCalling` -> `Jido.AI.Plugins.Chat`
- `Jido.AI.Plugins.Reasoning` -> Strategy plugins (`ChainOfThought`, `AlgorithmOfThoughts`, `TreeOfThoughts`, `GraphOfThoughts`, `TRM`, `Adaptive`)

## Signal Mapping

Legacy -> New:

- `llm.chat` -> `chat.simple`
- `llm.complete` -> `chat.complete`
- `llm.embed` -> `chat.embed`
- `llm.generate_object` -> `chat.generate_object`
- `tool.call` -> `chat.message`
- `tool.execute` -> `chat.execute_tool`
- `tool.list` -> `chat.list_tools`
- `reasoning.analyze` -> use `Jido.AI.Actions.Reasoning.Analyze` directly
- `reasoning.explain` -> use `Jido.AI.Actions.Reasoning.Explain` directly
- `reasoning.infer` -> use `Jido.AI.Actions.Reasoning.Infer` directly
- strategy execution (new):
  - `reasoning.cot.run`
  - `reasoning.aot.run`
  - `reasoning.tot.run`
  - `reasoning.got.run`
  - `reasoning.trm.run`
  - `reasoning.adaptive.run`

## Action Mapping

- New dedicated strategy-run action:
  - `Jido.AI.Actions.Reasoning.RunStrategy`
- `Jido.AI.Plugins.Reasoning.*` route to `RunStrategy` with fixed strategy identity.
- Existing standalone actions remain available:
  - `Jido.AI.Actions.LLM.Chat`
  - `Jido.AI.Actions.LLM.GenerateObject`
  - `Jido.AI.Actions.LLM.Embed`
  - `Jido.AI.Actions.ToolCalling.*`
  - `Jido.AI.Actions.Planning.*`
  - `Jido.AI.Actions.Reasoning.Analyze/Infer/Explain`

## Migration Steps

1. Replace removed plugin modules in agent definitions.
2. Update signal emitters to new namespaces.
3. If you need explicit strategy execution, emit `reasoning.*.run` or call `RunStrategy` directly.
4. Move any LLM + tool defaults into `Jido.AI.Plugins.Chat` config (`auto_execute`, tool policy, defaults).
5. Run your integration tests against plugin routes and signal handlers.

## Example

Before:

```elixir
plugins: [
  {Jido.AI.Plugins.LLM, %{default_model: :fast}},
  {Jido.AI.Plugins.ToolCalling, %{auto_execute: true}}
]
```

After:

```elixir
plugins: [
  {Jido.AI.Plugins.Chat, %{default_model: :fast, auto_execute: true}},
  {Jido.AI.Plugins.Reasoning.ChainOfThought, %{default_model: :reasoning}}
]
```
