# ReqLLM Capability System

The ReqLLM capability system provides a comprehensive framework for discovering, validating, and testing AI provider and model capabilities. It enables runtime capability queries, compile-time metadata loading, and dynamic test execution against live models or cached fixtures.

## Overview

The capability system consists of several interconnected components:

1. **Provider Metadata Loading**: Compile-time loading of model metadata from JSON files via the DSL
2. **Capability Discovery**: Runtime querying of model features and limitations  
3. **Test Infrastructure**: Dynamic switching between live API calls and cached fixtures
4. **Environment Variable Management**: Dynamic key lookup and provider authentication

## Core Architecture

### 1. Provider and Model Capability System

The capability system is built around a mapping between models.dev JSON metadata and ReqLLM feature atoms. Capabilities are defined in the `ReqLLM.Capability` module and include:

**Core Capabilities:**
- `:max_tokens` - Maximum tokens for generation (always supported)
- `:system_prompt` - System prompt support (always supported)  
- `:metadata` - Metadata support (always supported)
- `:stop_sequences` - Stop sequence support (always supported)

**Advanced Capabilities:**
- `:temperature` - Temperature control for randomness
- `:top_p` - Nucleus sampling parameter
- `:top_k` - Top-k sampling parameter
- `:tools` - Tool/function calling support
- `:tool_choice` - Tool choice control
- `:reasoning` - Chain-of-thought reasoning tokens
- `:streaming` - Streaming response support

### 2. Compile-time Metadata Loading via ReqLLM.Provider.DSL

The DSL automatically handles compile-time metadata loading from JSON files:

```elixir
defmodule MyProvider do
  use ReqLLM.Provider.DSL,
    id: :my_provider,
    base_url: "https://api.example.com/v1",
    metadata: "priv/models_dev/my_provider.json"

  def attach(request, model) do
    # Provider-specific request configuration
  end

  def parse(response, model) do
    # Provider-specific response parsing
  end
end
```

**DSL Features:**
- Automatic metadata file loading during compilation
- JSON parsing and key atomization for safe access
- Provider registry registration
- Compile-time validation of metadata files

### 3. Models.dev Metadata Structure

Capability metadata is derived from models.dev JSON files stored in `priv/models_dev/`:

```json
{
  "models": [
    {
      "id": "claude-3-5-sonnet-20240620",
      "cost": {
        "input": 3.0,
        "output": 15.0
      },
      "limit": {
        "context": 200000,
        "output": 8192
      },
      "modalities": {
        "input": ["text", "image"],
        "output": ["text"]
      },
      "temperature": true,
      "tool_call": true,
      "reasoning": false
    }
  ]
}
```

**Key Mapping:**
- `temperature: true` → `:temperature` capability
- `tool_call: true` → `:tools` and `:tool_choice` capabilities  
- `reasoning: true` → `:reasoning` capability
- `streaming: true` → `:streaming` capability

### 4. Runtime Capability Discovery

The `ReqLLM.Capability` module provides programmatic access to model capabilities:

```elixir
# Get all capabilities for a model
capabilities = ReqLLM.Capability.for("anthropic:claude-3-sonnet-20240620")
# Returns: [:max_tokens, :system_prompt, :temperature, :tools, :streaming, :metadata]

# Check if a model supports a specific feature
supports_tools = ReqLLM.Capability.supports?("anthropic:claude-3-sonnet-20240620", :tools)
# Returns: true

# Find all models supporting a capability
reasoning_models = ReqLLM.Capability.models_for(:anthropic, :reasoning)
# Returns: ["anthropic:claude-3-5-sonnet-20241022"]

# Get all providers supporting a feature
tool_providers = ReqLLM.Capability.providers_for(:tools)
# Returns: [:anthropic, :openai, :github_models]
```

## Capability Struct Fields

The Model struct includes several capability-related fields:

```elixir
defmodule ReqLLM.Model do
  typedstruct do
    # Runtime configuration
    field(:provider, atom(), enforce: true)
    field(:model, String.t(), enforce: true)
    field(:temperature, float() | nil)
    field(:max_tokens, non_neg_integer() | nil)
    field(:max_retries, non_neg_integer() | nil, default: 3)

    # Capability metadata
    field(:limit, limit() | nil)           # Context/output token limits
    field(:modalities, modalities() | nil) # Supported input/output types
    field(:capabilities, capabilities() | nil) # Feature flags
    field(:cost, cost() | nil)             # Pricing per 1K tokens
  end
end
```

**Capability Types:**
- `limit`: `%{context: integer(), output: integer()}`
- `modalities`: `%{input: [atom()], output: [atom()]}`
- `capabilities`: `%{reasoning?: boolean(), tool_call?: boolean(), supports_temperature?: boolean()}`
- `cost`: `%{input: float(), output: float()}`

## Test Infrastructure

### Live Fixture System

The `ReqLLM.Test.LiveFixture` system enables dynamic test execution:

```elixir
defmodule MyProviderTest do
  use ExUnit.Case
  import ReqLLM.Test.LiveFixture

  test "basic generation" do
    use_fixture :anthropic, "basic_generation", fn ->
      ReqLLM.generate_text("anthropic:claude-3-haiku", "Hello", max_tokens: 5)
    end
  end
end
```

**Test Modes:**
- **Fixture Mode** (default): Uses cached responses from `test/support/fixtures/`
- **Live Mode** (`LIVE=true`): Executes real API calls and captures new fixtures

