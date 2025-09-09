# ReqLLM

A clean, composable Elixir library for AI interactions built on Req, following [Vercel AI SDK](https://ai-sdk.dev/docs/reference/ai-sdk-core) patterns.

ReqLLM provides a unified interface to AI providers through a plugin-based architecture that leverages Req's HTTP client capabilities.

## Features

- **Unified API**: Consistent interface across all AI providers
- **Plugin Architecture**: Clean separation of provider logic using Req plugins
- **Vercel AI SDK Alignment**: Familiar patterns for JavaScript developers
- **Streaming Support**: Real-time text generation with `ReqLLM.stream_text/3`
- **Tool Calling**: Function calling capabilities across providers
- **Multi-modal**: Support for text, images, and structured data
- **Type Safety**: Comprehensive NimbleOptions validation and TypedStruct definitions
- **Model Metadata**: Rich model information from models.dev integration

## Installation

Add `req_llm` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:req_llm, "~> 0.1.0"}
  ]
end
```

## Quick Start

### Basic Text Generation

```elixir
# Simple text generation
model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
{:ok, response} = ReqLLM.generate_text(model, "Hello, how are you?")
IO.puts(response) # "Hello! I'm doing well, thank you for asking..."

# With options
{:ok, response} = ReqLLM.generate_text(
  model, 
  "Write a short poem", 
  temperature: 0.8, 
  max_tokens: 200
)
```

### Streaming Text Generation

```elixir
model = ReqLLM.Model.from("anthropic:claude-3-sonnet-20241022")
{:ok, stream} = ReqLLM.stream_text(model, "Tell me a story about AI", stream: true)

stream
|> Stream.each(fn chunk ->
  case chunk do
    %ReqLLM.StreamChunk{type: :text, content: text} -> 
      IO.write(text)
    %ReqLLM.StreamChunk{type: :meta, data: %{finish_reason: reason}} -> 
      IO.puts("\n[Finished: #{reason}]")
    _ -> 
      :ok
  end
end)
|> Stream.run()
```

## ReqLLM.attach/2 - The Core Plugin API

ReqLLM uses a composable plugin architecture where each provider is a Req plugin:

```elixir
# Create a base request
request = Req.Request.new(method: :post, url: "/messages")

# Attach provider-specific configuration  
model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
configured_request = ReqLLM.attach(request, model)

# Execute the request
{:ok, response} = Req.request(configured_request)

# Parse the response using the provider's parser
{:ok, result} = ReqLLM.Providers.Anthropic.parse(response, model)
```

This plugin approach enables:
- **Composability**: Mix and match different provider capabilities
- **Transparency**: Full control over HTTP requests and responses  
- **Extensibility**: Easy to add custom request/response middleware
- **Testing**: Mock any part of the request/response cycle

## Provider Plugin Architecture

### Basic Provider Implementation

Each provider implements the `ReqLLM.Plugin` behavior:

```elixir
defmodule MyProvider do
  use ReqLLM.Provider.DSL,
    id: :my_provider,
    base_url: "https://api.myprovider.com/v1",
    auth: {:header, "authorization", :bearer},
    metadata: "priv/models_dev/my_provider.json"

  @impl ReqLLM.Plugin
  def attach(request, %ReqLLM.Model{} = model) do
    api_key = ReqLLM.get_key(:my_provider_api_key)
    
    %{request |
      headers: [
        {"authorization", "Bearer #{api_key}"},
        {"content-type", "application/json"}
        | request.headers
      ],
      base_url: default_base_url(),
      body: build_request_body(model)
    }
  end

  @impl ReqLLM.Plugin
  def parse(response, %ReqLLM.Model{} = _model) do
    case response.body do
      %{"content" => content} -> {:ok, extract_text(content)}
      %{"error" => error} -> {:error, ReqLLM.Error.api_error(error)}
      _ -> {:error, ReqLLM.Error.parse_error("Invalid response")}
    end
  end

  # Private helper functions...
end
```

### Provider DSL Features

The `ReqLLM.Provider.DSL` macro automatically handles:

- **Plugin Registration**: Auto-registers with `ReqLLM.Provider.Registry`
- **Metadata Loading**: Loads model data from JSON files at compile time
- **Base URL Configuration**: Provides `default_base_url/0` callback
- **Error Handling**: Structured error types using Splode

## Advanced Usage

### Tool Calling

```elixir
# Define tools with NimbleOptions schemas
weather_tool = %ReqLLM.Tool{
  name: "get_weather",
  description: "Get weather for a location",
  parameters_schema: NimbleOptions.new!(
    location: [type: :string, required: true],
    unit: [type: {:in, ["celsius", "fahrenheit"]}, default: "celsius"]
  )
}

model = ReqLLM.Model.from("anthropic:claude-3-sonnet-20241022")
{:ok, response} = ReqLLM.generate_text(
  model, 
  "What's the weather in San Francisco?", 
  tools: [weather_tool]
)

