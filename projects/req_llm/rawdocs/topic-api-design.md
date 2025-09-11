# API Design: Clean Abstraction with Extensibility

This document covers ReqLLM's top-level API design, inspired by the Vercel AI SDK, providing a unified interface to AI providers while maintaining extensibility through a plugin-based architecture.

## Design Philosophy

ReqLLM follows several key principles:

1. **Vercel AI SDK Inspiration**: Clean, predictable APIs that follow established patterns
2. **Dual Return Modes**: Full response metadata vs. convenient result-only variants  
3. **Consistent Signatures**: Streaming and non-streaming functions share identical parameters
4. **Pipeline-Friendly**: Helper functions designed for easy composition
5. **Provider Abstraction**: Unified interface hiding provider-specific differences

## Top-Level API Structure

The main API facade (`ReqLLM`) provides a unified interface across all AI operations:

### Text Generation Family

```elixir
# Full response with metadata
{:ok, %Req.Response{}} = ReqLLM.generate_text(model_spec, messages, opts)

# Convenient text-only result  
{:ok, text} = ReqLLM.generate_text!(model_spec, messages, opts)

# Streaming with metadata
{:ok, %Req.Response{body: stream}} = ReqLLM.stream_text(model_spec, messages, opts)

# Convenient stream-only result
{:ok, stream} = ReqLLM.stream_text!(model_spec, messages, opts)
```

### Embedding Family

```elixir
# Single embedding
{:ok, embedding} = ReqLLM.embed(model_spec, text, opts)

# Batch embeddings
{:ok, embeddings} = ReqLLM.embed_many(model_spec, texts, opts)
```

## Bang (!) Variants: Unwrapping Results

The API provides two patterns for each operation:

### Regular Functions (Full Response)
- Return complete `Req.Response` objects
- Include usage data, headers, metadata
- Enable access to provider-specific information
- Support debugging and monitoring

```elixir
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
response.body        # => "Hello! How can I assist you today?"
response.headers     # => Provider-specific headers
response.status      # => HTTP status
```

### Bang Variants (Unwrapped Results)
- Extract core content from responses
- Simplify common usage patterns  
- Maintain same error handling (`{:ok, result}` / `{:error, reason}`)
- Perfect for straightforward use cases

```elixir
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello")
# text => "Hello! How can I assist you today?"
```

## Consistent Function Signatures

All text generation functions share identical signatures, ensuring predictable behavior:

```elixir
# Pattern: function(model_spec, messages, opts)
ReqLLM.generate_text(model_spec, messages, opts)
ReqLLM.generate_text!(model_spec, messages, opts)  
ReqLLM.stream_text(model_spec, messages, opts)
ReqLLM.stream_text!(model_spec, messages, opts)
```

### Parameters

- **`model_spec`**: Flexible model specification
  - String: `"anthropic:claude-3-sonnet"`
  - Tuple: `{:anthropic, model: "claude-3-sonnet", temperature: 0.7}`
  - Struct: `%ReqLLM.Model{}`

- **`messages`**: Prompt or conversation
  - String: `"Hello world"`
  - Message list: `[%ReqLLM.Message{role: :user, content: "Hello"}]`

- **`opts`**: Consistent options across all functions
  - `:temperature`, `:max_tokens`, `:top_p`
  - `:tools`, `:tool_choice`
  - `:system_prompt`, `:provider_options`

## Helper Functions: Pipeline-Friendly Design

Helper functions are designed for pipeline composition, extracting specific metadata:

### with_usage/1
Extracts token usage and cost information:

```elixir
{:ok, text, usage} = 
  ReqLLM.generate_text("openai:gpt-4o", "Hello")
  |> ReqLLM.with_usage()

usage
#=> %{tokens: %{input: 10, output: 15}, cost: 0.00075}
```

### with_cost/1  
Extracts only cost information:

```elixir
{:ok, text, cost} =
  ReqLLM.generate_text("openai:gpt-4o", "Hello")  
  |> ReqLLM.with_cost()

cost #=> 0.00075
```

### Works with Both Patterns
Helper functions work with both full responses and bang variants:

```elixir
# With full response
{:ok, text, usage} = 
  ReqLLM.generate_text("openai:gpt-4o", "Hello")
  |> ReqLLM.with_usage()

# With bang variant (usage will be nil)
{:ok, text, usage} = 
  ReqLLM.generate_text!("openai:gpt-4o", "Hello")  
  |> ReqLLM.with_usage()
```

## Delegation Architecture

The top-level API acts as a facade, delegating to specialized modules:

