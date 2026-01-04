# Phase 2 Section 2.4: ToolExec Directive Enhancement

**Branch**: `feature/phase2-toolexec-enhancement`
**Status**: Complete

## Problem Statement

The current `ToolExec` directive requires `action_module` to be provided directly, which means:
1. The caller must know and pass the module reference
2. No support for executing `Jido.AI.Tools.Tool` modules (only Actions)
3. Duplicated error handling logic (already exists in Executor)
4. No integration with the new Registry and Executor

We need to enhance ToolExec to:
1. Use Registry-based lookup exclusively
2. Support both Actions and Tools through the unified Executor
3. Use consistent error handling from the Executor

## Solution Overview

Simplify the `ToolExec` directive and its `DirectiveExec` implementation to:
- Remove `action_module` field entirely
- Look up tools in Registry by `tool_name`
- Use `Jido.AI.Tools.Executor.execute/3` for all execution
- Use structured error reporting from Executor

## Technical Details

### File Structure

```
lib/jido_ai/
├── directive.ex       # MODIFIED - ToolExec schema and DirectiveExec impl
└── tools/
    ├── registry.ex    # Existing - Tool lookup
    └── executor.ex    # Existing - Unified execution
```

### Key Design Decisions

1. **Registry-only lookup**: All tools are looked up by name in the Registry
2. **Executor integration**: Use Executor for consistent normalization, error handling
3. **Simplified schema**: Only required fields are `id` and `tool_name`

## Implementation Plan

### 2.4.1 Registry Integration

- [x] 2.4.1.1 Remove `action_module` from ToolExec schema
- [x] 2.4.1.2 Update DirectiveExec to use Registry lookup only
- [x] 2.4.1.3 Support both Actions and Tools via Registry

### 2.4.2 Enhanced Error Reporting

- [x] 2.4.2.1 Use Executor.execute/3 for all execution
- [x] 2.4.2.2 Include structured error in ToolResult signal
- [x] 2.4.2.3 Emit telemetry via Executor (already implemented)

### 2.4.3 Unit Tests

- [x] Test ToolExec with Registry lookup
- [x] Test ToolExec with context and metadata

## Success Criteria

1. [x] ToolExec works with `tool_name` only (Registry lookup)
2. [x] Both Actions and Tools can be executed via ToolExec
3. [x] Error handling is consistent with Executor
4. [x] All existing tests still pass (296 tests, 0 failures)

## Current Status

**What Works**: All functionality implemented and tested
**Completed**: 2026-01-04
**How to Run**: `mix test test/jido_ai/directive_test.exs`
