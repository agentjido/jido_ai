# Jido.AI Signals Guide

This guide covers the signal system used for communication between components in Jido.AI.

## Table of Contents

1. [Overview](#overview)
2. [Signal Types](#signal-types)
3. [Signal Routing](#signal-routing)
4. [Signal Lifecycle](#signal-lifecycle)
5. [Creating Custom Signals](#creating-custom-signals)

---

## Overview

Signals are the primary communication mechanism in Jido.AI. They carry results between the AgentServer, strategies, and external systems.

### Key Principles

1. **Typed**: All signals are structured types
2. **Routed**: Signals are routed via `signal_routes/1`
3. **Immutable**: Signals cannot be modified once created
4. **Observable**: Signal emission can be tracked

### Signal Flow

```
┌──────────────┐     emit     ┌──────────────┐     route     ┌──────────────┐
│ External     │ ──────────▶  │ AgentServer  │ ──────────▶  │   Strategy    │
│ (ReqLLM, etc)│              │              │              │              │
└──────────────┘              └──────┬───────┘              └──────┬───────┘
                                     │                             │
                                     │ emit                       │ process
                                     ▼                             ▼
                              ┌──────────────┐              ┌──────────────┐
                              │   Signals    │              │ Instructions │
                              │ (recorded)   │              │ (executed)   │
                              └──────────────┘              └──────────────┘
```

---

## Signal Types

### ReqLLMResult

LLM call completion with tool calls or final answer.

```elixir
%Jido.AI.Signal.ReqLLMResult{
  id: "call_abc123",
  status: :ok,
  result: %{
    type: :tool_calls,
    tool_calls: [
      %{id: "tool_1", name: "calculator", arguments: %{...}}
    ]
  }
}

# Or final answer
%Jido.AI.Signal.ReqLLMResult{
  id: "call_abc123",
  status: :ok,
  result: %{
    type: :final_answer,
    text: "The answer is 42"
  }
}

# Or error
%Jido.AI.Signal.ReqLLMResult{
  id: "call_abc123",
  status: :error,
  error: "API rate limit exceeded"
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `:id` | `String.t()` | Call identifier |
| `:status` | `:ok \| :error` | Result status |
| `:result` | `map() \| nil` | Response data |
| `:error` | `term() \| nil` | Error if failed |

---

### ReqLLMPartial

Streaming token chunk from LLM.

```elixir
%Jido.AI.Signal.ReqLLMPartial{
  id: "call_abc123",
  delta: "Hello",
  chunk_type: :content  # or :thinking
}

# Thinking token (for extended thinking models)
%Jido.AI.Signal.ReqLLMPartial{
  id: "call_abc123",
  delta: "(thinking...)",
  chunk_type: :thinking
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `:id` | `String.t()` | Call identifier |
| `:delta` | `String.t()` | Token text |
| `:chunk_type` | `:content \| :thinking` | Token type |

---

### ToolResult

Tool execution result.

```elixir
%Jido.AI.Signal.ToolResult{
  id: "tool_abc123",
  tool_name: "calculator",
  status: :ok,
  result: %{
    value: 4
  }
}

# Or error
%Jido.AI.Signal.ToolResult{
  id: "tool_abc123",
  tool_name: "calculator",
  status: :error,
  error: "Division by zero"
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `:id` | `String.t()` | Call identifier |
| `:tool_name` | `String.t()` | Tool name |
| `:status` | `:ok \| :error` | Result status |
| `:result` | `term() \| nil` | Return value |
| `:error` | `term() \| nil` | Error if failed |

---

### UsageReport

Token usage and cost tracking.

```elixir
%Jido.AI.Signal.UsageReport{
  call_id: "call_abc123",
  model: "anthropic:claude-sonnet-4-20250514",
  input_tokens: 100,
  output_tokens: 50,
  total_tokens: 150,
  cache_creation_input_tokens: 0,
  cache_read_input_tokens: 0
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `:call_id` | `String.t()` | Associated call |
| `:model` | `String.t()` | Model used |
| `:input_tokens` | `non_neg_integer()` | Input tokens |
| `:output_tokens` | `non_neg_integer()` | Output tokens |
| `:total_tokens` | `non_neg_integer()` | Total tokens |
| `:cache_creation_input_tokens` | `non_neg_integer()` | Cache write tokens |
| `:cache_read_input_tokens` | `non_neg_integer()` | Cache read tokens |

---

### EmbedResult

Embedding generation result.

```elixir
%Jido.AI.Signal.EmbedResult{
  id: "embed_abc123",
  status: :ok,
  embeddings: [
    %{embedding: [0.1, 0.2, ...], index: 0},
    %{embedding: [0.3, 0.4, ...], index: 1}
  ],
  model: "openai:text-embedding-3-small",
  usage: %{total_tokens: 10}
}
```

---

## Signal Routing

Strategies define signal routes for automatic message delivery.

### Defining Routes

```elixir
@impl true
def signal_routes(_ctx) do
  [
    {"react.user_query", {:strategy_cmd, @start}},
    {"reqllm.result", {:strategy_cmd, @llm_result}},
    {"reqllm.partial", {:strategy_cmd, @llm_partial}},
    {"ai.tool_result", {:strategy_cmd, @tool_result}}
  ]
end
```

### Route Format

```elixir
{signal_pattern, destination}
```

**Signal Pattern**: String pattern matching signal type (e.g., `"reqllm.result"`)
**Destination**: `{:strategy_cmd, action}` routes to strategy action

### Available Signals

| Signal | Source | Route Pattern |
|--------|--------|---------------|
| `ReqLLMResult` | ReqLLM | `"reqllm.result"` |
| `ReqLLMPartial` | ReqLLM | `"reqllm.partial"` |
| `ToolResult` | ToolExec | `"ai.tool_result"` |
| `UsageReport` | ReqLLM | `"reqllm.usage"` |
| `EmbedResult` | ReqLLM | `"reqllm.embed"` |

---

## Signal Lifecycle

```
┌────────────────┐
│ State Machine │ Returns {:call_llm_stream, id, context}
└────────┬───────┘
         │
         ▼
┌────────────────┐
│   Strategy     │ lift_directives → ReqLLMStream directive
└────────┬───────┘
         │
         ▼
┌────────────────┐
│  AgentServer   │ Executes directive
└────────┬───────┘
         │
         ▼
┌────────────────┐
│    ReqLLM      │ Makes API call, streams response
└────────┬───────┘
         │
         ▼
┌────────────────┐
│  Emit signals  │
│  - Partial     │ ────▶ Strategy (as instruction)
│  - Result      │ ────▶ Strategy (as instruction)
└────────────────┘
```

---

## Creating Custom Signals

### Step 1: Define Signal Struct

```elixir
defmodule Jido.AI.Signal.CustomSignal do
  @moduledoc """
  Custom signal for X.
  """

  @type t :: %__MODULE__{
          id: String.t(),
          status: :ok | :error,
          result: term() | nil,
          error: term() | nil
        }

  defstruct [:id, :status, :result, :error]

  @doc """
  Creates a new custom signal.
  """
  def new(id, status, result \\ nil, error \\ nil) do
    %__MODULE__{
      id: id,
      status: status,
      result: result,
      error: error
    }
  end

  @doc """
  Creates a success signal.
  """
  def ok(id, result) do
    new(id, :ok, result)
  end

  @doc """
  Creates an error signal.
  """
  def error(id, error) do
    new(id, :error, nil, error)
  end
end
```

### Step 2: Emit Signal

```elixir
# In directive execution
AgentServer.emit_signal(agent, %Jido.AI.Signal.CustomSignal{
  id: "custom_123",
  status: :ok,
  result: %{data: "..."}
})
```

### Step 3: Route Signal

```elixir
# In strategy
def signal_routes(_ctx) do
  [
    {"custom.signal", {:strategy_cmd, :custom_signal}}
  ]
end
```

---

## Helper Functions

### Extract Tool Calls

```elixir
alias Jido.AI.Signal

# Get tool calls from result
case result do
  %{type: :tool_calls, tool_calls: calls} ->
    # Process tool calls
  _ ->
    # No tool calls
end
```

### Classify Response

```elixir
# Determine response type
cond do
  result.type == :tool_calls -> :has_tools
  result.type == :final_answer -> :final
  result.status == :error -> :error
  true -> :unknown
end
```

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [Directives Guide](./04_directives.md) - Directive system
- [Strategies Guide](./02_strategies.md) - Strategy implementations
