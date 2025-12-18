---
name: commit
description: Analyze changes in the worktree and commit them in logical chunks
agents:
  - consistency-reviewer
---

# Commit - Logical Change Organization

Analyzes changes in the working tree and commits them in logical, focused chunks for better version control history.

## Workflow

### 1. Analyze Current Changes

Review all uncommitted changes:

```bash
# Show current status
git status

# Show detailed diff of all changes
git diff

# Show diff statistics
git diff --stat

# List changed files by type
git diff --name-status
```

### 2. Categorize Changes

Group changes by logical units:

**Categories to consider:**
- **Feature changes** - New functionality
- **Bug fixes** - Problem resolutions
- **Refactoring** - Code improvements
- **Tests** - Test additions or modifications
- **Documentation** - Doc updates
- **Configuration** - Config file changes
- **Dependencies** - Package updates
- **Style** - Formatting changes

### 3. Review Changes by File

Examine each file to understand changes:

```bash
# Review specific file changes
git diff path/to/file

# Show changes with context
git diff -U10 path/to/file

# Check for whitespace issues
git diff --check
```

### 4. Stage and Commit Logical Chunks

#### Chunk 1: Core Functionality

```bash
# Stage related functional changes
git add lib/module/feature.ex
git add lib/module/helper.ex

# Create focused commit
git commit -m "feat: add user authentication module

- Implement login functionality
- Add session management
- Include password hashing"
```

#### Chunk 2: Tests

```bash
# Stage test files
git add test/module/feature_test.exs
git add test/support/test_helpers.ex

# Commit tests separately
git commit -m "test: add tests for authentication module

- Unit tests for login flow
- Integration tests for sessions
- Test helpers for auth mocking"
```

#### Chunk 3: Documentation

```bash
# Stage documentation
git add README.md
git add docs/authentication.md

# Commit documentation
git commit -m "docs: add authentication documentation

- Update README with auth setup
- Add authentication guide
- Include API examples"
```

#### Chunk 4: Configuration

```bash
# Stage config changes
git add config/config.exs
git add .env.example

# Commit configuration
git commit -m "chore: update configuration for authentication

- Add auth-related config options
- Update example environment file"
```

### 5. Interactive Staging (When Needed)

For complex changes within a single file:

```bash
# Stage parts of a file interactively
git add -p path/to/file

# Options during interactive staging:
# y - stage this hunk
# n - don't stage this hunk
# s - split hunk into smaller hunks
# e - manually edit the hunk
```

### 6. Verify Commits

After creating commits:

```bash
# Review commit history
git log --oneline -5

# Check commit details
git show HEAD

# Verify nothing left uncommitted
git status
```

## Commit Message Conventions

Use conventional commit format:

```
<type>(<scope>): <subject>

<body>

<footer>
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation only
- `style`: Formatting, no code change
- `refactor`: Code restructuring
- `test`: Test additions/changes
- `chore`: Maintenance tasks

**Examples:**

```bash
# Feature commit
git commit -m "feat(auth): implement JWT token generation"

# Bug fix commit
git commit -m "fix(api): handle null response in user endpoint"

# Documentation commit
git commit -m "docs: update API documentation for v2 endpoints"

# Refactoring commit
git commit -m "refactor: extract validation logic to separate module"
```

## Logical Chunking Guidelines

### What Makes a Good Chunk

- **Single Purpose**: Each commit does one thing
- **Self-Contained**: Commit is complete and functional
- **Reviewable**: Changes are easy to understand
- **Revertable**: Can be reverted without breaking other features

### What to Avoid

- **Mixed Concerns**: Don't mix features with unrelated fixes
- **Incomplete Work**: Don't commit broken code
- **Giant Commits**: Don't commit everything at once
- **Formatting with Logic**: Separate style changes from functional changes

## Example Chunking Scenarios

### Scenario 1: Feature with Tests and Docs

```bash
# Chunk 1: Core feature implementation
git add lib/feature/*.ex
git commit -m "feat: implement user profile management"

# Chunk 2: Database migrations
git add priv/repo/migrations/*.exs
git commit -m "feat: add user profile database schema"

# Chunk 3: Tests
git add test/feature/*_test.exs
git commit -m "test: add user profile tests"

# Chunk 4: Documentation
git add docs/user_profiles.md
git commit -m "docs: add user profile documentation"
```

### Scenario 2: Bug Fix with Regression Test

```bash
# Chunk 1: The fix
git add lib/module/broken_part.ex
git commit -m "fix: correct calculation in payment processor"

# Chunk 2: Regression test
git add test/regression/payment_test.exs
git commit -m "test: add regression test for payment calculation"
```

## Success Criteria

- [ ] All changes analyzed and understood
- [ ] Changes grouped into logical units
- [ ] Each commit has single purpose
- [ ] Commit messages follow conventions
- [ ] No unrelated changes mixed together
- [ ] All changes committed
- [ ] Git history clean and readable

## Notes

- Logical commits make code review easier
- Clean history helps with debugging (git bisect)
- Focused commits enable selective reverts
- Good commit messages document intent
- Consider squashing related commits before merging
