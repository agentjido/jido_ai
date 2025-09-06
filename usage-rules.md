# Kagi Usage Rules

Kagi is a centralized configuration and secret management system for Elixir applications, optimized for LLM API keys and Livebook environments.

## Core Principles

- **Hierarchical Configuration**: Session values override environment variables, which override application config, which override defaults
- **Process Isolation**: Session values are scoped to specific processes for safe testing and isolation
- **Livebook Integration**: Automatically handles `LB_` prefixed environment variables
- **Security First**: Built-in filtering prevents accidental credential exposure in logs

## Primary API Functions

### Configuration Retrieval

**ALWAYS use `Kagi.get/2` or `Kagi.get!/1` for retrieving configuration values:**

```elixir
# Correct - with default value
api_key = Kagi.get(:openai_api_key, "fallback_key")

# Correct - without default (returns nil if not found)
api_key = Kagi.get(:openai_api_key)

# Correct - raises ArgumentError if not found
api_key = Kagi.get!(:openai_api_key)
```

### Checking Configuration

**USE `Kagi.has?/1` and `Kagi.has_value?/1` for validation:**

```elixir
# Check if key exists (even if empty)
if Kagi.has?(:openai_api_key) do
  # Key exists
end

# Check if key has meaningful value (not nil or empty string)
if Kagi.has_value?(:openai_api_key) do
  # Key has actual value
end
```

### Configuration Management

**RELOAD configuration dynamically when needed:**

```elixir
# Correct - reload configuration
Kagi.reload()

# With options for future extensions
Kagi.reload(force: true)
```

**LIST available configuration keys:**

```elixir
# Get all loaded keys
keys = Kagi.list()
```

**DO NOT directly access environment variables when using Kagi:**

```elixir
# Incorrect - bypasses Kagi's hierarchical lookup
api_key = System.get_env("OPENAI_API_KEY")
```

### Key Naming Conventions

**USE lowercase atoms with underscores for keys:**

```elixir
# Correct
Kagi.get(:openai_api_key)
Kagi.get(:anthropic_api_key)
Kagi.get(:model_temperature)

# Avoid - inconsistent with environment variable normalization
Kagi.get(:OPENAI_API_KEY)
Kagi.get(:"openai-api-key")
```

### Environment Variable Mapping

**UNDERSTAND the automatic key normalization:**

- Environment variables are converted to lowercase atoms
- Non-alphanumeric characters become underscores
- `LB_` prefix is stripped for Livebook compatibility

```elixir
# Environment: OPENAI_API_KEY=sk-123 → :openai_api_key
# Environment: LB_ANTHROPIC_API_KEY=sk-ant-123 → :anthropic_api_key
```

## Configuration Patterns

### Application Setup

**CONFIGURE defaults in application environment:**

```elixir
# config/config.exs
config :kagi, :keyring, %{
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  model_name: "gpt-4",
  temperature: 0.7
}
```

### Livebook Usage

**LEVERAGE Livebook's `LB_` prefix pattern:**

```elixir
# In Livebook, set: LB_OPENAI_API_KEY=sk-123
# Access as: Kagi.get(:openai_api_key)
```

## Security Rules

**ENABLE log filtering to prevent credential exposure:**

```elixir
# Application configuration
config :kagi, Kagi.LogFilter,
  enabled: true,
  redaction_text: "[REDACTED]"

# Logger integration
config :logger, :console,
  metadata_filter: {Kagi.LogFilter, :filter}
```

**CONFIGURE log filter dynamically if needed:**

```elixir
# Correct - use LogFilter module for configuration
Kagi.LogFilter.configure(enabled: false)
Kagi.LogFilter.configure(redaction_text: "***HIDDEN***")

# Incorrect - manual logging of sensitive data
Logger.info("API Key: #{api_key}")
```

**VALIDATE key existence before use:**

```elixir
# Correct - check if key has value
if Kagi.has_value?(:openai_api_key) do
  # Proceed with API call
else
  {:error, "API key not configured"}
end
```

## Common Anti-Patterns

**AVOID directly checking environment variables:**

```elixir
# Incorrect - bypasses session overrides
case System.get_env("API_KEY") do
  nil -> "default"
  key -> key
end
```

**AVOID hardcoding sensitive values:**

```elixir
# Incorrect - security risk
api_key = "sk-1234567890"
```

## Error Handling

**USE `Kagi.get!/1` for required configuration:**

```elixir
# Correct - raises ArgumentError with clear message if missing
api_key = Kagi.get!(:openai_api_key)
```

**PROVIDE meaningful defaults with `Kagi.get/2`:**

```elixir
# Correct - graceful fallback
temperature = Kagi.get(:model_temperature, 0.7)
```

**CHECK for configuration completeness at startup:**

```elixir
def validate_config! do
  required_keys = [:openai_api_key, :anthropic_api_key]
  
  Enum.each(required_keys, fn key ->
    unless Kagi.has_value?(key) do
      raise ArgumentError, "Missing required configuration: #{key}"
    end
  end)
end
```
