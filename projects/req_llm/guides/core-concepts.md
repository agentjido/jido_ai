# Core Concepts: ReqLLM Architecture Guide

ReqLLM provides a unified, composable interface to AI providers through a sophisticated plugin-based architecture. This guide explains the fundamental design patterns, data flow, and architectural principles that make ReqLLM both powerful and extensible.

## Overview: Plugin-Based Normalization

ReqLLM's core innovation is **plugin-based normalization** - a clean separation between HTTP transport concerns (handled by Req) and format translation concerns (handled by ReqLLM providers). This approach enables:

- **Unified Interface**: Work with any AI provider using the same API
- **HTTP Reuse**: Leverage Req's battle-tested HTTP infrastructure
- **Composability**: Insert custom middleware at any point in the request pipeline
- **Extensibility**: Add new providers with minimal code

```elixir
# Same interface across all providers
ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
ReqLLM.generate_text("openai:gpt-4", "Hello")
ReqLLM.generate_text("custom:my-model", "Hello")
```

## 1. Provider-Agnostic Data Model

ReqLLM defines a canonical data model that abstracts away provider differences while preserving rich functionality.

### Core Data Structures

```
ReqLLM.Model          # Model configuration with metadata
    ↓
ReqLLM.Context        # Collection of conversation messages  
    ↓
ReqLLM.Message        # Individual messages with typed content
    ↓
ReqLLM.Message.ContentPart  # Text, images, files, tool calls
    ↓
ReqLLM.StreamChunk    # Unified streaming response format
    ↓
ReqLLM.Tool           # Function definitions with validation
```

### Model Abstraction

Models encapsulate provider information, generation parameters, and capability metadata:

```elixir
%ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-5-sonnet",
  temperature: 0.7,
  max_tokens: 1000,
  
  # Capability metadata from models.dev
  capabilities: %{tool_call?: true, reasoning?: false},
  modalities: %{input: [:text, :image], output: [:text]},
  cost: %{input: 3.0, output: 15.0}
}
```

### Multimodal Content Support

`ContentPart` enables rich, multimodal conversations:

```elixir
message = %ReqLLM.Message{
  role: :user,
  content: [
    ContentPart.text("Analyze this image and document:"),
    ContentPart.image_url("https://example.com/chart.png"),
    ContentPart.file(pdf_data, "report.pdf", "application/pdf"),
    ContentPart.text("What insights do you see?")
  ]
}
```

### Unified Streaming Format

All providers produce standardized `StreamChunk` structures:

```elixir
# Text content
%StreamChunk{type: :content, text: "Hello there!"}

# Reasoning tokens (for supported models)
%StreamChunk{type: :thinking, text: "Let me consider..."}

# Tool calls
%StreamChunk{type: :tool_call, name: "get_weather", arguments: %{location: "NYC"}}

# Metadata
%StreamChunk{type: :meta, metadata: %{finish_reason: "stop"}}
```

## 2. Plugin-Based Architecture

Each AI provider is implemented as a Req plugin that handles format translation while delegating transport to Req.

### Provider as Plugin Pattern

```elixir
defmodule ReqLLM.Providers.Anthropic do
  @behaviour ReqLLM.Provider
  
  # Auto-loads metadata and registers with system
  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json"

  @impl ReqLLM.Provider
  def attach(request, model, opts \\ []) do
    # Configure HTTP request for Anthropic API
    request
    |> Req.Request.put_header("anthropic-version", "2023-06-01")
    |> Req.Request.put_header("x-api-key", get_api_key())
    |> Map.put(:body, encode_request(model, opts))
  end
  
  @impl ReqLLM.Provider
  def parse_response(response, model) do
    # Convert Anthropic response to ReqLLM chunks
    response.body
    |> decode_anthropic_format()
    |> convert_to_stream_chunks()
  end
end
```

### Request Flow Architecture

The complete request flow demonstrates clean separation of concerns:

```
User API Call
    ↓ ReqLLM.generate_text/3
Model Resolution
    ↓ ReqLLM.Model.from/1  
Provider Lookup
    ↓ ReqLLM.provider/1
Request Creation
    ↓ Req.new/1
Provider Attachment  
    ↓ ReqLLM.attach/2
HTTP Request
    ↓ Req.request/1
Provider Parsing
    ↓ provider.parse_response/2
Canonical Response
```

