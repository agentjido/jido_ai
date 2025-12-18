---
name: feature
description: Create comprehensive feature planning document and guide implementation with continuous updates
agents:
  - feature-planner
  - research-agent
  - elixir-expert
  - senior-engineer-reviewer
  - implementation-agent
  - test-developer
  - elixir-reviewer
---

# Feature - Planning and Implementation

Creates comprehensive feature planning documents and guides systematic implementation with continuous plan updates and quality assurance.

## Workflow

### 1. Feature Planning Phase

Invoke `feature-planner` to create comprehensive planning document:

The `feature-planner` will:
- **Consult `research-agent`** for unfamiliar technologies, APIs, frameworks
- **Consult `elixir-expert`** for Elixir, Phoenix, Ash, Ecto patterns
- **Consult `senior-engineer-reviewer`** for architectural decisions
- Create structured implementation plan with clear, testable steps
- Save planning document in `notes/features/[feature-name].md`

#### Planning Document Structure

The planning document will include:

1. **Problem Statement** - Clear description and impact analysis
2. **Solution Overview** - High-level approach and key decisions
3. **Agent Consultations Performed** - Documents all expert consultations
4. **Technical Details** - File locations, dependencies, configuration
5. **Success Criteria** - Measurable outcomes with test requirements
6. **Implementation Plan** - Logical steps with testing integration
7. **Notes/Considerations** - Edge cases, future improvements, risks

### 2. Git Workflow Setup

Establish proper branch structure:

```bash
# Check current branch
git branch --show-current

# If not on a feature branch, create one
git checkout -b feature/[feature-name]
```

**Commit Standards:**
- Use conventional commits (`feat:`, `test:`, `docs:`, etc.)
- Make small, focused commits for better analysis
- Never reference AI assistants in commit messages
- Commit after each implementation step

### 3. Implementation with Plan Updates

Follow the planning document systematically:

#### For Each Implementation Step

1. **Read step requirements** from planning document
2. **Implement the functionality** following the plan
3. **Create comprehensive tests** (MANDATORY)
4. **Update planning document** with progress
5. **Output status summary** and wait for instructions

#### Progress Documentation Format

```markdown
## Implementation Plan

### Step 1: [Step Name]
- [x] Status: ✅ Completed
- Implementation: [What was built]
- Tests: [Test coverage added]
- Notes: [Any discoveries or changes]

### Step 2: [Step Name]
- [ ] Status: 🚧 In Progress
- Implementation: [Current work]
- Next: [What needs to be done]

## Current Status

### What Works
- [Completed functionality]
- [Passing tests]

### What's Next
- [Next implementation step]
- [Required tests]

### How to Run
```bash
# Commands to test the feature
mix test test/feature_test.exs
mix phx.server
```

### Discovered Limitations
- [Any limitations found]
- [Planned workarounds]
```

### 4. Quality Requirements

#### Testing Requirements (MANDATORY)

**Features are NOT complete without working tests:**

- Every feature must have comprehensive test coverage
- Tests must pass before marking any step complete
- Invoke `test-developer` for systematic test creation
- Never claim feature completion without all tests passing

```bash
# Verify all tests pass
mix test

# Check test coverage
mix test --cover
```

#### Code Quality Requirements (MANDATORY)

**Features are NOT complete without passing quality checks:**

For Elixir projects:
```bash
# Must have zero warnings
mix credo --strict

# Check formatting
mix format --check-formatted

# Run dialyzer if configured
mix dialyzer
```

Never claim feature completion if any of these return:
- Credo warnings
- Refactoring opportunities
- Code readability issues

### 5. Implementation Workflow

Complete cycle for each step:

```bash
# 1. Implement functionality
# [Write code following plan]

# 2. Create tests
# [Comprehensive test coverage]

# 3. Run quality checks
mix test
mix credo --strict
mix format

# 4. Update planning document
# [Mark step complete, add notes]

# 5. Commit changes
git add .
git commit -m "feat: [description of completed step]"

# 6. Report status
# [Output summary and wait]
```

### 6. Expert Consultation During Implementation

Consult agents as needed:
- `elixir-expert` for Elixir-specific patterns
- `research-agent` for unfamiliar concepts
- `test-developer` for test strategies
- `senior-engineer-reviewer` for architectural validation

## Success Criteria

### Planning Phase Complete
- [ ] Comprehensive planning document created
- [ ] All necessary research conducted
- [ ] Expert consultations documented
- [ ] Clear implementation steps defined

### Implementation Complete
- [ ] All planning steps executed
- [ ] Comprehensive test coverage added
- [ ] All tests passing
- [ ] Zero credo warnings
- [ ] Code properly formatted
- [ ] Planning document fully updated
- [ ] Git history clean with focused commits

## Error Handling

### Missing Planning Document

```markdown
❌ No planning document found

Creating comprehensive plan first...
[Invokes feature-planner]
```

### Tests Failing

```markdown
⚠️ Tests failing - feature incomplete

Fix tests before proceeding:
- Debug failing tests
- Use `/fix-tests` if needed
```

### Code Quality Issues

```markdown
⚠️ Credo warnings detected

Feature incomplete until resolved:
```bash
mix credo --strict --all
# Fix all issues shown
```
```

## Example Usage Flow

```markdown
1. Start: "Build user authentication feature"

2. Planning:
   - feature-planner creates comprehensive plan
   - Consults research-agent for JWT best practices
   - Consults elixir-expert for Phoenix auth patterns
   - Creates notes/features/user-authentication.md

3. Implementation:
   - Step 1: Create user schema → tests → ✅
   - Step 2: Add authentication context → tests → ✅
   - Step 3: Create login endpoint → tests → ✅
   - Step 4: Add JWT generation → tests → ✅
   - Each step: update plan, commit, report

4. Quality Validation:
   - All tests passing
   - Zero credo warnings
   - Documentation complete

5. Feature Complete ✅
```

## Notes

- This command orchestrates the complete feature development lifecycle
- Planning is mandatory - no implementation without a plan
- Testing is mandatory - no step complete without tests
- Quality gates prevent substandard code
- Continuous documentation maintains project knowledge
- Small commits enable easy rollback if needed
