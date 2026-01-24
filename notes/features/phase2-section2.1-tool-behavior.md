# Phase 2 Section 2.1: Tool Behavior

**Branch**: `feature/phase2-tool-behavior`
**Status**: Complete

## Problem Statement

Jido.Actions are powerful but heavyweight for simple tool implementations. When you only need a basic function exposed to the LLM (no lifecycle hooks, no complex validation, no output schema), a full Jido.Action is overkill.

This section implements a lightweight `Jido.AI.Tools.Tool` behavior that provides:
- Simple callback-based tool definition
- NimbleOptions-style schema for parameter validation
- Direct conversion to ReqLLM.Tool

## Solution Overview

Create a `Tool` behavior that mirrors the essential parts of Jido.Action but without the full machinery:

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
      operation: [type: :string, required: true, doc: "Operation to perform"]
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
```

## Technical Details

### File Structure

```
lib/jido_ai/tools/
└── tool.ex        # Tool behavior + __using__ macro
```

### Key Decisions

1. **NimbleOptions Schema**: Use the same keyword list schema format as Actions for consistency
2. **Noop Callback**: Like ToolAdapter, use noop callback (execution via Jido, not ReqLLM)
3. **Context Parameter**: Include context in run/2 for future extensibility
4. **JSON Schema**: Use `Jido.Action.Schema.to_json_schema/1` for conversion (same as ToolAdapter)

## Implementation Plan

### 2.1.1 Behavior Definition

- [x] 2.1.1.1 Create `lib/jido_ai/tools/tool.ex` with module documentation
- [x] 2.1.1.2 Document relationship to Jido.Action (Actions are preferred for complex tools)
- [x] 2.1.1.3 Define `@callback name() :: String.t()` for tool name
- [x] 2.1.1.4 Define `@callback description() :: String.t()` for tool description
- [x] 2.1.1.5 Define `@callback schema() :: keyword()` for NimbleOptions parameter schema
- [x] 2.1.1.6 Define `@callback run(params :: map(), context :: map()) :: {:ok, term()} | {:error, term()}`

### 2.1.2 Using Macro

- [x] 2.1.2.1 Implement `__using__/1` macro with opts (name, description)
- [x] 2.1.2.2 Inject `@behaviour Jido.AI.Tools.Tool`
- [x] 2.1.2.3 Provide default implementations for name/0 and description/0 from opts
- [x] 2.1.2.4 Generate `to_reqllm_tool/0` that creates `ReqLLM.Tool` struct directly

### 2.1.3 Conversion to ReqLLM

- [x] 2.1.3.1 Implement `to_reqllm_tool/1` that takes a tool module
- [x] 2.1.3.2 Convert NimbleOptions schema to JSON Schema for ReqLLM
- [x] 2.1.3.3 Use noop callback (execution via Jido, not ReqLLM callbacks)
- [x] 2.1.3.4 Match the pattern used by ToolAdapter for consistency

### 2.1.4 Unit Tests

- [x] Test behavior callbacks are defined
- [x] Test `__using__` macro injects behavior and defaults
- [x] Test to_reqllm_tool/1 creates valid ReqLLM.Tool
- [x] Test schema validation works
- [x] Test run/2 execution

## Success Criteria

1. ✅ Tool behavior compiles without warnings
2. ✅ Simple tools can be defined with minimal boilerplate
3. ✅ Tools convert correctly to ReqLLM.Tool format
4. ✅ All tests pass (25 new tests, 229 total)

## Current Status

**What Works**: Full Tool behavior implementation complete
**What's Next**: Phase 2 Section 2.2 (Tool Registry)
**How to Run**: `mix test test/jido_ai/tools/tool_test.exs`
