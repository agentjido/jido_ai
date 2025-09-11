# Core Data Structures and Their Relationships

ReqLLM provides a unified, provider-agnostic architecture for AI interactions built around six core data structures. These structures work together to enable consistent handling of models, conversations, multimodal content, tool calling, and streaming responses across different AI providers.

## Overview of Core Structures

The ReqLLM data model follows a hierarchical design:

```
ReqLLM.Model          # Model configuration and metadata
    ↓
ReqLLM.Context        # Collection of conversation messages  
    ↓
ReqLLM.Message        # Individual conversation messages
    ↓
ReqLLM.Message.ContentPart  # Typed content within messages
    ↓
ReqLLM.StreamChunk    # Streaming response chunks
    ↓
ReqLLM.Tool           # Function calling definitions
```

## 1. ReqLLM.Model - AI Model Configuration

The `ReqLLM.Model` struct represents an AI model configuration with provider information, runtime parameters, and optional metadata.

### Core Fields

```elixir
%ReqLLM.Model{
  # Required runtime fields
  provider: :anthropic,                    # Provider atom
  model: "claude-3-5-sonnet",             # Model name
  temperature: 0.7,                        # Generation temperature (0.0-2.0)
  max_tokens: 1000,                        # Maximum tokens to generate
  max_retries: 3,                          # Retry attempts
  
  # Optional metadata fields
  limit: %{context: 128_000, output: 4_096},  # Token limits
  modalities: %{                           # Supported input/output types
    input: [:text, :image],
    output: [:text]
  },
  capabilities: %{                         # Model capabilities
    reasoning?: true,
    tool_call?: true,
    supports_temperature?: true
  },
  cost: %{input: 3.0, output: 15.0}       # Cost per 1K tokens
}
```

### Creation Patterns

```elixir
# From string specification
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")

# From tuple with options
{:ok, model} = ReqLLM.Model.from({:anthropic, 
  model: "claude-3-5-sonnet", 
  temperature: 0.7, 
  max_tokens: 1000
})

# Direct construction
model = ReqLLM.Model.new(:anthropic, "claude-3-5-sonnet", 
  temperature: 0.5, 
  capabilities: %{tool_call?: true}
)
```

### Provider Agnosticism

Models abstract away provider-specific details while maintaining compatibility:

```elixir
# Same API works across providers
anthropic_model = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")
openai_model = ReqLLM.Model.from("openai:gpt-4")

# Both use identical generation interface
ReqLLM.generate_text(anthropic_model, context)
ReqLLM.generate_text(openai_model, context)
```

## 2. ReqLLM.Context - Conversation Collection

The `ReqLLM.Context` struct represents a conversation as a collection of messages, providing constructor functions for clean message creation.

### Structure

```elixir
%ReqLLM.Context{
  messages: [                    # List of ReqLLM.Message structs
    %ReqLLM.Message{role: :system, content: [...]},
    %ReqLLM.Message{role: :user, content: [...]},
    %ReqLLM.Message{role: :assistant, content: [...]}
  ]
}
```

### Message Constructor Functions

```elixir
import ReqLLM.Context

# Build conversations naturally
context = Context.new([
  system("You are a helpful assistant"),
  user("What's the weather like?"),
  assistant("I'll check that for you"),
  user([
    ContentPart.text("Here's an image of the current conditions:"),
    ContentPart.image_url("https://weather.com/current.jpg")
  ])
])
```

### Validation and Enumeration

```elixir
# Context validation
{:ok, valid_context} = ReqLLM.Context.validate(context)

# Enumerable protocol support
context
|> Enum.filter(&(&1.role == :user))
|> Enum.count()
#=> 2

# Collectable protocol support  
new_context = Enum.into([new_message], context)
```

## 3. ReqLLM.Message - Individual Conversation Messages

Messages represent individual conversation turns with support for multiple content types through the `content` field (always a list of `ContentPart` structs).

### Structure

```elixir
%ReqLLM.Message{
  role: :user | :assistant | :system | :tool,    # Message role
  content: [ContentPart.t()],                     # List of content parts
  name: "function_name",                          # Optional name (for tools)
  tool_call_id: "call_123",                      # Tool call identifier
  tool_calls: [%{...}],                          # Tool call definitions
  metadata: %{}                                   # Additional metadata
}
```

### Content Always as List

ReqLLM eliminates polymorphism by always using lists for content:

```elixir
# Text-only message
message = %ReqLLM.Message{
  role: :user,
  content: [ContentPart.text("Hello world")]
}

# Multimodal message
message = %ReqLLM.Message{
  role: :user, 
  content: [
    ContentPart.text("Describe this image:"),
    ContentPart.image_url("https://example.com/image.jpg")
  ]
}
```

## 4. ReqLLM.Message.ContentPart - Typed Content

`ContentPart` represents individual pieces of content within messages, supporting multiple content types through a discriminated union.

### Content Types

