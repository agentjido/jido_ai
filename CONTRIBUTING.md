# Contributing

Thank you for your interest in contributing!

## Getting Started

```bash
git clone git@github.com:agentjido/jido_ai.git
cd jido_ai
mix deps.get
mix test
mix quality
```

## Development

- Run `mix quality` (or `mix q`) before committing
- Follow [conventional commits](https://www.conventionalcommits.org/)
- Install git hooks: `mix git_hooks.install`

## Commit Message Format

```
<type>[optional scope]: <description>

[optional body]

[optional footer(s)]
```

**Types:** feat, fix, docs, style, refactor, perf, test, chore, ci

**Examples:**
```
feat: add retry logic to API client
fix(auth): handle expired tokens gracefully
feat!: rename User to Account (breaking change)
```

## Testing

```bash
mix test                   # Run all tests
mix test --only tag_name   # Run specific tests
mix test --cover           # With coverage
```

## Pull Request Process

1. Create a feature branch from `main`
2. Make changes following our code style
3. Run `mix quality` - all checks must pass
4. Write a descriptive PR with conventional commit format
5. Reference related issues

## Questions?

Open a GitHub issue or join our [Discord](https://agentjido.xyz/discord).
