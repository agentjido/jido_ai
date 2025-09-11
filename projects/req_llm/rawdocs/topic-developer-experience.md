# Developer Experience Guide

ReqLLM is designed with developer productivity and ease of adoption as core principles. This guide covers the developer-friendly features that make the library intuitive to use and extend.

## Flexible Model Specification

ReqLLM supports multiple formats for specifying models, allowing developers to choose the approach that best fits their workflow:

### String Format (Simplest)
```elixir
# Quick and simple for common models
ReqLLM.generate_text("gpt-4", messages)
ReqLLM.generate_text("claude-3-5-sonnet-20241022", messages)
```

### Tuple Format (Provider + Model)
```elixir
# Explicit provider specification
ReqLLM.generate_text({"anthropic", "claude-3-5-sonnet-20241022"}, messages)
ReqLLM.generate_text({"openai", "gpt-4"}, messages)
```

### Struct Format (Full Control)
```elixir
# Complete specification with custom settings
model = %ReqLLM.Model{
  provider: "anthropic",
  name: "claude-3-5-sonnet-20241022",
  max_tokens: 8192,
  temperature: 0.7
}

ReqLLM.generate_text(model, messages)
```

The library automatically resolves and validates model specifications, providing helpful error messages when models are not found or incorrectly specified.

## Secure Key Management

ReqLLM integrates with multiple key management systems to keep credentials secure and configuration simple.

### JidoKeys Integration
```elixir
# Automatic key resolution from JidoKeys
config :req_llm,
  key_resolver: ReqLLM.KeyResolver.JidoKeys

# Keys are automatically fetched and cached
ReqLLM.generate_text("gpt-4", messages)
# No need to manually configure API keys
```

### Kagi Integration
```elixir
# Universal key management through Kagi
config :req_llm,
  key_resolver: ReqLLM.KeyResolver.Kagi,
  kagi_session: "your-session-token"

# All provider keys managed centrally
```

### Environment Variables (Fallback)
```elixir
# Traditional environment variable support
# OPENAI_API_KEY, ANTHROPIC_API_KEY, etc.
```

## Models.dev Integration

ReqLLM automatically syncs with Models.dev for up-to-date model metadata and pricing information.

### Automatic Model Discovery
```elixir
# Models are automatically discovered and validated
# Mix task syncs metadata regularly
mix req_llm.sync_models

# Check available models
mix req_llm.models --provider anthropic
```

### Rich Model Metadata
```elixir
# Access comprehensive model information
model = ReqLLM.Model.from("gpt-4")
model.max_tokens        # 8192
model.context_window    # 128000
model.pricing.input     # Cost per token
model.capabilities      # [:text, :json, :tools]
```

### Automatic Updates
```elixir
# Background sync keeps models current
config :req_llm,
  auto_sync_models: true,
  sync_interval: :timer.hours(24)
```

## Consistent API Patterns

ReqLLM provides a unified interface across all providers with consistent function signatures and behavior.

### Generate Text
```elixir
# Consistent signature across all providers
{:ok, response} = ReqLLM.generate_text(model, messages, opts \\ [])

# Same options work everywhere
opts = [
  temperature: 0.7,
  max_tokens: 1000,
  stop: ["\n\n"]
]
```

### Stream Text
```elixir
# Streaming with the same signature
{:ok, stream} = ReqLLM.stream_text(model, messages, opts \\ [])

# Process chunks uniformly
stream
|> Stream.each(fn chunk -> IO.write(chunk.content) end)
|> Stream.run()
```

### Generate Objects
```elixir
# Structured output with JSON schema
schema = %{
  type: "object",
  properties: %{
    summary: %{type: "string"},
    sentiment: %{type: "string", enum: ["positive", "negative", "neutral"]}
  }
}

{:ok, object} = ReqLLM.generate_object(model, messages, schema, opts)
```

## Human-Readable Error System

ReqLLM uses Splode to provide structured, informative error messages that help developers quickly identify and fix issues.

### API Errors
```elixir
case ReqLLM.generate_text("invalid-model", messages) do
  {:error, %ReqLLM.Error.API{} = error} ->
    # error.message: "Model 'invalid-model' not found. Available models: gpt-4, gpt-3.5-turbo"
    # error.provider: "openai"
    # error.status_code: 404
end
```

### Authentication Errors
```elixir
{:error, %ReqLLM.Error.Auth{} = error} ->
  # error.message: "Invalid API key for provider 'anthropic'. Check your ANTHROPIC_API_KEY environment variable."
  # error.provider: "anthropic"
```

### Parse Errors
```elixir
{:error, %ReqLLM.Error.Parse{} = error} ->
  # error.message: "Failed to parse JSON response: unexpected token at line 3"
  # error.raw_response: "invalid json..."
```

