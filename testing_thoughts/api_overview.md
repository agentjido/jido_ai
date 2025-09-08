# ReqLLM API Overview: Vercel AI SDK Alignment with Elixir Idioms

## Executive Summary

ReqLLM provides a comprehensive Elixir implementation of the [Vercel AI SDK](https://ai-sdk.dev/docs/reference/ai-sdk-core) patterns, adapted for BEAM ecosystem conventions. The library maintains functional purity through tagged tuples, leverages TypedStruct for data integrity, and uses NimbleOptions for comprehensive validation throughout the API surface.

## 1. Core API Methods

### 1.1 Primary Functions (Vercel AI SDK Compatible)

| Vercel AI SDK | ReqLLM Equivalent | Return Type | Purpose |
|---------------|-------------------|-------------|---------|
| `generateText()` | `generate_text/3` | `{:ok, Req.Response.t()}` | Generate text with full response metadata |
| `streamText()` | `stream_text/3` | `{:ok, Req.Response.t()}` | Stream text with metadata access |
| `generateObject()` | `generate_object/4` | `{:ok, validated_map()}` | Generate structured data with schema validation |
| `streamObject()` | `stream_object/4` | `{:ok, Req.Response.t()}` | Stream validated structured objects |
| `embed()` | `embed/3` | `{:ok, [float()]}` | Generate single embedding vector |
| `embedMany()` | `embed_many/3` | `{:ok, [[float()]]}` | Generate batch embedding vectors |

### 1.2 Function Signatures

```elixir
# Core text generation
@spec generate_text(model_spec(), messages(), opts()) :: {:ok, Req.Response.t()} | {:error, term()}
@spec stream_text(model_spec(), messages(), opts()) :: {:ok, Req.Response.t()} | {:error, term()}

# Structured data generation  
@spec generate_object(model_spec(), messages(), schema(), opts()) :: {:ok, map()} | {:error, term()}
@spec stream_object(model_spec(), messages(), schema(), opts()) :: {:ok, Req.Response.t()} | {:error, term()}

# Embeddings
@spec embed(model_spec(), String.t(), opts()) :: {:ok, [float()]} | {:error, term()}
@spec embed_many(model_spec(), [String.t()], opts()) :: {:ok, [[float()]]} | {:error, term()}
```

### 1.3 Bang Variants (!) for Convenience

All primary functions have bang variants that extract results from response tuples:

```elixir
# Extract text content only (loses metadata)
@spec generate_text!(model_spec(), messages(), opts()) :: {:ok, String.t()} | {:error, term()}
@spec stream_text!(model_spec(), messages(), opts()) :: {:ok, Enumerable.t()} | {:error, term()}

# Usage examples
{:ok, text} = ReqLLM.generate_text!("openai:gpt-4", "Hello")
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", messages)
```

### 1.4 Response Modifier Pipeline Functions

```elixir
# Extract usage metadata (tokens, cost)
@spec with_usage(result_tuple()) :: {:ok, content(), usage_map() | nil} | {:error, term()}
@spec with_cost(result_tuple()) :: {:ok, content(), float() | nil} | {:error, term()}

# Pipeline usage examples
{:ok, text, usage} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_usage()
{:ok, text, cost} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_cost() 
{:ok, stream, usage} = ReqLLM.stream_text(model, messages) |> ReqLLM.with_usage()
```

### 1.5 Utility Functions (Vercel AI SDK Helpers)

```elixir
# Tool creation (equivalent to Vercel's tool() helper)
@spec tool(keyword()) :: {:ok, ReqLLM.Tool.t()} | {:error, term()}

# Schema creation (equivalent to Vercel's jsonSchema() helper)  
@spec json_schema(keyword(), keyword()) :: ReqLLM.ObjectSchema.t()

# Vector similarity calculation
@spec cosine_similarity([float()], [float()]) :: float()
```

## 2. Data Structures

### 2.1 ReqLLM.Model - AI Model Configuration

**TypedStruct Definition:**
```elixir
typedstruct enforce: true do
  # Required runtime fields
  field(:provider, atom(), enforce: true)           # :openai, :anthropic, etc.
  field(:model, String.t(), enforce: true)          # "gpt-4", "claude-3-sonnet" 
  field(:temperature, float() | nil)                # 0.0 to 2.0
  field(:max_tokens, non_neg_integer() | nil)
  field(:max_retries, non_neg_integer() | nil, default: 3)
  
  # Optional metadata fields
  field(:limit, limit() | nil)                      # %{context: int, output: int}
  field(:modalities, modalities() | nil)            # %{input: [modality], output: [modality]}
  field(:capabilities, capabilities() | nil)        # %{reasoning?: bool, tool_call?: bool}
  field(:cost, cost() | nil)                        # %{input: float, output: float}
end
```

**Model Specification Formats:**
1. **String**: `"openai:gpt-4"` → Auto-parsed with provider validation
2. **Tuple**: `{:openai, model: "gpt-4", temperature: 0.7}` → Runtime parameter override
3. **Struct**: `%ReqLLM.Model{provider: :openai, model: "gpt-4"}` → Full control

**Metadata Enhancement:**
```elixir
# Load with rich metadata from models_dev/*.json
{:ok, enhanced_model} = ReqLLM.Model.with_metadata("openai:gpt-4")
enhanced_model.capabilities #=> %{reasoning?: true, tool_call?: true}
enhanced_model.cost #=> %{input: 0.03, output: 0.06}  # per 1K tokens
```

### 2.2 ReqLLM.Message - Conversation Messages

**TypedStruct Definition:**
```elixir
typedstruct do
  field(:role, :user | :assistant | :system | :tool, enforce: true)
  field(:content, String.t() | [ContentPart.t()], enforce: true)
  field(:name, String.t() | nil)
  field(:tool_call_id, String.t() | nil)           # Required for :tool role
  field(:tool_calls, [map()] | nil)
  field(:metadata, map() | nil)                    # Provider-specific options
end
```

**Multi-modal Support:**
```elixir
# Simple text message
%ReqLLM.Message{role: :user, content: "Hello"}

# Multi-modal with text + image
%ReqLLM.Message{
  role: :user, 
  content: [
    %ReqLLM.ContentPart{type: :text, text: "Describe this:"},
    %ReqLLM.ContentPart{type: :image_url, url: "https://example.com/image.png"}
  ]
}

# Tool calling workflow
%ReqLLM.Message{
  role: :assistant,
  content: [
    %ReqLLM.ContentPart{type: :text, text: "I'll check the weather."},
    %ReqLLM.ContentPart{type: :tool_call, tool_call_id: "call_123", 
                        tool_name: "get_weather", input: %{location: "NYC"}}
  ]
}
```

**Builder Pattern API:**
```elixir
message = ReqLLM.Message.build()
  |> ReqLLM.Message.role(:user)
  |> ReqLLM.Message.text("Describe this image:")
  |> ReqLLM.Message.image_url("https://example.com/image.png")
  |> ReqLLM.Message.create!()
```

### 2.3 ReqLLM.Tool - Function Calling

**TypedStruct Definition:**
```elixir
typedstruct enforce: true do
  field(:name, String.t(), enforce: true)          # Valid identifier (alphanumeric + _)
  field(:description, String.t(), enforce: true)   # For AI model understanding
  field(:parameters, keyword() | nil, default: []) # NimbleOptions schema
  field(:callback, callback(), enforce: true)      # MFA tuple or function/1
  field(:schema, NimbleOptions.t() | nil)          # Compiled parameter schema
end
```

**Parameter Schema (NimbleOptions):**
```elixir
weather_tool = ReqLLM.Tool.new!(
  name: "get_weather",
  description: "Get current weather for a location",
  parameters: [
    location: [type: :string, required: true, doc: "City name"],
    units: [type: :string, default: "metric", doc: "Temperature units"],
    include_forecast: [type: :boolean, default: false, doc: "Include 5-day forecast"]
  ],
  callback: {WeatherAPI, :fetch_weather}
)
```

**Callback Formats:**
1. `{Module, :function}` → `Module.function(args)`
2. `{Module, :function, [:extra, :args]}` → `Module.function(:extra, :args, args)`  
3. `fn args -> {:ok, result} end` → Anonymous function

**JSON Schema Export:**
```elixir
json_schema = ReqLLM.Tool.to_json_schema(tool)
#=> %{
#     "type" => "function",
#     "function" => %{
#       "name" => "get_weather", 
#       "description" => "Get current weather for a location",
#       "parameters" => %{
#         "type" => "object",
#         "properties" => %{
#           "location" => %{"type" => "string", "description" => "City name"},
#           "units" => %{"type" => "string", "description" => "Temperature units"}
#         },
#         "required" => ["location"]
#       }
#     }
#   }
```

### 2.4 ReqLLM.ContentPart - Multi-modal Content

**TypedStruct Definition:**
```elixir
typedstruct do
  field(:type, :text | :image_url | :image | :file | :tool_call | :tool_result, enforce: true)
  
  # Text content
  field(:text, String.t() | nil)
  
  # Image/file content  
  field(:url, String.t() | nil)                    # For :image_url type
  field(:data, binary() | nil)                     # Binary data for :image/:file
  field(:media_type, String.t() | nil)             # MIME type
  field(:filename, String.t() | nil)               # For :file type
  
  # Tool calling content
  field(:tool_call_id, String.t() | nil)
  field(:tool_name, String.t() | nil)
  field(:input, map() | nil)                       # Tool call parameters
  field(:output, any() | nil)                      # Tool result data
  
  # Provider-specific metadata
  field(:metadata, map() | nil)
end
```

**Content Type Constructors:**
```elixir
# Text content
ReqLLM.ContentPart.text("Hello world")

# Image from URL
ReqLLM.ContentPart.image_url("https://example.com/image.png")

# Image from binary data
ReqLLM.ContentPart.image_data(image_binary, "image/png") 

# File attachment
ReqLLM.ContentPart.file(pdf_binary, "application/pdf", "document.pdf")

# Tool call
ReqLLM.ContentPart.tool_call("call_123", "get_weather", %{location: "NYC"})

# Tool result
ReqLLM.ContentPart.tool_result("call_123", "get_weather", %{temperature: 72})
```

## 3. Elixir Adaptations

### 3.1 Tagged Tuples vs Exceptions

**Vercel AI SDK (Exceptions):**
```javascript
try {
  const result = await generateText(model, messages);
  return result.text;
} catch (error) {
  console.error(error);
}
```

**ReqLLM (Tagged Tuples):**
```elixir
case ReqLLM.generate_text(model, messages) do
  {:ok, response} -> response.body
  {:error, error} -> Logger.error("Generation failed: #{inspect(error)}")
end

# Or with pipeline and bang operator for convenience
{:ok, text} = ReqLLM.generate_text!(model, messages)
```

### 3.2 NimbleOptions vs Zod Schemas

**Vercel AI SDK (Zod):**
```javascript
import { z } from 'zod';

const schema = z.object({
  name: z.string(),
  age: z.number().positive()
});
```

**ReqLLM (NimbleOptions):**
```elixir
schema = [
  name: [type: :string, required: true, doc: "User's full name"],
  age: [type: :pos_integer, required: true, doc: "User's age in years"]
]

# Validation with detailed error context
case NimbleOptions.validate(data, schema) do
  {:ok, validated_data} -> validated_data
  {:error, error} -> ReqLLM.Error.Validation.Error.exception(
    tag: :invalid_data,
    reason: Exception.message(error),
    context: [input: data]
  )
end
```

### 3.3 Stream Module vs Async Iterators

**Vercel AI SDK (Async Iterators):**
```javascript
const { textStream } = await streamText(model, messages);

for await (const textPart of textStream) {
  process.stdout.write(textPart);
}
```

**ReqLLM (Elixir Streams):**
```elixir
{:ok, response} = ReqLLM.stream_text(model, messages)

response.body
|> Stream.each(&IO.write/1)
|> Stream.run()

# Or collect all chunks
text_chunks = response.body |> Enum.to_list()
```

### 3.4 Response Metadata Access

**Vercel AI SDK (Direct Properties):**
```javascript
const { text, usage, finishReason } = await generateText(model, messages);
console.log(`Tokens used: ${usage.totalTokens}, Cost: ${usage.cost}`);
```

**ReqLLM (Response.private Access):**
```elixir
# Access via response.private[:req_llm]
{:ok, response} = ReqLLM.generate_text(model, messages)
usage = response.private[:req_llm][:usage]
Logger.info("Tokens: #{usage.total}, Cost: $#{usage.cost}")

# Or via pipeline modifiers
{:ok, text, usage} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_usage()
{:ok, text, cost} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_cost()
```

## 4. Functionality Requirements

### 4.1 Validation Requirements

**All public functions MUST:**
- Use NimbleOptions.validate/2 for input validation
- Return structured error tuples with context
- Provide @spec annotations with proper types
- Include @doc with usage examples

**Example validation pattern:**
```elixir
@spec generate_text(model_spec(), messages(), opts()) :: {:ok, Req.Response.t()} | {:error, term()}
def generate_text(model_spec, messages, opts \\ []) do
  with {:ok, validated_opts} <- NimbleOptions.validate(opts, @text_opts_schema),
       {:ok, model} <- Model.from(model_spec),
       {:ok, provider_module} <- ReqLLM.provider(model.provider) do
    provider_module.generate_text(model, messages, validated_opts)
  end
end
```

### 4.2 TypedStruct Requirements

**All data structures MUST:**
- Use `typedstruct enforce: true` for required fields
- Include @enforce_keys for critical fields
- Provide validation functions (valid?/1)
- Support JSON encoding/decoding where needed

```elixir
use TypedStruct

typedstruct enforce: true do
  field(:provider, atom(), enforce: true)
  field(:model, String.t(), enforce: true)
  field(:temperature, float() | nil)
end
```

### 4.3 Multi-modal Content Handling

**ContentPart MUST support:**
- Text content with metadata
- Image URLs with validation
- Binary image/file data with MIME type validation
- Tool calls with parameter validation
- Tool results with output serialization

**Provider-specific options:**
```elixir
# Image with OpenAI-specific detail setting
%ReqLLM.ContentPart{
  type: :image_url,
  url: "https://example.com/image.png",
  metadata: %{
    provider_options: %{
      openai: %{detail: "high"}
    }
  }
}
```

### 4.4 Tool Calling Requirements

**Tool execution MUST:**
- Validate parameters against NimbleOptions schema
- Handle multiple callback formats (MFA tuples, anonymous functions)
- Return structured results: `{:ok, result} | {:error, reason}`
- Export to JSON Schema for LLM integration
- Support parameter documentation for AI understanding

### 4.5 Response Metadata Requirements

**All responses MUST provide:**
- Token usage: `%{input: int, output: int, total: int}`
- Cost calculation: `float` (USD per response)
- Provider-specific metadata in `response.private[:req_llm]`
- Streaming support with chunk-level validation

## 5. Architecture Patterns

### 5.1 Provider DSL Pattern
```elixir
defmodule ReqLLM.Providers.Example do
  use ReqLLM.Provider.DSL,
    provider_id: :example,
    base_url: "https://api.example.com",
    auth: {:bearer, "EXAMPLE_API_KEY"},
    models_file: "example.json"

  # Only implement provider-specific logic
  @impl true
  def build_request(model, messages, opts), do: # ...
  
  @impl true  
  def parse_response(response, _model, _opts), do: # ...
end
```

### 5.2 Plugin Architecture
```elixir
# HTTP requests use composable plugin stack
request
|> ReqLLM.Plugins.Kagi.attach()           # Auth injection
|> ReqLLM.Plugins.TokenUsage.attach(model) # Usage tracking
|> ReqLLM.Plugins.Stream.attach()          # SSE handling  
|> ReqLLM.Plugins.Splode.attach()          # Error handling
|> Req.request()
```

### 5.3 Error Handling Pattern
```elixir
# Consistent error structures using Splode
{:error, ReqLLM.Error.Validation.Error.exception(
  tag: :invalid_model,
  reason: "Model not found",
  context: [model: "unknown:model"]
)}
```

This comprehensive API design maintains Vercel AI SDK compatibility while embracing Elixir's strengths: pattern matching, immutable data structures, supervision trees, and explicit error handling. The result is a robust, type-safe AI integration library that feels natural to Elixir developers while providing familiar patterns to those coming from the JavaScript AI ecosystem.
