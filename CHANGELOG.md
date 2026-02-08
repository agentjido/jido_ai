# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - Unreleased

### Added

#### Core Architecture
- Complete rewrite with clean architecture: pure state machines, directive pattern, signal-driven communication
- Splode-based error handling via `Jido.AI.Error`
- Zoi schema validation across all directives, signals, and actions
- Integration with ReqLLM for multi-provider LLM abstraction (Anthropic, OpenAI, Google, Mistral)
- Integration with `jido` 2.0 action framework for composable AI actions
- Model alias system (`:fast`, `:capable`, `:reasoning`, `:planning`) with environment-based overrides
- Built-in telemetry and usage tracking across strategies and directives

#### Reasoning Strategies
- `Jido.AI.Strategies.ReAct` — Reason-Act loop with tool use, streaming support, and dynamic tool registration
- `Jido.AI.Strategies.ChainOfThought` — Sequential step-by-step reasoning
- `Jido.AI.Strategies.TreeOfThoughts` — Branching exploration with configurable traversal (BFS, DFS, best-first)
- `Jido.AI.Strategies.GraphOfThoughts` — Graph-based reasoning with thought aggregation and synthesis
- `Jido.AI.Strategies.TRM` — Thought-Refine-Merge with supervision modes
- `Jido.AI.Strategies.Adaptive` — Automatic strategy selection based on task characteristics
- `Jido.AI.Strategy.StateOpsHelpers` — Shared state operation helpers for strategy implementations

#### Pure State Machines
- `Jido.AI.ReAct.Machine` — Fsmx-based pure state machine for ReAct loop with serialization support
- State machines for all strategies with defined states, transitions, and directive emission
- Full conversation history tracking with streaming text and thinking content accumulation

#### Directives
- `Jido.AI.Directive.LLMStream` — Streaming LLM completion with tool support
- `Jido.AI.Directive.LLMGenerate` — Non-streaming LLM completion
- `Jido.AI.Directive.LLMEmbed` — Embedding generation
- `Jido.AI.Directive.ToolExec` — Tool execution with argument normalization
- `Jido.AI.Directive.AgentSession` — Mode 2 directive for delegating to autonomous agents via `agent_session_manager`
- `Jido.AI.Directive.EmitToolError` — Error signaling for tool execution failures
- `Jido.AI.Directive.EmitRequestError` — Error signaling for request rejections (deadlock prevention)
- `DirectiveExec` protocol implementations for all directives

#### Signals
- `Jido.AI.Signal.LLMResponse` — LLM call completion (`react.llm.response`)
- `Jido.AI.Signal.LLMDelta` — Streaming token chunks (`react.llm.delta`)
- `Jido.AI.Signal.LLMError` — Structured LLM errors (`react.llm.error`)
- `Jido.AI.Signal.ToolResult` — Tool execution results (`react.tool.result`)
- `Jido.AI.Signal.EmbedResult` — Embedding results (`react.embed.result`)
- `Jido.AI.Signal.Usage` — Token usage tracking (`react.usage`)
- `Jido.AI.Signal.AgentSession` — 6 signal types for autonomous agent observation:
  - `Started` (`ai.agent_session.started`)
  - `Message` (`ai.agent_session.message`)
  - `ToolCall` (`ai.agent_session.tool_call`)
  - `Progress` (`ai.agent_session.progress`)
  - `Completed` (`ai.agent_session.completed`)
  - `Failed` (`ai.agent_session.failed`)
- `from_event/2`, `completed/2`, `failed/2` helpers for `agent_session_manager` event-to-signal conversion

#### Tool System
- `Jido.AI.Tools.Registry` — ETS-backed unified registry for actions and tools
- `Jido.AI.Tools.Executor` — Consistent execution with argument normalization, timeout handling, and telemetry
- `Jido.AI.ToolAdapter` — Converts `Jido.Action` modules to ReqLLM tool format with JSON schema generation
- Dynamic tool registration and unregistration at runtime
- Tool context management for concurrent request tracking

