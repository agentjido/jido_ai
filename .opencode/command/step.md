---
name: step
description: Analyze current implementation state and execute the next step from the planning document
agents:
  - implementation-agent
  - research-agent
  - elixir-expert
  - plan-updater
---

# Step - Incremental Implementation Progress

Analyzes the current state of implementation and guides through the next step in the planning document.

## Workflow

### 1. Identify Current Context

Determine what we're working on from git branch:

```bash
# Get current branch name
git branch --show-current
```

Based on branch type, locate the planning document:
- Feature branches (`feature/*`) → `notes/features/<feature_name>.md`
- Fix branches (`fix/*`) → `notes/fixes/<fix_name>.md`
- Task branches (`task/*`) → `notes/tasks/<task_name>.md`

### 2. Read Planning Document

Analyze the planning document to understand:
- Overall goal and context
- Completed steps (marked with ✅)
- Current implementation status
- Next uncompleted step in the plan

### 3. Analyze Current State

Examine the codebase to determine:
- What has been implemented so far
- Current working state of the feature/fix/task
- Any existing tests or documentation
- Potential blockers or dependencies

### 4. Identify Next Step

From the planning document:
- Identify the next uncompleted todo item
- Understand the requirements for this step
- Note any specific technical details
- Identify testing requirements

### 5. Research if Needed

If the next step requires unfamiliar technology or approaches:

**Invoke appropriate agents:**
- `research-agent` for unfamiliar technologies or APIs
- `elixir-expert` for Elixir/Phoenix/Ash/Ecto guidance
- Other specialized agents as needed

Document any research findings for implementation.

### 6. Output Status Summary

Provide a comprehensive summary:

```markdown
## Current Implementation Status

### Branch: [branch-name]
Working on: [feature/fix/task name]

### Completed Steps ✅
- [List of completed items from plan]

### Current State
- [What's currently working]
- [Any partial implementations]
- [Test coverage status]

### Next Step
**Step [N]: [Step description]**

Requirements:
- [Specific requirements for this step]
- [Technical details needed]
- [Testing requirements]

### Research/Documentation
[If research was performed, cite sources and key findings]
- Source: [Documentation/API reference]
- Key insight: [What was learned]

### Action Plan
1. [First action to implement the step]
2. [Second action]
3. [Testing approach]

### Potential Considerations
- [Any blockers or dependencies]
- [Risk factors]
- [Alternative approaches if needed]
```

### 7. Wait for Instructions

After outputting the summary:
- **STOP** and wait for user confirmation or guidance
- Do not proceed with implementation automatically
- User may want to:
  - Proceed with the suggested approach
  - Modify the approach
  - Skip this step
  - Get more information

### 8. Execute Step (After Confirmation)

Once user confirms, execute the step by:
1. Implementing the required changes
2. Creating/updating tests as specified
3. Verifying the implementation works
4. Running quality checks

### 9. Update Planning Document

After step completion, invoke `plan-updater` to:

**Update the planning document with:**

```markdown
## Implementation Plan

### Step [N]: [Step Name]
- [x] Status: ✅ Completed
- **Implementation**: [Brief summary of what was done]
- **Tests**: [Test coverage added]
- **Notes**: [Any important discoveries or decisions]
- **Completed**: [timestamp]

## Current Status

### What Works
- [Updated list of working features]
- [New functionality from this step]

### What's Next
- [Next step to tackle]
- [Any prerequisites identified]

### How to Test
```bash
# Commands to verify this step
mix test test/specific_test.exs
```
```

### 10. Commit Changes

Create focused commits:

```bash
# Commit implementation changes
git add [implementation files]
git commit -m "feat: [description of step completed]"

# Commit planning document update
git add notes/[type]/[name].md
git commit -m "docs: update planning document - completed [step name]"
```

## Success Criteria

- Current context correctly identified from git branch
- Planning document located and analyzed
- Next step clearly identified
- Research performed when needed with sources cited
- Comprehensive status summary provided
- User confirmation obtained before proceeding
- Step implemented successfully
- Planning document updated accurately
- Changes committed with descriptive messages

## Error Handling

### No Planning Document Found

If planning document doesn't exist:
```markdown
❌ No planning document found for branch: [branch-name]

Expected location: notes/[type]/[name].md

Please create a planning document first using:
- /feature - for new features
- /fix - for bug fixes
- /task - for simple tasks
```

### No Uncompleted Steps

If all steps are complete:
```markdown
✅ All steps in the planning document are complete!

Consider:
- Running final quality checks
- Updating documentation
- Creating a pull request
- Planning deployment
```

### Blocked Step

If step cannot proceed:
```markdown
⚠️ Step blocked by: [blocker description]

Options:
- Resolve the blocker first
- Skip to another step
- Update plan to work around blocker
```

## Notes

- This command enables incremental progress through planned work
- Always waits for user confirmation before implementing
- Maintains clear documentation of progress
- Ensures planning documents stay current
- Supports research and learning during implementation
