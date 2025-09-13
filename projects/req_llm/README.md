# Req LLM

Req plugin that gives a uniform, provider-agnostic Elixir API for Large Language Models.

- 45 providers / 665 models auto-synced from [models.dev](https://models.dev) (`mix req_llm.models.sync`)
  - Cost, context length, modality and capability metadata included
- Typed data structures for every call
  - Context, Message, ContentPart, StreamChunk, Tool
  - All structs are `Jason.Encoder`s and can be inspected / persisted
- Two ergonomic client layers
  - Low-level `Req` plugin (`ReqLLM.run/3`) with full HTTP + model metadata
  - Vercel AI-style helpers (`generate_text/3`, `stream_text/3`, bang `!` variants)
- Streaming built in (`ReqLLM.stream_text/3`) — each chunk is a `StreamChunk`
- Usage & cost extraction on every response (`response.usage`)
- Provider system
  - Anthropic and OpenAI included
  - Implement `ReqLLM.Provider` behaviour to add new ones; composes with other Req plugins
- Context Codec protocol converts ReqLLM structs to provider wire formats
- Extensive test matrix (local fixtures + optional live calls)

## Quick Start

```elixir
# Configure API keys
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")

model = "anthropic:claude-3-sonnet"

# Simple text generation
{:ok, text} = ReqLLM.generate_text!(model, "Hello world")
#=> {:ok, "Hello! How can I assist you today?"}

# Structured data generation
schema = [name: [type: :string, required: true], age: [type: :pos_integer]]
{:ok, person} = ReqLLM.generate_object!(model, "Generate a person", schema)
#=> {:ok, %{name: "John Doe", age: 30}}

# With system prompts and parameters
{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet",
  [
    system("You are a helpful coding assistant"),
    user("Explain recursion in Elixir")
  ],
  temperature: 0.7,
  max_tokens: 200
)

# Tool calling
weather_tool = ReqLLM.tool(
  name: "get_weather",
  description: "Get current weather for a location",
  parameter_schema: [
    location: [type: :string, required: true, doc: "City name"]
  ],
  callback: fn args -> {:ok, "Sunny, 72°F"} end
)

{:ok, response} = ReqLLM.generate_text(
  "anthropic:claude-3-sonnet",
  "What's the weather in Paris?",
  tools: [weather_tool]
)
```

## Docs

- [Getting Started](guides/getting-started.md) – first call
- [Core Concepts](guides/core-concepts.md) – architecture & data model
- [API Reference](guides/api-reference.md) – functions & types

## Development

```bash
mix deps.get           # install
mix test               # run fixture tests
LIVE=true mix test     # live API tests
```