### Fixture Storage Format

Fixtures are stored as JSON with metadata:

```json
{
  "captured_at": "2024-01-15T10:30:00Z",
  "provider": "anthropic",
  "result": {
    "type": "ok_response",
    "status": 200,
    "body": {"content": "Hello there!"},
    "headers": {"content-type": "application/json"}
  }
}
```

### Capability Testing

Tests can verify provider capabilities against their metadata:

```elixir
test "provider supports advertised capabilities" do
  model_spec = "anthropic:claude-3-sonnet-20240620"
  
  # Check metadata claims
  assert ReqLLM.Capability.supports?(model_spec, :tools)
  assert ReqLLM.Capability.supports?(model_spec, :temperature)
  
  # Verify live functionality
  use_fixture :anthropic, "tool_calling_test", fn ->
    ReqLLM.generate_text(model_spec, "Call get_weather function", 
      tools: [%{name: "get_weather", description: "Get current weather"}])
  end
end
```

## Environment Variable System

### Dynamic Key Lookup

ReqLLM uses the Kagi keyring system for dynamic API key management:

```elixir
# Provider-specific key lookup
api_key = ReqLLM.get_key(:anthropic_api_key)
api_key = ReqLLM.get_key("ANTHROPIC_API_KEY")

# Automatic provider-to-key mapping
defmodule ReqLLM.Providers.Anthropic do
  def attach(request, model) do
    # Automatically resolves ANTHROPIC_API_KEY
    api_key = ReqLLM.get_key(:anthropic_api_key)
    # ... configure request
  end
end
```

### Environment Variable Hints

Provider metadata includes environment variable requirements:

```json
{
  "provider": {
    "name": "Anthropic",
    "env": ["ANTHROPIC_API_KEY"],
    "website": "https://anthropic.com"
  },
  "models": [...]
}
```

### Testing Environment Variables

Tests can specify required environment variables:

```elixir
# Skip test if key not available
test "live anthropic generation" do
  unless ReqLLM.get_key(:anthropic_api_key) do
    skip("ANTHROPIC_API_KEY not configured")
  end
  
  use_fixture :anthropic, "live_test", fn ->
    ReqLLM.generate_text("anthropic:claude-3-haiku", "Hello")
  end
end
```

## Provider Registry Integration

The `ReqLLM.Provider.Registry` stores and manages capability metadata:

```elixir
# Get provider metadata including environment requirements
{:ok, metadata} = ReqLLM.Provider.Registry.get_provider_metadata(:anthropic)
env_vars = get_in(metadata, ["provider", "env"])
# Returns: ["ANTHROPIC_API_KEY"]

# Check model existence
exists = ReqLLM.Provider.Registry.model_exists?("anthropic:claude-3-sonnet")
# Returns: true

# List all models for capability testing
{:ok, models} = ReqLLM.Provider.Registry.list_models(:anthropic)
# Returns: ["claude-3-haiku-20240307", "claude-3-sonnet-20240229", ...]
```

## Best Practices

### 1. Capability-Driven Testing

Design tests that verify capabilities match implementation:

```elixir
test "temperature capability works as advertised" do
  model_spec = "anthropic:claude-3-sonnet"
  
  if ReqLLM.Capability.supports?(model_spec, :temperature) do
    use_fixture :anthropic, "temperature_test", fn ->
      # Test with temperature parameter
      ReqLLM.generate_text(model_spec, "Be creative", temperature: 1.0)
    end
  else
    skip("Model does not support temperature")
  end
end
```

### 2. Environment Variable Management

Use descriptive variable names and provide fallbacks:

```elixir
def get_api_key(provider) do
  case provider do
    :anthropic -> ReqLLM.get_key(:anthropic_api_key) || System.get_env("ANTHROPIC_API_KEY")
    :openai -> ReqLLM.get_key(:openai_api_key) || System.get_env("OPENAI_API_KEY")
    _ -> nil
  end
end
```

### 3. Fixture Organization

Organize fixtures by provider and capability:

```
test/support/fixtures/
├── anthropic/
│   ├── basic_generation.json
│   ├── tool_calling.json
│   └── reasoning_test.json
└── openai/
    ├── basic_generation.json
    └── streaming_test.json
```

### 4. Capability Validation

Always validate capabilities before using advanced features:

```elixir
def generate_with_tools(model_spec, prompt, tools) do
  unless ReqLLM.Capability.supports?(model_spec, :tools) do
    raise ArgumentError, "Model #{model_spec} does not support tools"
  end
  
  ReqLLM.generate_text(model_spec, prompt, tools: tools)
end
```

## Implementation Details

### Metadata Loading Pipeline

1. **Compile Time**: DSL loads JSON files and registers providers
2. **Runtime**: Registry provides fast lookup via `:persistent_term`
3. **Capability Query**: Maps JSON fields to capability atoms
4. **Test Execution**: Uses capabilities to determine test requirements

### Thread Safety

The capability system is designed for concurrent access:
- Provider registry uses `:persistent_term` for lock-free reads
- Capability queries are pure functions
- Fixture system handles concurrent test execution

### Performance Considerations

- Metadata is loaded once at compile time
- Capability queries use efficient pattern matching
- Registry lookups are O(1) via `:persistent_term`
- Fixture loading is lazy and cached

This capability system enables ReqLLM to provide a consistent interface across diverse AI providers while respecting individual provider limitations and features.
