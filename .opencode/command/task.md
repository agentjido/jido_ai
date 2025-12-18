---
name: task
description: Create lightweight task planning for simple work items or delegate to appropriate specialized planners
agents:
  - task-planner
  - feature-planner
  - fix-planner
  - research-agent
  - elixir-expert
  - consistency-reviewer
---

# Task Planning and Execution

Determines the right planning approach for your work item and delegates to the appropriate planning agent.

## Decision Framework

### Determine Work Type

The command will analyze your request and route to the appropriate planner:

- **Complex New Functionality** → Delegates to `feature-planner`
- **Bug Fixes or Issues** → Delegates to `fix-planner`  
- **Simple Tasks** → Uses `task-planner`

## Workflow

### 1. Work Classification

Analyze the work item to determine complexity:

**Simple Tasks** (uses task-planner):
- Configuration changes
- Simple refactoring
- Documentation updates
- Tool setup or installation
- Small improvements
- Quick fixes without investigation

**Complex Features** (escalates to feature-planner):
- New complex functionality
- Multi-component integrations
- Architectural changes
- Features requiring extensive research

**Bug Fixes** (escalates to fix-planner):
- Bug investigations
- Security issues
- System stability problems
- Issues requiring root cause analysis

### 2. Task Planning Process

For simple tasks, the `task-planner` agent will:

1. Create lightweight planning document in `./notes/tasks/<task_name>.md`
2. Include essential task description and todo list
3. Consult agents as needed:
   - `research-agent` for unfamiliar tools
   - `elixir-expert` for Elixir-related tasks
   - `consistency-reviewer` for pattern-related work
4. Escalate if complexity exceeds scope

### 3. Git Workflow Setup

```bash
# Check current branch
git branch --show-current

# If not on a task branch, create one
git checkout -b task/[task-name]
```

**Commit Standards:**
- Use conventional commits (feat:, fix:, docs:, chore:)
- Make small, focused commits
- Never reference AI assistants in messages
- Commit after each completed step

### 4. Execute Task

Follow the planning document created by task-planner:

1. Work through todo list items
2. Update planning document as you progress
3. Mark items complete with checkboxes
4. Commit changes incrementally

## Planning Document Structure

The task-planner creates a focused document with:

```markdown
# [Task Name]

## Task Description
Clear description of what needs to be done and why

## Agent Consultations (if needed)
- Research findings
- Expert guidance received

## Approach
High-level strategy for completing the task

## Todo List
- [ ] Specific, actionable steps
- [ ] Each item completable and verifiable
- [ ] Include testing/verification steps

## Success Criteria
- Clear completion indicators
- Measurable outcomes
- Quality standards maintained

## Notes (Optional)
- Edge cases
- Future improvements
- Dependencies
```

## Agent Consultation Strategy

### Minimal Consultations (Task-Planner)

When task is straightforward:
- Well-understood requirements
- Using familiar tools and patterns
- Following established procedures
- Non-code changes (docs, config)

### Include Agent Consultations

When task involves:
- Unfamiliar technologies → `research-agent`
- Elixir/Phoenix/Ash code → `elixir-expert`
- Pattern consistency → `consistency-reviewer`
- Security implications → Escalate to `fix-planner`
- Complex architecture → Escalate to `feature-planner`

## Escalation Triggers

Task-planner will recommend escalation when:

### To Feature-Planner
- Multiple components affected
- New API endpoints needed
- Database schema changes
- Complex state management
- Extensive testing required

### To Fix-Planner
- Root cause investigation needed
- Security vulnerabilities found
- Performance issues discovered
- System stability affected
- Rollback strategies required

## Example Task Executions

### Simple Configuration Task

```markdown
Input: "Add git aliases for common commands"

Process:
1. Task-planner creates plan
2. Reviews existing alias patterns
3. Adds aliases to configuration
4. Tests each alias
5. Updates documentation
```

### Task Requiring Escalation

```markdown
Input: "Add user authentication"

Process:
1. Task-planner analyzes complexity
2. Recognizes multi-component feature
3. Escalates to feature-planner
4. Feature-planner creates comprehensive plan
```

## Success Criteria

- Appropriate planner selected for work complexity
- Planning overhead matches task size
- Essential consultations included
- Clear, actionable todo items created
- Git workflow properly initialized
- Incremental commits made

## Notes

- This command acts as a smart router to appropriate planners
- Prevents over-engineering simple tasks
- Ensures complex work gets proper planning
- Maintains consistent git workflow
- Enables quick execution for simple work
