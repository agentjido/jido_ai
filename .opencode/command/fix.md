---
name: fix
description: Create a plan and implement a bug fix or issue resolution with systematic investigation and testing
agents:
  - fix-planner
  - implementation-agent
  - factual-reviewer
  - senior-engineer-reviewer
  - security-reviewer
  - consistency-reviewer
  - elixir-expert
  - research-agent
  - test-developer
---

# Fix - Bug Resolution Planning and Implementation

Creates a comprehensive plan and implements a bug fix or issue resolution with systematic investigation, root cause analysis, and regression testing.

## Workflow

### 1. Git Workflow Setup

Establish proper branch structure:

```bash
# Check current branch
git branch --show-current

# If not on a fix branch, create one
git checkout -b fix/[issue-description]
```

**Commit standards:**
- Use conventional commits: `fix: [description]`
- Make small, focused commits
- Never reference AI assistants in messages
- Commit after each investigation and implementation step

### 2. Investigation Phase

Systematic issue investigation with multi-perspective analysis:

#### Initial Investigation
1. **Reproduce the issue** reliably
2. **Analyze symptoms**: Error messages, logs, behavior
3. **Check existing codebase**: Related code and documentation
4. **Review recent changes**: Git history for potential causes

#### Expert Consultation
Invoke specialized agents for comprehensive analysis:

**Core Reviewers (run in parallel):**
- `factual-reviewer`: Verify facts and evidence
- `senior-engineer-reviewer`: Architectural implications
- `security-reviewer`: Security vulnerability assessment
- `consistency-reviewer`: Pattern and convention review

**Language/Framework Experts:**
- `elixir-expert`: For Elixir/Phoenix/Ash issues
- `research-agent`: For unfamiliar error patterns

#### Documentation
Save investigation findings in `notes/fixes/[issue-name].md`

### 3. Fix Planning

Invoke `fix-planner` to create structured planning document:

```markdown
# Fix [Issue Name]

## Issue Description
- Clear problem description
- Steps to reproduce
- Expected vs actual behavior
- Impact and urgency

## Root Cause Analysis
- Investigation findings
- Origin of issue
- Technical explanation
- Affected components

## Solution Overview
- High-level approach
- Key technical decisions
- Alternative approaches considered

## Technical Details
- Files to change
- Configuration updates
- Dependencies
- Compatibility considerations

## Testing Strategy
- Verification approach
- Regression tests
- Edge cases
- Performance impact

## Rollback Plan
- Reversion procedures
- Monitoring points
- Backup procedures

## Implementation Plan
- [ ] Step-by-step tasks
- [ ] Each with validation
- [ ] Test requirements
```

### 4. Implementation Phase

Execute the fix following the plan:

#### For Each Implementation Step

1. **Read step requirements** from plan
2. **Implement the fix** following guidance
3. **Create regression tests** (MANDATORY)
4. **Verify fix works** locally
5. **Update planning document** with progress
6. **Commit changes** incrementally

#### Regression Testing Requirements

**CRITICAL: Fixes are NOT complete without regression tests**

Invoke `test-developer` to create:
- Tests that fail before the fix
- Tests that pass after the fix
- Verification that existing tests still pass
- Edge case coverage

Example regression test:
```elixir
# Elixir example
test "session timeout is correctly set to 5 minutes" do
  # This test would have failed before the fix
  config = Application.get_env(:my_app, :session)
  assert config[:timeout] == 300_000  # 5 minutes in milliseconds
end
```

### 5. Progress Documentation

Update planning document continuously:

```markdown
## Current Status

### What's Fixed ✅
- [Completed fix components]
- [Tests passing]

### What's Still Broken ❌
- [Remaining issues]
- [Failing tests]

### How to Test
```bash
# Commands to verify the fix
mix test test/session_test.exs
```

### Complications Discovered
- [New findings during implementation]
- [Additional considerations]
```

### 6. Quality Validation

Before marking complete:

```bash
# Run all tests
mix test

# Run quality checks
mix credo --strict
mix format --check-formatted

# Verify regression tests
mix test test/regression/[issue]_test.exs
```

### 7. Final Verification

Ensure fix is complete:
- [ ] Issue can no longer be reproduced
- [ ] All regression tests passing
- [ ] Existing tests still passing
- [ ] Code quality checks passing
- [ ] Planning document fully updated
- [ ] Rollback plan documented

## Fix Categories

### Simple Bug Fix Example

**Issue**: Login timeout too short (30s instead of 5min)

**Process:**
1. Investigate config files
2. Find incorrect timeout value
3. Update configuration
4. Add regression test
5. Verify fix works

### Complex Bug Fix Example

**Issue**: Memory leak in background job processor

**Process:**
1. Memory profiling investigation
2. Identify objects not being released
3. Implement cleanup handlers
4. Add memory monitoring
5. Create memory leak tests
6. 24-hour stability testing

## Investigation Techniques

### Debugging Approaches
- **Consistent reproduction**: Ensure reliable triggering
- **Log analysis**: Pattern identification
- **Tool usage**: Profilers, debuggers, monitors
- **Component isolation**: Narrow scope
- **History review**: Check recent changes

### Evidence Collection
- Investigation steps taken
- Screenshots and log snippets
- Error messages and stack traces
- Environment details
- Time tracking for similar issues

## Success Criteria

### Must Have
- [ ] Issue reliably reproduced before fix
- [ ] Root cause identified and understood
- [ ] Fix implemented following plan
- [ ] Regression tests created and passing
- [ ] All existing tests still passing
- [ ] Planning document complete

### Quality Gates
- [ ] Code review passed
- [ ] Security implications assessed
- [ ] Performance impact evaluated
- [ ] Documentation updated
- [ ] Monitoring plan in place

## Error Handling

### Cannot Reproduce Issue

```markdown
⚠️ Unable to reproduce issue

Required before proceeding:
- Detailed reproduction steps
- Environment specifications
- Error logs or screenshots
- Consistent trigger conditions
```

### Root Cause Unknown

```markdown
⚠️ Root cause not identified

Consider:
- Additional logging
- Profiling tools
- Expert consultation
- Code bisection
- Environment comparison
```

### Tests Failing After Fix

```markdown
❌ Fix causes test failures

Actions:
- Review fix implementation
- Check for side effects
- Adjust fix approach
- Update affected tests if behavior change is intended
```

## Notes

- This command orchestrates complete bug fix workflow
- Investigation phase is critical - never skip
- Regression tests are mandatory
- Small commits enable easy rollback
- Documentation helps prevent similar issues
- Multi-perspective analysis improves fix quality
