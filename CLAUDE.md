# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build/Test/Lint Commands

```bash
# Install dependencies
mix deps.get

# Run tests (excludes flaky tests by default)
mix test

# Run a single test file
mix test path/to/specific_test.exs

# Run all tests including flaky ones
mix test --include flaky

# Quality checks (format, compile warnings, credo, dialyzer)
mix quality   # or `mix q`

# Individual quality commands
mix format              # Auto-format code
mix credo               # Code analysis
mix dialyzer            # Type checking
mix coveralls           # Test coverage report

# Generate documentation
mix docs
```

## Architecture

Jido.AI is the **AI integration layer** for the Jido ecosystem, providing LLM orchestration capabilities for AI agents.

### Core Modules

- **`Jido.AI`** (`lib/jido_ai.ex`) - Facade module for AI interactions
- **`Jido.AI.Directive`** (`lib/jido_ai/directive.ex`) - LLM directives for agent runtime
  - `ReqLLMStream` - Directive for streaming LLM responses
  - `ToolExec` - Directive for executing Jido.Actions as tools
- **`Jido.AI.Signal`** (`lib/jido_ai/signal.ex`) - Custom signal types for LLM events
  - `ReqLLMResult`, `ReqLLMPartial`, `ToolResult`
- **`Jido.AI.Error`** (`lib/jido_ai/error.ex`) - Splode-based error handling

### ReAct Agent System

The ReAct (Reason-Act) pattern provides multi-step LLM reasoning with tool use:

- **`Jido.AI.ReActAgent`** (`lib/jido_ai/react_agent.ex`) - Base macro for ReAct agents
- **`Jido.AI.Strategies.ReAct`** (`lib/jido_ai/strategies/react.ex`) - Strategy implementation
- **`Jido.AI.ReAct.Machine`** (`lib/jido_ai/react/machine.ex`) - Pure state machine (Fsmx-based)
- **`Jido.AI.ToolAdapter`** (`lib/jido_ai/tool_adapter.ex`) - Converts Jido.Actions to ReqLLM tools

### Key Dependencies

- **jido** - Core agent framework
- **req_llm** - LLM provider abstraction (Anthropic, OpenAI, Google, etc.)
- **zoi** - Schema validation with transformations
- **splode** - Structured error handling
- **fsmx** - State machine for ReAct pattern

## Code Style

- Use Zoi schemas for parameter validation in actions and directives
- Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Use TypeSpecs with `@type` and `@spec` throughout
- Tag flaky tests with `@tag :flaky`
- Test support modules go in `test/support/`

### Zoi Schema Pattern

```elixir
@schema Zoi.struct(__MODULE__, %{
  model: Zoi.string() |> Zoi.default("anthropic:claude-haiku-4-5"),
  prompt: Zoi.string() |> Zoi.min_length(1),
  temperature: Zoi.number() |> Zoi.default(0.7)
}, coerce: true)

@type t :: unquote(Zoi.type_spec(@schema))
@enforce_keys Zoi.Struct.enforce_keys(@schema)
defstruct Zoi.Struct.struct_fields(@schema)
```

## Git Commit Guidelines

Use **Conventional Commits** format:

```
<type>[optional scope]: <description>
```

Types: `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`

Examples:
```
feat(react): add streaming support for tool results
fix(directive): handle rate limit errors gracefully
```
