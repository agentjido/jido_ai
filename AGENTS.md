# AGENTS.md - Jido AI Development Guide

## Build/Test/Lint Commands

- `mix test` - Run tests (excludes flaky and live CLI tests)
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix test --include requires_live_agent_cli` - Run live agent session tests (Claude, Codex, Amp)
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation
- `mix jido.skill` - Skill management task

## Test Tags

| Tag | Purpose | Default |
|-----|---------|---------|
| `@tag :flaky` | Non-deterministic tests | Excluded |
| `@tag :requires_live_agent_cli` | Live AgentSession provider matrix (Claude/Codex/Amp) | Excluded |

To run excluded tests, use the `--include` flag:
```bash
mix test --include requires_live_agent_cli
```

## Architecture

Jido.AI is the **AI integration layer** for the Jido ecosystem. It operates in two modes:

- **Mode 1 (App-Orchestrated)**: Jido.AI controls the reasoning loop via ReAct/ReqLLM, executing tools locally
- **Mode 2 (Provider-Orchestrated)**: Delegates to autonomous agents (Claude Code CLI, Codex CLI) via `agent_session_manager`, observing events as signals

### Core Modules

| Area | Modules | Purpose |
|------|---------|---------|
| **Facade** | `Jido.AI` | Entry point for text generation and structured output |
| **Strategies** | `Jido.AI.Strategies.*` | ReAct, CoT, ToT, GoT, TRM, Adaptive reasoning patterns |
| **State Machines** | `Jido.AI.ReAct.Machine`, etc. | Pure Fsmx-based state machines for each strategy |
| **Directives** | `Jido.AI.Directive.*` | Declarative side effects: LLMStream, ToolExec, AgentSession, etc. |
| **Signals** | `Jido.AI.Signal.*` | Typed events: LLMResponse, LLMDelta, ToolResult, AgentSession.* |
| **Tools** | `Jido.AI.Tools.*` | Registry, Executor, ToolAdapter for LLM tool calling |
| **Skills** | `Jido.AI.Skill.*` | agentskills.io-compatible skill abstraction (module + SKILL.md) |
| **Actions** | `Jido.AI.Actions.*` | Pre-built actions: LLM, Orchestration, Planning, Reasoning, Streaming |
| **Accuracy** | `Jido.AI.Accuracy.*` | Self-Consistency, Search, Verification, Reflection, Pipeline |
| **Config** | `Jido.AI.Config` | Model aliases, provider settings, resolution |
| **Error** | `Jido.AI.Error` | Splode-based structured error handling |

### Dependencies

| Package | Purpose |
|---------|---------|
| `jido` ~> 2.0 | Agent framework (actions, plugins, signals) |
| `req_llm` ~> 1.5 | Multi-provider LLM abstraction |
| `agent_session_manager` ~> 0.4 | Autonomous agent session management (optional) |
| `fsmx` ~> 0.5 | Pure state machine transitions |
| `zoi` ~> 0.16 | Schema validation with transformations |
| `splode` ~> 0.3 | Structured error handling |
| `yaml_elixir` ~> 2.9 | YAML parsing for SKILL.md files |
| `nimble_options` ~> 1.1 | Option validation |
| `jason` ~> 1.4 | JSON encoding/decoding |

### Key Design Patterns

1. **Pure State Machines**: All strategies use Fsmx — state transitions are pure functions that return directives
2. **Directive Pattern**: Strategies describe side effects declaratively; the AgentServer runtime executes them
3. **Signal-Driven Communication**: Components communicate via typed signals routed through `signal_routes/1`
4. **Conditional Compilation**: `agent_session_manager` integration is conditionally compiled via `Code.ensure_loaded?/1`
5. **Skills vs Plugins**: Skills inject prompt context (stateless); Plugins provide runtime capabilities with state and lifecycle

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Use Zoi schemas for parameter validation in actions and directives
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Actions in `lib/jido_ai/actions/`, strategies in `lib/jido_ai/strategy/`, signals in `lib/jido_ai/signal/`
- Testing: Use ExUnit, test parameter validation and execution separately
- Naming: Snake_case for functions/variables, PascalCase for modules

### Zoi Schema Patterns

**Prefer Zoi schemas** for validation and transformations:

```elixir
use Jido.Action,
  schema: Zoi.object(%{
    model: Zoi.string() |> Zoi.trim(),
    prompt: Zoi.string() |> Zoi.min_length(1),
    temperature: Zoi.float() |> Zoi.optional() |> Zoi.default(0.7)
  })
```

### Signal Naming Convention

- Mode 1 LLM signals: `react.llm.<event>` (e.g., `react.llm.response`)
- Mode 1 Tool signals: `react.tool.<event>` (e.g., `react.tool.result`)
- Mode 2 Agent signals: `ai.agent_session.<event>` (e.g., `ai.agent_session.completed`)

## Git Commit Guidelines

Use **Conventional Commits** format for all commit messages:

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:**
- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation only
- `style` - Formatting, no code change
- `refactor` - Code change that neither fixes a bug nor adds a feature
- `test` - Adding or updating tests
- `chore` - Maintenance tasks, dependency updates

**Examples:**
```
feat(actions): add structured output generation action
fix(llm): handle rate limit errors gracefully
docs: update getting started guide
test(actions): add tests for chat completion action
chore(deps): bump req_llm to 1.5.0
```
