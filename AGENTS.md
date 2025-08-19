# AGENTS.md - JidoWorkspace Development Guide

## Project Overview

JidoWorkspace is a git subtree-powered monorepo workspace manager for the Jido ecosystem. It allows managing multiple repositories as subtrees within a single workspace.

## Common Commands

### Development
- `mix compile` - Compile the workspace
- `mix test` - Run local workspace tests
- `mix format` - Format Elixir code

### Workspace Management
- `mix morning` - Pull all projects and compile (start of day routine)
- `mix sync` - Pull all projects and run tests
- `mix workspace.pull` - Pull updates from all upstream repos
- `mix workspace.pull <project>` - Pull updates for specific project
- `mix workspace.push <project>` - Push changes to specific project upstream
- `mix workspace.status` - Show status of all projects
- `mix workspace.test.all` - Run tests across all projects
- `mix workspace.add <name> <url>` - Add new project to workspace

### Short Aliases
- `mix ws.pull` - Same as `workspace.pull`
- `mix ws.push` - Same as `workspace.push`
- `mix ws.status` - Same as `workspace.status`
- `mix ws.test` - Same as `workspace.test.all`

## Project Structure

```
jido_workspace/
├── mix.exs                    # Main project file with aliases
├── lib/
│   ├── jido_workspace.ex      # Core management module
│   └── mix/tasks/workspace.ex # Custom Mix tasks
├── projects/                  # Git subtrees go here
│   └── jido/                  # First subtree project
├── config/workspace.exs       # Project configurations
├── scripts/                   # Helper scripts
└── test/                      # Workspace tests
```

## Configuration

Projects are configured in `config/workspace.exs`:

```elixir
config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "https://github.com/agentjido/jido",
      branch: "main",
      type: :library,
      path: "projects/jido"
    }
  ]
```

## Core API

The `JidoWorkspace` module provides:
- `sync_all()` - Pull all projects
- `pull_project(name)` - Pull specific project
- `push_project(name)` - Push to upstream
- `test_all()` - Run tests across projects
- `status()` - Show workspace status

## Git Subtree Workflow

1. **Adding new project**: `mix workspace.add <name> <url>`
2. **Daily sync**: `mix morning` or `mix sync`
3. **Pulling updates**: `mix workspace.pull [project]`
4. **Pushing changes**: `mix workspace.push <project>`

## Code Style

- Follow standard Elixir conventions
- Use `Logger` for output instead of `IO.puts`
- Handle errors gracefully with pattern matching
- Use `System.cmd/3` for git operations
- Stream output for long-running commands
