# Summary: Phase 2 Section 2.3 - Tool Executor

**Date**: 2026-01-04
**Branch**: `feature/phase2-tool-executor`
**Status**: Complete

## What Was Built

Created `Jido.AI.Tools.Executor` - a unified execution layer for running both Jido.Actions and Jido.AI.Tools.Tool modules by name.

### Files Created

1. **`lib/jido_ai/tools/executor.ex`** - The executor implementation
2. **`test/jido_ai/tools/executor_test.exs`** - 29 comprehensive unit tests
3. **`notes/features/phase2-section2.3-tool-executor.md`** - Feature planning document

## Key Features

### Unified Execution
- `execute/3` - Execute tool by name with params and context
- `execute/4` - Execute with timeout option
- `execute_module/5` - Execute module directly without registry lookup
- Registry-based lookup determines if it's an Action or Tool
- Dispatches to `Jido.Exec.run/3` for Actions, `module.run/2` for Tools

### Parameter Normalization
- Uses `Jido.Action.Tool.convert_params_using_schema/2` from jido_action
- Converts string keys to atom keys (LLM returns JSON with string keys)
- Parses string numbers to integers/floats based on schema type

### Result Formatting
- `format_result/1` formats results for LLM consumption
- Maps/structs are kept as-is (JSON-safe)
- Large results (>10KB) are truncated with size indicators
- Binary data is base64-encoded for small binaries, described for large ones

### Error Handling
- Structured error maps with `:error`, `:tool_name`, `:type`, and `:details`
- Exception catching with stacktrace formatting
- Error types: `:not_found`, `:execution_error`, `:exception`, `:timeout`, `:caught`

### Timeout Support
- Default timeout of 30 seconds
- Task-based execution with `Task.yield/2` and `Task.shutdown/1`
- Timeout errors include duration information

### Telemetry
- `[:jido, :ai, :tool, :execute, :start]` - Execution started
- `[:jido, :ai, :tool, :execute, :stop]` - Execution completed
- `[:jido, :ai, :tool, :execute, :exception]` - Execution failed

## API Examples

```elixir
# Execute by name (looks up in Registry)
{:ok, result} = Executor.execute("calculator", %{"a" => "1", "b" => "2"}, %{})

# With timeout
{:ok, result} = Executor.execute("slow_tool", %{"delay" => "100"}, %{}, timeout: 5000)

# Execute module directly
{:ok, result} = Executor.execute_module(MyAction, :action, %{"x" => "1"}, %{})

# Parameter normalization
params = Executor.normalize_params(%{"count" => "42"}, [count: [type: :integer]])
# => %{count: 42}

# Result formatting
formatted = Executor.format_result(%{large: String.duplicate("x", 15000)})
# => %{truncated: true, size_bytes: ..., ...}
```

## Test Coverage

29 tests covering:
- Action execution via Jido.Exec
- Tool execution via run/2
- Parameter normalization (string keys, string numbers)
- Result formatting (truncation, binary handling)
- Error handling (structured errors, missing params)
- Timeout handling
- Registry lookup failures
- Telemetry events

## Technical Notes

### LLM Integration Pattern

When an LLM returns a tool call:
```json
{"name": "calculator", "arguments": {"operation": "add", "a": "1", "b": "2"}}
```

The Executor handles the full lifecycle:
1. Registry lookup: `Registry.get("calculator")` → `{:ok, {:action, MyCalculator}}`
2. Normalization: `%{"operation" => "add", "a" => "1", "b" => "2"}` → `%{operation: "add", a: 1, b: 2}`
3. Execution: `Jido.Exec.run(MyCalculator, normalized_params, context)`
4. Formatting: Result formatted for LLM consumption
5. Telemetry: Events emitted for monitoring

### Error Response Format

All errors return structured maps:
```elixir
{:error, %{
  error: "Human-readable message for LLM",
  tool_name: "calculator",
  type: :execution_error | :not_found | :timeout | :exception | :caught,
  details: %{...}  # Optional additional context
}}
```

## Next Steps

This executor can be integrated with:
- `ToolExec` directive (Phase 2 Section 2.4) - Use Executor instead of direct Jido.Exec calls
- Phase 2 Integration Tests (Section 2.5) - Test full tool calling flow
