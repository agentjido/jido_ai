---
name: cleanup
description: Perform comprehensive cleanup of Elixir projects including warnings, formatting, and code quality
agents:
  - elixir-expert
  - elixir-reviewer
---

# Cleanup - Elixir Project Quality Assurance

Performs comprehensive cleanup of Elixir projects to ensure code quality, remove warnings, and maintain professional standards.

## Workflow

### 1. Expert Consultation

Invoke `elixir-expert` for project-specific cleanup guidance:

The expert will provide:
- Project-specific cleanup patterns
- Best practices for the codebase
- Common issues to look for
- Elixir idioms to follow

### 2. Compilation Check

Compile with warnings as errors to catch all issues:

```bash
# Run compilation with strict warnings
MIX_ENV=test mix compile --warnings-as-errors

# If warnings appear, fix each one:
# - Unused variables
# - Unused imports
# - Missing parentheses
# - Deprecated functions
# - Pattern match warnings
```

### 3. Code Quality Analysis

Run credo with strict settings:

```bash
# Run strict analysis
mix credo --strict --all

# Fix all issues including:
# - Readability issues
# - Refactoring opportunities
# - Warning signs
# - Consistency issues
# - Design suggestions
```

Common credo fixes:
- Remove unnecessary parentheses
- Fix pipe chain consistency
- Remove trailing whitespace
- Improve naming conventions
- Simplify complex functions

### 4. Test Suite Cleanup

Ensure all tests pass cleanly:

```bash
# Run full test suite
mix test

# Fix all issues:
# - Test failures
# - Test warnings
# - Deprecated function warnings
# - Async test issues
```

Clean up test output:
- Remove `IO.inspect` statements
- Remove debugging output
- Clean up test descriptions
- Fix flaky tests

### 5. Remove Unnecessary Comments

Clean up code comments:

**Remove:**
- Obvious comments that duplicate code
- Commented-out code blocks
- TODO comments that are completed
- Temporary debugging comments
- Auto-generated comments without value

**Keep:**
- Complex algorithm explanations
- Important business logic documentation
- Warning comments about non-obvious behavior
- API documentation
- Legal/copyright notices

Example cleanup:
```elixir
# BAD - Remove these
# This function adds two numbers
def add(a, b) do
  # Add a and b
  a + b  # Return the sum
end

# GOOD - Keep these
# Uses the Euclidean algorithm for efficiency
# See: https://en.wikipedia.org/wiki/Euclidean_algorithm
def gcd(a, 0), do: a
def gcd(a, b), do: gcd(b, rem(a, b))
```

### 6. Format Code

Apply consistent formatting:

```bash
# Format all files
mix format

# Check formatting without changing
mix format --check-formatted

# Format specific files
mix format lib/**/*.{ex,exs}
```

### 7. Additional Cleanup Tasks

#### Remove Debug Statements

Search and remove debugging code:

```bash
# Find debug statements
grep -r "IO.inspect\|IO.puts\|dbg\|IEx.pry" lib/ test/

# Remove or convert to proper logging
```

#### Check for Unused Dependencies

```bash
# Check for unused dependencies
mix deps.unlock --check-unused

# Remove unused from mix.exs
```

#### Update Dependencies

```bash
# Check outdated dependencies
mix hex.outdated

# Update if appropriate (careful with breaking changes)
mix deps.update --all
```

### 8. Final Validation

Invoke `elixir-reviewer` for comprehensive quality checks:

The reviewer will run:
- Format verification
- Compilation checks
- Credo analysis
- Security scanning (sobelow)
- Dependency audit
- Test coverage analysis
- Dialyzer (if configured)

### 9. Commit Changes

Stage and commit cleanup changes:

```bash
# Stage all cleanup changes
git add -A

# Create focused commits
git commit -m "chore: remove compilation warnings"
git commit -m "style: fix credo issues"
git commit -m "chore: remove debug statements"
git commit -m "style: apply mix format"
```

## Cleanup Checklist

### Code Quality
- [ ] Zero compilation warnings
- [ ] Zero credo issues (strict mode)
- [ ] All tests passing
- [ ] No test warnings
- [ ] Code formatted

### Code Hygiene
- [ ] No debug statements (IO.inspect, etc.)
- [ ] No unnecessary comments
- [ ] No commented-out code
- [ ] No unused variables/functions
- [ ] No deprecated function usage

### Dependencies
- [ ] No unused dependencies
- [ ] Dependencies up to date (where safe)
- [ ] Security vulnerabilities addressed

### Final State
- [ ] Project compiles cleanly
- [ ] All quality tools pass
- [ ] Code is maintainable
- [ ] Documentation is current

## Success Criteria

- **Clean compilation**: No warnings or errors
- **Quality passing**: Credo strict mode clean
- **Tests green**: All tests passing without warnings
- **Formatted**: Consistent code style
- **Production ready**: No debug code remaining

## Common Issues and Solutions

### Unused Variables

```elixir
# Problem
def process(data, _options) do  # _options unused

# Solution - prefix with underscore
def process(data, _options) do
```

### Pipe Chain Consistency

```elixir
# Problem - inconsistent
result = data
|> transform()
Enum.map(result, &process/1)

# Solution - consistent pipes
data
|> transform()
|> Enum.map(&process/1)
```

### Complex Functions

```elixir
# Problem - too complex
def complex_function(data) do
  # 50 lines of code
end

# Solution - extract helpers
def complex_function(data) do
  data
  |> prepare_data()
  |> process_data()
  |> format_result()
end
```

## Notes

- This command ensures production-ready code quality
- Focuses on Elixir-specific best practices
- Maintains zero-tolerance for warnings
- Creates maintainable, professional code
- Should be run before any PR or deployment