```elixir
# Text content
ContentPart.text("Hello world")
#=> %ContentPart{type: :text, text: "Hello world"}

# Reasoning content (for models that support thinking)
ContentPart.reasoning("Let me think about this...")  
#=> %ContentPart{type: :reasoning, text: "Let me think about this..."}

# Image from URL
ContentPart.image_url("https://example.com/image.jpg")
#=> %ContentPart{type: :image_url, url: "https://example.com/image.jpg"}

# Image from binary data
ContentPart.image(image_data, "image/png")
#=> %ContentPart{type: :image, data: <<binary>>, media_type: "image/png"}

# File attachment
ContentPart.file(file_data, "document.pdf", "application/pdf")  
#=> %ContentPart{type: :file, data: <<binary>>, filename: "document.pdf", media_type: "application/pdf"}

# Tool call
ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
#=> %ContentPart{type: :tool_call, tool_call_id: "call_123", tool_name: "get_weather", input: %{location: "NYC"}}

# Tool result
ContentPart.tool_result("call_123", %{temperature: 72, conditions: "sunny"})
#=> %ContentPart{type: :tool_result, tool_call_id: "call_123", output: %{temperature: 72, conditions: "sunny"}}
```

### Multimodal Support

ContentPart enables rich multimodal conversations:

```elixir
# Complex multimodal message
multimodal_message = %ReqLLM.Message{
  role: :user,
  content: [
    ContentPart.text("Please analyze these documents:"),
    ContentPart.file(pdf_data, "report.pdf", "application/pdf"),
    ContentPart.text("And compare with this image:"),
    ContentPart.image_url("https://example.com/chart.png"),
    ContentPart.text("What insights can you provide?")
  ]
}
```

## 5. ReqLLM.StreamChunk - Uniform Streaming Output

`StreamChunk` provides a unified format for streaming responses across different providers, supporting text content, tool calls, reasoning tokens, and metadata.

### Chunk Types and Structure

```elixir
%ReqLLM.StreamChunk{
  type: :content | :thinking | :tool_call | :meta,  # Chunk type
  text: "response text",                            # For :content and :thinking
  name: "function_name",                            # For :tool_call
  arguments: %{key: "value"},                       # For :tool_call  
  metadata: %{}                                     # Additional data
}
```

### Chunk Type Examples

```elixir
# Content chunk (main response text)
ReqLLM.StreamChunk.text("Hello there!")
#=> %StreamChunk{type: :content, text: "Hello there!"}

# Thinking chunk (reasoning tokens)
ReqLLM.StreamChunk.thinking("Let me consider the options...")
#=> %StreamChunk{type: :thinking, text: "Let me consider the options..."}

# Tool call chunk
ReqLLM.StreamChunk.tool_call("get_weather", %{location: "NYC"})
#=> %StreamChunk{type: :tool_call, name: "get_weather", arguments: %{location: "NYC"}}

# Metadata chunk  
ReqLLM.StreamChunk.meta(%{finish_reason: "stop", tokens_used: 42})
#=> %StreamChunk{type: :meta, metadata: %{finish_reason: "stop", tokens_used: 42}}
```

### Streaming Patterns

```elixir
# Stream processing with filtering
{:ok, response} = ReqLLM.stream_text(model, context)

# Extract only content text
response.body
|> Stream.filter(&(&1.type == :content))
|> Stream.map(&(&1.text))
|> Stream.each(&IO.write/1)
|> Stream.run()

# Process tool calls separately
response.body  
|> Stream.filter(&(&1.type == :tool_call))
|> Stream.each(fn chunk ->
  IO.puts("Tool call: #{chunk.name}(#{inspect(chunk.arguments)})")
end)
|> Stream.run()
```

## 6. ReqLLM.Tool - Function Calling Definitions

`Tool` represents function definitions for AI model tool calling, following Vercel AI SDK patterns with NimbleOptions schema validation.

### Structure

```elixir
%ReqLLM.Tool{
  name: "get_weather",                    # Tool identifier
  description: "Get weather for location", # AI-readable description
  parameter_schema: [                     # NimbleOptions schema
    location: [type: :string, required: true, doc: "City name"],
    units: [type: :string, default: "celsius", doc: "Temperature units"]
  ],
  compiled: compiled_schema,              # Compiled validation schema
  callback: {WeatherService, :get_weather} # Execution callback
}
```

### Tool Creation and Usage

```elixir
# Create tool
{:ok, tool} = ReqLLM.Tool.new(
  name: "get_weather",
  description: "Get current weather for a location",
  parameter_schema: [
    location: [type: :string, required: true, doc: "City name"],
    units: [type: :string, default: "celsius", doc: "Temperature units"]
  ],
  callback: {WeatherService, :get_weather}
)

# Execute tool
{:ok, result} = ReqLLM.Tool.execute(tool, %{location: "San Francisco"})
#=> {:ok, %{temperature: 72, conditions: "sunny", units: "celsius"}}

# Convert to provider schema
anthropic_schema = ReqLLM.Tool.to_schema(tool, :anthropic)
#=> %{
#     "name" => "get_weather",
#     "description" => "Get current weather for a location", 
#     "input_schema" => %{
#       "type" => "object",
#       "properties" => %{
#         "location" => %{"type" => "string", "description" => "City name"},
#         "units" => %{"type" => "string", "description" => "Temperature units"}
#       },
#       "required" => ["location"]
#     }
#   }
```

