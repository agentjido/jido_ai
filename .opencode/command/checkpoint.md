---
name: checkpoint
description: Create a recoverable checkpoint commit with quality checks and progress updates
agents:
  - elixir-reviewer
  - plan-updater
  - consistency-reviewer
---

# Checkpoint - Create Recoverable Progress Commit

Creates a recoverable checkpoint commit after ensuring code quality, updating progress documentation, and organizing changes into logical commits.

## Workflow

### 1. Run Code Quality Tools

Ensure all quality tools pass before creating checkpoint:

#### For Elixir Projects

```bash
# Run tests
mix test

# Check code quality
mix credo --strict

# Fix minor issues found
mix format
mix compile --warnings-as-errors
```

#### For Rust Projects

```bash
# Run tests
cargo test

# Run clippy
cargo clippy -- -D warnings

# Fix formatting
cargo fmt
```

#### For JavaScript Projects

```bash
# Run tests
npm test

# Run linter
npm run lint

# Fix issues
npm run lint:fix
```

Fix all minor issues before proceeding. Major issues should be documented for later resolution.

### 2. Analyze Uncommitted Changes

Review all changes in working tree:

```bash
# View current status
git status

# Review detailed changes
git diff

# Check for untracked files
git status -u
```

Categorize changes:
- Completed features/fixes
- Work in progress
- Temporary/debug code
- Documentation updates

### 3. Update Planning Documents

Invoke `plan-updater` to update current progress:

Update the relevant planning document:
- `notes/features/*.md` for feature work
- `notes/fixes/*.md` for bug fixes
- `notes/tasks/*.md` for tasks

#### Progress Update Format

```markdown
## Current Progress - Checkpoint [Date/Time]

### Completed ✅
- [Completed items since last checkpoint]

### In Progress 🚧
- [Current work status]
- [Percentage complete]

### Blocked ⚠️
- [Any blockers encountered]

### Next Steps 📋
- [What comes next after checkpoint]

### Notes
- [Important observations]
- [Decisions made]
- [Issues to address later]
```

Also update PROJECT.md if significant progress made:

```markdown
## Project Status

Last Checkpoint: [Date/Time]
Overall Progress: [X]% complete
Current Phase: [Phase name]
```

### 4. Clean Working Directory

Remove temporary files not part of the project:

```bash
# Remove common temporary files
rm -f *.tmp *.log *.swp

# Clean build artifacts if needed
mix clean  # Elixir
cargo clean  # Rust
rm -rf node_modules/.cache  # JavaScript

# Remove debug files
find . -name "*.debug" -delete

# Check what will be removed
git clean -n

# Remove untracked files (careful!)
git clean -f
```

### 5. Create Logical Commits

Organize changes into logical commits using conventional commit syntax:

#### Stage and Commit by Category

```bash
# Feature/functionality changes
git add lib/feature/*.ex
git commit -m "feat: implement user authentication flow"

# Bug fixes
git add lib/fixes/*.ex
git commit -m "fix: resolve session timeout issue"

# Test updates
git add test/*.exs
git commit -m "test: add authentication tests"

# Documentation updates
git add docs/*.md notes/*.md
git commit -m "docs: update progress and API documentation"

# Checkpoint commit
git commit -m "checkpoint: save progress on authentication feature

- Authentication flow 80% complete
- Tests passing for completed portions
- Database schema finalized
- Next: implement password reset flow"
```

### 6. Verify Checkpoint

Ensure checkpoint is complete:

```bash
# Verify no uncommitted changes
git status

# Review commit history
git log --oneline -5

# Check that tests still pass
mix test  # or appropriate test command

# Verify branch is ready
git branch -v
```

### 7. Optional: Push to Remote

Create remote backup if desired:

```bash
# Push to remote branch
git push origin $(git branch --show-current)

# Or push to checkpoint branch
git push origin HEAD:checkpoint/$(date +%Y%m%d-%H%M%S)
```

### 8. Prompt for Continuation

After checkpoint is created:

```markdown
## Checkpoint Complete ✅

### Summary
- Code quality checks: PASSING
- Progress documented: UPDATED
- Changes committed: [X] commits
- Current branch: [branch-name]
- Remote backup: [YES/NO]

### Current Status
[Brief summary of where things stand]

### Next in Plan
[Next item from planning document]

Would you like to:
1. Continue with the next item in the plan?
2. Take a break and resume later?
3. Switch to a different task?
4. Review what was accomplished?
```

## Checkpoint Standards

### Code Quality Requirements
- All tests must pass
- Linting/formatting tools clean
- No critical warnings
- Minor issues fixed

### Documentation Requirements
- Planning documents updated
- Progress clearly documented
- Blockers identified
- Next steps defined

### Commit Requirements
- Logical grouping of changes
- Conventional commit format
- No AI attribution in messages
- Clear, descriptive messages

### Working Directory
- Temporary files removed
- Debug code cleaned up
- Only project files remain
- Build artifacts managed

## Success Criteria

- [ ] All quality tools passing
- [ ] Planning documents updated
- [ ] Temporary files cleaned
- [ ] Changes logically committed
- [ ] No uncommitted changes
- [ ] Progress documented
- [ ] Ready to continue or pause

## Notes

- Checkpoints enable safe experimentation
- Can rollback to checkpoint if needed
- Documents progress for handoffs
- Maintains clean git history
- Enables easy resumption of work
