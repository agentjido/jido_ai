# AGENTS.md - JidoWorkspace Development Guide

## Project Overview

JidoWorkspace is a git subtree-powered monorepo workspace manager for the Jido ecosystem. It allows managing multiple repositories as subtrees within a single workspace.

## Common Commands

### Development
- `mix compile` - Compile the workspace
- `mix test` - Run local workspace tests
- `mix format` - Format Elixir code

### Workspace Management

**Daily Workflow:**
- `mix morning` - Pull all projects and compile (start of day routine)
- `mix sync` - Pull all projects and run tests

**Generic Task Runner:**
- `mix ws <task>` - Run any Mix task across all projects (e.g., `mix ws compile`, `mix ws test`, `mix ws format`)

**Git Operations:**
- `mix ws.git.pull` - Pull updates from all upstream repos
- `mix ws.git.push <project>` - Push changes to specific project upstream
- `mix ws.git.status` - Show git status of all projects
- `mix ws.git.diff` - Show local changes vs upstream

**Dependencies:**
- `mix ws.deps.get` - Safely fetch dependencies (preserves mix.lock integrity)
- `mix ws.deps.upgrade` - Upgrade dependencies across all projects

**Quality & Testing:**
- `mix ws.quality` - Run quality checks across all projects
- `mix workspace.add <name> <url>` - Add new project to workspace

**Publishing:**
- `mix hex.publish.all <version> [--dry-run]` - Publish all packages to Hex
- `mix version.check` - Check version consistency across projects
- `mix hex_validate` - Validate packages for publishing

### Convenient Aliases
- `mix ws.pull` - Same as `ws.git.pull`
- `mix ws.push` - Same as `ws.git.push`
- `mix ws.status` - Same as `ws.git.status`
- `mix ws.test` - Same as `ws test`
- `mix ws.deps` - Same as `ws.deps.get`

## Project Structure

```
jido_workspace/
├── mix.exs                    # Main project file with aliases
├── lib/
│   ├── jido_workspace.ex      # Core management module
│   ├── jido_workspace/        # Core modules
│   │   └── runner.ex          # Task execution engine
│   └── mix/tasks/             # Mix task definitions
│       ├── ws.ex              # Generic task runner
│       ├── ws_*.ex            # Workspace commands
│       └── workspace_add.ex   # Add new projects
├── projects/                  # Git subtrees (15+ projects)
├── config/workspace.exs       # Project configurations
└── test/                      # Workspace tests
```

## Configuration

Projects are configured in `config/workspace.exs`:

```elixir
config :jido_workspace,
  projects: [
    %{
      name: "jido",
      upstream_url: "git@github.com:agentjido/jido.git",
      branch: "main",
      type: :library,
      path: "projects/jido"
    }
  ]
```

**Git URL Guidelines:**
- Always use SSH URLs (`git@github.com:`) for project repositories
- SSH provides secure authentication and avoids credential prompts

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
3. **Pulling updates**: `mix ws.git.pull [project]`
4. **Pushing changes**: `mix ws.git.push <project>`

## Dependency Management

### Workspace vs External Development

The workspace uses a simple environment variable strategy to switch between local and Hex dependencies:

**External developers (default):**
- Dependencies come from Hex packages (e.g., `{:jido_action, "~> 0.3"}`)
- Zero configuration required
- Standard Mix workflow

**Workspace developers:**
- Dependencies automatically switch to local path dependencies when the project directory exists
- No environment variables required - detection is automatic
- Dependencies switch to local paths (e.g., `{:jido_action, path: "../jido_action"}`)

### Implementation

Each project's `mix.exs` includes workspace helpers using `jido_dep/4`:

```elixir
defp jido_dep(app, rel_path, hex_req, extra_opts \\ []) do
  path = Path.expand(rel_path, __DIR__)

  if File.dir?(path) and File.exists?(Path.join(path, "mix.exs")) do
    {app, Keyword.merge([path: rel_path, override: true], extra_opts)}
  else
    {app, hex_req, extra_opts}
  end
  |> case do
    {app, opts} when is_list(opts) -> {app, opts}
    {app, req, opts} -> {app, req, opts}
  end
end
```

Dependencies are declared using `jido_dep/4`:

```elixir
defp deps do
  [
    jido_dep(:jido_action, "../jido_action", "~> 1.3.0"),
    jido_dep(:jido_signal, "../jido_signal", "~> 1.3.0"),
    # ... other deps
  ]
end
```

**Projects with `jido_dep` implementation:**
- `jido_ai` - Uses `jido_dep` for jido ecosystem dependencies
- `jido` - Uses `jido_dep` for jido_action, jido_signal dependencies  
- `jido_chat` - Uses `jido_dep` for jido, jido_ai dependencies
- `jido_dialogue` - Uses `jido_dep` for jido dependency
- `jido_eval` - Uses `jido_dep` for jido_ai dependency
- `jido_htn` - Uses `jido_dep` for jido, jido_action dependencies

### Publishing Safety

The workspace automatically uses Hex dependencies when publishing - no environment variable management needed.

## Code Style

- Follow standard Elixir conventions
- Use `Logger` for output instead of `IO.puts`
- Handle errors gracefully with pattern matching
- Use `System.cmd/3` for git operations
- Stream output for long-running commands
