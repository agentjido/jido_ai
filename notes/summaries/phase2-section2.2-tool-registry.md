# Summary: Phase 2 Section 2.2 - Tool Registry

**Date**: 2026-01-04
**Branch**: `feature/phase2-tool-registry`
**Status**: Complete

## What Was Built

Created `Jido.AI.Tools.Registry` - a unified Agent-based registry for managing both Jido.Actions and Jido.AI.Tools.Tool modules.

### Files Created

1. **`lib/jido_ai/tools/registry.ex`** - The registry implementation
2. **`test/jido_ai/tools/registry_test.exs`** - 36 comprehensive unit tests
3. **`notes/decisions/adr-001-tools-registry-design.md`** - Architecture Decision Record
4. **`notes/features/phase2-section2.2-tool-registry.md`** - Feature planning document

## Key Features

### Registration
- `register/1` - Auto-detects Action vs Tool by checking behaviors
- `register_action/1`, `register_actions/1` - Explicit Action registration
- `register_tool/1`, `register_tools/1` - Explicit Tool registration
- Validates modules implement correct behaviors before registration

### Lookup
- `get/1` - Returns `{:ok, {:action | :tool, module}}` or `{:error, :not_found}`
- `get!/1` - Raises `KeyError` if not found
- `list_all/0` - All registered items as `{name, type, module}` tuples
- `list_actions/0`, `list_tools/0` - Filtered by type

### ReqLLM Integration
- `to_reqllm_tools/0` - Converts all registered items to `ReqLLM.Tool` structs
- Uses `ToolAdapter.from_action/1` for Actions
- Uses `Tool.to_reqllm_tool/1` for Tools

### Utilities
- `clear/0` - Resets registry (for testing)
- `unregister/1` - Removes by name

## Technical Notes

### Behavior Detection

The registry distinguishes Actions from Tools by checking module behaviors:

```elixir
defp action?(module) do
  behaviours = module_behaviours(module)
  Jido.Action in behaviours or
    (has_action_functions?(module) and Jido.AI.Tools.Tool not in behaviours)
end

defp tool?(module) do
  behaviours = module_behaviours(module)
  Jido.AI.Tools.Tool in behaviours
end
```

This approach:
1. Checks for `Jido.Action` in declared behaviors first
2. Falls back to function check for Actions without explicit behavior declaration
3. Excludes modules that have `Jido.AI.Tools.Tool` behavior from Action detection

### Agent-Based Storage

Uses Elixir Agent with auto-start pattern:
- `ensure_started/0` starts the Agent if not running
- Handles `{:error, {:already_started, _pid}}` race condition
- State stored as `%{name => {:action | :tool, module}}`

## Test Coverage

36 tests covering:
- Registration (action, tool, auto-detection, batch)
- Validation (rejects invalid modules, type mismatches)
- Lookup (get, get!, list variants)
- ReqLLM conversion
- Utilities (clear, unregister)
- Concurrent access

## Next Steps

This registry will be used by the Tool Executor (Phase 2 Section 2.3) to:
1. Look up modules by tool name from LLM responses
2. Determine execution strategy based on type
3. Dispatch to Jido.Exec for Actions or direct `run/2` for Tools
