# JidoWorkspace

Git subtree-powered monorepo workspace manager for the Jido ecosystem.

## Quick Start

```bash
# Daily sync - pull all projects and compile
mix morning

# Run tests across all projects  
mix ws.test

# Run quality checks across all projects
mix ws.quality

# Check dependencies across all projects
mix ws.deps --check
```

## Workspace Management

```bash
mix workspace.pull              # Pull all projects
mix workspace.pull <project>    # Pull specific project
mix workspace.push <project>    # Push to upstream
mix workspace.status            # Show workspace status
mix workspace.add <name> <url>  # Add new project
```

## Development Setup

**External developers** (default): Uses Hex packages automatically.

**Workspace developers**: Dependencies automatically switch to local path dependencies when project directories exist - no configuration needed.

## Hex Publishing

The workspace includes automated Hex publishing for all ecosystem packages.

### Commands

```bash
mix hex.publish.all    # Publish all modified projects to Hex
mix version.check      # Check version consistency across projects  
mix hex_validate      # Validate Hex metadata before publishing
```

### Publishing Workflow

1. **Version Check**: `mix version.check` to ensure consistency
2. **Validation**: `mix hex_validate` to check metadata
3. **Publish**: `mix hex.publish.all` to publish all modified packages
4. **Publishing handled automatically**: Hex dependencies are used automatically when publishing

### Key Notes

- The `jido_dep` helper automatically switches between local paths and Hex packages
- No environment variable configuration needed
- Publishing validates dependencies are pointing to Hex, not local paths

## Projects

- **jido** - Core Jido library
- **jido_action** - Composable action framework with AI integration  
- **jido_signal** - Event-driven messaging and workflow system

See [AGENTS.md](AGENTS.md) for detailed commands and architecture.

