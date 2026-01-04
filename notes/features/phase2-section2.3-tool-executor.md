# Phase 2 Section 2.3: Tool Executor

**Branch**: `feature/phase2-tool-executor`
**Status**: Complete

## Problem Statement

When an LLM returns a tool call, Jido.AI needs to:
1. Look up the tool in the Registry (Action or Tool)
2. Normalize parameters from LLM format (string keys, string numbers)
3. Execute using the appropriate mechanism (Jido.Exec for Actions, run/2 for Tools)
4. Format results for LLM consumption
5. Handle errors and timeouts gracefully

Currently, `ToolExec` directive execution requires `action_module` to be provided directly. We need a unified executor that works with the new Registry.

## Solution Overview

Create `Jido.AI.Tools.Executor` as a unified execution layer that:
- Looks up tools in Registry by name
- Normalizes parameters based on schema type
- Dispatches to appropriate executor (Jido.Exec or direct run/2)
- Formats results for LLM consumption
- Provides comprehensive error handling and timeout support

## Technical Details

### File Structure

```
lib/jido_ai/tools/
├── tool.ex        # Existing - Tool behavior
├── registry.ex    # Existing - Tool registry
└── executor.ex    # NEW - Unified executor
```

### Key Design Decisions

1. **Registry-based lookup**: Look up tools by name from Registry
2. **Type-aware dispatch**: Use Jido.Exec for Actions, direct run/2 for Tools
3. **Schema-based normalization**: Convert string keys and parse numbers based on schema
4. **Result formatting**: Convert results to JSON-safe format for LLM
5. **Task-based timeout**: Use Task.await for timeout handling

### Dependencies

- `Jido.AI.Tools.Registry` - For tool lookup
- `Jido.Action.Tool.convert_params_using_schema/2` - For parameter normalization (existing in jido)
- `Jido.Exec` - For Action execution

## Implementation Plan

### 2.3.1 Unified Execution

- [x] 2.3.1.1 Create `lib/jido_ai/tools/executor.ex` with module documentation
- [x] 2.3.1.2 Implement `execute/3` with name, params, context
- [x] 2.3.1.3 Look up tool/action in Registry
- [x] 2.3.1.4 Dispatch to appropriate executor (Jido.Exec for Actions, run/2 for Tools)

### 2.3.2 Parameter Normalization

- [x] 2.3.2.1 Implement `normalize_params/2` with schema
- [x] 2.3.2.2 Convert string keys to atom keys
- [x] 2.3.2.3 Parse string numbers based on schema type
- [x] 2.3.2.4 Use existing `Jido.Action.Tool.convert_params_using_schema/2`

### 2.3.3 Result Formatting

- [x] 2.3.3.1 Implement `format_result/1` for tool results
- [x] 2.3.3.2 Convert maps/structs to JSON strings
- [x] 2.3.3.3 Handle binary data (base64 encode or describe)
- [x] 2.3.3.4 Truncate large results with size indicator

### 2.3.4 Error Handling

- [x] 2.3.4.1 Catch exceptions during execution
- [x] 2.3.4.2 Return structured error with tool name, reason, stacktrace
- [x] 2.3.4.3 Convert errors to LLM-friendly messages
- [x] 2.3.4.4 Emit telemetry for execution metrics

### 2.3.5 Timeout Handling

- [x] 2.3.5.1 Implement `execute/4` with timeout option
- [x] 2.3.5.2 Use Task.await with timeout
- [x] 2.3.5.3 Return timeout error with context
- [x] 2.3.5.4 Support per-tool timeout configuration via opts

### 2.3.6 Unit Tests

- [x] Test execute/3 runs action via Jido.Exec
- [x] Test execute/3 runs tool via run/2
- [x] Test normalize_params/2 handles string keys
- [x] Test normalize_params/2 parses string numbers
- [x] Test format_result/1 produces JSON
- [x] Test format_result/1 truncates large results
- [x] Test error handling
- [x] Test timeout handling
- [x] Test registry lookup failure

## Success Criteria

1. [x] Executor compiles without warnings
2. [x] All unit tests pass (29 tests, 0 failures)
3. [x] Both Actions and Tools can be executed by name
4. [x] Parameter normalization works correctly
5. [x] Results are formatted for LLM consumption
6. [x] Errors and timeouts are handled gracefully

## Current Status

**What Works**: All functionality implemented and tested
**Completed**: 2026-01-04
**How to Run**: `mix test test/jido_ai/tools/executor_test.exs`