# Response contains tool calls that can be executed
```

### Structured Data Generation

```elixir
# Define output schema
person_schema = NimbleOptions.new!(
  name: [type: :string, required: true],
  age: [type: :integer, required: true],
  interests: [type: {:list, :string}, default: []]
)

model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
{:ok, person} = ReqLLM.generate_object(
  model,
  "Create a person profile for a software engineer",
  schema: person_schema
)

# person = %{name: "Alex Chen", age: 32, interests: ["programming", "AI", "music"]}
```

### Multi-modal Inputs

```elixir
# Image and text input
image_part = ReqLLM.Message.ContentPart.image("/path/to/image.jpg")
text_part = ReqLLM.Message.ContentPart.text("What's in this image?")

message = ReqLLM.Message.user([image_part, text_part])
model = ReqLLM.Model.from("anthropic:claude-3-sonnet-20241022")

{:ok, response} = ReqLLM.generate_text(model, [message])
```

## Model Specification Formats

ReqLLM supports three flexible formats for specifying models:

### String Format (Simple)
```elixir
"anthropic:claude-3-haiku-20240307"
"anthropic:claude-3-sonnet-20241022"
```

### Tuple Format (With Options)
```elixir
{:anthropic, "claude-3-sonnet-20241022", temperature: 0.7, max_tokens: 1000}
```

### Model Struct Format (Full Control)
```elixir
%ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-sonnet-20241022",
  temperature: 0.7,
  max_tokens: 1000,
  metadata: %{...}  # Enhanced with models.dev data
}
```

## Configuration

### Environment Variables

Set your API keys via environment variables:

```bash
export ANTHROPIC_API_KEY="your-anthropic-key-here"
```

### Application Configuration

Configure providers in your application config:

```elixir
config :req_llm,
  default_provider: :anthropic,
  default_model: "claude-3-haiku-20240307",
  request_timeout: 30_000
```

## Supported Providers

### Anthropic Claude
- **Models**: Claude 3 family (Haiku, Sonnet, Opus)
- **Features**: Text generation, streaming, tool calling, multi-modal
- **API Key**: `ANTHROPIC_API_KEY`

```elixir
model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
```

*Additional providers (OpenAI, etc.) can be easily added using the plugin architecture.*

## Error Handling

ReqLLM uses structured error handling with Splode:

```elixir
case ReqLLM.generate_text(model, "Hello") do
  {:ok, response} -> 
    IO.puts("Success: #{response}")
    
  {:error, %ReqLLM.Error.API.Response{reason: reason}} ->
    IO.puts("API Error: #{reason}")
    
  {:error, %ReqLLM.Error.Parse{reason: reason}} ->
    IO.puts("Parse Error: #{reason}")
    
  {:error, %ReqLLM.Error.Auth{reason: reason}} ->
    IO.puts("Auth Error: #{reason}")
end
```

## Testing

ReqLLM includes comprehensive testing utilities:

```elixir
# Test provider plugins directly
test "anthropic provider attaches correct headers" do
  model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
  request = Req.Request.new()
  
  result = ReqLLM.Providers.Anthropic.attach(request, model)
  
  assert {"x-api-key", _} = List.keyfind(result.headers, "x-api-key", 0)
end

# Test capability verification
test "provider supports text generation" do
  model = ReqLLM.Model.from("anthropic:claude-3-haiku-20240307")
  assert ReqLLM.Capability.supports?(model, :text_generation)
end
```

## Architecture Benefits

ReqLLM's plugin architecture provides several advantages:

1. **Separation of Concerns**: Core logic separate from provider-specific code
2. **Composability**: Mix different providers and capabilities  
3. **Testability**: Easy to mock and test individual components
4. **Extensibility**: Add new providers without changing core code
5. **Transparency**: Full access to HTTP requests and responses
6. **Performance**: Minimal overhead with compile-time optimizations

## Comparison to Other Libraries

ReqLLM focuses on simplicity and composability compared to more complex alternatives:

- **vs jido_ai**: Simpler provider system, fewer abstractions, more direct implementations
- **vs OpenAI libraries**: Provider-agnostic, unified interface across vendors
- **vs Custom solutions**: Type-safe, well-tested, following established patterns

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Add comprehensive tests for your changes
4. Ensure `mix quality` passes (formatting, dialyzer, tests)
5. Commit your changes (`git commit -am 'Add amazing feature'`)
6. Push to the branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Vercel AI SDK Compatibility

ReqLLM closely follows the Vercel AI SDK patterns:

| Vercel AI SDK | ReqLLM Equivalent |
|---------------|-------------------|
| `generateText()` | `ReqLLM.generate_text/3` |
| `streamText()` | `ReqLLM.stream_text/3` |
| `generateObject()` | `ReqLLM.generate_object/4` |
| `embed()` | `ReqLLM.embed/3` |
| `tool()` | `%ReqLLM.Tool{}` struct |

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
