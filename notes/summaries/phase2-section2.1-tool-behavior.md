# Phase 2 Section 2.1: Tool Behavior Summary

**Date**: 2026-01-04
**Branch**: `feature/phase2-tool-behavior`
**Status**: Complete - Ready for merge

## Overview

Implemented a lightweight `Jido.AI.Tools.Tool` behavior as an alternative to full Jido.Actions for simple LLM tool implementations.

## What Was Built

### New Module: `Jido.AI.Tools.Tool`

A behavior module that provides:

1. **Behavior Callbacks**:
   - `name/0` - Returns tool name for LLM
   - `description/0` - Returns tool description
   - `schema/0` - Returns NimbleOptions-style parameter schema
   - `run/2` - Executes tool with params and context

2. **`__using__` Macro**:
   - Injects `@behaviour Jido.AI.Tools.Tool`
   - Provides default implementations from opts
   - Generates `to_reqllm_tool/0` function

3. **ReqLLM Conversion**:
   - `to_reqllm_tool/1` converts tool module to ReqLLM.Tool
   - Uses `Jido.Action.Schema.to_json_schema/1` for schema conversion
   - Uses noop callback (execution via Jido, not ReqLLM)

## Usage Example

```elixir
defmodule MyApp.Tools.Calculator do
  use Jido.AI.Tools.Tool,
    name: "calculator",
    description: "Performs basic arithmetic"

  @impl true
  def schema do
    [
      a: [type: :number, required: true, doc: "First operand"],
      b: [type: :number, required: true, doc: "Second operand"],
      operation: [type: :string, required: true, doc: "Operation"]
    ]
  end

  @impl true
  def run(params, _context) do
    result = case params.operation do
      "add" -> params.a + params.b
      "subtract" -> params.a - params.b
      _ -> {:error, "Unknown operation"}
    end
    {:ok, %{result: result}}
  end
end

# Convert to ReqLLM.Tool
tool = MyApp.Tools.Calculator.to_reqllm_tool()
ReqLLM.stream_text(model, messages, tools: [tool])
```

## Files Created

| File | Description |
|------|-------------|
| `lib/jido_ai/tools/tool.ex` | Tool behavior module |
| `test/jido_ai/tools/tool_test.exs` | 25 unit tests |

## Design Decisions

1. **NimbleOptions Schema**: Uses keyword list format matching Jido.Action for consistency
2. **Noop Callback**: Like ToolAdapter, tools are executed via Jido's executor, not ReqLLM callbacks
3. **Context Parameter**: Included for future extensibility (execution metadata, etc.)
4. **Required Options**: Both `name` and `description` are required in `use` statement

## Test Results

```
25 tests, 0 failures
229 total tests in suite
```

Test coverage includes:
- Behavior callback definitions
- `__using__` macro functionality
- ReqLLM.Tool conversion
- Schema to JSON Schema conversion
- run/2 execution

## Relationship to Jido.Action

| Feature | Tool | Action |
|---------|------|--------|
| Lifecycle hooks | No | Yes |
| Output schema | No | Yes |
| Action composition | No | Yes |
| Workflow integration | Limited | Full |
| Boilerplate | Minimal | More |

**Recommendation**: Use `Tool` for simple LLM functions, `Action` for complex workflow operations.
