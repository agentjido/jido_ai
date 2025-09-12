# ReqLLM Usage Rules

This document provides best practices and guidelines for using ReqLLM effectively in Elixir applications.

## Core Purpose and Scope

ReqLLM is a composable library for AI interactions that normalizes LLM provider differences through a plugin-based architecture. It treats each provider as a Req plugin, handling format translation via a Codec protocol while leveraging Req's HTTP infrastructure.

Key concepts:
- **Provider Plugins**: Each AI provider (Anthropic, OpenAI) is a Req plugin
- **Codec Protocol**: Translates between canonical structures and provider-specific formats
- **Model Specifications**: Flexible ways to specify models (string, tuple, struct)
- **StreamChunks**: Unified output format across all providers
- **Context/Message/ContentPart**: Provider-agnostic conversation structures

## Essential Usage Guidelines

### Model Specifications

**Best Practice**: Start with string format and graduate to struct format as needed.

```elixir
# Simple - good for basic usage
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")

# Advanced - good for complex configurations  
model = %ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-sonnet", 
  temperature: 0.7,
  max_tokens: 1000
}
{:ok, response} = ReqLLM.generate_text(model, "Hello")
```

**Avoid**: Creating Model structs manually when string format suffices.

### API Function Selection

**Best Practice**: Use bang variants (`!`) for simple use cases, full functions for production.

```elixir
# Development/simple cases
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello")

# Production - need access to metadata, errors, usage data
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
{:ok, text, usage} = ReqLLM.with_usage({:ok, response})
```

**Avoid**: Using bang variants when you need detailed error handling or usage tracking.

### Context and Message Construction

**Best Practice**: Import context helpers for clean message building.

```elixir
import ReqLLM.Context

context = Context.new([
  system("You are a helpful assistant"),
  user("What's 2+2?")
])

{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", context)
```

**Avoid**: Manually constructing Message structs when helpers exist.

```elixir
# Avoid this verbose approach
messages = [
  %ReqLLM.Message{
    role: :system,
    content: [%ReqLLM.Message.ContentPart{type: :text, text: "You are helpful"}]
  }
]
```

### Multimodal Content

**Best Practice**: Import ContentPart helpers for clean multimodal handling.

```elixir
import ReqLLM.Message.ContentPart

message = ReqLLM.Context.user([
  text("Analyze this image"),
  image_url("https://example.com/chart.png")
])

{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", [message])
```

**Important**: Always validate image URLs/data before passing to ContentPart functions.

### Streaming

**Best Practice**: Filter StreamChunks by type for clean processing.

```elixir
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Tell a story")

# Collect only text content
text = stream
|> Stream.filter(&(&1.type == :text))
|> Stream.map(&(&1.text))
|> Enum.join()

# Handle different chunk types  
stream
|> Enum.each(fn chunk ->
  case chunk.type do
    :text -> IO.write(chunk.text)
    :tool_call -> handle_tool_call(chunk)
    :meta -> handle_metadata(chunk)
    _ -> :ok
  end
end)
```

**Avoid**: Assuming all chunks contain text data without checking the type.

### Error Handling

**Best Practice**: Pattern match on specific error types for appropriate handling.

```elixir
case ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello") do
  {:ok, response} -> 
    handle_success(response)
    
  {:error, %ReqLLM.Error.Invalid.Provider{}} ->
    Logger.error("Unsupported provider")
    {:error, :unsupported_provider}
    
  {:error, %ReqLLM.Error.API.RateLimit{retry_after: seconds}} ->
    Logger.warn("Rate limited, retry after #{seconds}s")
    :timer.sleep(seconds * 1000)
    retry_request()
    
  {:error, %ReqLLM.Error.API.Authentication{}} ->
    Logger.error("Authentication failed - check API key")
    {:error, :auth_failed}
    
  {:error, error} ->
    Logger.error("Unexpected error: #{inspect(error)}")
    {:error, :unknown}
end
```

## Configuration and Setup

### Key Management

**Important**: Use ReqLLM's key management instead of direct environment variables.

```elixir
# Preferred - uses Kagi keyring integration
ReqLLM.put_key("anthropic_api_key", System.get_env("ANTHROPIC_API_KEY"))
ReqLLM.put_key("openai_api_key", System.get_env("OPENAI_API_KEY"))

# Providers automatically retrieve keys
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")
```

**Avoid**: Direct environment variable access in provider code.

