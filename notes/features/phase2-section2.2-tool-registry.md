# Phase 2 Section 2.2: Tool Registry

**Branch**: `feature/phase2-tool-registry`
**Status**: Complete

## Problem Statement

When an LLM returns a tool call by name, Jido.AI needs to:
1. Look up the corresponding module (Action or Tool)
2. Determine its type for correct execution dispatch
3. Have a unified view of all available tools

Currently, `ToolAdapter` has an Action-only registry. We need a unified registry for both Actions and Tools.

## Solution Overview

Create `Jido.AI.Tools.Registry` as a unified, Agent-based registry that:
- Manages both Jido.Actions and Jido.AI.Tools.Tool modules
- Provides type-aware lookup by name
- Validates modules implement correct behaviors
- Converts all registered items to ReqLLM.Tool format

**See**: `notes/decisions/adr-001-tools-registry-design.md` for full design rationale.

## Technical Details

### File Structure

```
lib/jido_ai/tools/
├── tool.ex       # Existing - Tool behavior
└── registry.ex   # NEW - Unified registry
```

### Key Design Decisions

1. **Agent-based runtime registry** - Auto-starts on first access
2. **Type discrimination** - `get/1` returns `{:ok, {type, module}}`
3. **Validation on registration** - Rejects invalid modules
4. **Delegation for conversion** - Uses ToolAdapter and Tool for ReqLLM conversion

## Implementation Plan

### 2.2.1 Registry Design

- [x] 2.2.1.1 Create `lib/jido_ai/tools/registry.ex` with module documentation
- [x] 2.2.1.2 Document that this manages both Actions and Tools
- [x] 2.2.1.3 Implement Agent-based storage with auto-start
- [x] 2.2.1.4 Define internal state structure: `%{name => {type, module}}`

### 2.2.2 Action Registration

- [x] 2.2.2.1 Implement `register_action/1` to add a Jido.Action module
- [x] 2.2.2.2 Implement `register_actions/1` for batch registration
- [x] 2.2.2.3 Validate module implements Jido.Action behavior
- [x] 2.2.2.4 Store as `{:action, module}` tuple

### 2.2.3 Tool Registration

- [x] 2.2.3.1 Implement `register_tool/1` to add a Tool module
- [x] 2.2.3.2 Implement `register_tools/1` for batch registration
- [x] 2.2.3.3 Validate module implements Jido.AI.Tools.Tool behavior
- [x] 2.2.3.4 Store as `{:tool, module}` tuple

### 2.2.4 Auto-Detection Registration

- [x] 2.2.4.1 Implement `register/1` that auto-detects type
- [x] 2.2.4.2 Check for Jido.Action behavior first, then Tool
- [x] 2.2.4.3 Return error if neither behavior is implemented

### 2.2.5 Listing and Lookup

- [x] 2.2.5.1 Implement `list_all/0` to get all registered items
- [x] 2.2.5.2 Implement `list_actions/0` for actions only
- [x] 2.2.5.3 Implement `list_tools/0` for simple tools only
- [x] 2.2.5.4 Implement `get/1` for lookup by name
- [x] 2.2.5.5 Implement `get!/1` that raises on not found

### 2.2.6 ReqLLM Conversion

- [x] 2.2.6.1 Implement `to_reqllm_tools/0` to convert all registered items
- [x] 2.2.6.2 Use `ToolAdapter.from_action/1` for actions
- [x] 2.2.6.3 Use `Tool.to_reqllm_tool/1` for simple tools
- [x] 2.2.6.4 Return combined list of `ReqLLM.Tool` structs

### 2.2.7 Utility Functions

- [x] 2.2.7.1 Implement `clear/0` to reset registry (for testing)
- [x] 2.2.7.2 Implement `unregister/1` to remove by name

### 2.2.8 Unit Tests

- [x] Test register_action/1 adds action with correct type
- [x] Test register_tool/1 adds tool with correct type
- [x] Test register/1 auto-detects action
- [x] Test register/1 auto-detects tool
- [x] Test register/1 rejects invalid modules
- [x] Test list_all/0 returns combined list
- [x] Test list_actions/0 filters to actions only
- [x] Test list_tools/0 filters to tools only
- [x] Test get/1 finds by name with type
- [x] Test get/1 returns error for unknown
- [x] Test get!/1 raises for unknown
- [x] Test to_reqllm_tools/0 converts all
- [x] Test clear/0 resets registry
- [x] Test unregister/1 removes item

## Success Criteria

1. [x] Registry compiles without warnings
2. [x] All unit tests pass (36 tests, 0 failures)
3. [x] Both Actions and Tools can be registered and looked up
4. [x] `to_reqllm_tools/0` returns valid ReqLLM.Tool structs
5. [x] Validation rejects modules without correct behaviors

## Current Status

**What Works**: All functionality implemented and tested
**Completed**: 2026-01-04
**How to Run**: `mix test test/jido_ai/tools/registry_test.exs`