### ReqLLM → ReqLLM.Generation
```elixir
# In ReqLLM module
defdelegate generate_text(model_spec, messages, opts \\ []), to: Generation
defdelegate generate_text!(model_spec, messages, opts \\ []), to: Generation
defdelegate stream_text(model_spec, messages, opts \\ []), to: Generation  
defdelegate stream_text!(model_spec, messages, opts \\ []), to: Generation
defdelegate with_usage(result), to: Generation
defdelegate with_cost(result), to: Generation
```

### ReqLLM → ReqLLM.Embedding
```elixir
defdelegate embed(model_spec, text, opts \\ []), to: Embedding
defdelegate embed_many(model_spec, texts, opts \\ []), to: Embedding
```

## Provider Resolution Flow

The API provides a clean abstraction over the provider resolution process:

### 1. Model Specification Parsing
```elixir
# ReqLLM.model/1 delegates to ReqLLM.Model.from/1
{:ok, model} = ReqLLM.model("anthropic:claude-3-sonnet")
#=> %ReqLLM.Model{provider: :anthropic, model: "claude-3-sonnet"}
```

### 2. Provider Lookup
```elixir
# ReqLLM.provider/1 delegates to Registry
{:ok, provider_module} = ReqLLM.provider(:anthropic)
#=> ReqLLM.Providers.Anthropic
```

### 3. Request Building with attach/2
```elixir
# Core infrastructure function
{:ok, configured_request} = ReqLLM.attach(request, model_spec)

# The attach function:
def attach(%Req.Request{} = request, model_spec) do
  with {:ok, model} <- ReqLLM.Model.from(model_spec),
       {:ok, provider_module} <- ReqLLM.Provider.Registry.get_provider(model.provider) do
    configured_request = provider_module.attach(request, model)
    {:ok, configured_request}
  end
end
```

### 4. Provider Plugin System
Each provider implements the `ReqLLM.Plugin` behavior:

```elixir
defmodule ReqLLM.Providers.Anthropic do
  @behaviour ReqLLM.Plugin
  
  # Configure request with provider-specific settings
  def attach(request, model) do
    request
    |> Req.Request.put_base_url("https://api.anthropic.com")
    |> Req.Request.put_header("anthropic-version", "2023-06-01")
    |> add_authentication()
  end
  
  # Parse provider-specific responses
  def parse(response) do
    # Transform provider response to ReqLLM format
  end
end
```

## Extensibility Through Abstraction

### Clean Provider Interface
The API hides provider differences behind a unified interface:

```elixir
# Same function call works across providers
ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
ReqLLM.generate_text("openai:gpt-4o", "Hello")
ReqLLM.generate_text("ollama:llama3", "Hello")
```

### Provider Registration
New providers integrate seamlessly through the registry:

```elixir
defmodule ReqLLM.Providers.CustomProvider do
  use ReqLLM.Provider.DSL

  provider :custom do
    base_url "https://api.custom.com"
    models ["custom-model-1", "custom-model-2"]
  end
  
  @behaviour ReqLLM.Plugin
  
  def attach(request, model), do: # ... configure request
  def parse(response), do: # ... parse response
end
```

### Configuration Management  
Unified configuration through keyring integration:

```elixir
# Store credentials securely
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
ReqLLM.put_key(:openai_api_key, "sk-...")

# Providers automatically retrieve credentials
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
```

## Vercel AI SDK Compatibility

ReqLLM provides equivalent functions for Vercel AI SDK patterns:

### Tool Definition
```elixir
# Equivalent to Vercel's tool() helper
weather_tool = ReqLLM.tool(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: [
    location: [type: :string, required: true],
    units: [type: :string, default: "metric"]
  ],
  callback: {WeatherAPI, :fetch_weather}
)
```

### Schema Creation
```elixir  
# Equivalent to Vercel's jsonSchema() helper
schema = ReqLLM.json_schema([
  name: [type: :string, required: true],
  age: [type: :integer, doc: "User age"]
])
```

### Embedding Utilities
```elixir
# Equivalent to Vercel's cosineSimilarity()
similarity = ReqLLM.cosine_similarity(embedding_a, embedding_b)
```

## Summary

ReqLLM's API design achieves clean abstraction through:

1. **Consistent dual patterns**: Full responses + convenient bang variants
2. **Unified signatures**: Same parameters across streaming/non-streaming 
3. **Pipeline-friendly helpers**: Extract metadata without breaking flow
4. **Delegation architecture**: Specialized modules handle implementation details
5. **Provider abstraction**: Plugin system hides provider differences  
6. **Extensible foundation**: Easy to add new providers and capabilities

This design provides immediate productivity for simple use cases while maintaining full access to advanced features and extensibility for complex applications.
