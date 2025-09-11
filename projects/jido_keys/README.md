# JidoKeys

[![Hex.pm](https://img.shields.io/hexpm/v/jido_keys.svg)](https://hex.pm/packages/jido_keys)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/jido_keys)
[![License](https://img.shields.io/hexpm/l/jido_keys.svg)](https://github.com/agentjido/jido_keys/blob/main/LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/agentjido/jido_keys/ci.yml?branch=main)](https://github.com/agentjido/jido_keys/actions)

A fast, secure configuration management library for Elixir applications that provides easy access to API keys and environment variables. Part of the [Jido ecosystem](https://github.com/agentjido/jido) for LLM-powered applications.

## Installation

Add `jido_keys` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:jido_keys, "~> 0.1.0"}
  ]
end
```

JidoKeys starts automatically - no setup required.

## Quick Start

```elixir
# Get values with optional defaults
JidoKeys.get(:openai_api_key)
JidoKeys.get(:openai_api_key, "fallback-key")

# Bang variant raises on missing keys
JidoKeys.get!(:openai_api_key)

# Check if keys exist
JidoKeys.has?(:openai_api_key)
JidoKeys.has_value?(:openai_api_key)  # non-empty values only

# List all available keys
JidoKeys.list()
```

## Configuration Sources

Hierarchical resolution from multiple sources (in order of precedence):

1. **Runtime overrides** (via `JidoKeys.put/2`)
2. **Environment variables** (from `.env` files and system)
3. **Application config** (from `config.exs`)
4. **Defaults** (provided in `get/2`)

```elixir
# .env file
OPENAI_API_KEY=sk-1234567890
DATABASE_URL=postgres://localhost:5432/mydb

# Application config
config :jido_keys, :keys, %{
  custom_key: "app_value"
}

# Runtime override
JidoKeys.put(:openai_api_key, "sk-override")
```

## Key Formats

Supports both atoms and strings with automatic normalization:

```elixir
# All these access the same value
JidoKeys.get("OPENAI_API_KEY")      # Standard env var format
JidoKeys.get("openai_api_key")      # Lowercase
JidoKeys.get("OpenAI-API-Key")      # Mixed case with special chars
JidoKeys.get(:openai_api_key)       # Atom format

# Any string format works
JidoKeys.get("VERY_LONG_KEY_NAME_WITH_UNDERSCORES")
JidoKeys.get("key-with-dashes")
JidoKeys.get("key.with.dots")
JidoKeys.get("KEY@WITH#SPECIAL$CHARS")
```

## Livebook Integration

Special support for Livebook with `LB_` prefixed environment variables:

```elixir
# Environment variable: LB_OPENAI_API_KEY=sk-123
JidoKeys.get("openai_api_key")  # Works with or without LB_ prefix
```

## Security Features

### Automatic Log Filtering

Built-in logger filter that redacts sensitive information:

```elixir
# Automatically redacts secrets in logs
Logger.info("API key: #{JidoKeys.get(:openai_api_key)}")
# Output: "API key: [REDACTED]"
```

### Safe LLM Key Conversion

Memory-safe atom conversion for common LLM providers:

```elixir
# Safe conversion to atoms (hardcoded allowlist)
JidoKeys.to_llm_atom("openai_api_key")     # => :openai_api_key
JidoKeys.to_llm_atom("anthropic_api_key")  # => :anthropic_api_key

# Unknown keys remain as strings 
JidoKeys.to_llm_atom("custom_key")         # => "custom_key"
```

## Runtime Updates

```elixir
# Set values at runtime
JidoKeys.put(:test_key, "test_value")

# Reload configuration
JidoKeys.reload()
JidoKeys.reload(force: true)
```

## Testing Support

Perfect for testing with runtime configuration:

```elixir
# In tests
JidoKeys.put(:test_api_key, "test-value")
assert JidoKeys.get(:test_api_key) == "test-value"

# Clean up after tests
JidoKeys.reload()
```

## Error Handling

Comprehensive error system with specific error types:

```elixir
# Raises ArgumentError for missing keys
JidoKeys.get!(:missing_key)
# ** (ArgumentError) Configuration key :missing_key not found

# Custom error types for different scenarios
JidoKeys.Error.InvalidError
JidoKeys.Error.NotFoundError
JidoKeys.Error.ConfigurationError
JidoKeys.Error.ServerError
```

## Performance

- **ETS-based storage** for O(1) lookup times
- **Concurrent reads** with protected access
- **Fast startup** with efficient environment loading

## Environment File Support

Loads from multiple `.env` files with environment-specific overrides:

```
.env                           # Base environment
envs/.env                      # Environment-specific
envs/.dev.env                  # Development overrides
envs/.dev.overrides.env        # Development overrides
```

## API Reference

### Core Functions

- `get/2` - Get value with optional default
- `get!/1` - Get value or raise exception
- `has?/1` - Check if key exists
- `has_value?/1` - Check if key exists with non-empty value
- `list/0` - List all configuration keys
- `put/2` - Set value at runtime
- `reload/0` - Reload from all sources
- `to_llm_atom/1` - Safe atom conversion for LLM keys

## Zero Dependencies

Minimal external dependencies - only uses:
- `Dotenvy` for environment file loading
- `Splode` for error handling

## Production Ready

- **Supervised GenServer** for reliability
- **Comprehensive error handling**
- **Type specifications** for all public functions
- **Extensive test coverage** (57 tests)
- **Code quality checks** (Credo, Dialyzer, formatting)

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run quality checks
mix quality

# Check formatting
mix format --check-formatted

# Run static analysis
mix dialyzer
mix credo --strict
```

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.
