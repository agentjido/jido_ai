# ReqLLM Codec System: Format Translation Architecture

The ReqLLM.Codec protocol provides a clean abstraction layer that isolates provider-specific format conversion from transport concerns. This enables clean separation between data translation and HTTP request/response handling, allowing each provider to implement its own format conversion logic while maintaining a unified interface.

## Core Concepts

### 1. The ReqLLM.Codec Protocol

The codec protocol defines two primary operations:

- **`encode/1`**: Transform canonical ReqLLM structures → Provider-specific JSON
- **`decode/1`**: Transform provider response JSON → List of ReqLLM.StreamChunk structs

```elixir
defprotocol ReqLLM.Codec do
  @doc "Encode canonical ReqLLM structures to provider wire JSON format"
  def encode(tagged_context)

  @doc "Decode provider wire JSON back to canonical structures"  
  def decode(tagged_data)
end
```

### 2. Provider-Tagged Wrapper Structs

The codec system uses provider-specific "tagged" structs to enable protocol dispatch. Each provider defines a lightweight wrapper struct that holds the data to be transformed:

```elixir
# Anthropic's tagged wrapper
defmodule ReqLLM.Providers.Anthropic do
  defstruct [:context]
  
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
end
```

This tagging approach allows Elixir's protocol system to dispatch to the correct implementation based on the struct type, ensuring each provider's codec handles only its own format requirements.

### 3. Canonical Structures ↔ Provider JSON Flow

```
ReqLLM.Context (canonical)
         ↓ encode/1
Provider JSON (wire format)
         ↓ HTTP transport
Provider Response JSON
         ↓ decode/1  
List of ReqLLM.StreamChunk (canonical)
```

## Implementation Details

### Encode: Canonical → Provider Format

The encode function takes a provider-tagged wrapper containing a `ReqLLM.Context` and transforms it to the provider's expected JSON structure:

```elixir
defimpl ReqLLM.Codec, for: ReqLLM.Providers.Anthropic do
  def encode(%ReqLLM.Providers.Anthropic{context: ctx}) do
    {system_prompt, regular_messages} = extract_system_message(ctx)

    %{
      messages: Enum.map(regular_messages, &encode_message/1)
    }
    |> maybe_put_system(system_prompt)
  end

  defp encode_message(%ReqLLM.Message{role: role, content: parts}) do
    %{
      role: Atom.to_string(role),
      content: Enum.map(parts, &encode_content_part/1)
    }
  end
end
```

### Decode: Provider Response → StreamChunks

The decode function transforms provider response JSON into standardized StreamChunk structs:

```elixir
def decode(%ReqLLM.Providers.Anthropic{context: %{"content" => content}}) do
  content
  |> Enum.map(&decode_content_block/1)
  |> List.flatten()
  |> Enum.reject(&is_nil/1)
end

defp decode_content_block(%{"type" => "text", "text" => text}) do
  [ReqLLM.StreamChunk.text(text)]
end

defp decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
  [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
end
```

## Usage in Request/Response Flow

### 1. Outbound Request Encoding

During request preparation, the provider uses the codec to transform the canonical context:

```elixir
# In provider's attach/3 callback
def attach(request, %ReqLLM.Model{} = model, opts) do
  ctx = ReqLLM.Context.wrap(opts[:context] || default_ctx(request.body), model)
  
  # Use codec to transform canonical context to provider JSON
  body =
    ctx
    |> wrap_context()  # Wrap in provider-tagged struct
    |> ReqLLM.Codec.encode()  # Transform to provider format
    |> Map.merge(model_params(model, opts))
  
  request
  |> Map.put(:body, Jason.encode!(body))
end
```

### 2. Inbound Response Decoding

When processing responses, the codec transforms provider JSON back to canonical structures:

```elixir
# In provider's parse_response/2 callback
def parse_response(%Req.Response{status: 200, body: body}, _model) do
  chunks = 
    body
    |> wrap_response()  # Wrap in provider-tagged struct  
    |> ReqLLM.Codec.decode()  # Transform to StreamChunks
    
  {:ok, chunks}
end
```

## Content Type Handling

The codec system handles multiple content types seamlessly:

### Text Content

```elixir
# Encoding
defp encode_content_part(%ReqLLM.Message.ContentPart{type: :text, text: text}) do
  %{"type" => "text", "text" => text}
end

# Decoding  
defp decode_content_block(%{"type" => "text", "text" => text}) do
  [ReqLLM.StreamChunk.text(text)]
end
```

### Image Content

```elixir
# Encoding
defp encode_content_part(%ReqLLM.Message.ContentPart{
       type: :image, 
       data: data, 
       media_type: type
     }) do
  %{
    "type" => "image",
    "source" => %{
      "type" => "base64",
      "media_type" => type,
      "data" => data
    }
  }
end
```

### Tool Calls

