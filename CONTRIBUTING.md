# Contributing to Jido.AI

Thank you for your interest in contributing to Jido.AI!

## Development Setup

1. Clone the repository
2. Install dependencies: `mix deps.get`
3. Run tests: `mix test`
4. Run quality checks: `mix quality`

## Pull Request Process

1. Ensure all tests pass: `mix test`
2. Run quality checks: `mix quality` (format, compile, credo, dialyzer)
3. Update documentation as needed
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
- Use Zoi schemas for validation in new actions
- Return `{:ok, result}` or `{:error, reason}` tuples

## Testing

- Write tests for new functionality
- Ensure existing tests pass
- Use `test/support/` for shared test helpers
- Tag flaky tests with `@tag :flaky`

## Questions?

Join our [Discord](https://agentjido.xyz/discord) for discussion.
