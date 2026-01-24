# Directives Guide

This guide covers the directive system in Jido.AI, which provides declarative side effects for agent execution.

## Table of Contents

- [Overview](#overview)
- [Available Directives](#available-directives)
- [Directive Lifecycle](#directive-lifecycle)
- [ReqLLMStream Directive](#reqllmstream-directive)
- [ToolExec Directive](#toolexec-directive)
- [ReqLLMGenerate Directive](#reqllmgenerate-directive)
- [ReqLLMEmbed Directive](#reqllmembed-directive)
- [Creating Custom Directives](#creating-custom-directives)

## Overview

Directives are **declarative descriptions of side effects**. Strategies return directives, and the AgentServer runtime executes them.

### Key Benefits

1. **Separation of Concerns**: Strategies don't execute side effects
2. **Testability**: Can test strategies without mocking
3. **Composability**: Directives can be batched and reordered
4. **Observability**: All side effects are explicit

### Directive Pattern

```mermaid
graph LR
    Strategy[Strategy] -->|Returns| Directive[Directive]
    Directive -->|Executed by| Runtime[AgentServer Runtime]
    Runtime -->|Sends| Signal[Signal]
    Signal -->|Routes to| Strategy
```

## Available Directives

| Directive | Module | Purpose |
|-----------|--------|---------|
| `ReqLLMStream` | `Jido.AI.Directive.ReqLLMStream` | Stream LLM response |
| `ReqLLMGenerate` | `Jido.AI.Directive.ReqLLMGenerate` | Generate non-streaming response |
| `ReqLLMEmbed` | `Jido.AI.Directive.ReqLLMEmbed` | Generate embeddings |
| `ToolExec` | `Jido.AI.Directive.ToolExec` | Execute a tool |

## Directive Lifecycle

```mermaid
sequenceDiagram
    participant Machine as State Machine
    participant Strategy as Strategy
    participant Runtime as AgentServer
    participant Impl as DirectiveExec Impl
    participant External as External Service

    Machine->>Strategy: Returns {:exec_tool, ...}
    Strategy->>Strategy: lift_directives()
    Strategy->>Runtime: Directive.ToolExec struct

    Runtime->>Impl: exec(directive, signal, state)
    Impl->>Impl: Spawn async task
    Impl->>External: Execute tool
    External-->>Impl: Result
    Impl->>Runtime: Signal.ToolResult
    Runtime->>Strategy: signal_routes()
    Strategy->>Machine: update(machine, message)
```

## ReqLLMStream Directive

Streams an LLM response with optional tool support.

### Schema

```elixir
@schema Zoi.struct(__MODULE__, %{
  id: Zoi.string(description: "Unique call ID for correlation"),
  model: Zoi.string(description: "Model spec")
    |> Zoi.optional(),
  model_alias: Zoi.atom(description: "Model alias (e.g., :fast)")
    |> Zoi.optional(),
  system_prompt: Zoi.string(description: "Optional system prompt")
    |> Zoi.optional(),
  context: Zoi.any(description: "Conversation context"),
  tools: Zoi.list(Zoi.any(), description: "ReqLLM tools")
    |> Zoi.default([]),
  tool_choice: Zoi.any(description: "Tool choice mode")
    |> Zoi.default(:auto),
  max_tokens: Zoi.integer(description: "Max tokens")
    |> Zoi.default(1024),
  temperature: Zoi.number(description: "Temperature (0.0–2.0)")
    |> Zoi.default(0.2),
  timeout: Zoi.integer(description: "Timeout in milliseconds")
    |> Zoi.optional(),
  metadata: Zoi.map(description: "Tracking metadata")
    |> Zoi.default(%{})
}, coerce: true)
```

### Creating the Directive

```elixir
alias Jido.AI.Directive

# Using model alias
directive = Directive.ReqLLMStream.new!(%{
  id: "call_123",
  model_alias: :fast,
  context: [
    %{role: :system, content: "You are a helpful assistant."},
    %{role: :user, content: "What is 2 + 2?"}
  ],
  tools: tools,
  max_tokens: 2048
})

# Using direct model spec
directive = Directive.ReqLLMStream.new!(%{
  id: "call_123",
  model: "anthropic:claude-haiku-4-5",
  context: context,
  tools: tools
})
```

### Execution Behavior

The directive implementation:

1. Resolves model alias (if used)
2. Prepends system prompt (if provided)
3. Spawns an async task
4. Streams tokens from LLM
5. Sends `reqllm.partial` signals for each chunk
6. Sends `reqllm.result` signal on completion

### Signals Emitted

```elixir
# During streaming
%Jido.Signal{
  type: "reqllm.partial",
  data: %{
    call_id: "call_123",
    delta: "Hello",
    chunk_type: :content
  }
}

# On completion
%Jido.Signal{
  type: "reqllm.result",
  data: %{
    call_id: "call_123",
    result: {:ok, %{type: :final_answer, text: "Hello!"}}
  }
}
```

## ToolExec Directive

Executes a Jido.Action or Jido.AI.Tools.Tool as a tool.

### Schema

```elixir
@schema Zoi.struct(__MODULE__, %{
  id: Zoi.string(description: "Tool call ID from LLM"),
  tool_name: Zoi.string(description: "Name of the tool"),
  arguments: Zoi.map(description: "Arguments from LLM")
    |> Zoi.default(%{}),
  context: Zoi.map(description: "Execution context")
    |> Zoi.default(%{}),
  metadata: Zoi.map(description: "Tracking metadata")
    |> Zoi.default(%{})
}, coerce: true)
```

### Creating the Directive

```elixir
directive = Directive.ToolExec.new!(%{
  id: "tc_123",
  tool_name: "calculator",
  arguments: %{
    "a" => 1,
    "b" => 2,
    "operation" => "add"
  },
  context: %{
    agent_id: "agent_456"
  }
})
```

### Argument Normalization

LLM tool calls use string keys (JSON format). The executor normalizes them:

```elixir
# Before normalization (from LLM)
%{"a" => "1", "b" => "2", "operation" => "add"}

# After normalization (based on schema)
%{a: 1, b: 2, operation: "add"}
```

### Execution Flow

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: Directive.ToolExec do
  def exec(directive, _input_signal, state) do
    agent_pid = self()

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result = Executor.execute(
        directive.tool_name,
        directive.arguments,
        directive.context
      )

      signal = Signal.ToolResult.new!(%{
        call_id: directive.id,
        tool_name: directive.tool_name,
        result: result
      })

      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end
end
```

## ReqLLMGenerate Directive

Generates a non-streaming LLM response.

### Schema

```elixir
@schema Zoi.struct(__MODULE__, %{
  id: Zoi.string(description: "Unique call ID"),
  model: Zoi.string(description: "Model spec") |> Zoi.optional(),
  model_alias: Zoi.atom(description: "Model alias") |> Zoi.optional(),
  system_prompt: Zoi.string(description: "System prompt") |> Zoi.optional(),
  context: Zoi.any(description: "Conversation context"),
  tools: Zoi.list(Zoi.any()) |> Zoi.default([]),
  tool_choice: Zoi.any() |> Zoi.default(:auto),
  max_tokens: Zoi.integer() |> Zoi.default(1024),
  temperature: Zoi.number() |> Zoi.default(0.2),
  timeout: Zoi.integer() |> Zoi.optional(),
  metadata: Zoi.map() |> Zoi.default(%{})
}, coerce: true)
```

### When to Use

- When streaming is not needed
- For simple one-shot responses
- When you need the complete response before processing

```elixir
directive = Directive.ReqLLMGenerate.new!(%{
  id: "call_123",
  model_alias: :fast,
  context: messages
})
```

## ReqLLMEmbed Directive

Generates embeddings for text.

### Schema

```elixir
@schema Zoi.struct(__MODULE__, %{
  id: Zoi.string(description: "Unique call ID"),
  model: Zoi.string(description: "Embedding model"),
  texts: Zoi.any(description: "Text or list of texts"),
  dimensions: Zoi.integer(description: "Embedding dimensions")
    |> Zoi.optional(),
  timeout: Zoi.integer() |> Zoi.optional(),
  metadata: Zoi.map() |> Zoi.default(%{})
}, coerce: true)
```

### Usage

```elixir
# Single text
directive = Directive.ReqLLMEmbed.new!(%{
  id: "embed_123",
  model: "openai:text-embedding-3-small",
  texts: "Hello, world!"
})

# Batch embedding
directive = Directive.ReqLLMEmbed.new!(%{
  id: "embed_124",
  model: "openai:text-embedding-3-small",
  texts: ["Text 1", "Text 2", "Text 3"],
  dimensions: 1536
})
```

### Signal Emitted

```elixir
%Jido.Signal{
  type: "ai.embed_result",
  data: %{
    call_id: "embed_123",
    result: {:ok, %{
      embeddings: [0.1, 0.2, ...],
      count: 1
    }}
  }
}
```

## Creating Custom Directives

To create a custom directive:

### Step 1: Define the Directive Struct

```elixir
defmodule MyApp.Directive.MyCustomDirective do
  @moduledoc """
  Custom directive for my specific use case.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(description: "Unique ID"),
              data: Zoi.any(description: "My data"),
              options: Zoi.map(description: "Options")
                |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))
  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc false
  def schema, do: @schema

  @doc "Create a new directive."
  def new!(attrs) when is_map(attrs) do
    case Zoi.parse(@schema, attrs) do
      {:ok, directive} -> directive
      {:error, errors} -> raise "Invalid MyCustomDirective: #{inspect(errors)}"
    end
  end
end
```

### Step 2: Implement DirectiveExec Protocol

```elixir
defimpl Jido.AgentServer.DirectiveExec, for: MyApp.Directive.MyCustomDirective do
  @moduledoc """
  Executes the custom directive.
  """

  require Logger

  def exec(directive, _input_signal, state) do
    Logger.info("Executing custom directive: #{directive.id}")

    agent_pid = self()

    Task.Supervisor.start_child(Jido.TaskSupervisor, fn ->
      result = do_execute(directive)

      # Send result back as a signal
      signal = %Jido.Signal{
        type: "my_app.custom_result",
        data: %{
          directive_id: directive.id,
          result: result
        }
      }

      Jido.AgentServer.cast(agent_pid, signal)
    end)

    {:async, nil, state}
  end

  defp do_execute(directive) do
    # Your custom execution logic
    {:ok, %{processed: directive.data}}
  end
end
```

### Step 3: Use in Strategy

```elixir
defmodule MyApp.Strategies.MyStrategy do
  use Jido.Agent.Strategy

  alias MyApp.Directive.MyCustomDirective

  defp process_instruction(agent, %{action: :my_action, params: params}) do
    # Return your custom directive
    directive = MyCustomDirective.new!(%{
      id: generate_id(),
      data: params
    })

    {agent, [directive]}
  end
end
```

## Directive Helpers

### Model Resolution

The `Jido.AI.Helpers` module provides helper functions:

```elixir
alias Jido.AI.Helpers

# Resolve model alias to full spec
{:ok, model} = Helpers.resolve_model(:fast)
# => {:ok, "anthropic:claude-haiku-4-5"}

# Build messages from context with system prompt
messages = Helpers.build_directive_messages(context, system_prompt)
```

### Error Classification

```elixir
# Classify errors for telemetry
error_type = Helpers.classify_error(error)
# => :rate_limit | :auth | :timeout | :provider_error | :unknown
```

## Next Steps

- [Signals Guide](./05_signals.md) - Results from directive execution
- [Tool System Guide](./06_tool_system.md) - Tool execution details
- [Configuration Guide](./08_configuration.md) - Model aliases and providers