### Core Bridge: ReqLLM.attach/2

The `attach/2` function is the bridge between ReqLLM's abstractions and Req's HTTP pipeline:

```elixir
def attach(%Req.Request{} = request, model_spec) do
  with {:ok, model} <- ReqLLM.Model.from(model_spec),
       {:ok, provider_module} <- ReqLLM.provider(model.provider) do
    # Provider configures the HTTP request
    configured_request = provider_module.attach(request, model)
    {:ok, configured_request}
  end
end
```

This enables powerful composition:

```elixir
# Start with base request
request = Req.new()

# Add custom middleware
request = request
|> Req.Request.append_request_steps(log_request: &log_request/1)
|> Req.Request.append_response_steps(cache_response: &cache/1)

# Attach provider-specific configuration
{:ok, configured} = ReqLLM.attach(request, "anthropic:claude-3-sonnet")

# Execute with all middleware
{:ok, response} = Req.request(configured)
```

## 3. Codec Protocol for Format Translation

ReqLLM uses Elixir protocols to handle format translation between canonical structures and provider-specific APIs.

### Protocol Definition

```elixir
defprotocol ReqLLM.Codec do
  @doc "Encode canonical ReqLLM structures to provider JSON format"
  def encode(tagged_context)

  @doc "Decode provider response JSON to canonical StreamChunks"  
  def decode(tagged_response)
end
```

### Provider-Tagged Wrappers

Each provider defines a lightweight wrapper struct for protocol dispatch:

```elixir
defmodule ReqLLM.Providers.Anthropic do
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end

defimpl ReqLLM.Codec, for: ReqLLM.Providers.Anthropic do
  def encode(%ReqLLM.Providers.Anthropic{context: ctx}) do
    # Transform ReqLLM.Context → Anthropic Messages API format
    %{
      messages: format_messages(ctx),
      system: extract_system_prompt(ctx)
    }
  end
  
  def decode(%ReqLLM.Providers.Anthropic{context: response}) do
    # Transform Anthropic response → List of ReqLLM.StreamChunk
    response["content"]
    |> Enum.map(&convert_content_block/1)
    |> List.flatten()
  end
end
```

### Translation Flow

```
ReqLLM.Context (canonical)
    ↓ wrap_context/1
Provider.Tagged{context: ctx}
    ↓ Codec.encode/1  
Provider JSON (wire format)
    ↓ HTTP transport
Provider Response JSON
    ↓ wrap_response/1
Provider.Tagged{context: response}
    ↓ Codec.decode/1
List of ReqLLM.StreamChunk (canonical)
```

## 4. Req Integration and HTTP Capabilities

ReqLLM leverages Req's mature HTTP infrastructure rather than reimplementing transport concerns.

### Transport vs Format Separation

**Transport Layer (Handled by Req):**
- Connection management and pooling
- SSL/TLS handling
- Request/response lifecycle
- Compression and encoding
- Error handling and retries
- Streaming (Server-Sent Events)

**Format Layer (Handled by ReqLLM):**
- Model specification and validation
- Message format normalization
- Response standardization
- Tool calling abstraction
- Usage extraction and cost calculation
- Provider-specific error translation

### Middleware Composition

ReqLLM's plugin architecture enables seamless middleware composition:

```elixir
# Custom logging middleware
request = Req.new()
|> Req.Request.append_request_steps(log_request: fn req ->
  Logger.info("Calling #{req.url}")
  req
end)
|> Req.Request.append_response_steps(log_response: fn {req, resp} ->
  Logger.info("Response: #{resp.status}")
  {req, resp}
end)

# Add tracing
request = request
|> Req.Request.append_request_steps(trace_start: &start_trace/1)
|> Req.Request.append_response_steps(trace_end: &end_trace/1)

# Attach ReqLLM provider
{:ok, configured} = ReqLLM.attach(request, "anthropic:claude-3-sonnet")

# All middleware runs in order
{:ok, response} = Req.request(configured)
```

### Built-in ReqLLM Plugins

ReqLLM includes several HTTP-level plugins:

```elixir
# Usage tracking
request = ReqLLM.Plugins.Usage.attach(request, model)
# → Extracts token counts and costs

# Streaming support  
request = ReqLLM.Plugins.Stream.attach(request)
# → Processes Server-Sent Events

# Error handling
request = ReqLLM.Plugins.Splode.attach(request)  
# → Converts HTTP errors to ReqLLM.Error structs
```

