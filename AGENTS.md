# AGENTS.md - Jido AI Development Guide

## Build/Test/Lint Commands

- `mix test` - Run tests (excludes flaky tests)
- `mix test path/to/specific_test.exs` - Run a single test file
- `mix test --include flaky` - Run all tests including flaky ones
- `mix quality` or `mix q` - Run full quality check (format, compile, dialyzer, credo)
- `mix format` - Auto-format code
- `mix dialyzer` - Type checking
- `mix credo` - Code analysis
- `mix coveralls` - Test coverage report
- `mix docs` - Generate documentation

## Architecture

Jido.AI is the **AI integration layer** for the Jido ecosystem, providing:

- **Jido.AI** - Core module for AI interactions via ReqLLM
- **Jido.AI.Actions** - Pre-built actions for common AI operations
- **Jido.AI.Error** - Splode-based error handling

### Dependencies

- **jido_action** - Composable action framework
- **jido_signal** - Event/signal handling
- **req_llm** - LLM provider abstraction (Anthropic, OpenAI, Google, etc.)
- **zoi** - Schema validation with transformations
- **splode** - Structured error handling

## Code Style Guidelines

- Use `@moduledoc` for module documentation following existing patterns
- TypeSpecs: Define `@type` for custom types, use strict typing throughout
- Use Zoi schemas for parameter validation in actions
- Error handling: Return `{:ok, result}` or `{:error, reason}` tuples consistently
- Module organization: Actions in `lib/jido_ai/actions/`, core in `lib/jido_ai/`
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
chore(deps): bump req_llm to 1.2.0
```
