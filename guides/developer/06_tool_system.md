# Jido.AI Tool System Guide

This guide covers the tool system used for executing functions in Jido.AI agents.

## Table of Contents

1. [Overview](#overview)
2. [Tool Registry](#tool-registry)
3. [Tool Executor](#tool-executor)
4. [Tool Adapter](#tool-adapter)
5. [Creating Tools](#creating-tools)

---

## Overview

The tool system enables LLMs to call functions as tools. It provides:

- **Unified Registry**: Single source of truth for tool lookup
- **Execution**: Consistent execution with error handling
- **Adaptation**: Convert Jido.Actions to ReqLLM format

```
┌─────────────────────────────────────────────────────────────┐
│                     Tool System Flow                        │
│                                                              │
│   Strategy ──► ToolExec Directive ──► Executor ──► Tool    │
│                   (tool_name)        (lookup+run)   (result) │
│                                                              │
│   Result sent as Signal (ai.tool_result) ──► Strategy       │
└─────────────────────────────────────────────────────────────┘
```

---

## Tool Registry

**Module**: `Jido.AI.Tools.Registry`

The registry provides a unified storage for both Jido.Actions and Jido.AI.Tools.Tool modules.

### Registration

```elixir
# Auto-detect type (Action or Tool)
:ok = Registry.register(MyApp.Actions.Calculator)
:ok = Registry.register(MyApp.Tools.Search)

# Explicit registration
:ok = Registry.register_action(MyApp.Actions.Calculator)
:ok = Registry.register_tool(MyApp.Tools.Search)

# Bulk registration
:ok = Registry.register_actions([Add, Subtract, Multiply])
```

### Lookup

```elixir
# Get by name (returns type and module)
{:ok, {:action, MyApp.Actions.Calculator}} = Registry.get("calculator")
{:ok, {:tool, MyApp.Tools.Search}} = Registry.get("search")
{:error, :not_found} = Registry.get("unknown")

# Get with raise on not found
{:action, MyApp.Actions.Calculator} = Registry.get!("calculator")
```

### Listing

```elixir
# List all (with types)
Registry.list_all()
# => [{"calculator", :action, Calculator}, {"search", :tool, Search}]

# List only actions
Registry.list_actions()
# => [{"calculator", Calculator}]

# List only tools
Registry.list_tools()
# => [{"search", Search}]
```

### ReqLLM Conversion

```elixir
# Convert all registered modules to ReqLLM.Tool structs
tools = Registry.to_reqllm_tools()

# Use in LLM call
ReqLLM.stream_text(model, messages, tools: tools)
```

### Telemetry

The registry emits telemetry events:

- `[:jido, :ai, :registry, :register]` - Module registered
- `[:jido, :ai, :registry, :unregister]` - Module unregistered

---

## Tool Executor

**Module**: `Jido.AI.Tools.Executor`

The executor handles the full execution lifecycle: lookup, normalization, execution, and result formatting.

### Basic Execution

```elixir
# Execute by name
{:ok, result} = Executor.execute("calculator", %{"a" => 1, "b" => 2}, %{})

# With timeout
{:ok, result} = Executor.execute("slow_tool", %{}, %{}, timeout: 5000)

# Execute directly with module (no registry lookup)
{:ok, result} = Executor.execute_module(MyAction, :action, %{a: 1}, %{})
```

### Parameter Normalization

The executor normalizes LLM arguments (JSON with string keys) to Elixir format:

```elixir
# LLM sends: {"a": "42", "b": "hello"}
# Normalized to: %{a: 42, b: "hello"}

# Schema defines expected types
schema = [a: [type: :integer], b: [type: :string]]

# Normalization uses schema
normalized = Executor.normalize_params(%{"a" => "42", "b" => "hello"}, schema)
# => %{a: 42, b: "hello"}
```

### Result Formatting

Results are formatted for LLM consumption:

```elixir
# Simple values
"string"  # Returned as-is
42        # Returned as-is

# Maps (JSON-encoded if small enough)
%{answer: 42}  # => %{"answer" => 42}

# Large results (truncated)
# %{truncated: true, size_bytes: 15000, keys: [:key1, :key2], ...}

# Binary (base64-encoded if small)
%{type: :binary, encoding: :base64, data: "...", size_bytes: 1024}

# Lists (JSON-encoded or truncated)
[1, 2, 3, ...]  # => %{truncated: true, count: 1000, sample: [1, 2, 3]}
```

### Error Handling

All errors return structured maps:

```elixir
{:error, %{
  error: "Tool not found: calculator",
  tool_name: "calculator",
  type: :not_found
}}

{:error, %{
  error: "Division by zero",
  tool_name: "calculator",
  type: :execution_error
}}

{:error, %{
  error: "Tool execution timed out after 30000ms",
  tool_name: "slow_tool",
  type: :timeout,
  timeout_ms: 30000
}}
```

### Security

The executor sanitizes sensitive parameters in telemetry:

- Sensitive keys: `api_key`, `password`, `secret`, `token`, `auth_token`, etc.
- Values are replaced with `[REDACTED]` in logs
- Stacktraces logged server-side only (not in responses)

### Telemetry

- `[:jido, :ai, :tool, :execute, :start]` - Execution started
- `[:jido, :ai, :tool, :execute, :stop]` - Execution completed
- `[:jido, :ai, :tool, :execute, :exception]` - Exception during execution

---

## Tool Adapter

**Module**: `Jido.AI.ToolAdapter`

Converts Jido.Actions to ReqLLM.Tool format for LLM consumption.

### Converting Actions to Tools

```elixir
# Single action
tool = ToolAdapter.from_action(MyApp.Actions.Calculator)
# => %ReqLLM.Tool{name: "calculator", description: "...", ...}

# Multiple actions
tools = ToolAdapter.from_actions([
  MyApp.Actions.Calculator,
  MyApp.Actions.Search
])

# With prefix
tools = ToolAdapter.from_actions(actions, prefix: "myapp_")
# Tool names become "myapp_calculator", "myapp_search"

# With filter
tools = ToolAdapter.from_actions(actions,
  filter: fn mod -> mod.category() == :math end
)
```

### Schema Conversion

The adapter converts NimbleOptions schemas to JSON Schema:

```elixir
# Action schema
@schema [
  expression: [type: :string, required: true],
  precision: [type: :integer, default: 2]
]

# Converted to JSON Schema for LLM
%{
  "type" => "object",
  "properties" => %{
    "expression" => %{"type" => "string"},
    "precision" => %{"type" => "integer", "default" => 2}
  },
  "required" => ["expression"]
}
```

---

## Creating Tools

### As Jido.Action

```elixir
defmodule CalculatorAction do
  @moduledoc """
  Calculator action for basic arithmetic operations.
  """

  use Jido.Action

  @impl true
  def describe, do: "Performs basic arithmetic calculations"

  @impl true
  def schema do
    [
      expression: [
        type: :string,
        required: true,
        doc: "Mathematical expression to evaluate (e.g., '2 + 2')"
      ]
    ]
  end

  @impl true
  def run(params, _context) do
    expression = params["expression"]

    # Safe evaluation
    result =
      try do
        {result, _} = Code.eval_string(expression)
        {:ok, %{result: result, expression: expression}}
      rescue
        e -> {:error, "Invalid expression: #{Exception.message(e)}"}
      end

    result
  end
end
```

### Using in Strategies

```elixir
# Register with strategy
use Jido.Agent,
  name: "my_agent",
  strategy: {
    Jido.AI.Strategies.ReAct,
    tools: [CalculatorAction],  # Actions become tools
    max_iterations: 10
  }

# Or register dynamically
Registry.register(CalculatorAction)
```

### As Simple Tool (using Jido.AI.Tools.Tool)

```elixir
defmodule SimpleTool do
  @moduledoc """
  Simple tool without full Action behavior.
  """

  use Jido.AI.Tools.Tool

  @impl true
  def name, do: "simple_tool"

  @impl true
  def description, do: "A simple tool that does X"

  @impl true
  def schema, do: [
    input: [type: :string, required: true]
  ]

  @impl true
  def run(params, _context) do
    input = params["input"]
    {:ok, %{output: "Processed: #{input}"}}
  end

  @impl true
  def to_reqllm_tool do
    ReqLLM.Tool.new!(
      name: name(),
      description: description(),
      parameter_schema: Tool.json_schema_from_schema(schema()),
      callback: fn args -> run(args, %{}) end
    )
  end
end
```

---

## Tool Best Practices

### 1. Use Clear Names

```elixir
# ❌ Bad
def name, do: :do_thing

# ✅ Good
def name, do: :calculate_sum
```

### 2. Provide Descriptions

```elixir
# ❌ Bad
def describe, do: "Does stuff"

# ✅ Good
def describe, do: "Calculates the sum of two integers"
```

### 3. Validate Inputs

```elixir
# Use Zoi for validation
@schema [
  amount: [
    type: :integer,
    required: true,
    min: 0,
    max: 1_000_000
  ]
]
```

### 4. Return Structured Results

```elixir
# ❌ Bad
{:ok, "success"}  # What was the result?

# ✅ Good
{:ok, %{
  result: 42,
  calculation: "2 + 2",
  timestamp: DateTime.utc_now()
}}
```

### 5. Handle Errors Gracefully

```elixir
# ❌ Bad
def run(params, _context) do
  # May raise exception
  {:ok, Code.eval_string(params["expression"])}
end

# ✅ Good
def run(params, _context) do
  expression = params["expression"]

  try do
    {result, _} = Code.eval_string(expression)
    {:ok, %{result: result}}
  rescue
    e -> {:error, "Invalid expression: #{Exception.message(e)}"}
  end
end
```

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [Strategies Guide](./02_strategies.md) - Using tools in strategies
- [Directives Guide](./04_directives.md) - ToolExec directive
