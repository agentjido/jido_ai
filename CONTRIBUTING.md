# Contributing to Jido.AI

Thank you for your interest in contributing to Jido.AI!

## Development Setup

1. Clone the repository
2. Install dependencies: `mix deps.get`
3. Run tests: `mix test`
4. Run quality checks: `mix quality`

### Prerequisites

- Elixir >= 1.17
- Erlang/OTP (compatible with your Elixir version)
- API keys for LLM providers you want to test against (see Environment Variables below)

### Environment Variables

```bash
# Required for live LLM tests
export ANTHROPIC_API_KEY="sk-ant-..."
export OPENAI_API_KEY="sk-..."

# Optional: for Mode 2 agent session tests
# Requires claude-code or codex CLI installed locally
```

## Running Tests

```bash
# Standard test suite (excludes flaky and live CLI tests)
mix test

# Run a single test file
mix test path/to/specific_test.exs

# Include flaky tests
mix test --include flaky

# Include live AgentSession provider matrix (Claude/Codex/Amp)
mix test --include requires_live_agent_cli
```

### Test Tags

| Tag | Purpose |
|-----|---------|
| `@tag :flaky` | Non-deterministic tests (excluded by default) |
| `@tag :requires_live_agent_cli` | Live AgentSession provider matrix (excluded by default) |

## Pull Request Process

1. Ensure all tests pass: `mix test`
2. Run quality checks: `mix quality` (format, compile warnings-as-errors, credo, dialyzer)
3. Update documentation as needed (guides, CHANGELOG.md)
4. Use conventional commit messages

## Commit Message Format

We use [Conventional Commits](https://www.conventionalcommits.org/):

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
- `refactor` - Code change, no fix or feature
- `test` - Adding or updating tests
- `chore` - Maintenance tasks

## Code Style

- Run `mix format` before committing
- Follow Elixir community conventions
- Add `@moduledoc` and `@doc` for public modules and functions
- Use Zoi schemas for validation in new actions and directives
- Return `{:ok, result}` or `{:error, reason}` tuples
- All strategies must use pure state machines (no side effects in state transitions)
- Use the directive pattern for side effects: strategies return directives, the runtime executes them

## Testing

- Write tests for new functionality
- Ensure existing tests pass
- Use `test/support/` for shared test helpers
- Tag flaky tests with `@tag :flaky`
- Tag tests requiring external CLIs with the appropriate tag (see Test Tags above)

## Project Structure

```
lib/jido_ai/
├── actions/           # Pre-built actions (LLM, Orchestration, Planning, Reasoning, Streaming)
├── accuracy/          # Accuracy improvement techniques
├── directive/         # Declarative side effects (LLMStream, ToolExec, AgentSession, etc.)
├── signal/            # Typed event signals (LLMResponse, ToolResult, AgentSession.*, etc.)
├── skill/             # Skill system (Spec, Loader, Registry, Prompt)
├── strategy/          # Reasoning strategies (ReAct, CoT, ToT, GoT, TRM, Adaptive)
├── tools/             # Tool registry and execution
├── react/             # ReAct state machine
├── config.ex          # Model aliases and provider configuration
├── error.ex           # Splode error handling
├── helpers.ex         # Shared utility functions
└── tool_adapter.ex    # Action-to-ReqLLM tool conversion
```

## Questions?

Join our [Discord](https://agentjido.xyz/discord) for discussion.
