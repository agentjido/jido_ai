# Core Concepts

ReqLLM = Req (HTTP) + Provider Plugins (format) + Canonical Data Model

## Data Model

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

### Multimodal Content

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

### Unified Streaming

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

## Plugin Architecture

Provider = module that implements ReqLLM.Provider and a Codec.

```elixir
defmodule ReqLLM.Providers.Anthropic do
  use ReqLLM.Provider.DSL,
    id: :anthropic,
    base_url: "https://api.anthropic.com/v1",
    metadata: "priv/models_dev/anthropic.json"

  def attach(req, model, _opts),  do: encode_request(req, model)
  def parse_response(resp, model), do: decode_response(resp, model)
end
```

### Request Flow

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

### Composable Middleware

```elixir
request = Req.new()
|> Req.Request.append_request_steps(log_request: &log_request/1)
|> Req.Request.append_response_steps(cache_response: &cache/1)

{:ok, configured} = ReqLLM.attach(request, "anthropic:claude-3-sonnet")
{:ok, response} = Req.request(configured)
```

## Codec Protocol

Format translation between canonical structures and provider APIs.

```elixir
defprotocol ReqLLM.Codec do
  def encode(tagged_context)
  def decode(tagged_response)
end
```

### Provider Implementation

```elixir
defmodule ReqLLM.Providers.Anthropic do
  defstruct [:context]
end

defimpl ReqLLM.Codec, for: ReqLLM.Providers.Anthropic do
  def encode(%ReqLLM.Providers.Anthropic{context: ctx}) do
    %{
      messages: format_messages(ctx),
      system: extract_system_prompt(ctx)
    }
  end
  
  def decode(%ReqLLM.Providers.Anthropic{context: response}) do
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

## Req Integration

Transport vs Format separation:

**Transport (Req):**
- Connection pooling
- SSL/TLS 
- Streaming (SSE)
- Retries & error handling

**Format (ReqLLM):**
- Model validation
- Message normalization  
- Response standardization
- Usage extraction

### Generation Flow

```elixir
# API call
ReqLLM.generate_text("anthropic:claude-3-sonnet", "Hello")

# Model resolution  
{:ok, model} = ReqLLM.Model.from("anthropic:claude-3-sonnet")

# Provider lookup
{:ok, provider} = ReqLLM.provider(:anthropic)

# Request creation & attachment
{:ok, configured} = ReqLLM.attach(Req.new(), model)

# HTTP execution
{:ok, http_response} = Req.request(configured) 

# Response parsing
{:ok, chunks} = provider.parse_response(http_response, model)
```

### Streaming Flow

```elixir
{:ok, response} = ReqLLM.stream_text("anthropic:claude-3-sonnet", "Tell a story")

response.body
|> Stream.filter(&(&1.type == :content))
|> Stream.map(&(&1.text))
|> Stream.each(&IO.write/1)
|> Stream.run()
```

## Provider System

### Creating Providers

```elixir
defmodule ReqLLM.Providers.CustomProvider do
  use ReqLLM.Provider.DSL,
    id: :custom,
    base_url: "https://api.custom.com"
    
  def attach(request, model), do: configure_request(request, model)
  def parse_response(response, model), do: parse_custom_format(response)
end
```

### Integration Points

1. `ReqLLM.Provider` behavior implementation
2. `ReqLLM.Codec` protocol for format translation  
3. Models.dev metadata for capabilities

## Testing

The architecture enables testing at multiple levels:

```elixir
# Format translation in isolation
test "anthropic codec encodes tool calls" do
  context = ReqLLM.Context.new([...])
  tagged = %ReqLLM.Providers.Anthropic{context: context}
  
  encoded = ReqLLM.Codec.encode(tagged)
  assert encoded["messages"] |> hd() |> get_in(["content", "type"]) == "tool_use"
end

# Complete integration with fixtures
test "full generation flow" do
  use_fixture :anthropic, "basic_generation", fn ->
    {:ok, response} = ReqLLM.generate_text("anthropic:claude-3-haiku", "Hello")
    assert response =~ "Hello"
  end
end
```

## Observability

Standard Req middleware enables monitoring:

```elixir
request = Req.new()
|> ReqLLM.Middleware.RequestLogger.attach()
|> ReqLLM.Middleware.ResponseLogger.attach()
|> ReqLLM.Middleware.Tracing.attach(trace_id: "req_123")
|> ReqLLM.Middleware.Metrics.attach()
```
