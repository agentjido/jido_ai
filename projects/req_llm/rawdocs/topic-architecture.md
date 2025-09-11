# ReqLLM Architecture: Plugin-Based LLM Normalization

ReqLLM provides a unified interface to AI providers by leveraging Req's plugin system for HTTP request normalization. Rather than reimplementing HTTP concerns, ReqLLM focuses on format translation while delegating transport to Req's mature HTTP infrastructure.

## Core Architectural Pattern

### Plugin-Based Normalization Approach

ReqLLM's architecture centers on **plugin-based normalization** - each AI provider is implemented as a Req plugin that handles:

1. **Request Preparation**: Converting ReqLLM abstractions to provider-specific HTTP requests
2. **Response Interpretation**: Converting provider responses back to ReqLLM abstractions
3. **Format Translation**: Bridging ReqLLM's unified interface with provider-specific APIs

This approach provides several key advantages:

- **Separation of Concerns**: Transport (HTTP) vs Format (API schemas)
- **Composability**: Users can insert additional Req middleware seamlessly
- **Reusability**: Leverages Req's battle-tested HTTP handling
- **Extensibility**: Easy to add new providers or middleware

### Every Provider is a Req Plugin

Each AI provider in ReqLLM implements the `ReqLLM.Provider` behavior and functions as a Req plugin:

```elixir
defmodule ReqLLM.Providers.Anthropic do
  @behaviour ReqLLM.Provider
  
  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json"

  @impl ReqLLM.Provider
  def attach(request, model, opts \\ []) do
    # Configure request for Anthropic API
    request
    |> add_authentication_headers()
    |> set_anthropic_specific_headers()
    |> prepare_messages_format()
    |> configure_streaming()
  end
  
  @impl ReqLLM.Provider
  def parse_response(response, model) do
    # Convert Anthropic response to ReqLLM chunks
  end
end
```

The `ReqLLM.Provider.DSL` macro automatically handles:
- Plugin registration with the provider registry
- Metadata loading from JSON files
- Base URL configuration
- Default plugin behavior setup

## Request Flow Architecture

The complete request flow demonstrates how ReqLLM orchestrates the plugin system:

### 1. Entry Point: High-Level API

```elixir
ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello world")
```

### 2. Flow: Req.Request → ReqLLM.attach/2 → Req Pipeline

The flow follows this sequence:

```
User Call → ReqLLM.Generation → Model Resolution → Provider Attachment → Req Pipeline → Provider Callbacks
```

**Step-by-step breakdown:**

1. **ReqLLM.Generation.generate_text/3**:
   ```elixir
   def generate_text(model_spec, messages, opts) do
     with {:ok, model} <- Model.from(model_spec),                    # Parse model spec
          {:ok, provider_module} <- ReqLLM.provider(model.provider), # Get provider
          request = Req.new(method: :post, body: prepare_body(...)), # Create base request
          {:ok, configured_request} <- ReqLLM.attach(request, model),# Attach provider
          {:ok, response} <- Req.request(configured_request),        # Execute request
          {:ok, chunks} <- provider_module.parse_response(response, model) do
       {:ok, process_chunks(chunks)}
     end
   end
   ```

2. **ReqLLM.attach/2** - The Core Bridge:
   ```elixir
   def attach(%Req.Request{} = request, model_spec) do
     with {:ok, model} <- ReqLLM.Model.from(model_spec),
          {:ok, provider_module} <- ReqLLM.Provider.Registry.get_provider(model.provider) do
       configured_request = provider_module.attach(request, model)
       {:ok, configured_request}
     end
   end
   ```

3. **Provider.attach/3** - Request Configuration:
   ```elixir
   def attach(request, %ReqLLM.Model{} = model, opts) do
     request
     |> Req.Request.put_header("x-api-key", get_api_key())
     |> Req.Request.put_header("content-type", "application/json")
     |> Req.Request.merge_options(base_url: default_base_url())
     |> Map.put(:body, encode_request_body(model, opts))
     |> maybe_install_streaming_steps(opts[:stream])
   end
   ```

4. **Req Pipeline Execution**:
   ```elixir
   {:ok, response} = Req.request(configured_request)
   ```

5. **Provider Response Parsing**:
   ```elixir
   {:ok, chunks} = provider_module.parse_response(response, model)
   ```

### 3. Provider Callbacks in Detail

Each provider implements these key callbacks:

**Request Phase:**
- `attach(request, model, opts)` - Configure the HTTP request for the provider's API

**Response Phase:**
- `parse_response(response, model)` - Parse non-streaming responses into `ReqLLM.StreamChunk` format
- `parse_stream(response, model)` - Parse streaming responses into lazy `Stream` of chunks
- `extract_usage(response, model)` - Extract token usage and cost information

**Context Wrapping:**
- `wrap_context(context)` - Wrap `ReqLLM.Context` for protocol-based encoding/decoding

## Transport vs Format Separation

ReqLLM achieves clean separation between transport and format concerns:

### Transport Layer (Handled by Req)

Req handles all HTTP transport concerns:
- **Connection Management**: Keep-alive, connection pooling
- **Request/Response Lifecycle**: Headers, body encoding, compression
- **Error Handling**: Network failures, timeouts, retries  
- **Streaming**: Server-Sent Events, chunked transfer encoding
- **Authentication**: Bearer tokens, custom headers
- **Middleware**: Logging, caching, request/response transformation

