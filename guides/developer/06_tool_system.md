# Tool System Guide

This guide describes how Jido.AI handles tool calling with `Jido.Action` modules.

## Overview

Jido.AI does **not** use a global tools registry module.
Tools are provided as action modules and passed through runtime context (usually `context[:tools]`).

## Core Components

| Module | Purpose |
|--------|---------|
| `Jido.AI.Actions.ToolCalling.CallWithTools` | LLM call with tool definitions and optional auto-execution |
| `Jido.AI.Actions.ToolCalling.ExecuteTool` | Directly execute one tool by name |
| `Jido.AI.Actions.ToolCalling.ListTools` | Discover available tools from context |
| `Jido.AI.Executor` | Name lookup, argument normalization, execution, timeout, telemetry |
| `Jido.AI.ToolAdapter` | Convert action modules into ReqLLM tool definitions |

## Tool Map Pattern

Tools are represented as `%{"tool_name" => MyActionModule}` maps.

```elixir
tools = Jido.AI.Executor.build_tools_map([
  MyApp.Actions.Calculator,
  MyApp.Actions.Search
])
# => %{"calculator" => MyApp.Actions.Calculator, "search" => MyApp.Actions.Search}
```

You can pass this map into tool-calling actions via context:

```elixir
context = %{tools: tools}

{:ok, result} =
  Jido.Exec.run(Jido.AI.Actions.ToolCalling.ExecuteTool, %{
    tool_name: "calculator",
    params: %{a: 5, b: 3, operation: "add"}
  }, context)
```

## Execution Flow

`Jido.AI.Executor.execute/4` performs:

1. Tool name lookup in the provided `tools:` map
2. Parameter normalization from JSON-style string keys
3. Action execution (`Jido.Exec.run/3`)
4. Result formatting
5. Structured error handling

Example:

```elixir
tools = Jido.AI.Executor.build_tools_map([MyApp.Actions.Calculator])

{:ok, result} =
  Jido.AI.Executor.execute(
    "calculator",
    %{"a" => "5", "b" => "3", "operation" => "add"},
    %{},
    tools: tools,
    timeout: 5_000
  )
```

## ReqLLM Tool Conversion

Convert action modules into ReqLLM tool definitions:

```elixir
tools = Jido.AI.ToolAdapter.from_actions([
  MyApp.Actions.Calculator,
  MyApp.Actions.Search
])

{:ok, response} =
  Jido.AI.LLMClient.generate_text(%{}, "anthropic:claude-sonnet-4-20250514", messages,
    tools: tools
  )
```

## ToolCalling Plugin

`Jido.AI.Plugins.ToolCalling` accepts tools through plugin config:

```elixir
plugins: [
  {Jido.AI.Plugins.ToolCalling,
   tools: [MyApp.Actions.Calculator, MyApp.Actions.Search],
   auto_execute: true,
   max_turns: 10}
]
```

The plugin stores tools in its state and supplies them to actions via context.

## Creating Tools

Tools are normal `Jido.Action` modules:

```elixir
defmodule MyApp.Actions.Calculator do
  use Jido.Action,
    name: "calculator",
    description: "Performs arithmetic",
    schema:
      Zoi.object(%{
        a: Zoi.number(),
        b: Zoi.number(),
        operation: Zoi.string() |> Zoi.default("add")
      })

  @impl true
  def run(%{a: a, b: b, operation: "add"}, _context), do: {:ok, %{result: a + b}}
  def run(%{a: a, b: b, operation: "subtract"}, _context), do: {:ok, %{result: a - b}}
  def run(%{a: a, b: b, operation: "multiply"}, _context), do: {:ok, %{result: a * b}}
  def run(%{a: _a, b: 0, operation: "divide"}, _context), do: {:error, "division by zero"}
  def run(%{a: a, b: b, operation: "divide"}, _context), do: {:ok, %{result: a / b}}
  def run(_params, _context), do: {:error, "unsupported operation"}
end
```

## Best Practices

1. Pass tools explicitly through context instead of relying on global mutable state.
2. Keep schemas strict so argument normalization is predictable.
3. Return structured results (`%{...}`) and explicit `{:error, reason}` tuples.
4. Use `ListTools` with `allowed_tools` and `include_sensitive` in user-facing flows.
5. Set execution timeouts on `Executor.execute/4` for external/network-bound tools.
