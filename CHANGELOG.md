# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added

- Complete rewrite with clean architecture
- Splode-based error handling via `Jido.AI.Error`
- Zoi schema validation support
- Integration with ReqLLM for LLM provider abstraction
- Integration with jido_action for composable AI actions
- `Jido.AI.Directive.AgentSession` — Mode 2 directive for delegating to autonomous agents via `agent_session_manager`
- `Jido.AI.Signal.AgentSession` — 6 signal types (`Started`, `Message`, `ToolCall`, `Progress`, `Completed`, `Failed`) for observing autonomous agent events
- `DirectiveExec` implementation for `AgentSession` — async execution via `SessionManager.run_once/4` with real-time event streaming
- `from_event/2`, `completed/2`, `failed/2` helper functions for event-to-signal conversion
- Optional dependency on `agent_session_manager ~> 0.2` (conditionally compiled)

### Changed

- **Breaking**: Complete API redesign for v2
- Module namespace changed from `JidoAi` to `Jido.AI`
