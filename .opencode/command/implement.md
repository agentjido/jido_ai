---
name: implement
description: Execute the implementation for the current planning document systematically
agents:
  - implementation-agent
  - architecture-agent
  - elixir-expert
  - test-developer
  - consistency-reviewer
  - elixir-reviewer
  - qa-reviewer
---

# Implement - Execute Planning Document

Executes the implementation for the current planning document using systematic, quality-driven development.

## Workflow

### 1. Identify Work Context

Determine current work from git branch:

```bash
# Get current branch
git branch --show-current
```

Locate the planning document based on branch type:
- Feature branches (`feature/*`) → `notes/features/<feature_name>.md`
- Fix branches (`fix/*`) → `notes/fixes/<fix_name>.md`
- Task branches (`task/*`) → `notes/tasks/<task_name>.md`

### 2. Planning Document Verification

Verify planning document exists and is ready:

```bash
# Check for planning document
ls -la notes/features/ 2>/dev/null
ls -la notes/fixes/ 2>/dev/null
ls -la notes/tasks/ 2>/dev/null
```

Read the planning document to understand:
- Problem statement and solution approach
- Implementation steps to execute
- Success criteria and test requirements
- Agent consultations needed

### 3. Pre-Implementation Consultations

Before starting, the `implementation-agent` consults:

**`architecture-agent`**: 
- Confirm code placement and integration approach
- Verify architectural decisions
- Understand module boundaries

**`elixir-expert`** (for Elixir projects):
- Get implementation patterns for the technology stack
- Understand framework-specific approaches
- Review best practices

**`consistency-reviewer`**:
- Understand existing patterns to follow
- Ensure naming and structure consistency

### 4. Systematic Implementation

The `implementation-agent` executes each step from the planning document:

```markdown
## Implementation Process

For each step in the plan:
1. Read the step requirements
2. Consult relevant agents for guidance
3. Implement the code following patterns
4. Create tests alongside implementation
5. Verify step works correctly
6. Update planning document progress
7. Commit changes
```

### 5. Test Development (MANDATORY)

**CRITICAL: No implementation is complete without working tests**

For each implemented component:
- Invoke `test-developer` for comprehensive test strategy
- Implement unit tests for new functionality
- Add integration tests as appropriate
- Verify all tests pass before proceeding
- Never mark step complete without passing tests

Test implementation pattern:
```elixir
# Example for Elixir
defmodule MyApp.FeatureTest do
  use MyApp.DataCase

  test "feature works as expected" do
    # Setup with generators
    data = generate(data_generator())
    
    # Single action under test
    result = MyApp.Feature.execute(data)
    
    # Assertions
    assert result.status == :success
  end
end
```

### 6. Continuous Quality Validation

After implementing each component:

**Run quality checks:**
```bash
# For Elixir projects
mix test                    # All tests must pass
mix format                  # Code formatting
mix credo --strict          # Code quality
mix dialyzer               # Type checking (if configured)

# General
git diff --check           # No whitespace errors
```

**Invoke review agents:**
- `elixir-reviewer` for Elixir-specific checks
- `qa-reviewer` for test coverage validation
- `consistency-reviewer` for pattern adherence

### 7. Progress Documentation

Update planning document after each step:

```markdown
## Implementation Steps

### Step 1: [Step Name]
- [x] Status: ✅ Completed
- Implementation: [Summary of what was built]
- Tests: [Test coverage added]
- Quality: All checks passing
- Committed: [Commit hash/message]

### Step 2: [Step Name]
- [ ] Status: 🚧 In Progress
- Implementation: [Current work]
- Next: [What needs to be done]
```

### 8. Commit Strategy

Make focused commits after each step:

```bash
# Implementation commit
git add [implementation files]
git commit -m "feat: [step description]"

# Test commit
git add [test files]
git commit -m "test: add tests for [feature]"

# Documentation update
git add notes/[type]/[name].md
git commit -m "docs: update planning document progress"
```

## Success Criteria

Before marking implementation complete:

### Must Have
- [ ] All planning steps executed
- [ ] All tests written and passing
- [ ] Code quality checks passing
- [ ] Planning document fully updated
- [ ] All commits made with clear messages

### Quality Gates
- [ ] Test coverage adequate for changes
- [ ] No credo warnings or errors
- [ ] Code properly formatted
- [ ] Patterns consistent with codebase
- [ ] Documentation updated

### Final Verification
```bash
# Run full test suite
mix test

# Run quality checks
mix credo --strict
mix format --check-formatted

# Verify no debug statements
grep -r "IO.inspect\|console.log\|debugger" lib/ test/
```

## Error Handling

### No Planning Document

```markdown
❌ No planning document found

Expected: notes/[type]/[name].md

Please create a planning document first:
- Use /feature for new features
- Use /fix for bug fixes  
- Use /task for simple tasks
```

### Test Failures

```markdown
⚠️ Tests failing - implementation incomplete

Failed tests must be fixed before proceeding.
Run test-fixer agent or debug manually.
```

### Quality Issues

```markdown
⚠️ Quality checks failing

Fix all issues before marking complete:
- Credo warnings: [count]
- Format issues: [count]
- Test coverage: [percentage]
```

## Usage Examples

```bash
# Feature implementation
git checkout feature/user-authentication
/implement  # Executes notes/features/user-authentication.md

# Bug fix implementation
git checkout fix/memory-leak
/implement  # Executes notes/fixes/memory-leak.md

# Task implementation
git checkout task/update-dependencies
/implement  # Executes notes/tasks/update-dependencies.md
```

## Key Benefits

- **Systematic execution**: Follows planning documents precisely
- **Expert guidance**: Consults appropriate agents for each component
- **Quality assurance**: Continuous review throughout implementation
- **Test-driven**: Enforces comprehensive testing
- **Progress tracking**: Maintains updated planning documents
- **Architectural integrity**: Ensures proper code placement and patterns

## Notes

- This command orchestrates the complete implementation process
- Testing is mandatory - no exceptions
- Quality gates prevent substandard code
- Planning documents serve as single source of truth
- Incremental commits enable easy rollback if needed
