# Jido.AI Directives Guide

This guide covers the directive system used in Jido.AI for describing external effects.

## Table of Contents

1. [Overview](#overview)
2. [Directive Types](#directive-types)
3. [Using Directives](#using-directives)
4. [Directive Lifecycle](#directive-lifecycle)
5. [Creating Custom Directives](#creating-custom-directives)

---

## Overview

Directives describe **external effects** that should be performed. They are returned by state machines and executed by the AgentServer runtime.

### Key Principles

1. **Declarative**: Directives describe *what* to do, not *how* to do it
2. **Immutable**: Directives cannot be modified once created
3. **Type-Safe**: All directives use Zoi schemas for validation
4. **Observable**: Directive execution emits telemetry

### Pattern

```elixir
# State machine returns directives
{machine, directives} = Machine.update(machine, message, env)

# Strategy lifts to SDK directives
sdk_directives = lift_directives(directives, config)

# AgentServer executes directives
# Results sent back as signals
```

---

## Directive Types

### ReqLLMStream

**Module**: `Jido.AI.Directive.ReqLLMStream`

Stream an LLM response with optional tool support.

```elixir
Directive.ReqLLMStream.new!(%{
  id: "call_abc123",
  model: "anthropic:claude-sonnet-4-20250514",
  context: [
    %{role: :system, content: "You are a helpful assistant..."},
    %{role: :user, content: "Hello!"}
  ],
  tools: [
    %{name: "calculator", description: "...", input_schema: %{...}}
  ]
})
```

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `:id` | `String.t()` | ✅ | Unique call identifier |
| `:model` | `String.t()` | ✅ | LLM model identifier |
| `:context` | `[ReqLLM.Message.t()]` | ✅ | Conversation context |
| `:tools` | `[ReqLLM.Tool.t()]` | ❌ | Available tools |
| `:max_tokens` | `pos_integer()` | ❌ | Max tokens to generate |
| `:temperature` | `float()` | ❌ | Sampling temperature |
| `:metadata` | `map()` | ❌ | Additional metadata |

**Result Signal**: `ReqLLMResult` or `ReqLLMPartial`

---

### ToolExec

**Module**: `Jido.AI.Directive.ToolExec`

Execute a Jido.Action as a tool.

```elixir
Directive.ToolExec.new!(%{
  id: "tool_abc123",
  tool_name: "calculator",
  action_module: CalculatorAction,
  arguments: %{expression: "2 + 2"}
})
```

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `:id` | `String.t()` | ✅ | Unique call identifier |
| `:tool_name` | `String.t()` | ✅ | Tool name |
| `:action_module` | `module()` | ✅ | Jido.Action module |
| `:arguments` | `map()` | ✅ | Tool parameters |
| `:timeout` | `pos_integer()` | ❌ | Execution timeout |

**Result Signal**: `ToolResult`

---

### ReqLLMGenerate

**Module**: `Jido.AI.Directive.ReqLLMGenerate`

Generate a non-streaming LLM response.

```elixir
Directive.ReqLLMGenerate.new!(%{
  id: "call_abc123",
  model: "anthropic:claude-haiku-4-5",
  context: [
    %{role: :user, content: "What is 2 + 2?"}
  ]
})
```

**Fields**: Same as ReqLLMStream, but response is not streamed.

---

### ReqLLMEmbed

**Module**: `Jido.AI.Directive.ReqLLMEmbed`

Generate embeddings for text.

```elixir
Directive.ReqLLMEmbed.new!(%{
  id: "embed_abc123",
  model: "openai:text-embedding-3-small",
  texts: ["Hello world", "Goodbye world"]
})
```

**Fields**:

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `:id` | `String.t()` | ✅ | Unique call identifier |
| `:model` | `String.t()` | ✅ | Embedding model |
| `:texts` | `[String.t()]` | ✅ | Texts to embed |

**Result Signal**: `EmbedResult`

---

## Using Directives

### In State Machines

```elixir
def update(machine, {:start, prompt, call_id}, env) do
  with_transition(machine, "processing", fn machine ->
    conversation = build_conversation(prompt, env)
    {machine, [{:call_llm_stream, call_id, conversation}]}
  end)
end
```

### Lifting Directives (in Strategies)

```elixir
defp lift_directives(directives, config) do
  %{model: model, reqllm_tools: tools} = config

  Enum.flat_map(directives, fn
    {:call_llm_stream, id, conversation} ->
      [Directive.ReqLLMStream.new!(%{
        id: id,
        model: model,
        context: convert_to_reqllm_context(conversation),
        tools: tools
      })]

    {:exec_tool, id, tool_name, arguments} ->
      case lookup_tool(tool_name, config) do
        {:ok, action_module} ->
          [Directive.ToolExec.new!(%{
            id: id,
            tool_name: tool_name,
            action_module: action_module,
            arguments: arguments
          })]

        :error ->
          []
      end
  end)
end
```

---

## Directive Lifecycle

```
┌────────────────┐     lift_directives      ┌────────────────┐
│ State Machine  │ ──────────────────────▶ │   Strategy     │
│                │   {:call_llm_stream,...} │                │
└────────────────┘                          └────────┬───────┘
                                                    │
                                                    ▼
┌────────────────┐     Directive.ReqLLMStream  ┌────────────────┐
│ AgentServer    │ ◀────────────────────────── │   Strategy     │
│                │                              │                │
└────────┬───────┘                              └────────────────┘
         │
         │ Execute directive
         ▼
┌────────────────┐
│ ReqLLM         │
│ Stream text    │
└────────┬───────┘
         │
         │ Emit signals
         ▼
┌────────────────┐
│ reqllm.result │ ────────────────────────▶ AgentServer
│ reqllm.partial│     ( routed back )
└────────────────┘
```

---

## Creating Custom Directives

### Step 1: Define Module

```elixir
defmodule Jido.AI.Directive.CustomDirective do
  @moduledoc """
  Custom directive for doing X.
  """

  use Jido.AI.Directive

  @impl true
  def describe do
    %{
      name: "custom_directive",
      description: "Does something custom...",
      schema: @schema
    }
  end

  @impl true
  def validate(params) do
    # Return {:ok, validated} or {:error, reason}
    Zoi.validate(@schema, params)
  end

  @impl true
  def execute(directive, context) do
    # Execute the directive
    # Return {:ok, result} or {:error, reason}
  end
end
```

### Step 2: Define Schema

```elixir
@schema Zoi.object(%{
  id: Zoi.string(),
  param1: Zoi.string(),
  param2: Zoi.integer() |> Zoi.default(10)
})
```

### Step 3: Use in State Machine

```elixir
# Return directive tuple
{machine, [{:custom_directive, id, %{param1: "value"}}]}

# Lift in strategy
defp lift_directives(directives, config) do
  Enum.flat_map(directives, fn
    {:custom_directive, id, params} ->
      [Directive.CustomDirective.new!(Map.put(params, :id, id))]

    # ... other directives
  end)
end
```

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [State Machines Guide](./03_state_machines.md) - State machine patterns
- [Signals Guide](./05_signals.md) - Signal types
