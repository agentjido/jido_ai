# Req LLM

Req Plugin to normalize LLM API calls across providers.

- Model Metadata is sync'd from [models.dev](https://models.dev) via a mix task
  - Metadata available for 45 providers and 665 models 
  - Includes model capabilities and cost data

- Basic data structures provided to normalize LLM interactions:
  - Context (collection of messages)
  - Message (individual message with content)
  - ContentPart (typed content within messages)
  - StreamChunk (streaming response chunks)
  - Tool (function calling definitions)

- Two levels of API provided:
  - Direct Req API with full response metadata
  - Vercel AI SDK style API with bang variants for convenient result unwrapping

- Providers are implemented as Req plugins, composable with other Req plugins
  - Supported providers:
    - Anthropic
    - Open AI

  - Easily create new providers by implementing the ReqLLM.Provider behavior

- Context Codec protocol used to translate between ReqLLM data structures and provider-specific formats
- Usage tracking and cost extraction from responses
- Comprehensive model coverage testing with local fixtures and live API calls



Composable Elixir library for AI interactions built on Req. Provides unified interface to LLM providers through plugin-based architecture that normalizes provider differences behind canonical data structures and Req's HTTP pipeline.

## Architecture

**Plugin-Based Normalization**: Each provider is a Req plugin. ReqLLM handles format translation via Codec protocol while Req handles HTTP transport, retries, and middleware.

**Provider-Agnostic Data Model**: Unified structures (Context, Message, ContentPart, StreamChunk) work across all providers. Provider-specific formats handled by Codec implementations.

**Vercel AI SDK Patterns**: Familiar `generate_text/stream_text` API with consistent signatures. Bang variants for convenient result unwrapping.

**Enhanced Metadata**: Model capabilities, limits, and cost data loaded from models.dev at compile time.

## Quick Start

```elixir
# Installation
{:req_llm, "~> 0.1.0"}

# Basic generation  
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello world")

# Streaming
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Tell a story")
stream |> Stream.filter(&(&1.type == :text)) |> Stream.map(&(&1.text)) |> Enum.join()

# With options
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet",
  "Write a haiku", 
  temperature: 0.8,
  max_tokens: 100
)

# Usage tracking
{:ok, text, usage} = 
  ReqLLM.generate_text("openai:gpt-4o", "Hello")
  |> ReqLLM.with_usage()
```

## Model Specifications

Flexible model specification formats:

```elixir
# String format
"anthropic:claude-3-sonnet"

# Tuple with options
{:anthropic, model: "claude-3-sonnet", temperature: 0.7}

# Full struct
%ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet", temperature: 0.7}
```

## Key Management

Secure key management via Kagi/JidoKeys integration:

```elixir
ReqLLM.put_key("anthropic_api_key", "sk-ant-...")
ReqLLM.put_key("openai_api_key", "sk-...")

# Providers automatically retrieve keys
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
```

## Multimodal Content

Type-safe multimodal content handling:

```elixir
import ReqLLM.Message.ContentPart

messages = [
  ReqLLM.Context.user([
    text("Analyze this image"),
    image_url("https://example.com/chart.png")
  ])
]

{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", messages)
```

## Tool Calling

Function calling with validation:

```elixir
weather_tool = ReqLLM.Tool.new!(
  name: "get_weather",
  description: "Get current weather",
  parameter_schema: [
    location: [type: :string, required: true],
    units: [type: :string, default: "celsius"]
  ],
  callback: {WeatherAPI, :fetch_weather}
)

{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet",
  "What's the weather in Tokyo?",
  tools: [weather_tool]
)
```

## Streaming

Back-pressure aware streaming with unified chunk format:

```elixir
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Count to 100")

stream
|> Stream.filter(&(&1.type == :text))
|> Stream.each(&IO.write(&1.text))
|> Stream.run()
```

## Core Plugin API

Direct access to provider plugins for advanced usage:

