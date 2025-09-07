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
- **Data Structures**: Model, Message, Tool, ContentPart with multi-modal support and NimbleOptions validation
- **Provider System**: DSL-generated behaviors, auto-registration, minimal code per provider (OpenAI, Anthropic)
- **Req Plugins**: Token counting, Kagi auth, streaming (SSE), error handling - composable cross-cutting concerns
- **Capabilities**: ExUnit-based testing framework via `mix req_llm.verify` for model capability validation
- **Metadata Sync**: `mix req_llm.model_sync` fetches from models.dev, stores in `priv/models_dev/*.json`

## Key Features

- **Models Metadata**: Auto-sync from models.dev with cost/capability data for 44+ providers
- **Provider Pattern**: DSL macro generates boilerplate, providers implement only unique request/response logic
- **Req Plugin Stack**: Composable middleware for auth, usage tracking, streaming, error handling
- **Capability Testing**: Automated model verification against defined capabilities (text, tools, streaming)
- **NimbleOptions Schema**: Consistent validation and documentation throughout, keeping API simple

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
# Format: {:provider, [options]}
{:openai, model: "gpt-4", temperature: 0.7, max_tokens: 1000}
{:anthropic, model: "claude-3-sonnet", temperature: 0.3}

# Runtime parameters override defaults
model = ReqLLM.Model.from({:openai, model: "gpt-4", temperature: 0.7})
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
Models are enhanced with rich metadata from `priv/models_dev/*.json`:

```elixir
# Load basic model spec
model = ReqLLM.model("openai:gpt-4")

# Enhance with capabilities, costs, limits
enhanced = ReqLLM.Model.with_metadata(model)
# enhanced.metadata contains:
# - capabilities: [:generate_text, :tool_calling, :reasoning]
# - pricing: %{input: 0.03, output: 0.06}  # per 1K tokens
# - context_length: 8192
# - modalities: [:text]
```

**Provider Allow-list**: String parsing uses a curated provider list to prevent atom-bombing attacks while supporting all 44+ providers from models.dev.

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
- **Req.Response objects**: Full HTTP response with metadata in `response.private[:req_llm]`
- **Bang methods**: `generate_text!/3`, `stream_text!/3` return unwrapped results for convenience
- **Response modifiers**: `with_usage/1`, `with_cost/1` extract metadata from responses
- **NimbleOptions**: Replaces Zod schemas for validation and documentation
- **Streaming**: Uses Elixir `Stream` module with `Stream.each/2` patterns
- **Multi-modal**: ContentPart structs for images, files, tool calls
- **Provider system**: DSL-generated behaviors vs. direct provider objects

## Usage Examples (Required Patterns)

### Core API Usage
```elixir
# Text generation - REQUIRED: Use tuples for model specs
{:ok, result} = ReqLLM.generate_text({:openai, model: "gpt-4"}, messages)

# Bang methods for convenience - unwraps results
{:ok, text} = ReqLLM.generate_text!(model, messages)

# Response modifiers - extract usage/cost metadata
{:ok, text, usage} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_usage()
{:ok, text, cost} = ReqLLM.generate_text(model, messages) |> ReqLLM.with_cost()

# Full Req.Response access for metadata
{:ok, %Req.Response{body: text} = response} = ReqLLM.generate_text(model, messages)
usage = response.private[:req_llm][:usage]

# Streaming - REQUIRED: Handle stream chunks properly
{:ok, stream} = ReqLLM.stream_text("anthropic:claude-3-sonnet", messages)
stream |> Stream.each(&IO.puts(&1.content)) |> Stream.run()

# Structured objects - REQUIRED: Use NimbleOptions schema
schema = [name: [type: :string, required: true], age: [type: :integer]]
{:ok, person} = ReqLLM.generate_object(model, messages, :object, schema)

# Tool calling - REQUIRED: Use Tool struct with NimbleOptions
tool = %ReqLLM.Tool{name: "get_weather", parameters: [location: [type: :string]]}
{:ok, result} = ReqLLM.generate_text(model, messages, tools: [tool])
```

