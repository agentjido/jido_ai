# Setup Git Subtree Monorepo for JidoWorkspace

Transform fresh Mix project `JidoWorkspace` into git subtree-powered monorepo workspace.

## Structure
```
jido_workspace/
├── mix.exs                    # Umbrella with custom aliases
├── lib/jido_workspace.ex      # Core management module  
├── lib/mix/tasks/workspace.ex # Custom Mix tasks
├── projects/                  # Git subtrees go here
├── config/workspace.exs       # Project configs
└── scripts/                   # Helper scripts
```

## Requirements

1. **Mix Tasks**: `workspace.add`, `workspace.pull`, `workspace.push`, `workspace.status`, `workspace.test.all`

2. **Config-driven**: Store project metadata (name, upstream_url, branch, type) in `config/workspace.exs`

3. **Core Module**: `JidoWorkspace` module with functions:
   - `sync_all()` - pull all projects 
   - `pull_project(name)` - pull specific project
   - `push_project(name)` - push to upstream
   - `test_all()` - run tests across projects
   - `status()` - show workspace status

4. **Aliases**: Add convenient `mix.exs` aliases like `morning` (pull + compile), `sync` (pull + test)

5. **Git Subtree Commands**: Wrap `git subtree add/pull/push` with proper error handling

## Implementation Notes
- Use `System.cmd/3` for git operations
- Handle both :library and :application project types  
- Stream output for long-running commands
- Validate project configs on startup
- Support both SSH and HTTPS git URLs

Generate complete, working implementation.