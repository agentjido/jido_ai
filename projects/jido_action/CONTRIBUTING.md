# Contributing to Jido Action

Thank you for your interest in contributing to Jido Action! This document provides guidelines for contributing to the project.

## Getting Started

1. Fork the repository
2. Clone your fork locally
3. Install dependencies: `mix deps.get`
4. Run tests: `mix test`
5. Run quality checks: `mix quality`

## Development Workflow

1. Create a feature branch from `main`
2. Make your changes
3. Add tests for new functionality
4. Ensure all tests pass: `mix test`
5. Run quality checks: `mix quality`
6. Submit a pull request

## Code Style

- Follow the existing code style and patterns
- Use `mix format` to format your code (includes Quokka formatting)
- Ensure Dialyzer passes: `mix dialyzer`
- Follow Credo guidelines: `mix credo`

### Code Formatting with Quokka

This project uses [Quokka](https://hexdocs.pm/quokka/) for advanced code formatting and style enforcement. Quokka is integrated into `mix format` and provides additional code improvements beyond standard formatting:

- Automatic application of Credo style rules
- Import/alias organization and optimization
- Code structure improvements
- Consistent styling patterns

Quokka runs automatically when you use `mix format` or `mix quality`. It may make significant changes to your code during the first run, so review changes carefully before committing.

## Security Scanning

The project includes automated security scanning to detect dependency vulnerabilities and code-level security issues.

### Local Security Scans

Run security checks locally before submitting:

```bash
# Check for dependency vulnerabilities
mix deps.audit

# Run all quality checks including security
mix quality
```

### CI Security Checks

The CI pipeline automatically runs:
- **Dependency audit**: Scans for known vulnerabilities in dependencies using `mix_audit`
- **CodeQL analysis**: Static code analysis for security patterns and vulnerabilities

High-severity security findings will cause CI to fail. Address any security issues before merging.

## Testing

- Add tests for all new functionality
- Maintain existing test coverage
- Use property-based testing where appropriate
- Include integration tests for complex features

### Test Coverage Policy

This project maintains a minimum test coverage threshold of **90%**. All contributions must:

- Maintain or improve the overall coverage percentage
- Include comprehensive tests for new code paths
- Not introduce uncovered code without justification

Check coverage locally:
```bash
# Generate coverage report
mix coveralls.html

# Check if coverage meets threshold
mix coveralls
```

The CI pipeline enforces the 90% threshold - builds will fail if coverage drops below this level.

## Documentation

- Update documentation for any API changes
- Add examples for new features
- Update guides if adding new concepts
- Ensure `mix docs` builds without errors

### Documentation Standards

All public APIs must be properly documented:

- **@moduledoc**: All public modules must have module documentation explaining their purpose
- **@doc**: All public functions must have function documentation with parameters, returns, and examples
- **@spec**: All public functions must have type specifications
- **@typedoc**: Custom types must have type documentation
- **@moduledoc false**: Use for internal/private modules that shouldn't appear in generated docs

Check documentation coverage locally:
```bash
# Generate documentation report
mix doctor

# Check for missing documentation
mix doctor --report
```

The CI pipeline enforces documentation standards - builds will fail if documentation coverage is incomplete.

## Pull Request Guidelines

- Provide a clear description of the changes
- Reference any related issues
- Include tests and documentation updates
- Ensure CI passes

## Maintenance Policy

This project follows a formal maintenance policy that outlines our commitments for:

- Issue response times and resolution targets
- Security vulnerability handling procedures  
- Release cadence and version support windows
- Long-term support and end-of-life processes

For complete details, see [MAINTENANCE.md](MAINTENANCE.md).

## Questions?

Feel free to open an issue for questions or discussion about potential contributions.