### Application Startup

**Important**: Initialize keys during application startup.

```elixir
# In your application.ex start/2 function
def start(_type, _args) do
  # Initialize API keys
  setup_llm_keys()
  
  children = [
    # ... other children
  ]
  
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end

defp setup_llm_keys do
  if api_key = System.get_env("ANTHROPIC_API_KEY") do
    ReqLLM.put_key("anthropic_api_key", api_key)
  end
  
  if api_key = System.get_env("OPENAI_API_KEY") do
    ReqLLM.put_key("openai_api_key", api_key)  
  end
end
```

## Tool Calling

### Tool Definition

**Best Practice**: Define tools with comprehensive parameter schemas.

```elixir
weather_tool = ReqLLM.Tool.new!(
  name: "get_weather", 
  description: "Get current weather for a location",
  parameter_schema: [
    location: [type: :string, required: true, doc: "City name"],
    units: [type: :string, default: "celsius", doc: "Temperature units"]
  ],
  callback: {WeatherAPI, :fetch_weather}
)
```

**Important**: Tool names must be valid identifiers (alphanumeric + underscores, start with letter).

**Avoid**: Tools without proper parameter validation or unclear descriptions.

### Tool Execution

**Best Practice**: Handle tool execution errors gracefully.

```elixir
defmodule WeatherAPI do
  def fetch_weather(%{location: location, units: units}) do
    case HTTPClient.get("/weather", location: location, units: units) do
      {:ok, %{status: 200, body: data}} ->
        {:ok, data}
        
      {:ok, %{status: 404}} ->
        {:error, "Location not found"}
        
      {:error, reason} ->
        {:error, "Weather service unavailable: #{inspect(reason)}"}
    end
  rescue
    error ->
      {:error, "Weather fetch failed: #{Exception.message(error)}"}
  end
end
```

## Testing, Fixtures & Live Mode

### Fixture vs Live Testing

ReqLLM records all successful HTTP interactions into deterministic JSON fixtures so the default `mix test` run is fast, offline and free. When you need fresh ground-truth data, turn on live mode.

**Best Practice**: Use fixtures for CI, live testing for capability verification.

```bash
# Default – use cached fixtures
mix test

# Regenerate or create new fixtures
LIVE=true mix test                   # all providers
FIXTURE_FILTER=openai LIVE=true mix test  # single provider

# CI uses cached fixtures by default; live runs can be scheduled nightly.
```

### Using ReqLLM.Test.LiveFixture

- `use ReqLLM.Test.LiveFixture, provider: :anthropic` injects `use_fixture/3`
- `use_fixture(name, opts \\ [], fun)` returns the *value* your anonymous function produced but transparently stores/reads the HTTP transcript
- By convention, `name` mirrors the `describe` title in snake-case
- When `LIVE=true` the first live call's response is written; subsequent tests in the same run read the just-written file to avoid double billing
- Fixtures are stored under `test/fixtures/#{provider}/#{name}.json`
- NEVER commit new fixtures that include secrets; the helper automatically strips auth headers, but review before committing

```elixir
defmodule CoreTest do
  use ReqLLM.Test.LiveFixture, provider: :openai
  use ExUnit.Case, async: true

  describe "generate_text/3" do
    test "basic happy-path" do
      {:ok, text} =
        use_fixture("core-basic") do
          ReqLLM.generate_text!("openai:gpt-4o", "Hello!")
        end

      assert text =~ "Hello"
    end
  end
end
```

**Test Structure**: Organize tests by capability, not just function.

```elixir
defmodule StreamingTest do
  use ReqLLM.Test.LiveFixture, provider: :anthropic
  use ExUnit.Case, async: true

  describe "stream_text/3" do
    test "returns :text chunks" do
      stream =
        use_fixture("streaming-basic") do
          {:ok, s} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Count to 3")
          s
        end

      assert Enum.any?(stream, &(&1.type == :text))
    end
  end
end
```

### Capability Testing

**Best Practice**: Test against advertised capabilities.

```elixir
test "provider supports advertised capabilities" do
  model = ReqLLM.Model.from!("anthropic:claude-3-sonnet")
  
  # Test capabilities match metadata
  assert model.capabilities.tool_call? == true
  assert model.capabilities.reasoning? == true
  
  # Verify actual functionality
  {:ok, _} = ReqLLM.generate_text(model, "Hello", tools: [simple_tool()])
end
```