### Callback Formats

```elixir
# Module and function
callback: {MyModule, :my_function}

# Module, function, and extra args
callback: {MyModule, :my_function, [:extra, :args]}

# Anonymous function
callback: fn args -> {:ok, "result"} end
```

## Data Flow Through the System

### 1. Basic Text Generation Flow

```elixir
# 1. Create model configuration
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")

# 2. Build conversation context
context = ReqLLM.Context.new([
  ReqLLM.Context.system("You are helpful"),
  ReqLLM.Context.user("Hello!")
])

# 3. Generate response
{:ok, response} = ReqLLM.generate_text(model, context, max_tokens: 100)
```

### 2. Multimodal Conversation Flow

```elixir
# 1. Model with image support
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")

# 2. Multimodal context
context = ReqLLM.Context.new([
  ReqLLM.Context.system("You analyze images"),
  ReqLLM.Context.user([
    ContentPart.text("What's in this image?"),
    ContentPart.image_url("https://example.com/photo.jpg")
  ])
])

# 3. Generate with multimodal input
{:ok, response} = ReqLLM.generate_text(model, context)
```

### 3. Streaming Response Flow

```elixir
# 1. Setup model and context
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")
context = ReqLLM.Context.new([ReqLLM.Context.user("Tell me a story")])

# 2. Stream response
{:ok, response} = ReqLLM.stream_text(model, context)

# 3. Process stream chunks
response.body
|> Stream.each(fn chunk ->
  case chunk.type do
    :content -> IO.write(chunk.text)
    :thinking -> IO.puts("[thinking: #{chunk.text}]")
    :tool_call -> IO.puts("[calling #{chunk.name}]") 
    :meta -> IO.puts("[meta: #{inspect(chunk.metadata)}]")
  end
end)
|> Stream.run()
```

### 4. Tool Calling Flow

```elixir
# 1. Create tool
{:ok, weather_tool} = ReqLLM.Tool.new(
  name: "get_weather",
  description: "Get weather",
  parameter_schema: [location: [type: :string, required: true]],
  callback: {WeatherAPI, :get_current}
)

# 2. Model with tools
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-5-sonnet")
context = ReqLLM.Context.new([
  ReqLLM.Context.user("What's the weather in NYC?")
])

# 3. Generate with tool calling
{:ok, response} = ReqLLM.generate_text(model, context, 
  tools: [weather_tool], 
  max_tokens: 100
)

# 4. Process tool calls in response
# Response context will contain tool call messages that can be executed
```

## Provider Agnosticism

All data structures are designed to work uniformly across providers:

### Model Abstraction

```elixir
# Same interface works for all providers
models = [
  ReqLLM.Model.from("anthropic:claude-3-5-sonnet"),
  ReqLLM.Model.from("openai:gpt-4"),
  ReqLLM.Model.from("google:gemini-pro")
]

# All use identical generation API
for {:ok, model} <- models do
  ReqLLM.generate_text(model, context, max_tokens: 100)
end
```

### Content Part Translation

```elixir
# ContentPart structures work across all providers
multimodal_content = [
  ContentPart.text("Analyze this:"),
  ContentPart.image_url("https://example.com/image.jpg")
]

# Provider plugins translate to native formats
# Anthropic: {"type": "image", "source": {"type": "base64", ...}}
# OpenAI: {"type": "image_url", "image_url": {"url": "..."}}
```

### Stream Chunk Normalization

```elixir
# All providers produce identical StreamChunk formats
{:ok, anthropic_stream} = ReqLLM.stream_text("anthropic:claude-3-haiku", context)
{:ok, openai_stream} = ReqLLM.stream_text("openai:gpt-4", context)

# Same processing code works for both
process_stream = fn stream ->
  stream.body
  |> Stream.filter(&(&1.type == :content))
  |> Stream.map(&(&1.text))
  |> Enum.join()
end

anthropic_text = process_stream.(anthropic_stream)
openai_text = process_stream.(openai_stream)
```

## Key Design Principles

### 1. Consistency Over Flexibility
All structures follow consistent patterns - messages always contain lists of ContentParts, tools always use NimbleOptions schemas, streams always produce StreamChunks.

### 2. Type Safety 
Discriminated unions (ContentPart types, StreamChunk types) provide compile-time guarantees about data structure usage.

### 3. Provider Abstraction
Core structures remain provider-agnostic while provider plugins handle translation to native formats.

### 4. Rich Metadata Support
All structures include metadata fields for extensibility without breaking changes.

### 5. Functional Composition
Structures are immutable and compose naturally with Elixir's functional programming patterns.

This data model enables ReqLLM to provide a unified, type-safe interface for AI interactions while maintaining the flexibility to support diverse provider capabilities and emerging AI features.