```elixir
request = Req.new()
|> ReqLLM.attach("anthropic:claude-3-sonnet")
|> Req.Request.append_request_steps(custom_middleware: &add_tracing/1)
|> Req.request(json: %{messages: messages})
```

## Provider System

Clean provider implementation via DSL:

```elixir
defmodule MyProvider do
  use ReqLLM.Provider.DSL,
    id: :myprovider,
    base_url: "https://api.example.com",
    metadata: "priv/models_dev/myprovider.json"

  @impl ReqLLM.Provider
  def attach(request, model, opts), do: configure_request(request, model)
  
  @impl ReqLLM.Provider  
  def parse_response(response, model), do: parse_to_chunks(response.body)
end

# Codec implementation for format translation
defimpl ReqLLM.Codec, for: MyProvider.Tagged do
  def encode(%{context: ctx}), do: convert_to_provider_format(ctx)
  def decode(%{data: data}), do: convert_to_stream_chunks(data)  
end
```

## Error Handling

Structured errors via Splode:

```elixir
case ReqLLM.generate_text("invalid:model", "Hello") do
  {:ok, response} -> handle_success(response)
  {:error, %ReqLLM.Error.Invalid.Provider{}} -> handle_bad_provider()
  {:error, %ReqLLM.Error.API.RateLimit{}} -> handle_rate_limit() 
  {:error, error} -> handle_other_error(error)
end
```

## Capability Testing

Live testing against provider capabilities:

```elixir
# Fixture-based testing (default)
mix test

# Live API testing  
LIVE=true mix test

# Capability verification
test "provider supports streaming" do
  model = ReqLLM.Model.from!("anthropic:claude-3-sonnet")
  assert ReqLLM.Model.supports?(model, :streaming)
end
```

## Data Structures

**ReqLLM.Context**: Collection of messages with enumeration support
**ReqLLM.Message**: Role-based messages with multimodal ContentPart list
**ReqLLM.Message.ContentPart**: Typed union (text, image, tool_call, reasoning)
**ReqLLM.Model**: Provider configuration with metadata from models.dev
**ReqLLM.StreamChunk**: Unified streaming output format
**ReqLLM.Tool**: Vercel-style function definitions with NimbleOptions validation

## Supported Providers

**Current**: Anthropic (Claude 3 family)
**Planned**: OpenAI, Ollama, others via plugin architecture

New providers integrate through:
1. `ReqLLM.Provider` behavior implementation
2. `ReqLLM.Codec` protocol for format translation  
3. Models.dev metadata for capabilities

## Documentation

- [Getting Started](guides/getting-started.md) - Installation and first API calls
- [Core Concepts](guides/core-concepts.md) - Architecture and design principles  
- [API Reference](guides/api-reference.md) - Complete function reference
- [Data Structures](guides/data-structures.md) - Advanced usage patterns
- [Capability Testing](guides/capability-testing.md) - Testing and verification
- [Provider System](guides/adding_a_provider.md) - Creating new providers

## Development

```bash
# Quality checks
mix quality

# Test with fixtures
mix test

# Test against live APIs  
LIVE=true mix test

# Sync model metadata
mix req_llm.model_sync
```

## Features

- **Unified API**: Consistent interface across all providers
- **Plugin Architecture**: Provider logic as composable Req plugins
- **Type Safety**: TypedStruct definitions with NimbleOptions validation
- **Streaming Support**: Back-pressure aware lazy streams
- **Multimodal**: Text, images, files, reasoning content
- **Tool Calling**: Function calling with parameter validation
- **Cost Tracking**: Usage and cost extraction from responses
- **Metadata Integration**: Enhanced model data from models.dev
- **Secure Keys**: Kagi/JidoKeys integration for credential management
- **Capability Testing**: Live verification against advertised capabilities

Built for Elixir developers who need reliable, extensible AI integration without abstractions that obscure the underlying HTTP layer.
