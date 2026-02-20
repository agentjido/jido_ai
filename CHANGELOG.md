# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0-beta] - Unreleased

### Added

- `Jido.AI.Plugins.Chat` as the conversational anchor plugin with built-in tool-calling paths.
- New strategy capability plugins:
  - `Jido.AI.Plugins.Reasoning.ChainOfThought`
  - `Jido.AI.Plugins.Reasoning.TreeOfThoughts`
  - `Jido.AI.Plugins.Reasoning.GraphOfThoughts`
  - `Jido.AI.Plugins.Reasoning.TRM`
  - `Jido.AI.Plugins.Reasoning.Adaptive`
- `Jido.AI.Actions.Reasoning.RunStrategy` for isolated strategy execution (`:cot | :tot | :got | :trm | :adaptive`).
- Internal dedicated strategy runner agents for plugin-driven strategy execution.
- Shared strategy module-action fallback execution in `Jido.AI.Reasoning.Helpers`.
- Migration guide for plugin/signal changes: `guides/user/migration_plugins_and_signals_v3.md`.

### Changed

- Strategy runtimes now execute plugin-routed `Jido.Action` module instructions instead of no-oping unknown module actions.
- Plugin-routed action context is standardized to include `state`, `agent`, and `plugin_state`.
- LLM/tool-calling actions now consistently read mounted defaults from context/plugin state.
- `Jido.AI.Actions.ToolCalling.CallWithTools` and `ListTools` now resolve tools from broader fallback context sources.
- Public docs updated to the new plugin taxonomy and strategy-run capability model.

### Removed

- Public plugin modules:
  - `Jido.AI.Plugins.LLM`
  - `Jido.AI.Plugins.ToolCalling`
  - `Jido.AI.Plugins.Reasoning`
- Legacy public plugin signal contracts tied to those modules (`llm.*`, `tool.*`, and `reasoning.analyze|infer|explain` plugin routes).

### Migration Notes

- This is a hard-replace breaking release for the plugin surface (no compatibility adapters).
- Replace removed plugins/signals using:
  - `guides/user/migration_plugins_and_signals_v3.md`

## [2.0.0] - Previous

### Added

- Complete rewrite with clean architecture
- Splode-based error handling via `Jido.AI.Error`
- Zoi schema validation support
- Integration with ReqLLM for LLM provider abstraction
- Integration with jido_action for composable AI actions

### Changed

- **Breaking**: Complete API redesign for v2
- Module namespace changed from `JidoAi` to `Jido.AI`
