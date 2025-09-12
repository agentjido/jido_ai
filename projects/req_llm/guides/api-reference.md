# API Reference

Complete reference for ReqLLM's public API. This library provides Vercel AI SDK-inspired functions with consistent signatures across streaming and non-streaming modes.

## Text Generation Functions

### generate_text/3

Generate text using the specified model and messages.

```elixir
@spec generate_text(model_spec, messages, opts) :: {:ok, Req.Response.t()} | {:error, term()}
```

**Parameters:**
- `model_spec` - Model specification (string, tuple, or struct)
- `messages` - Prompt string or list of Message structs
- `opts` - Generation options (keyword list)

**Examples:**
```elixir
# Simple text generation
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello world")
response.body  # => "Hello! How can I assist you today?"

# With options
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet", 
  "Write a haiku",
  temperature: 0.8,
  max_tokens: 100
)

# Complex conversation
messages = [
  ReqLLM.Context.system("You are a helpful assistant"),
  ReqLLM.Context.user("What's 2+2?")
]
{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", messages)
```

### generate_text!/3

Convenient variant that returns only the text content.

```elixir
@spec generate_text!(model_spec, messages, opts) :: {:ok, String.t()} | {:error, term()}
```

**Examples:**
```elixir
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello")
# text => "Hello! How can I assist you today?"
```

### stream_text/3

Stream text generation with the specified model.

```elixir
@spec stream_text(model_spec, messages, opts) :: {:ok, Req.Response.t()} | {:error, term()}
```

Returns a response where `response.body` is a lazy Stream of StreamChunk structs.

**Examples:**
```elixir
{:ok, response} = ReqLLM.stream_text("anthropic:claude-3-sonnet", "Tell me a story")

response.body
|> Stream.filter(&(&1.type == :text))
|> Stream.map(&(&1.text))
|> Enum.each(&IO.write/1)
```

### stream_text!/3

Convenient variant that returns only the stream.

```elixir
@spec stream_text!(model_spec, messages, opts) :: {:ok, Stream.t()} | {:error, term()}
```

**Examples:**
```elixir
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Count to 10")

stream
|> Stream.filter(&(&1.type == :text))
|> Stream.map(&(&1.text))
|> Enum.join()
```

## Embedding Functions

### embed/3

Generate a single embedding vector.

```elixir
@spec embed(model_spec, text, opts) :: {:ok, [float()]} | {:error, term()}
```

**Examples:**
```elixir
{:ok, embedding} = ReqLLM.embed("openai:text-embedding-3-small", "Hello world")
# embedding => [0.1234, -0.5678, ...]
```

### embed_many/3

Generate embeddings for multiple texts in a batch.

```elixir
@spec embed_many(model_spec, [text], opts) :: {:ok, [[float()]]} | {:error, term()}
```

**Examples:**
```elixir
texts = ["Hello", "World", "AI is amazing"]
{:ok, embeddings} = ReqLLM.embed_many("openai:text-embedding-3-small", texts)
# embeddings => [[0.1, 0.2], [0.3, 0.4], [0.5, 0.6]]
```

## Helper Functions

### with_usage/1

Extract usage metadata from API response.

```elixir
@spec with_usage({:ok, term()}) :: {:ok, term(), map()} | {:error, term()}
```

**Examples:**
```elixir
{:ok, text, usage} = 
  ReqLLM.generate_text("openai:gpt-4o", "Hello")
  |> ReqLLM.with_usage()

usage
#=> %{
#     tokens: %{input: 10, output: 15, total: 25},
#     cost: 0.00075
#   }
```

### with_cost/1

Extract only cost information from API response.

```elixir
@spec with_cost({:ok, term()}) :: {:ok, term(), float()} | {:error, term()}
```

**Examples:**
```elixir
{:ok, text, cost} = 
  ReqLLM.generate_text("openai:gpt-4o", "Hello")
  |> ReqLLM.with_cost()

cost #=> 0.00075
```

## Model Specification Formats

ReqLLM accepts flexible model specifications:

### String Format
```elixir
"provider:model"
"anthropic:claude-3-sonnet"
"openai:gpt-4o"
"ollama:llama3"
```

