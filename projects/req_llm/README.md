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
# mix.exs
{:req_llm, "~> 0.1.0"}

# Configure at runtime
ReqLLM.put_key(:anthropic_api_key, "sk-...")

# One-shot generation (bang variant unwraps the text directly)
{:ok, text} = ReqLLM.generate_text!("anthropic:claude-3-sonnet", "Hello")

# Streaming
{:ok, stream} = ReqLLM.stream_text!("anthropic:claude-3-sonnet", "Tell a story")

# Non-bang variant returns a ReqLLM.Response struct — inspect usage directly
{:ok, response} = ReqLLM.generate_text("openai:gpt-4o", "Hello")
IO.inspect(response.usage)

# or explicitly
usage = ReqLLM.Response.usage(response)
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