### Validation Errors
```elixir
{:error, %ReqLLM.Error.Validation{} = error} ->
  # error.message: "Temperature must be between 0.0 and 2.0, got 3.5"
  # error.field: :temperature
  # error.value: 3.5
```

## Streaming-First Philosophy

ReqLLM is designed around streaming by default, with back-pressure preservation and memory efficiency.

### Lazy Streams
```elixir
# Streams are lazy and memory-efficient
{:ok, stream} = ReqLLM.stream_text(model, messages)

# Process chunks as they arrive
stream
|> Stream.take_while(fn chunk -> not chunk.stop end)
|> Stream.map(&process_chunk/1)
|> Enum.to_list()
```

### Back-Pressure Preservation
```elixir
# Streams respect GenStage back-pressure
stream
|> Flow.from_enumerable(stages: 2)
|> Flow.map(&expensive_processing/1)
|> Flow.run()
```

### Easy Conversion to Text
```elixir
# Simple conversion when you need the full response
{:ok, stream} = ReqLLM.stream_text(model, messages)
text = ReqLLM.Stream.to_text(stream)
```

### Streaming with Function Calls
```elixir
# Tool calls are streamed incrementally
tools = [%{name: "search", description: "Search the web"}]
{:ok, stream} = ReqLLM.stream_text(model, messages, tools: tools)

stream
|> Stream.each(fn
  %{tool_calls: calls} when calls != [] ->
    # Handle tool calls as they're streamed
    handle_tool_calls(calls)
  %{content: content} when content != "" ->
    IO.write(content)
  _ ->
    :ok
end)
|> Stream.run()
```

## Developer CLI and Mix Tasks

ReqLLM includes comprehensive Mix tasks for development and testing workflows.

### Model Management
```bash
# Sync models from Models.dev
mix req_llm.sync_models

# List available models
mix req_llm.models
mix req_llm.models --provider anthropic
mix req_llm.models --capability tools

# Show model details
mix req_llm.model gpt-4
```

### Interactive Testing
```bash
# Interactive chat session
mix req_llm.chat gpt-4

# Test with specific prompts
mix req_llm.generate "Explain quantum computing" --model claude-3-5-sonnet

# Test streaming
mix req_llm.stream "Write a story" --model gpt-4

# Test structured output
mix req_llm.object "Analyze sentiment" --schema sentiment.json --model gpt-4
```

### Provider Testing
```bash
# Test provider connectivity
mix req_llm.test_providers

# Validate API keys
mix req_llm.validate_keys

# Run provider benchmarks
mix req_llm.benchmark --models "gpt-4,claude-3-5-sonnet"
```

### Development Helpers
```bash
# Generate provider scaffolding
mix req_llm.gen.provider MyProvider

# Validate provider implementation
mix req_llm.validate_provider MyProvider

# Test custom models
mix req_llm.test_model my-custom-model
```

## Plugin Architecture

ReqLLM's plugin system makes it easy to add new providers and extend functionality.

### Simple Provider Creation
```elixir
defmodule MyProvider do
  use ReqLLM.Provider.DSL

  @impl ReqLLM.Plugin
  def attach(request, _opts) do
    request
    |> Req.merge(base_url: "https://api.myprovider.com")
    |> Req.Request.register_options([:api_key, :temperature])
  end

  @impl ReqLLM.Plugin  
  def parse(response, _opts) do
    # Transform provider response to ReqLLM format
    {:ok, %ReqLLM.Response{...}}
  end
end
```

### Provider Registration
```elixir
# Providers auto-register via DSL
config :req_llm,
  providers: [MyProvider]

# Or register manually
ReqLLM.register_provider(MyProvider)
```

## Testing Support

ReqLLM includes comprehensive testing utilities for applications using the library.

### Mock Responses
```elixir
# Easy response mocking
ReqLLM.Test.mock_response("gpt-4", %ReqLLM.Response{
  content: "Mocked response",
  usage: %{prompt_tokens: 10, completion_tokens: 5}
})

# Test your functions
assert {:ok, response} = MyApp.chat_with_ai("Hello")
assert response.content == "Mocked response"
```

### Stream Testing
```elixir
# Mock streaming responses
chunks = [
  %{content: "Hello", delta: true},
  %{content: " world", delta: true},
  %{content: "", finish_reason: "stop", delta: false}
]

ReqLLM.Test.mock_stream("gpt-4", chunks)
```

### Provider Testing
```elixir
# Test custom providers
ReqLLM.Test.test_provider(MyProvider, [
  model: "my-model",
  api_key: "test-key"
])
```

This developer-focused design makes ReqLLM easy to adopt incrementally, extend with custom providers, and integrate into existing Elixir applications with minimal configuration overhead.