**Q: Why not mock everything?**  
A: Recorded fixtures give us realistic provider semantics, enforce backwards-compat with the vendor and make refactors measurable.

## Advanced Usage Patterns

### Custom Req Middleware

**Best Practice**: Use `ReqLLM.attach/2` for custom request pipelines.

```elixir
defp add_request_tracing(request) do
  request_id = UUID.uuid4()
  
  %{request | 
    headers: [{"x-request-id", request_id} | request.headers],
    private: Map.put(request.private, :trace_id, request_id)
  }
end

def traced_generate_text(model_spec, messages, opts \\ []) do
  with {:ok, configured_request} <- 
    Req.new()
    |> ReqLLM.attach(model_spec)
    |> Req.Request.append_request_steps(tracing: &add_request_tracing/1) do
    
    # Execute with custom middleware
    Req.request(configured_request)
  end
end
```

### Usage Monitoring

**Best Practice**: Extract and log usage data for monitoring.

```elixir
def monitored_generation(model_spec, messages, opts \\ []) do
  start_time = System.monotonic_time()
  
  result = ReqLLM.generate_text(model_spec, messages, opts)
  
  case ReqLLM.with_usage(result) do
    {:ok, text, usage} ->
      duration = System.monotonic_time() - start_time
      
      Logger.info("LLM Generation", [
        model: inspect(model_spec),
        tokens: usage.tokens,
        cost: usage.cost,
        duration_ms: System.convert_time_unit(duration, :native, :millisecond)
      ])
      
      {:ok, text}
      
    {:error, error} ->
      Logger.error("LLM Generation failed: #{inspect(error)}")
      {:error, error}
  end
end
```

## Performance Considerations

### Batch Operations

**Best Practice**: Use batch operations for embeddings when possible.

```elixir
# Efficient - single API call
texts = ["Hello", "World", "AI is amazing"]
{:ok, embeddings} = ReqLLM.embed_many("openai:text-embedding-3-small", texts)

# Avoid - multiple API calls
embeddings = Enum.map(texts, fn text ->
  {:ok, embedding} = ReqLLM.embed("openai:text-embedding-3-small", text)
  embedding
end)
```

### Connection Reuse

**Important**: ReqLLM leverages Req's connection pooling automatically. Avoid creating new clients per request.

### Memory Management

**Best Practice**: Process streams incrementally for large responses.

```elixir
# Memory efficient
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Write a long story")

stream
|> Stream.filter(&(&1.type == :text))
|> Stream.chunk_every(100)  # Process in chunks
|> Stream.each(&process_chunk/1)
|> Stream.run()
```

## Common Pitfalls and Solutions

### 1. Model Specification Errors

**Problem**: Using unsupported model names or invalid provider IDs.

**Solution**: Use `ReqLLM.Model.from/1` to validate specifications early.

```elixir
case ReqLLM.Model.from("invalid:model") do
  {:ok, model} -> proceed_with_model(model)
  {:error, error} -> 
    Logger.error("Invalid model spec: #{inspect(error)}")
    use_fallback_model()
end
```

### 2. Content Type Mismatches  

**Problem**: Passing wrong content types to ContentPart functions.

**Solution**: Validate content before creating ContentPart structs.

```elixir
def safe_image_content(url) when is_binary(url) do
  if String.starts_with?(url, ["http://", "https://"]) do
    {:ok, ReqLLM.Message.ContentPart.image_url(url)}
  else
    {:error, "Invalid image URL"}
  end
end
```

### 3. Stream Processing Issues

**Problem**: Assuming all stream chunks contain text data.

**Solution**: Always filter by chunk type before processing.

```elixir
# Safe stream processing
text_chunks = stream
|> Stream.filter(fn chunk -> chunk.type == :text and chunk.text != nil end)
|> Stream.map(&(&1.text))
```

### 4. Tool Parameter Validation

**Problem**: Tool callbacks receiving unexpected parameter formats.

**Solution**: Use comprehensive parameter schemas with proper validation.

```elixir
# Comprehensive tool schema
parameter_schema: [
  location: [
    type: :string, 
    required: true,
    doc: "City name or coordinates"
  ],
  units: [
    type: {:in, ["celsius", "fahrenheit"]}, 
    default: "celsius"
  ],
  include_forecast: [
    type: :boolean, 
    default: false
  ]
]
```

This usage rules document should be included in your Hex package by adding it to the `files` list in `mix.exs`.