#### Skill System
- `Jido.AI.Skill` — Unified skill abstraction following the [agentskills.io](https://agentskills.io) specification
- `Jido.AI.Skill.Spec` — Skill specification struct with Zoi validation
- `Jido.AI.Skill.Loader` — Runtime SKILL.md file parsing with YAML frontmatter support
- `Jido.AI.Skill.Registry` — ETS-backed GenServer for skill discovery and lookup
- `Jido.AI.Skill.Prompt` — Prompt rendering helpers for injecting skills into system prompts
- `use Jido.AI.Skill` macro for compile-time module-based skills
- File-based skills via `priv/skills/*/SKILL.md` with allowed-tools enforcement
- Built-in example skills: Calculator, Skill Writer
- `mix jido.skill` task for skill management

#### Orchestration Actions
- `Jido.AI.Actions.Orchestration.DelegateTask` — LLM-assisted task routing and delegation
- `Jido.AI.Actions.Orchestration.SpawnChildAgent` — Child agent lifecycle management
- `Jido.AI.Actions.Orchestration.StopChildAgent` — Graceful child agent termination
- `Jido.AI.Actions.Orchestration.AggregateResults` — Multi-agent result aggregation
- `Jido.AI.Actions.Orchestration.DiscoverCapabilities` — Agent capability discovery

#### LLM Actions
- `Jido.AI.Actions.LLM.Chat` — Multi-turn chat completion
- `Jido.AI.Actions.LLM.Complete` — Single-shot text completion
- `Jido.AI.Actions.LLM.Embed` — Text embedding generation
- `Jido.AI.Actions.LLM.GenerateObject` — Structured output with Zoi schema validation

#### Planning & Reasoning Actions
- `Jido.AI.Actions.Planning.Plan` — Task planning and decomposition
- `Jido.AI.Actions.Planning.Decompose` — Subtask decomposition
- `Jido.AI.Actions.Planning.Prioritize` — Task prioritization
- `Jido.AI.Actions.Reasoning.Analyze` — Structured analysis
- `Jido.AI.Actions.Reasoning.Explain` — Explanation generation
- `Jido.AI.Actions.Reasoning.Infer` — Inference and deduction

#### Streaming Actions
- `Jido.AI.Actions.Streaming.StartStream` — Initialize streaming session
- `Jido.AI.Actions.Streaming.ProcessTokens` — Token processing pipeline
- `Jido.AI.Actions.Streaming.EndStream` — Stream finalization

#### Accuracy Improvement Techniques
- Self-Consistency with majority vote and weighted aggregation
- Adaptive Self-Consistency with dynamic resource allocation
- Search algorithms: Beam Search, MCTS, Diverse Decoding
- Verification: LLM, Code Execution, Deterministic, Static Analysis, Unit Test verifiers
- Reflection: Self-Refine, multi-stage reflection loops
- Critique & Revision cycles
- Process Reward Models for step-by-step quality scoring
- Confidence calibration and uncertainty quantification
- Difficulty estimation with heuristic and LLM-based estimators
- Pipeline orchestration combining multiple accuracy techniques

#### Autonomous Agent Sessions (Mode 2)
- Two-mode architecture: Mode 1 (app-orchestrated via ReAct/ReqLLM) and Mode 2 (provider-orchestrated via agent_session_manager)
- Optional dependency on `agent_session_manager` (conditionally compiled via `Code.ensure_loaded?/1`)
- Support for Claude Code CLI via `AgentSessionManager.Adapters.ClaudeAdapter`
- Support for Codex CLI via `AgentSessionManager.Adapters.CodexAdapter`
- Full event streaming with configurable suppression (`emit_events: false`)

#### Documentation
- Comprehensive developer guides: Architecture, Strategies, State Machines, Directives, Signals, Tools, Skills, Configuration
- User guides for all accuracy techniques with code examples
- `JIDO_SKILLS.md` — Skill system implementation plan and specification
- `ACTION_FIXES.md` — Production readiness tracking for action SDK

### Changed

- **Breaking**: Complete API redesign for v2
- Module namespace changed from `JidoAi` to `Jido.AI`
- Renamed directives and signals for naming consistency across the codebase
- Transitioned from skills to plugins terminology where appropriate (`Jido.Plugin` for runtime capabilities, `Jido.AI.Skill` for prompt-based capabilities)
- Standardized module aliases and imports across all modules
- Refactored signal routing architecture for clarity and consistency
- Updated `agent_session_manager` dependency from `~> 0.2` to `~> 0.4`
- Improved accuracy fallbacks and code-execution verifier scoring
- Refactored CLI/mix-task structure for skills management

### Fixed

- Resolved all Dialyzer warnings across the codebase
- Resolved all Credo violations (code readability, consistency, refactoring opportunities)
- Removed dead code and unused module attributes
- Fixed regex module attributes for Elixir 1.18 compatibility
- Aligned skill integration modules with upstream main branch
- Implemented deadlock prevention via `EmitToolError` and `EmitRequestError` directives
- Fixed concurrent request handling with proper request tracking

### Removed

- Removed obsolete documentation files
- Removed legacy test files superseded by new architecture
- Removed `quokka` from dev dependencies
- Removed unused dependencies (`typedstruct`, `uniq`)
