# Jido.AI.Agent Implementation

This document describes the implementation of the new `Jido.AI.Agent` module, which provides a high-level, convenient interface for AI operations using the Jido framework.

## Overview

The `Jido.AI.Agent` is a complete rewrite of the previous AI agent implementation, now fully integrated with the Jido framework and leveraging the `Jido.AI.Skill` for AI operations. It provides four main methods for AI interactions:

1. **`generate_text/4`** - Generate text responses
2. **`generate_object/4`** - Generate structured objects with JSON schemas
3. **`stream_text/4`** - Stream text generation in real-time
4. **`stream_object/4`** - Stream object generation in real-time

## Key Features

### Framework Integration
- Built using `use Jido.Agent` macro for full framework compatibility
- Leverages `Jido.AI.Skill` for actual AI operations
- Uses Jido's signal-based communication system
- Follows Jido patterns for agent lifecycle management

### Clean API Design
- Simple, synchronous methods that hide complexity
- Consistent parameter patterns across all methods  
- Flexible configuration options
- Proper error handling and validation

### Configuration Support
- Default model specification (e.g., "openai:gpt-4o")
- Temperature control (0.0-2.0)
- Token limits and timeouts
- System prompts and provider-specific options
- Tool/action integration

## API Reference

### Starting an Agent

```elixir
# Basic usage
{:ok, pid} = Jido.AI.Agent.start_link(id: "my_agent")

# With configuration
{:ok, pid} = Jido.AI.Agent.start_link(
  id: "ai_assistant", 
  default_model: "openai:gpt-4o",
  temperature: 0.7,
  max_tokens: 2000,
  system_prompt: "You are a helpful assistant."
)
```

### Text Generation

```elixir
# Simple text generation
{:ok, text} = Jido.AI.Agent.generate_text(pid, "Hello, how are you?")

# With options
{:ok, text} = Jido.AI.Agent.generate_text(pid, "Explain AI",
  model: "openai:gpt-3.5-turbo",
  temperature: 0.3,
  max_tokens: 500
)
```

### Object Generation

```elixir
schema = %{
  type: "object",
  properties: %{
    name: %{type: "string"},
    age: %{type: "integer"}
  }
}

{:ok, object} = Jido.AI.Agent.generate_object(pid, "Create a person", 
  schema: schema
)
```

### Streaming

```elixir
# Stream text
{:ok, stream} = Jido.AI.Agent.stream_text(pid, "Tell me a story")
Enum.each(stream, fn chunk -> IO.write(chunk) end)

# Stream objects
{:ok, stream} = Jido.AI.Agent.stream_object(pid, "Generate data", 
  schema: schema
)
Enum.each(stream, fn chunk -> IO.inspect(chunk) end)
```

## Architecture

### Signal Flow
1. **API Call** → Method receives parameters
2. **Signal Creation** → Builds appropriate signal type (`jido.ai.generate_text`, etc.)
3. **Agent Communication** → Sends signal via `Jido.Agent.Interaction.call/3`
4. **Skill Processing** → `Jido.AI.Skill` routes and processes the signal
5. **Action Execution** → Appropriate AI tool action executes the request
6. **Response Processing** → Result extracted and returned to caller

### Error Handling
- Proper validation of required parameters (e.g., schema for object methods)
- Timeout handling with configurable timeouts
- Graceful error propagation from underlying AI services
- Clear error messages for common issues

## Implementation Details

### Core Structure
```elixir
defmodule Jido.AI.Agent do
  use Jido.Agent,
    name: "jido_ai_agent",
    description: "General purpose AI agent powered by Jido",
    category: "AI Agents",
    tags: ["ai", "agent", "text", "generation", "streaming"],
    vsn: "1.0.0"

  @default_opts [skills: [Jido.AI.Skill]]
  
  @impl true
  def start_link(opts \\ []) do
    opts = 
      @default_opts
      |> Keyword.merge(opts)
      |> Keyword.put(:agent, __MODULE__)
    
    Jido.Agent.Server.start_link(opts)
  end
  
  # ... API methods
end
```

### Signal Processing
Each API method follows the same pattern:
1. Build data map from parameters
2. Create signal with appropriate type
3. Call agent with signal and timeout
4. Extract result from response signal
5. Return typed result or error

### Result Extraction
The agent includes robust result extraction logic that handles various response formats:
- Text responses: `text`, `content`, `message` fields
- Object responses: `object`, `result`, `data` fields  
- Stream responses: `stream`, `chunks` fields
- Error responses: proper error propagation

## Testing

The implementation includes comprehensive tests covering:
- Agent lifecycle (start/stop)
- Parameter validation (required schema parameters)
- Error handling scenarios
- Integration patterns (skipped tests for actual API calls)

All tests pass and the implementation follows Elixir best practices for error handling and API design.

## Usage Example

See [`examples/ai_agent_demo.exs`](examples/ai_agent_demo.exs) for a complete working example demonstrating all features.

## Migration from Old Implementation

The new implementation provides a cleaner, more powerful API:

**Old:**
```elixir
# Limited, signal-based interface
{:ok, signal} = build_signal("jido.ai.chat.response", message)
call(pid, signal, timeout)
```

**New:**
```elixir
# Clean, typed interface
{:ok, text} = Jido.AI.Agent.generate_text(pid, message)
{:ok, object} = Jido.AI.Agent.generate_object(pid, prompt, schema: schema)
```

The new implementation is fully backward compatible through the underlying signal system while providing a much more ergonomic developer experience.
