# AGENT.md - Jido AI Development Guide

## Commands

- **Test**: `mix test` (all), `mix test test/path/to/specific_test.exs` (single file), `mix test --trace` (verbose)
- **Lint**: `mix credo` (basic), `mix credo --strict` (strict mode)
- **Format**: `mix format` (format code), `mix format --check-formatted` (verify formatting)
- **Quality**: `mix quality` or `mix q` (runs format, compile, dialyzer, credo, doctor, docs)
- **Compile**: `mix compile` (basic), `mix compile --warnings-as-errors` (strict)
- **Type Check**: `mix dialyzer --format dialyxir`
- **Coverage**: `mix test --cover` (basic), `mix coveralls.html` (HTML report)
- **Docs**: `mix docs` (generate documentation)

## Architecture

Jido AI is an Elixir library for AI agent workflows with multiple LLM providers:

- **Core**: [`lib/jido_ai.ex`](lib/jido_ai.ex) - Main API facade with unified config access via `Jido.AI.config/2`
- **Keyring**: [`lib/jido_ai/keyring.ex`](lib/jido_ai/keyring.ex) - API key management (GenServer)
- **Providers**: [`lib/jido_ai/provider/`](lib/jido_ai/provider/) - LLM provider implementations (OpenAI, Anthropic, etc.)
- **Models**: [`lib/jido_ai/model.ex`](lib/jido_ai/model.ex) - Model configuration and validation

## SDLC

- **Coverage Goal**: Test coverage goal should be 90%+
- **Code Quality**: Use `mix quality` to run all checks
  - Fix all compiler warnings
  - Fix all dialyzer warnings
  - Add `@type` to all custom types
  - Add `@spec` to all public functions
  - Add `@doc` to all public functions and `@moduledoc` to all modules

## Public API Overview

The main `Jido.AI` module provides a clean, minimal interface:

### Configuration & Provider Access

- `Jido.AI.config(keyspace, default)` - Get config values using atom list paths with Keyring fallback
- `Jido.AI.api_key(provider)` - Get API key for a provider
- `Jido.AI.list_keys()` - List all configuration keys

### Model & Text Generation

_API is modeled after the Vercel AI SDK_

- `Jido.AI.model(spec)` - Create model from flexible spec (string/tuple/struct)
- `Jido.AI.provider(provider)` - Get provider module from registry
- `Jido.AI.generate_text(model_spec, prompt, opts)` - Generate text with any model spec
- `Jido.AI.stream_text(model_spec, prompt, opts)` - Stream text generation

### Model Creation Syntactic Sugar

The `Model.from/1` function provides flexible model creation from various input formats:

**String Format**: `"provider:model"` for quick model references

```elixir
Model.from("openrouter:anthropic/claude-3.5-sonnet")
Model.from("openai:gpt-4o")
Model.from("google:gemini-1.5-pro")
```

**Tuple Format**: `{provider, opts}` for custom configuration

```elixir
Model.from({:openrouter, model: "anthropic/claude-3.5-sonnet", temperature: 0.7})
Model.from({:openai, model: "gpt-4o", max_tokens: 4000, max_retries: 5})
```

**Struct Passthrough**: Existing Model structs are returned as-is

```elixir
Model.from(%Model{provider: :openai, model: "gpt-4o"})  # Returns the struct unchanged
```

This syntactic sugar allows developers to quickly reference models without needing to construct full Model structs, while maintaining type safety and provider validation.

## Code Style

- **Formatting**: Uses [`mix format`](.formatter.exs), line length max 120 chars
- **Types**: Add `@spec` to all public functions, use `@type` for custom types
- **Docs**: `@moduledoc` for modules, `@doc` for public functions with examples
- **Testing**: Mirror lib structure in test/, use ExUnit with async when possible, tag slow/integration tests
- **HTTP Testing**: Use Req.Test for HTTP mocking instead of Mimic - provides cleaner stubs and better integration
- **Error Handling**: Return `{:ok, result}` or `{:error, reason}` tuples, use `with` for complex flows
- **Imports**: Group aliases at module top, prefer explicit over wildcard imports
- **Naming**: `snake_case` for functions/variables, `PascalCase` for modules
- **Logging**: Avoid Logger metadata - integrate all fields into log message strings instead of using keyword lists

## Data Architecture

### Core Data Structures

**Provider** (`Jido.AI.Provider`): Represents an AI service provider (OpenAI, Anthropic, etc.)

- `id` (atom): Unique provider identifier
- `name` (string): Display name
- `base_url` (string): API endpoint URL (centralized here, not in models)
- `env` (list of atoms): Environment variable names for API keys
- `doc` (string): Provider description
- `models` (map): Collection of supported Model structs keyed by model ID

**Model** (`Jido.AI.Model`): Represents a specific AI model with runtime config and metadata

- Runtime fields: `provider` (atom), `model` (string), `temperature`, `max_tokens`, `max_retries`
- Metadata fields: `id`, `name`, `attachment`, `reasoning`, `tool_call`, `cost`, `limit`, `modalities`, etc.
- API access (base_url, api_key) is handled via the Provider, following DRY principles

### Data Pipeline

