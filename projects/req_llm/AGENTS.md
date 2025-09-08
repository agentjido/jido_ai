# AGENTS.md - ReqLLM Development Guide

## Commands

- **Test**: `mix test` (all), `mix test test/path/to/specific_test.exs` (single file), `mix test --trace` (verbose)
- **Quality**: `mix quality` (runs format, compile with warnings, dialyzer, credo)
- **Format**: `mix format` (format code), `mix format --check-formatted` (verify formatting)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer`
- **Coverage**: `mix test --cover` (basic coverage report)
- **Scripts**: Always use `mix run script_name.exs` to run test scripts - avoids Mix.install conflicts

## Architecture

ReqLLM is a simplified Elixir library for AI interactions built on Req HTTP client, following [Vercel AI SDK](https://ai-sdk.dev/docs/reference/ai-sdk-core) patterns:

- **Core API**: [`lib/req_llm.ex`](lib/req_llm.ex) - `generate_text`, `stream_text`, `generate_object`, `embed` (Vercel-inspired)
- **Data Structures**: Model, Message, Context, Tool, ContentPart with multi-modal support and NimbleOptions validation
- **Provider System**: DSL-generated behaviors, auto-registration, minimal code per provider (OpenAI, Anthropic)
- **Req Plugins**: Token counting, Kagi auth, streaming (SSE), error handling - composable cross-cutting concerns
- **Capabilities**: ExUnit-based testing framework via `mix req_llm.verify` for model capability validation
- **Metadata Sync**: `mix req_llm.model_sync` fetches from models.dev, stores in `priv/models_dev/*.json`

## Model Specification Formats

ReqLLM supports three flexible formats for specifying models, all parsed into `%ReqLLM.Model{}` structs:

### String Format (Simple)
```elixir
# Format: "provider:model_name"
"openai:gpt-4"
"anthropic:claude-3-sonnet"
"github-models:gpt-4o-mini"

# Parsed automatically by ReqLLM.Model.from/1
model = ReqLLM.model("openai:gpt-4")
```

### Tuple Format (With Options)
```elixir
# Format: {:provider, "model", [options]}
{:openai, "gpt-4", temperature: 0.7, max_tokens: 1000}
{:anthropic, "claude-3-sonnet", temperature: 0.3}

# Runtime parameters override defaults
model = ReqLLM.Model.from({:openai, "gpt-4", temperature: 0.7})
```

### Model Struct Format (Full Control)
```elixir
# Direct struct creation with all fields
%ReqLLM.Model{
  provider: :openai,
  model: "gpt-4",
  temperature: 0.7,
  max_tokens: 1000,
  metadata: %{...}  # Enhanced with models.dev data
}
```

### Metadata Enhancement
Models are enhanced with rich metadata from `priv/models_dev/*.json` at compile time:

```elixir
# Load basic model spec
model = ReqLLM.model("openai:gpt-4")

# Enhance with capabilities, costs, limits
enhanced = ReqLLM.Model.with_metadata(model)
# enhanced.metadata contains:
# - capabilities: [:generate_text, :tool_calling, :reasoning, ...]
# - pricing: %{input: 0.03, output: 0.06}  # per 1K tokens
# - context_length: 8192
# - modalities: [:text]
```

## Vercel AI SDK Alignment

ReqLLM closely follows the [Vercel AI SDK](https://ai-sdk.dev/docs/reference/ai-sdk-core) API patterns, adapted for Elixir conventions:

| Vercel AI SDK | ReqLLM Equivalent | Documentation |
|---------------|-------------------|---------------|
| [`generateText()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/generate-text) | `ReqLLM.generate_text/3` | Generate text and call tools |
| [`streamText()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/stream-text) | `ReqLLM.stream_text/3` | Stream text and tool calls |
| [`generateObject()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/generate-object) | `ReqLLM.generate_object/4` | Generate structured data |
| [`streamObject()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/stream-object) | `ReqLLM.stream_object/4` | Stream structured data |
| [`embed()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/embed) | `ReqLLM.embed/3` | Generate single embedding |
| [`embedMany()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/embed-many) | `ReqLLM.embed_many/3` | Generate batch embeddings |
| [`tool()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/tool) | `%ReqLLM.Tool{}` struct | Tool definitions |
| [`jsonSchema()`](https://ai-sdk.dev/docs/reference/ai-sdk-core/json-schema) | NimbleOptions schema | Schema validation |

### Key Adaptations for Elixir
- **Tagged tuples**: `{:ok, result}` or `{:error, reason}` instead of throwing exceptions
- **Bang methods**: `generate_text!/3`, `stream_text!/3` return unwrapped results for convenience
- **Response modifiers**: `with_usage/1`, `with_cost/1` extract metadata from responses
- **NimbleOptions**: Replaces Zod schemas for validation and documentation
- **Streaming**: Uses Elixir `Stream` module with `Stream.each/2` patterns, `%ReqLLM.StreamChunk` for chunked responses
- **Multi-modal**: ContentPart structs for images, files, tool calls
- **Provider system**: DSL-generated behaviors vs. direct provider objects

## SDLC

- **Coverage Goal**: Target 75%+ test coverage
- **Code Quality**: Use `mix quality` to run all checks
  - Fix all compiler warnings
  - Fix all dialyzer warnings
  - Add `@spec` to all public functions
  - Add `@doc` to all public functions and `@moduledoc` to all modules

## Consistency Rules (REQUIRED)

### API Layer Requirements
- **MUST use Vercel AI SDK patterns**: `generate_text`, `stream_text`, `generate_object`, `embed` function names
- **MUST use NimbleOptions**: All public functions require NimbleOptions schema validation
- **MUST support model specs**: `openai:gpt-4` or `{:openai, "gpt-4", temperature: 0.7}` format required
- **MUST return tagged tuples**: `{:ok, result}` or `{:error, reason}` - never bare results
- **MUST use Tool structs**: Tool definitions require NimbleOptions parameter schemas

### Code Quality Requirements
- **MUST use TypedStruct**: All data structures require TypedStruct with field validation
- **MUST add specs**: All public functions require `@spec` with proper types
- **MUST document**: All modules require `@moduledoc`, all public functions require `@doc` with examples
- **MUST handle errors**: Use Splode for error definitions, return structured error tuples

## Code Style

- **Comments Rule**: NEVER add inline comments within method boundaries. Keep code self-documenting. Only use module-level docs (@moduledoc, @doc).
- **Formatting**: Uses `mix format`, line length max 120 chars
- **Types**: Add `@spec` to all public functions, use TypedStruct for data structures
- **Docs**: `@moduledoc` for modules, `@doc` for public functions with examples
- **Testing**: Mirror lib structure in test/, use ExUnit, target 75%+ coverage, keep tests terse and focused
- **Error Handling**: Use Splode for consistent error handling, return `{:ok, result}` or `{:error, reason}` tuples
- **Dependencies**: Minimal deps (req, jason, typed_struct, splode, nimble_options)
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules
- **Simplicity**: Keep it simple - fewer abstractions than jido_ai, more direct implementations

## Project Goals

ReqLLM is designed to be a simpler, more focused alternative to jido_ai with:

1. **Simplified Provider System**: Minimal registry, direct implementations, as Req Plugins
2. **Clean Message Structures**: Multi-modal support without complexity
3. **Focused ObjectSchema**: JSON Schema export for LLM integration
4. **Consistent Error Handling**: Splode-based error management
5. **High Quality, Low Complexity**: 75%+ coverage with terse, focused tests