### Format Layer (Handled by ReqLLM)

ReqLLM focuses purely on format translation:
- **Model Abstraction**: Unified model specification across providers
- **Message Normalization**: Common message format for all providers
- **Response Standardization**: All responses converted to `StreamChunk` format
- **Tool Calling**: Unified tool definition and invocation
- **Usage Extraction**: Standardized token counting and cost calculation
- **Error Translation**: Provider errors converted to `ReqLLM.Error` types

### Protocol-Based Codec System

ReqLLM uses protocols for format translation:

```elixir
defprotocol ReqLLM.Codec do
  @doc "Encode ReqLLM context to provider format"
  def encode(wrapped_context)
  
  @doc "Decode provider response to ReqLLM chunks"  
  def decode(provider_response)
end

defimpl ReqLLM.Codec, for: ReqLLM.Providers.Anthropic do
  def encode(%{context: context}) do
    # Convert ReqLLM.Context to Anthropic Messages API format
    %{
      messages: context |> ReqLLM.Context.to_list() |> format_messages(),
      system: extract_system_prompt(context)
    }
  end
  
  def decode(anthropic_response) do
    # Convert Anthropic response to ReqLLM.StreamChunk list
    anthropic_response["content"]
    |> Enum.map(&convert_content_block/1)
  end
end
```

## Req Middleware Integration

The plugin architecture enables seamless integration with additional Req middleware:

### Built-in ReqLLM Plugins

ReqLLM includes several built-in plugins that extend Req's capabilities:

1. **Usage Plugin** (`ReqLLM.Plugins.Usage`):
   ```elixir
   req
   |> ReqLLM.Plugins.Usage.attach(model)
   # Extracts token usage and costs, stores in response.private[:req_llm][:usage]
   ```

2. **Stream Plugin** (`ReqLLM.Plugins.Stream`):
   ```elixir
   req
   |> ReqLLM.Plugins.Stream.attach()
   # Processes Server-Sent Events into enumerable chunks
   ```

3. **Error Plugin** (`ReqLLM.Plugins.Splode`):
   ```elixir
   req
   |> ReqLLM.Plugins.Splode.attach()
   # Converts HTTP errors to structured ReqLLM.Error exceptions
   ```

### User-Insertable Middleware

Users can insert additional Req middleware at any point:

```elixir
# Add logging middleware
request = Req.new()
|> Req.Request.append_request_steps(log_request: &log_request/1)
|> Req.Request.append_response_steps(log_response: &log_response/1)

# Add caching middleware  
request = request
|> Req.Request.append_response_steps(cache_response: &cache_response/1)

# Add tracing middleware
request = request
|> Req.Request.append_request_steps(trace_start: &start_trace/1)
|> Req.Request.append_response_steps(trace_end: &end_trace/1)

# Attach provider and execute
{:ok, configured_request} = ReqLLM.attach(request, "anthropic:claude-3-sonnet")
{:ok, response} = Req.request(configured_request)
```

### Plugin Installation Patterns

ReqLLM plugins follow standard Req patterns for middleware installation:

**Response Processing:**
```elixir
def attach(req) do
  Req.Request.append_response_steps(req, 
    token_usage: &__MODULE__.handle/1
  )
end
```

**Error Handling:**
```elixir
def attach(req) do
  Req.Request.append_error_steps(req,
    splode_errors: &handle_error_response/1  
  )
end
```

**Request Transformation:**
```elixir
def attach(req, model) do
  req
  |> Req.Request.put_header("authorization", "Bearer #{token}")
  |> Req.Request.put_base_url("https://api.provider.com")
  |> Map.put(:body, encode_body(model))
end
```

## Benefits of This Architecture

### 1. Composability
Users can compose functionality by mixing ReqLLM providers with standard Req middleware:
- Add retry logic with `Req.Steps.retry`
- Insert custom logging with `append_request_steps`
- Cache responses with custom caching middleware

### 2. Reusability
ReqLLM doesn't reimplement HTTP functionality:
- Connection pooling comes from Req/Finch
- SSL/TLS handling is delegated to lower layers
- Request/response formatting uses proven patterns

### 3. Extensibility
Adding new providers requires minimal code:
- Implement the `ReqLLM.Provider` behavior
- Use `ReqLLM.Provider.DSL` for boilerplate
- Focus on format translation, not HTTP transport

### 4. Testability
The architecture enables comprehensive testing:
- Mock HTTP responses at the Req level
- Test format translation separately from transport
- Unit test provider callbacks in isolation

### 5. Observability
Standard Req middleware patterns enable:
- Request/response logging
- Distributed tracing integration
- Metrics collection at HTTP and semantic levels
- Usage tracking and cost analysis

## Summary

ReqLLM's plugin-based architecture provides a clean separation between HTTP transport (handled by Req) and API format translation (handled by ReqLLM providers). This approach:

- **Leverages Req's HTTP capabilities** rather than reimplementing them
- **Enables seamless middleware composition** for logging, caching, and tracing
- **Simplifies provider implementation** by focusing on format concerns
- **Provides consistent interfaces** while supporting provider-specific features
- **Maintains extensibility** for new providers and middleware integration

The result is a composable, maintainable system that provides unified AI provider access while preserving the flexibility to customize HTTP behavior through Req's mature plugin ecosystem.
