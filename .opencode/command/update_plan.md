---
name: update-plan
description: Update existing planning documents with new requirements or changes
agents:
  - plan-updater
  - feature-planner
  - fix-planner
  - task-planner
---

# Update Planning Document

Updates existing planning documents (features, fixes, or tasks) with new information, requirements, or changes while maintaining proper structure and implementation guidance.

## When to Use

- **New requirements** discovered during implementation
- **Scope changes** or additional functionality needed
- **Technical constraints** or approach modifications
- **User feedback** requiring plan adjustments
- **Implementation blockers** requiring plan revision
- **Architecture changes** affecting the original plan

## Workflow

### 1. Locate Planning Document

First, identify the active planning document:

```bash
# Check for feature plans
ls -la notes/features/

# Check for fix plans
ls -la notes/fixes/

# Check for task plans
ls -la notes/tasks/
```

If no planning document exists, stop and create one first using the appropriate command (`/feature`, `/fix`, or `/task`).

### 2. Analyze Current State

Review the existing plan to understand:
- What has been implemented (marked with ✅)
- What remains to be done
- Current success criteria and testing requirements

Assess the new information:
- Gather all new requirements or changes
- Determine impact (additive, modifications, or removals)
- Evaluate timeline and complexity effects

### 3. Execute Plan Update

The `plan-updater` agent will:

1. Read and analyze the existing planning document
2. Determine the appropriate planning agent to invoke:
   - `feature-planner` for feature plan updates
   - `fix-planner` for fix plan updates
   - `task-planner` for task plan updates
3. Coordinate the update process with the selected planner
4. Document all changes with clear markers

### 4. Document Changes

The updated plan will include:

```markdown
# [Original Plan Title] - UPDATED [Date]

## Change Summary
**Update Date**: [Current date]
**Reason for Update**: [Brief explanation]
**Key Changes**:
- [Major change 1]
- [Major change 2]

## Implementation Plan

### Completed Steps ✅
- [x] Step 1: [Completed work]

### Modified Steps 🔄
- [ ] Step 3: [UPDATED] [Modified description]
  - **Original**: [What it was]
  - **Updated**: [What it is now]
  - **Reason**: [Why changed]

### New Steps 🆕
- [ ] Step 5: [NEW] [New requirement]
  - **Added because**: [Reason]

### Removed Steps ❌
- ~~Step 4: [REMOVED] [Original description]~~
  - **Removed because**: [Reason]
```

### 5. Update Success Criteria

Ensure success criteria reflect new requirements:
- Original criteria remain (unless explicitly changed)
- New criteria for additional features
- Modified criteria for changed requirements
- **All test requirements updated**

### 6. Prepare Implementation Handoff

Create clear guidance for implementation:

```markdown
## Current Implementation Status
- **Completed**: [X] of [Y] steps
- **In Progress**: [Current work]
- **Next Priority**: [What to do next]

## Impact of Changes
- **Timeline Impact**: [Estimated effect]
- **Complexity Change**: [Assessment]
- **Testing Impact**: [Additional test requirements]
```

## Update Patterns

### New Feature Requirements

When adding new functionality:
- Keep existing completed steps
- Add new implementation steps at appropriate position
- Update success criteria to include new features
- Ensure test coverage for new requirements

### Technical Constraint Changes

When approach needs modification:
- Mark affected steps as [MODIFIED]
- Document why the change is necessary
- Update technical details section
- Revise risk assessment if needed

### Scope Changes

When expanding or reducing scope:
- Clearly mark additions as [NEW]
- Strike through removed items
- Update timeline estimates
- Adjust success criteria accordingly

## Quality Assurance

The updated plan must:
- Maintain logical flow and coherence
- Preserve record of completed work
- Clearly differentiate changes (✅, 🔄, 🆕, ❌)
- Include test requirements for all changes
- Document rationale for modifications
- Provide clear next steps

## Success Criteria

- **Clear change documentation**: All modifications explained
- **Updated implementation steps**: Actionable and specific
- **Maintained plan structure**: All sections complete
- **Test requirements**: Updated for all changes
- **Implementation ready**: Clear next steps provided

## Notes

- This command only updates existing plans
- Always preserve completed work history
- Test requirements are mandatory for all changes
- Use visual indicators for clarity
- Document change rationale
