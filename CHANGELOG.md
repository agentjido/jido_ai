# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0-rc.0] - 2026-02-22

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

- Published the first 2.0.0 release-candidate line for Hex (`2.0.0-rc.0`)
- Aligned ecosystem dependency ranges to stable releases: `jido ~> 2.0`, `jido_action ~> 2.0`
- Updated dev/test smoke dependency to `jido_browser ~> 1.0`
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

<!-- changelog -->

## [2.0.0](https://github.com/agentjido/jido_ai/compare/v2.0.0-rc.0...2.0.0) (2026-03-15)
### Breaking Changes:

* remove Jido.AI.Thread compatibility shim by dbhowmick

* remove public Jido.AI.set_context API by dbhowmick

* react: project context lifecycle onto core thread by dbhowmick



### Features:

* react: add request-scoped tool controls (#200) by mikehostetler

* react: add request-scoped tool controls by mikehostetler

* add Igniter installer for automated setup (#169) by Nickcom4

* add Igniter installer for automated package setup by Nickcom4

* ai: add prompt builder and context lifecycle helpers (#188) by austin macciola

* react: add set_thread for conversation session resumption (#184) by dbhowmick

* react: add set_thread for conversation session resumption by dbhowmick

* add effect policy gating and runtime tool-effect application (#172) by mikehostetler

* reasoning: add effect policy and runtime tool-effect application by mikehostetler

### Bug Fixes:

* react: resolve lint issues by mikehostetler

* unify ReAct stream liveness and reasoning continuity (#196) by mikehostetler

* unify react stream liveness and reasoning continuity by mikehostetler

* use req_llm keepalive callbacks by mikehostetler

* test: align rebased stream timeout option names by mikehostetler

* react: remove unreachable assistant context clause by mikehostetler

* examples: restore weather tool compatibility by mikehostetler

* add LICENSE file (#194) by mikehostetler

* preserve OpenAI Responses continuation across tool loops (#192) by mikehostetler

* preserve openai responses tool continuation by mikehostetler

* preserve responses continuation in tool loops by mikehostetler

* align react runner with quality checks by mikehostetler

* raise and forward react max_tokens defaults by mikehostetler

* install jido as dependency via installs field by Nickcom4

* installer: satisfy doctor docs coverage by Nickcom4

* react: defer thread replacement until terminal run state by dbhowmick

* react: resolve dialyzer failures in context ops by dbhowmick

* forward streaming option from agent macro to strategy config (#186) by Edgar Gomes

* forward streaming option from agent macro to strategy config by Edgar Gomes

* break compile-connected ReAct cycle from xref issue #181 (#182) by mikehostetler

* react: break compile-connected ReAct dependency cycle by mikehostetler

* add runtime state snapshots to tool execution contexts (#180) by mikehostetler

* reasoning: inject runtime state snapshots into tool contexts by mikehostetler

* react: normalize standalone tool state snapshot aliases by mikehostetler

* react: remove unreachable snapshot fallback for dialyzer by mikehostetler

* harden Thread inspect for truncated telemetry payloads (#178) by mikehostetler

* effects: harden policy parsing and ToT policy wiring by mikehostetler

* dialyzer: remove unreachable tuple branches by mikehostetler

* reasoning: enforce deterministic tool effect ordering by mikehostetler

* dialyzer: remove unreachable fallback in ToT ordering helper by mikehostetler

* agent: preserve literal option evaluation after rebase by mikehostetler

* effects: enforce constraint normalization and ToT fallback ordering by mikehostetler

* reasoning: normalize canonical llm_result envelopes by mikehostetler

* react: forward llm opts and http options end-to-end (#171) by mikehostetler

* react: forward llm opts and http options end-to-end by mikehostetler

* react: harden llm option normalization and provider option translation by mikehostetler

* react: resolve dialyzer unreachable clauses in option mapping by mikehostetler

### Refactoring:

* examples: move examples to top-level folder (#190) by mikehostetler

* examples: move examples into standalone project by mikehostetler

* examples: keep examples in top-level folder by mikehostetler

* ai: adopt Context API and deprecate Thread shim by dbhowmick

* react: remove set_thread compatibility surface by dbhowmick

* reasoning: remove internal agent_state snapshot alias by mikehostetler