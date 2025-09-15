# Roadmap Management System

## Overview

The `roadmap/` folder provides a systematic approach to planning and tracking work across JidoWorkspace projects. It mirrors the monorepo structure and uses markdown files for simplicity and version control integration.

## Folder Structure

```
roadmap/
├── AGENTS.md               # This documentation
├── README.md               # Quick start guide
├── templates/              # Copy-paste ready markdown templates
│   ├── PLAN_TEMPLATE.md   # For quarterly/release planning
│   └── TASKS_TEMPLATE.md  # For backlog management
├── workspace/              # Cross-cutting or infrastructure work
│   ├── 2025-Q1.md         # Quarterly plans
│   └── backlog.md         # Unscheduled tasks
└── projects/               # Per-project planning (mirrors projects/ folder)
    ├── jido/
    │   ├── 2025-Q1.md
    │   └── backlog.md
    └── [project-name]/     # One folder per project in projects/
```

## File Naming Conventions

- **milestone-N.md** (e.g., `milestone-1.md`, `milestone-2.md`) - Milestone-based planning
- **backlog.md** - Unscheduled tasks and organized work
- **ideas.md** - Brain dump space for raw ideas and inspiration
- **vX.Y.md** (optional) - Version-based planning for libraries

Files are numbered sequentially for easy milestone progression.

## Markdown Front-matter

Each plan file begins with YAML metadata:

```yaml
---
project: jido_ai          # "workspace" for cross-project files
milestone: 1               # for milestone files
type: backlog             # backlog | ideas | milestone
owner: "@username"
status: planned           # planned | in-progress | done | archived | active
review: 2025-03-31        # next checkpoint date
---
```

## Workflow

### Daily Work
1. Create/assign tasks directly in relevant markdown files
2. Use commit messages with `roadmap:TASK-ID` for traceability
3. Update task checkboxes as work progresses
4. Brain dump ideas into `ideas.md` files as they come up

### Milestone Planning
1. Mark completed milestone files as `status: done`
2. Create new `milestone-N.md` (incrementing number)
3. Promote backlog and idea items to milestone plans
4. Review and adjust objectives

### Ideas Capture
- Use `ideas.md` for unstructured brain dumps
- Move refined ideas to `backlog.md` for organization
- Promote ready items to milestone plans

### Adding New Projects
When adding a project to the workspace:
1. `mkdir roadmap/projects/[project-name]`
2. `touch roadmap/projects/[project-name]/backlog.md`
3. Use `TASKS_TEMPLATE.md` to populate initial structure

## Task Reference System

Use consistent task IDs in the format:
- `TRK-N` for tracking/general tasks
- `FEAT-N` for features
- `BUG-N` for bug fixes
- `DOC-N` for documentation

Reference tasks in commits: `git commit -m "implement auth middleware roadmap:FEAT-42"`

## Future Automation

The system supports future Mix tasks for automation:
- `mix roadmap.status` - Show open tasks across all files
- `mix roadmap.todo` - Today's task checklist
- `mix roadmap.lint` - Validate metadata and links
- `mix roadmap.idea "quick idea"` - Fast idea capture to ideas.md
- `mix roadmap.dump` - Interactive brain dump session

## Templates Usage

Copy templates from `roadmap/templates/` to start new planning cycles:
- Use `PLAN_TEMPLATE.md` for structured milestone planning
- Use `TASKS_TEMPLATE.md` for backlog organization and ideas

## Best Practices

1. **Keep it simple** - Plain markdown works everywhere
2. **One source of truth** - Don't duplicate tasks across files
3. **Link liberally** - Reference GitHub issues, PRs, and documentation
4. **Regular reviews** - Schedule quarterly planning sessions
5. **Commit often** - Version control your planning evolution

## Integration with JidoWorkspace

This roadmap system complements existing workspace commands:
- Use `mix morning` to sync code, then review roadmap files
- Plan releases around `mix hex.publish.all` cycles
- Coordinate cross-project work visible in `mix ws.status`