## 5. Request/Response Flow

### Complete Generation Flow

Here's how a complete text generation request flows through the system:

```elixir
# 1. API call with model specification
ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello world")

# 2. Model resolution
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-sonnet")
#=> %ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet"}

# 3. Provider lookup  
{:ok, provider} = ReqLLM.provider(:anthropic)
#=> ReqLLM.Providers.Anthropic

# 4. Base request creation
request = Req.new(method: :post)

# 5. Provider attachment (format translation)
{:ok, configured} = ReqLLM.attach(request, model)
# Provider adds headers, authentication, request body

# 6. HTTP execution
{:ok, http_response} = Req.request(configured) 

# 7. Response parsing (format translation)
{:ok, chunks} = provider.parse_response(http_response, model)

# 8. Result processing
{:ok, final_text} = process_chunks(chunks)
```

### Streaming Flow

Streaming follows the same pattern with continuous chunk processing:

```elixir
{:ok, response} = ReqLLM.stream_text("anthropic:claude-3-sonnet", "Tell a story")

# Response contains a lazy stream
response.body
|> Stream.filter(&(&1.type == :content))  # Only content chunks
|> Stream.map(&(&1.text))                 # Extract text
|> Stream.each(&IO.write/1)               # Output incrementally
|> Stream.run()
```

## 6. Benefits of This Architecture

### 1. Composability and Extensibility

**Easy Provider Addition:**
```elixir
defmodule ReqLLM.Providers.CustomProvider do
  use ReqLLM.Provider.DSL,
    id: :custom,
    base_url: "https://api.custom.com"
    
  def attach(request, model), do: configure_request(request, model)
  def parse_response(response, model), do: parse_custom_format(response)
end
```

**Middleware Integration:**
```elixir
# Existing Req middleware works seamlessly
ReqLLM.generate_text("custom:my-model", "Hello", 
  retry: [max_retries: 3, delay: 100]
)
```

### 2. Separation of Concerns

- **HTTP Transport**: Connection management, retries, headers
- **Format Translation**: Provider-specific API handling
- **Core Logic**: Business logic works with canonical structures
- **Testing**: Mock at HTTP level or format level independently

### 3. Reusability

ReqLLM doesn't reimplement HTTP concerns:

- Connection pooling from Finch
- SSL/TLS from Erlang/OTP
- Streaming from Req
- Error handling from existing patterns

### 4. Testability

The architecture enables comprehensive testing:

```elixir
# Test format translation in isolation
test "anthropic codec encodes tool calls" do
  context = ReqLLM.Context.new([...])
  tagged = %ReqLLM.Providers.Anthropic{context: context}
  
  encoded = ReqLLM.Codec.encode(tagged)
  assert encoded["messages"] |> hd() |> get_in(["content", "type"]) == "tool_use"
end

# Test complete integration with HTTP mocking
test "full generation flow" do
  use_fixture :anthropic, "basic_generation", fn ->
    {:ok, response} = ReqLLM.generate_text("anthropic:claude-3-haiku", "Hello")
    assert response =~ "Hello"
  end
end
```

### 5. Observability

Standard Req patterns enable rich observability:

```elixir
# Request/response logging
request = Req.new()
|> ReqLLM.Middleware.RequestLogger.attach()
|> ReqLLM.Middleware.ResponseLogger.attach()

# Distributed tracing
request = request
|> ReqLLM.Middleware.Tracing.attach(trace_id: "req_123")

# Metrics collection
request = request  
|> ReqLLM.Middleware.Metrics.attach()
```

## Summary

ReqLLM's architecture achieves a clean separation between transport and format concerns through:

- **Provider-agnostic data model** that works across all AI providers
- **Plugin-based normalization** where each provider handles only format translation
- **Codec protocol system** for efficient, type-safe format conversion
- **Req integration** that leverages mature HTTP infrastructure
- **Composable middleware** enabling custom logging, caching, tracing
- **Unified streaming** with standardized chunk formats

This design provides immediate productivity for simple use cases while maintaining extensibility for complex applications, making ReqLLM both powerful and approachable for Elixir developers building AI-powered applications.
