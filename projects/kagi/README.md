# Kagi

[![Hex.pm](https://img.shields.io/hexpm/v/kagi.svg)](https://hex.pm/packages/kagi)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/kagi)
[![License](https://img.shields.io/hexpm/l/kagi.svg)](https://github.com/agentjido/kagi/blob/main/LICENSE)
[![Build Status](https://img.shields.io/github/actions/workflow/status/agentjido/kagi/ci.yml?branch=main)](https://github.com/agentjido/kagi/actions)

**Centralized configuration and secret management system for Elixir applications**

Kagi provides a robust, hierarchical configuration management system designed specifically for modern Elixir applications. Originally built for the [Jido AI ecosystem](https://github.com/agentjido/jido), Kagi excels at managing sensitive credentials like API keys while supporting any type of configuration value.

## Features

- **Secure by Design** - Built-in log filtering prevents credential exposure
- **LLM-Ready** - Optimized for AI/ML API key management
- **Hierarchical Configuration** - Clear precedence rules with multiple sources
- **Runtime Updates** - Change configuration without restarts
- **Process Isolation** - Perfect for testing with per-process overrides
- **Livebook Integration** - Special support for `LB_` prefixed variables
- **Zero Configuration** - Works out of the box with sensible defaults

## Installation

Add `kagi` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kagi, "~> 0.1.0"}
  ]
end
```

Kagi starts automatically with your application - no additional setup required.

## Quick Start

```elixir
# Get configuration values with optional defaults
api_key = Kagi.get(:openai_api_key, "fallback_key")
model = Kagi.get(:model_name, "gpt-4")

# Check if a value exists and is non-empty
if Kagi.has?(:openai_api_key) do
  # Make API call
end

# Simple retrieval with default
api_key = Kagi.get(:api_key, "default_key")

# Raise on missing values
secret = Kagi.get!(:required_secret)

# List all available configuration keys
Kagi.list()
```

## Configuration Hierarchy

Kagi uses a hierarchical lookup system with clear precedence rules:

```
1. Process Session Values (highest priority)
2. Environment Variables  
3. Application Environment
4. Default Values (lowest priority)
```

### Environment Variables

Kagi automatically loads environment variables using the [Dotenvy](https://hexdocs.pm/dotenvy) library:

```bash
# .env file
OPENAI_API_KEY=sk-1234567890
ANTHROPIC_API_KEY=sk-ant-1234567890
DATABASE_URL=postgresql://localhost/myapp
```

```elixir
# Access in your application
Kagi.get(:openai_api_key)    # "sk-1234567890"
Kagi.get(:database_url)      # "postgresql://localhost/myapp"
```

### Livebook Support

Special handling for Livebook environments where variables are prefixed with `LB_`:

```bash
# In Livebook
LB_OPENAI_API_KEY=sk-1234567890
LB_MODEL_NAME=gpt-4
```

```elixir
# Access without the prefix
Kagi.get(:openai_api_key)  # "sk-1234567890"
Kagi.get(:model_name)      # "gpt-4"
```

### Application Configuration

Configure defaults in your application config:

```elixir
# config/config.exs
config :my_app,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  model_name: "gpt-4",
  temperature: 0.7
```

## Advanced Usage

### Process Session Values

Set process-specific configuration overrides for testing or temporary changes:

```elixir
# Override for current process only
Kagi.set_session_value(:api_key, "test_key")
Kagi.get(:api_key)  # Returns "test_key"

# Clear session values
Kagi.clear_session_value(:api_key)
Kagi.clear_all_session_values()
```

### Testing Support

Session values are isolated per process, making testing seamless:

```elixir
defmodule MyAITest do
  use ExUnit.Case

  setup do
    # Set test credentials for this process only
    Kagi.set_session_value(:openai_api_key, "test-key")
    Kagi.set_session_value(:model, "gpt-3.5-turbo")
    
    on_exit(fn -> Kagi.clear_all_session_values() end)
    :ok
  end

  test "AI integration with mocked credentials" do
    # Your test code here - will use test credentials
    assert MyAI.generate_response("Hello") == "Test response"
  end
end
```

### Security & Logging

Kagi includes automatic log filtering to prevent credential exposure:

```elixir
# Configure in config/config.exs
config :logger, :console,
  filters: [Kagi.LogFilter]
```

The filter automatically redacts:
- API keys and tokens
- Passwords and secrets  
- Private keys and certificates
- Any sensitive-looking configuration values

### Named Instances

For advanced use cases, run multiple Kagi instances:

```elixir
# Start additional instances
{:ok, _pid} = Kagi.Server.start_link(name: :tenant_config)

# Use specific instance
api_key = Kagi.get(:tenant_config, :api_key)
```

## Real-World Examples

### LLM API Management

```elixir
defmodule MyAI.Client do
  def openai_request(prompt) do
    api_key = Kagi.get!(:openai_api_key)
    model = Kagi.get(:openai_model, "gpt-4")
    
    # Make API request with retrieved configuration
    HTTPoison.post(
      "https://api.openai.com/v1/chat/completions",
      Jason.encode!(%{
        model: model,
        messages: [%{role: "user", content: prompt}]
      }),
      [{"Authorization", "Bearer #{api_key}"}]
    )
  end
end
```

### Database Configuration

```elixir
defmodule MyApp.Repo do
  def config do
    database_url = Kagi.get(:database_url)
    pool_size = Kagi.get(:database_pool_size, "10") |> String.to_integer()
    
    [
      url: database_url,
      pool_size: pool_size
    ]
  end
end
```

### Multi-Environment Setup

```elixir
# config/dev.exs
config :my_app,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  log_level: :debug

# config/prod.exs  
config :my_app,
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  log_level: :info

# config/test.exs
config :my_app,
  openai_api_key: "test_key_for_mocking"
```

## API Reference

### Core Functions

- `get/2` - Retrieve value with optional default
- `get!/1` - Return value or raise exception
- `has?/1` - Check if key exists with non-empty value
- `list/0` - List all available configuration keys

### Session Management

- `set_session_value/2` - Set process-specific override
- `clear_session_value/1` - Remove process-specific override
- `clear_all_session_values/0` - Clear all session values for current process

### Debugging

- `reload/0` - Reload configuration from all sources
- `get_env_value/1` - Get value from environment only
- `get_session_value/1` - Get value from session only

## Development

```bash
# Install dependencies
mix deps.get

# Run tests
mix test

# Run quality checks (format, compile, dialyzer, credo)
mix quality

# Check formatting
mix format --check-formatted

# Run static analysis
mix dialyzer
mix credo --strict
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Run the quality checks (`mix quality`)
4. Commit your changes (`git commit -am 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built for the [Jido AI ecosystem](https://github.com/agentjido/jido)
- Powered by [Dotenvy](https://hexdocs.pm/dotenvy) for environment variable management
- Inspired by the need for secure, hierarchical configuration in AI applications
