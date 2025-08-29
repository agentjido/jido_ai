# Worktree Management Scripts

This directory contains scripts for managing Git worktrees in the Jido ecosystem.

## Scripts

### `create_worktree.sh`

Creates a new Git worktree for isolated development work.

**Usage:**
```bash
./bin/create_worktree.sh [worktree_name] [base_branch]
```

**Parameters:**
- `worktree_name` (optional): Name for the worktree. If not provided, generates a unique human-readable name like `swift_fix_1430`
- `base_branch` (optional): Branch to create the worktree from. Defaults to current branch

**Features:**
- Creates worktrees in `~/worktrees/jido_workspace/`
- Automatically sets up dependencies with `mix deps.get`
- Copies `.claude` directory for AI tool configuration
- Initializes humanlayer thoughts system
- Cleans up automatically if setup fails

**Examples:**
```bash
# Create with auto-generated name from current branch
./bin/create_worktree.sh

# Create with specific name from current branch
./bin/create_worktree.sh my_feature

# Create with specific name from specific branch
./bin/create_worktree.sh bug_fix main
```

### `cleanup_worktree.sh`

Removes Git worktrees and associated resources.

**Usage:**
```bash
./bin/cleanup_worktree.sh [worktree_name]
```

**Parameters:**
- `worktree_name` (optional): Name of the worktree to clean up. If not provided, lists available worktrees

**Features:**
- Lists available worktrees when no name provided
- Handles humanlayer thoughts cleanup
- Removes Git worktree and optionally deletes branch
- Prunes worktree references

**Examples:**
```bash
# List available worktrees
./bin/cleanup_worktree.sh

# Clean up specific worktree
./bin/cleanup_worktree.sh swift_fix_1430
```

## Environment Variables

- `JIDO_WORKTREE_OVERRIDE_BASE`: Override the base worktree directory (defaults to `~/worktrees`)

## Directory Structure

Worktrees are created in:
```
~/worktrees/
└── jido_workspace/
    ├── worktree_name_1/
    ├── worktree_name_2/
    └── ...
```

## Workflow

1. **Create a worktree** for feature development:
   ```bash
   ./bin/create_worktree.sh feature_auth
   cd ~/worktrees/jido_workspace/feature_auth
   ```

2. **Work in the worktree** as normal:
   ```bash
   mix compile
   mix test
   git add . && git commit -m "Add feature"
   ```

3. **Clean up when done**:
   ```bash
   ./bin/cleanup_worktree.sh feature_auth
   ```

## Notes

- Scripts are designed to work with the Jido workspace structure
- The humanlayer CLI tool is used for thoughts management (if available)
- Worktrees share the same Git history but have independent working directories
- Ideal for working on multiple features simultaneously without branch switching