### Provider Implementation (DSL Required)
```elixir
defmodule ReqLLM.Providers.Example do
  use ReqLLM.Provider.DSL,
    provider_id: :example,
    base_url: "https://api.example.com",
    auth: {:bearer, "EXAMPLE_API_KEY"},
    models_file: "example.json"

  # REQUIRED: Only implement unique request/response logic
  @impl true
  def build_request(model, messages, opts) do
    # Provider-specific request format
  end

  @impl true
  def parse_response(response, _model, _opts) do
    # Provider-specific response parsing
  end
end
```

### Req Plugin Usage (Required Integration)
```elixir
# REQUIRED: All HTTP requests must use plugin stack
request
|> ReqLLM.Plugins.Kagi.attach()        # Auto auth injection
|> ReqLLM.Plugins.TokenUsage.attach(model)  # Usage tracking
|> ReqLLM.Plugins.Stream.attach()      # SSE handling
|> Req.request()

# Usage extraction - REQUIRED: Check response.private
case response.private[:req_llm][:usage] do
  %{input_tokens: input, output_tokens: output, total_cost: cost} ->
    Logger.info("Used #{input + output} tokens, cost: $#{cost}")
  nil -> :no_usage_data
end
```

### Capability Testing (Required for New Providers)
```elixir
# REQUIRED: Test all provider capabilities
mix req_llm.verify openai:gpt-4 --format debug
mix req_llm.verify anthropic --only generate_text,stream_text

# REQUIRED: Implement custom capabilities
defmodule MyApp.Capabilities.CustomFeature do
  @behaviour ReqLLM.Capability

  def id, do: :custom_feature
  def advertised?(model), do: model.capabilities[:custom_feature] == true
  def verify(model, _opts), do: # Test implementation
end
```

### Metadata Sync (Required Maintenance)
```elixir
# REQUIRED: Keep model metadata current
mix req_llm.model_sync  # Syncs all 44+ providers from models.dev

# Model metadata usage - REQUIRED: Load with metadata
model = ReqLLM.Model.from({:openai, model: "gpt-4"}) |> ReqLLM.Model.with_metadata()
```

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
- **MUST support model tuples**: `{:openai, model: "gpt-4", temperature: 0.7}` format required
- **MUST return tagged tuples**: `{:ok, result}` or `{:error, reason}` - never bare results
- **MUST use Tool structs**: Tool definitions require NimbleOptions parameter schemas

### Provider Implementation Requirements
- **MUST use Provider DSL**: All providers require `use ReqLLM.Provider.DSL` with config
- **MUST implement only unique logic**: Only `build_request/3` and `parse_response/3` callbacks
- **MUST auto-register**: Providers auto-register via `@after_compile` hook - no manual registration
- **MUST include metadata**: Provider config requires `models_file` pointing to models.dev JSON
- **MUST follow auth patterns**: Use `{:bearer, "ENV_VAR"}` or `{:plain, "header", "ENV_VAR"}` formats

### HTTP/Plugin Requirements
- **MUST use plugin stack**: All HTTP requests require Kagi + TokenUsage + Stream plugins
- **MUST extract usage**: Always check `response.private[:req_llm][:usage]` for token/cost data
- **MUST handle streaming**: Use `Stream.each/2` with proper chunk processing for streaming responses
- **MUST use Splode errors**: Convert HTTP errors via `ReqLLM.Plugins.Splode`

### Testing Requirements
- **MUST test capabilities**: New providers require `mix req_llm.verify` passing for all advertised capabilities
- **MUST implement capability modules**: Custom capabilities require `@behaviour ReqLLM.Capability`
- **MUST sync metadata**: Run `mix req_llm.model_sync` before adding/updating providers
- **MUST validate with metadata**: Use `Model.with_metadata/1` for capability-aware model validation

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

1. **Simplified Provider System**: Minimal registry, direct implementations
2. **Clean Message Structures**: Multi-modal support without complexity
3. **Focused ObjectSchema**: JSON Schema export for LLM integration
4. **Consistent Error Handling**: Splode-based error management
5. **High Quality, Low Complexity**: 75%+ coverage with terse, focused tests
