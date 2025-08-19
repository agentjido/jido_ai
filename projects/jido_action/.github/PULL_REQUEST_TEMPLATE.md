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
  - [ ] Security checks pass (`mix deps.audit`)
- [ ] Documentation updated if needed
- [ ] CHANGELOG.md updated (if applicable)
- [ ] Semantic commit messages used (see format below)
- [ ] Breaking changes noted above (if any)
- [ ] Related issues referenced

## Code Quality Standards

Please ensure your code follows our quality standards outlined in [EX_BEST_PRACTICES.md](./EX_BEST_PRACTICES.md):

- [ ] Proper module documentation (`@moduledoc` and `@doc`)
- [ ] Type specifications (`@spec`) for public functions
- [ ] Pattern matching used appropriately
- [ ] Error handling follows `{:ok, result}` / `{:error, reason}` pattern
- [ ] Snake_case naming conventions followed
- [ ] Pure functional approach maintained

## Semantic Commit Message Format

This project follows conventional commit format. Ensure your commit messages follow this pattern:

```
type(scope): description

[optional body]

[optional footer(s)]
```

**Types:** `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`

**Examples:**
- `feat(action): add new execution pipeline support`
- `fix(instruction): resolve parsing edge case for complex commands`
- `docs(readme): update examples with new API usage`

## Related Issues

Closes #[issue number]
Relates to #[issue number]

## Additional Context

Add any other context, screenshots, or relevant information about the pull request here.

---

*Please review the [Contributing Guidelines](./CONTRIBUTING.md) and [Best Practices](./EX_BEST_PRACTICES.md) before submitting your PR.*