1. **Source**: Models.dev API (https://models.dev/api.json) - Community registry of AI models
2. **ETL**: `mix jido.ai.model_sync` downloads, transforms, and stores provider data
3. **Storage**: JSON files in `priv/models_dev/{provider}.json` with normalized schema
4. **Runtime**: Provider/Model structs loaded from JSON for application use

### Models.dev Integration

The `mix jido.ai.model_sync` task fetches model metadata from models.dev which provides:

- Model capabilities (tool calling, reasoning, attachments)
- Cost data (input/output pricing, cache costs)
- Technical limits (context length, output tokens)
- Modality support (text, image, audio, video)
- Release and update dates

**Field Mapping**:

- models.dev `providerId` → our `provider` field
- models.dev `providerModelId` → our `provider_model_id` field
- models.dev cost/limit structures → validated into our typed structs
- We add `base_url` via our provider modules
- Default API keys from the `env` field are added to the `api_key` field, and `Keyring` is used to get the actual key from the environment or Application config
- We filter out models.dev fields like `npm` package info we don't need

**Schema Mismatch Handling**:

- Provider `base_url`: Injected via hardcoded lookup table in model_sync
- Provider `env`: Configured per provider (e.g., `["OPENAI_API_KEY"]`)
- Missing metadata: Sensible defaults applied during Model construction

### Rich Prompts & Messages (Planned)

_Following Vercel AI SDK patterns for flexible prompt construction_

**Message** (`Jido.AI.Message`): Represents a single message in a conversation

- `role` (atom): Message sender - `:user`, `:assistant`, `:system`, or `:tool`
- `content` (string | list): Message content - string for simple text or list of ContentPart structs for multi-modal
- `name` (string, optional): Message author name for multi-participant conversations
- `tool_call_id` (string, optional): Links tool results to their originating tool calls
- `tool_calls` (list, optional): Array of tool calls made by assistant
- `metadata` (map, optional): Provider-specific options and hints

**ContentPart** (`Jido.AI.ContentPart`): Represents a piece of content within a message

- Text: `%{type: :text, text: string}`
- Image: `%{type: :image_url, url: string}` or `%{type: :image, data: binary, media_type: string}`
- File: `%{type: :file, data: binary, media_type: string, filename: string}`
- Tool Call: `%{type: :tool_call, tool_call_id: string, tool_name: string, input: map}`
- Tool Result: `%{type: :tool_result, tool_call_id: string, tool_name: string, output: map}`

**Prompt Types Supported**:

1. `String.t()` - Simple text prompt (current, always supported)
2. `[Message.t()]` - Array of message objects for conversations
3. `{system_prompt :: String.t(), messages :: [Message.t()]}` - System prompt with message history

## Testing Approach

### Test Infrastructure

The test suite uses modular case templates that provide clean, composable testing patterns:

#### HTTPCase - HTTP Testing Made Simple

```elixir
defmodule MyProviderTest do
  use Jido.AI.TestSupport.HTTPCase

  test "successful generation", %{test_name: test_name} do
    with_success(%{choices: [%{message: %{content: "Hello"}}]}) do
      result = MyProvider.generate_text(model, "test prompt")
      assert {:ok, "Hello"} = result
    end
  end

  test "handles API errors" do
    with_error(429, %{error: %{message: "Rate limited"}}) do
      result = MyProvider.generate_text(model, "test prompt")
      assert_error(result, Jido.AI.Error.APIError)
    end
  end
end
```

#### KeyringCase - Isolated Configuration Testing

```elixir
defmodule KeyringTest do
  use Jido.AI.TestSupport.KeyringCase

  test "environment precedence" do
    env(openai_api_key: "env-key") do
      session(openai_api_key: "session-key") do
        assert_value(:openai_api_key, "session-key")
      end
      assert_value(:openai_api_key, "env-key")
    end
  end
end
```

#### Custom Assertions for AI Testing

```elixir
# Extract values from success tuples
result = AI.generate_text(model, "hello")
text = assert_ok(result)  # Fails if not {:ok, text}

# Match specific error types
assert_error(result, Jido.AI.Error.APIError)
assert_error(result, %Jido.AI.Error.APIError{status: 429})

# Validate model structures
assert_valid_model(model)
assert_chat_completion_body(request_body)
```

### Test Organization

#### Fixtures vs. Inline Creation

**Use Fixtures**: `Jido.AI.Test.Fixtures.ModelFixtures` and `ProviderFixtures`

```elixir
# Good - reusable, consistent
model = ModelFixtures.gpt4()
response = ProviderFixtures.openai_json("Hello world")

# Avoid - inline model creation
model = %Model{provider: :openai, model: "gpt-4"}
```

#### Table-Driven Testing

```elixir
use Jido.AI.TestSupport.TestMacros

table_test "validates different inputs", [
  {nil, :invalid},
  {"", :invalid},
  {"valid-key", :valid}
] do
  {input, expected} ->
    assert validate_key(input) == expected
end
```

#### Shared Examples for Provider Conformance

```elixir
defmodule MyProviderTest do
  use ExUnit.Case
  import Jido.AI.TestSupport.SharedExamples

  describe "provider conformance" do
    test_provider_generate_text(MyProvider, model_fixture())
    test_provider_stream_text(MyProvider, model_fixture())
    test_provider_error_handling(MyProvider, model_fixture())
  end
end
```

### Best Practices

- **HTTP Testing**: Always use `HTTPCase` with `with_success/2`, `with_error/3` macros
- **Keyring Testing**: Use `KeyringCase` with `env/2`, `session/2` macros for isolation
- **Assertions**: Use `assert_ok/1`, `assert_error/2` for consistent error handling
- **Fixtures**: Prefer fixture modules over inline model/response creation
- **Property Testing**: Use StreamData for complex validation scenarios
- **Coverage**: Target ≥90% with `mix test --cover`
