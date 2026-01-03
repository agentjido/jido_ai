# Feature: Phase 1 Section 1.4 - Tool Adapter Enhancement

## Problem Statement

The current tool adapter has basic functionality but lacks:
1. Options support for batch conversion (filtering, prefixing)
2. An action registry for runtime tool management
3. The JSON schema conversion is delegated to `Jido.Action.Schema.to_json_schema/1` which already handles Zoi and NimbleOptions schemas well

**Impact**: Developers cannot filter actions by category, prefix tool names, or manage tools at runtime without maintaining their own lists.

## Solution Overview

1. **Enhanced `from_actions/2`** - Add options for filtering and prefixing
2. **Action Registry** - Runtime registry using an Agent for tool management
3. **Helper functions** - `lookup_action/1` to find action module by tool name

Note: Schema improvements (1.4.2) are already well-handled by `Jido.Action.Schema.to_json_schema/1` which delegates to `Zoi.to_json_schema/1`. We'll mark those as complete.

## Technical Details

### Files to Modify
- `lib/jido_ai/tool_adapter.ex` - Enhanced from_actions/2, add registry

### New Options for from_actions/2

```elixir
from_actions(action_modules, opts \\ [])

Options:
  - :prefix - String prefix to add to tool names (e.g., "myapp_")
  - :filter - Function to filter actions (fn module -> boolean)
  - :include_tags - List of tags to include (action must have at least one)
  - :exclude_tags - List of tags to exclude
```

### Action Registry Design

```elixir
# Registry functions
Jido.AI.ToolAdapter.register_action(action_module)
Jido.AI.ToolAdapter.register_actions([action_modules])
Jido.AI.ToolAdapter.unregister_action(action_module)
Jido.AI.ToolAdapter.list_actions()
Jido.AI.ToolAdapter.get_action(tool_name)
Jido.AI.ToolAdapter.to_tools(opts \\ [])
Jido.AI.ToolAdapter.clear_registry()
```

Using an Agent for simple runtime storage. The registry is optional - actions can still be converted directly without registering.

## Success Criteria

1. `from_actions/2` accepts options for prefix and filter
2. Registry functions work for runtime tool management
3. `get_action/1` looks up action module by tool name
4. `to_tools/0` converts all registered actions
5. All unit tests pass

## Implementation Plan

### Step 1: Enhanced from_actions/2 (1.4.1)
- [x] 1.4.1.1 Add `from_actions/2` with options parameter
- [x] 1.4.1.2 Support filtering actions with :filter option
- [x] 1.4.1.3 Support action name prefixing with :prefix option

### Step 2: Schema Improvements (1.4.2) - Already Complete
- [x] 1.4.2.1 Handle nested Zoi schemas correctly (via Zoi.to_json_schema)
- [x] 1.4.2.2 Add support for enum constraints (via Zoi.to_json_schema)
- [x] 1.4.2.3 Add support for string format constraints (via Zoi.to_json_schema)
- [x] 1.4.2.4 Generate better descriptions from schema metadata (via Zoi.to_json_schema)

### Step 3: Action Registry (1.4.3)
- [x] 1.4.3.1 Implement registry Agent and `register_action/1`
- [x] 1.4.3.2 Implement `list_actions/0`
- [x] 1.4.3.3 Implement `get_action/1` lookup by name
- [x] 1.4.3.4 Implement `to_tools/0` to convert all registered

### Step 4: Additional Helpers
- [x] Implement `register_actions/1` for batch registration
- [x] Implement `unregister_action/1`
- [x] Implement `clear_registry/0`
- [x] Implement `lookup_action/1` to find module by tool name (searches registered)

### Step 5: Unit Tests (1.4.4)
- [x] Test from_actions/2 with :prefix option
- [x] Test from_actions/2 with :filter option
- [x] Test registry operations (register, list, get, unregister)
- [x] Test to_tools/0 conversion
- [x] Test lookup_action/2

## Current Status

**Status**: Complete
**What works**: All features implemented and tested (29 tests passing)
**How to run**: `mix test test/jido_ai/tool_adapter_test.exs`

## Notes/Considerations

- Schema improvements are already handled by Jido.Action.Schema which uses Zoi.to_json_schema
- Registry is optional - from_actions/2 works without it
- Registry uses Agent for simplicity (could be upgraded to ETS later if needed)
- The registry is application-wide (single Agent process)