```elixir
# Encoding
defp encode_content_part(%ReqLLM.Message.ContentPart{
       type: :tool_call,
       tool_name: name,
       input: input, 
       tool_call_id: id
     }) do
  %{
    "type" => "tool_use",
    "id" => id,
    "name" => name,
    "input" => input
  }
end

# Decoding
defp decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) do
  [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
end
```

## Fallback Implementation

The codec protocol includes a fallback implementation for unsupported types:

```elixir
defimpl ReqLLM.Codec, for: Any do
  @doc """
  Default implementation for unsupported provider combinations.
  Returns an error indicating that no codec implementation exists.
  """
  def encode(_), do: {:error, :not_implemented}
  def decode(_), do: {:error, :not_implemented}
end
```

This ensures graceful failure when:
- Attempting to use an unsupported provider
- A provider hasn't implemented the codec protocol
- Invalid data structures are passed to codec functions

## Provider Implementation Pattern

When implementing a new provider, follow this pattern:

### 1. Define the Tagged Wrapper Struct

```elixir
defmodule ReqLLM.Providers.NewProvider do
  @behaviour ReqLLM.Provider
  
  defstruct [:context]
  @type t :: %__MODULE__{context: ReqLLM.Context.t()}
  
  @spec new(ReqLLM.Context.t()) :: t()
  def new(context), do: %__MODULE__{context: context}
  
  @impl ReqLLM.Provider
  def wrap_context(%ReqLLM.Context{} = ctx) do
    %__MODULE__{context: ctx}
  end
end
```

### 2. Implement the Codec Protocol

```elixir
defimpl ReqLLM.Codec, for: ReqLLM.Providers.NewProvider do
  def encode(%ReqLLM.Providers.NewProvider{context: ctx}) do
    # Transform ReqLLM.Context to provider JSON format
    %{
      # Provider-specific JSON structure
    }
  end

  def decode(%ReqLLM.Providers.NewProvider{context: response_data}) do
    # Transform provider response to ReqLLM.StreamChunk list
    response_data
    |> extract_content()
    |> Enum.map(&to_stream_chunk/1)
    |> List.flatten()
  end
end
```

### 3. Use in Provider Callbacks

```elixir
# In attach/3 - encoding requests
body = 
  ctx
  |> wrap_context()
  |> ReqLLM.Codec.encode()

# In parse_response/2 - decoding responses  
chunks = 
  response_body
  |> new()
  |> ReqLLM.Codec.decode()
```

## Benefits of the Codec System

### 1. Clean Separation of Concerns

- **Transport layer**: Handles HTTP requests, headers, authentication
- **Translation layer**: Handles format conversion between canonical and provider-specific formats
- **Core logic**: Works with canonical structures throughout

### 2. Provider Isolation

Each provider's format quirks are contained within its codec implementation:

- Anthropic's system message handling
- OpenAI's choice structure
- Provider-specific content type mappings
- Custom streaming formats

### 3. Protocol Dispatch Efficiency

Elixir's protocol system provides compile-time dispatch based on struct type, ensuring:

- Zero runtime overhead for provider selection  
- Compile-time verification of codec implementations
- Clear error messages for missing implementations

### 4. Extensibility

Adding new content types or provider features only requires:

- Extending the canonical structures (if needed)
- Updating the relevant codec implementations
- No changes to transport or core logic

### 5. Testing Benefits

The codec system enables focused unit testing:

```elixir
test "encodes tool_call content parts" do
  tool_part = ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})
  message = %Message{role: :assistant, content: [tool_part]}
  context = Context.new([message])

  tagged = %ReqLLM.Providers.Anthropic{context: context}
  encoded = Codec.encode(tagged)

  message = hd(encoded.messages)
  content = hd(message.content)

  assert content["type"] == "tool_use"
  assert content["id"] == "call_123"
  assert content["name"] == "get_weather"
  assert content["input"] == %{location: "NYC"}
end
```

## Best Practices

### 1. Handle Unknown Content Types Gracefully

```elixir
defp decode_content_block(_unknown), do: []
```

### 2. Validate Required Fields

```elixir
defp decode_content_block(%{"type" => "tool_use", "id" => id, "name" => name, "input" => input}) 
  when is_binary(id) and is_binary(name) do
  [ReqLLM.StreamChunk.tool_call(name, input, %{id: id})]
end

defp decode_content_block(%{"type" => "tool_use"}), do: []  # Missing required fields
```

### 3. Preserve Content Ordering

When encoding/decoding mixed content, maintain the original order:

```elixir
def encode(%Provider{context: ctx}) do
  %{
    messages: Enum.map(ctx.messages, fn msg ->
      %{
        role: to_string(msg.role),
        content: Enum.map(msg.content, &encode_content_part/1)  # Preserves order
      }
    end)
  }
end
```

### 4. Use Structured Error Returns

```elixir
def encode(%Provider{context: %{invalid: true}}) do
  {:error, :invalid_context}
end
```

The ReqLLM.Codec system provides a robust, extensible foundation for handling the format translation challenges inherent in multi-provider AI systems, while maintaining clean architectural separation and enabling comprehensive testing strategies.
