# Pull Request

## Description

Provide a clear and concise description of what this PR accomplishes.

## Type of Change

- [ ] 🐛 Bug fix (non-breaking change which fixes an issue)
- [ ] ✨ New feature (non-breaking change which adds functionality)
- [ ] 💥 Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] 📚 Documentation update
- [ ] 🔧 Refactoring (no functional changes)
- [ ] ⚡ Performance improvement
- [ ] 🧪 Test improvement
- [ ] 🔨 Build/CI related changes

## Breaking Changes

If this PR introduces breaking changes, describe them here and provide migration instructions:

```elixir
# Before
old_function(arg)

# After  
new_function(arg, new_required_param)
```

## Testing Approach

Describe how you tested these changes:

- [ ] Added new tests
- [ ] Updated existing tests
- [ ] Manual testing performed
- [ ] Integration tests verified

## Quality Checklist

- [ ] Tests pass (`mix test`)
- [ ] Quality checks pass (`mix quality` or `mix q`)
  - [ ] Code formatted (`mix format`)
  - [ ] No compilation warnings (`mix compile --warnings-as-errors`)
  - [ ] Type checking passes (`mix dialyzer`)
  - [ ] Static analysis passes (`mix credo --all`)
- [ ] Documentation updated if needed
- [ ] Semantic commit messages used (see format below)
- [ ] Breaking changes noted above (if any)
- [ ] Related issues referenced

## Semantic Commit Message Format

This project follows conventional commit format. Ensure your commit messages follow this pattern:

```
type(scope): description

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

**Examples:**
- `feat(bus): add new subscription filtering options`
- `fix(router): resolve pattern matching edge case`
- `docs(signal): update README with new examples`

## Related Issues

Closes #[issue number]
Relates to #[issue number]

## Additional Context

Add any other context, screenshots, or relevant information about the pull request here.

---

*Please review the [Contributing Guidelines](./CONTRIBUTING.md) before submitting your PR.*
