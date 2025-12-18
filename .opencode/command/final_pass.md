---
name: final-pass
description: Perform final quality checks before merging to ensure all tests pass, code is formatted, and documentation is current
agents:
  - elixir-reviewer
  - documentation-updater
  - qa-reviewer
---

# Final Pass - Pre-Merge Quality Checks

Performs comprehensive final checks before merging to ensure code quality, passing tests, and up-to-date documentation.

## Workflow

### 1. Identify Current Work

Determine what we've been working on:

```bash
# Get current branch
git branch --show-current

# View recent commits
git log --oneline -10
```

### 2. Run All Tests

Ensure complete test suite passes:

```bash
# For Elixir projects
mix test --seed 0
mix test --seed 42  # Run with different seed to catch order dependencies

# For JavaScript projects
npm test

# For Python projects
pytest

# General - ensure all tests pass
echo "Test Status: $(if [test-command]; then echo '✅ PASSING'; else echo '❌ FAILING'; fi)"
```

If tests fail, stop and fix them using `/fix-tests` command.

### 3. Code Quality Checks

Ensure code is properly formatted and linted:

#### For Elixir Projects

```bash
# Format check
mix format --check-formatted

# If formatting needed
mix format

# Run linter
mix credo --strict

# Run dialyzer if configured
mix dialyzer

# Security checks
mix sobelow --config
mix deps.audit
```

#### For Other Languages

```bash
# JavaScript
npm run lint
npm run format

# Python
black --check .
flake8
mypy .

# Go
go fmt ./...
golint ./...
```

### 4. Documentation Update

Invoke `documentation-updater` to ensure all docs reflect current state:

#### Check Documentation Locations

```bash
# Feature/fix documentation
ls -la notes/features/
ls -la notes/fixes/
ls -la notes/tasks/

# Project documentation
ls -la docs/

# Core project files
ls PROJECT.md CLAUDE.md README.md
```

#### Update Required Documentation

The `documentation-updater` will:
1. **Planning documents** (`notes/**/*.md`):
   - Mark features as complete
   - Update implementation status
   - Add retrospective notes

2. **Project documentation** (`docs/**/*.md`):
   - Update API documentation
   - Revise architecture diagrams
   - Update user guides

3. **Core files**:
   - **PROJECT.md**: Add new features, update architecture
   - **CLAUDE.md**: Add learnings and patterns
   - **README.md**: Update if user-facing changes

### 5. Commit Final Changes

Stage and commit all updates:

```bash
# Stage all changes
git add -A

# Create comprehensive commit
git commit -m "chore: final pass - tests, formatting, and documentation

- All tests passing
- Code formatted and linted
- Documentation updated to reflect current state
- Ready for merge"
```

### 6. Update from Main

Ensure we're up to date with main branch:

```bash
# Fetch latest from origin
git fetch origin main

# Check if main is up to date
git log origin/main..main

# If behind, update main
git checkout main
git pull origin main
git checkout -

# Rebase or merge main into current branch
git rebase main
# OR
git merge main
```

### 7. Generate Diff Summary

Review all changes against main:

```bash
# Show diff statistics
git diff main --stat

# Show commit list
git log main..HEAD --oneline

# Show detailed diff for review
git diff main
```

### 8. Prepare Merge Commit Message

Generate comprehensive merge commit message:

```markdown
## Suggested Merge Commit Message

[Type]: [Brief description of main change]

## Summary
[One paragraph describing what this PR accomplishes]

## Changes
- [Major change 1]
- [Major change 2]
- [Major change 3]

## Tests
- Added [number] new tests
- All tests passing
- Coverage: [percentage if available]

## Documentation
- Updated PROJECT.md with [changes]
- Updated API docs for [endpoints/features]
- Added user guide for [feature]

## Breaking Changes
[None | Description of breaking changes]

## Migration Notes
[None | Instructions for migration if needed]

## Checklist
✅ All tests passing
✅ Code formatted and linted
✅ Documentation updated
✅ Security considerations addressed
✅ Performance impact assessed
✅ Backward compatibility maintained

Closes #[issue-number] (if applicable)
```

## Quality Checklist

Before proceeding with merge:

### Code Quality
- [ ] All tests passing (multiple seeds if applicable)
- [ ] No linting errors or warnings
- [ ] Code properly formatted
- [ ] No debug statements (console.log, IO.inspect, etc.)
- [ ] No commented-out code

### Documentation
- [ ] Planning documents marked complete
- [ ] Project documentation updated
- [ ] API documentation current
- [ ] README reflects new features
- [ ] CHANGELOG updated (if applicable)

### Repository State
- [ ] Current with main branch
- [ ] No merge conflicts
- [ ] Commit history clean
- [ ] No unnecessary files

### Final Verification
```bash
# One final test run
[test-command]

# Verify no uncommitted changes
git status

# Check diff one more time
git diff main --stat
```

## Success Criteria

- **All tests passing** consistently
- **Code quality** checks passing
- **Documentation** fully updated
- **Clean diff** against main
- **Ready for merge** without issues

## Error Handling

### Tests Failing

```markdown
❌ Tests are failing

Cannot proceed with final pass. Fix tests first:
- Run `/fix-tests` to systematically fix failures
- Or debug manually and fix
```

### Formatting Issues

```markdown
⚠️ Code formatting issues detected

Auto-fixing:
```bash
mix format  # Elixir
npm run format  # JavaScript
black .  # Python
```
```

### Documentation Out of Date

```markdown
⚠️ Documentation needs updating

Run documentation update:
- Use `/update-docs` command
- Or manually update affected documentation
```

### Merge Conflicts

```markdown
⚠️ Merge conflicts with main

Resolve conflicts:
```bash
git merge main
# Resolve conflicts in editor
git add [resolved-files]
git commit
```
```

## Notes

- This command ensures code is production-ready before merge
- Catches common issues that could break main branch
- Maintains high code quality standards
- Ensures documentation stays synchronized
- Provides clean, informative merge commits