### Tuple Format
```elixir
{:anthropic, "claude-3-sonnet", temperature: 0.7}
{:openai, "gpt-4o", max_tokens: 1000}
```

### Struct Format
```elixir
%ReqLLM.Model{
  provider: :anthropic,
  model: "claude-3-sonnet", 
  temperature: 0.7,
  max_tokens: 1000
}
```

## Common Options

All generation functions accept these common options:

### Generation Parameters
- `:temperature` - Controls randomness (0.0 to 2.0)
- `:max_tokens` - Maximum tokens to generate
- `:top_p` - Nucleus sampling parameter
- `:top_k` - Top-k sampling parameter
- `:stop` - Stop sequences (string or list)

### System and Tools
- `:system_prompt` - System message for the model
- `:tools` - List of tool definitions for function calling
- `:tool_choice` - Tool selection strategy (`:auto`, `:required`, specific tool)

### Provider Options
- `:provider_options` - Provider-specific options map
- `:headers` - Additional HTTP headers
- `:timeout` - Request timeout in milliseconds

**Examples:**
```elixir
opts = [
  temperature: 0.8,
  max_tokens: 500,
  system_prompt: "You are a creative writer",
  tools: [weather_tool, calculator_tool],
  tool_choice: :auto,
  provider_options: %{
    "top_k" => 40,
    "repetition_penalty" => 1.1
  }
]

{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", "Write a story", opts)
```

## Error Handling

ReqLLM uses structured errors based on the Splode error system:

### Common Error Types
- `ReqLLM.Error.Invalid.Provider` - Unknown or unsupported provider
- `ReqLLM.Error.Invalid.Model` - Invalid model specification
- `ReqLLM.Error.API.Authentication` - Authentication failures
- `ReqLLM.Error.API.RateLimit` - Rate limiting errors
- `ReqLLM.Error.API.BadRequest` - Malformed requests

**Examples:**
```elixir
case ReqLLM.generate_text("invalid:model", "Hello") do
  {:ok, response} -> 
    handle_success(response)
    
  {:error, %ReqLLM.Error.Invalid.Provider{} = error} ->
    Logger.error("Unsupported provider: #{error.message}")
    
  {:error, %ReqLLM.Error.API.RateLimit{} = error} ->
    Logger.warn("Rate limited: #{error.message}")
    retry_after_delay()
    
  {:error, error} ->
    Logger.error("Generation failed: #{inspect(error)}")
end
```

## Advanced Usage

### Custom Request Configuration

Use `ReqLLM.attach/2` to build custom Req workflows:

```elixir
{:ok, configured_request} = 
  Req.new()
  |> ReqLLM.attach("anthropic:claude-3-sonnet")

# Add custom middleware
configured_request
|> Req.Request.append_request_steps(my_custom_step: &add_tracing/1)
|> Req.request(json: %{messages: messages})
```

### Tool Calling

Define tools for function calling:

```elixir
weather_tool = %ReqLLM.Tool{
  name: "get_weather",
  description: "Get current weather for a location",
  parameter_schema: [
    location: [type: :string, required: true],
    units: [type: :string, default: "metric"]
  ],
  callback: {WeatherAPI, :fetch_weather}
}

{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet",
  "What's the weather in Paris?",
  tools: [weather_tool]
)
```

### Multimodal Content

Handle images and files in conversations:

```elixir
import ReqLLM.Message.ContentPart

messages = [
  ReqLLM.Context.user([
    text("What's in this image?"),
    image_url("https://example.com/photo.jpg")
  ])
]

{:ok, response} = ReqLLM.generate_text("anthropic:claude-3-sonnet", messages)
```

## Provider-Specific Features

Some providers support additional capabilities:

### Anthropic Features
- Reasoning mode with `ContentPart.reasoning/1`
- PDF document processing
- Advanced tool calling patterns

### OpenAI Features  
- Vision capabilities with GPT-4 Vision models
- Structured output generation
- Custom fine-tuned models

### Local Providers (Ollama)
- Custom model paths
- Local file processing
- Hardware-specific optimizations

See [Provider System Guide](provider-system.md) for detailed provider capabilities.
