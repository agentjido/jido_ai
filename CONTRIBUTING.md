# Contributing to Jido.AI

Thank you for your interest in contributing to Jido.AI!

## Development Setup

1. Clone the repository
2. Install dependencies: `mix deps.get`
3. Run the fast stable gate: `mix precommit`
4. Run full stable tests: `mix test`
5. Run the full quality gate: `mix quality`

## Local Quality Gates

Use these gates during development:

Fast per-story gate (target runtime budget: under 90 seconds on a warm cache):

```bash
mix precommit
mix test.fast
```

Full checkpoint gate (target runtime budget: under 10 minutes on a warm cache):

```bash
mix test
```

Static quality gate:

```bash
mix quality
```

Notes:
- `mix precommit` is repository-local and runs format/compile/doctor plus `mix test.fast`.
- `mix test.fast` runs stable smoke coverage only (`--only stable_smoke`, excluding flaky tests).
- `mix test` is the full stable suite (`--exclude flaky` via alias).
- `mix quality` runs format, compile with warnings-as-errors, Credo, Doctor, and Dialyzer.

## Pull Request Process

1. Ensure all tests pass: `mix test`
2. Run quality checks: `mix quality` (format, compile, strict Credo, Doctor, Dialyzer)
3. If docs changed, verify docs build: `mix docs`
4. Update documentation as needed
5. Use conventional commit messages

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
- Use Zoi schemas for validation in new actions
- Return `{:ok, result}` or `{:error, reason}` tuples

## Testing

- Write tests for new functionality
- Ensure existing tests pass
- Use `test/support/` for shared test helpers
- Tag flaky tests with `@tag :flaky`

## Questions?

Join our [Discord](https://agentjido.xyz/discord) for discussion.
