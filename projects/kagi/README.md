# Kagi

**Centralized configuration and secret management system for the Jido ecosystem**

Kagi provides a centralized system for managing environment variables, API keys, and configuration settings across different environments and execution contexts with a hierarchical, context-aware approach. While originally designed to handle LLM API keys for the Jido AI ecosystem, Kagi can manage any type of environment variable or configuration setting.

## Jido Ecosystem Integration

Kagi was extracted from the [Jido AI](https://github.com/agentjido/jido) project to provide standalone configuration management that can be shared across the entire Jido ecosystem of AI agent libraries. It handles sensitive credentials like OpenAI API keys, Anthropic tokens, and other LLM provider authentication while maintaining security best practices.

## Livebook Support

Kagi has special support for [Livebook](https://livebook.dev/) environments, where environment variables are prefixed with `LB_`. For example:

```bash
# In your Livebook environment
LB_OPENAI_API_KEY=sk-1234567890
LB_ANTHROPIC_API_KEY=sk-ant-1234567890
```

These are automatically detected and made available as `:openai_api_key` and `:anthropic_api_key` respectively, making it seamless to use LLM APIs within Livebook notebooks.

## Installation

Add `kagi` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:kagi, "~> 0.1.0"}
  ]
end
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc) and published on [HexDocs](https://hexdocs.pm). Once published, the docs can be found at <https://hexdocs.pm/kagi>.

## Overview

Kagi helps manage configuration values and API keys with a focus on security and flexibility. While it excels at handling LLM provider credentials (OpenAI, Anthropic, Google AI, etc.), it can manage any configuration setting your application needs.

### Key Features

- **LLM-Ready**: Optimized for managing API keys for OpenAI, Anthropic, Google AI, and other LLM providers
- **Hierarchical Configuration**: Values are loaded with explicit precedence rules
- **Process-Specific Overrides**: Isolate configuration changes to specific processes with per-PID session values
- **Livebook Integration**: Special handling for `LB_`-prefixed environment variables
- **Runtime Configuration**: Change settings without application restarts
- **Security First**: Built-in logger filter to prevent accidental credential exposure
- **Default Fallbacks**: Specify fallback values for missing configurations
- **Automatic Startup**: Started automatically by `Kagi.Application`

## Conceptual Model

The Keyring implements a hierarchical lookup system with the following precedence (highest to lowest):

1. **Session Values**: Process-specific overrides (stored in ETS)
2. **Environment Variables**: System-wide environment settings (via Dotenvy)
3. **Application Environment**: Configuration in your application
4. **Default Values**: Fallbacks for missing configurations

```
Session Values → Environment Variables → Application Environment → Default Values
                         (highest)                                    (lowest)
```

## Basic Usage

### Installation

Kagi is automatically started by the `Kagi.Application` module, so you don't need to add it to your application's supervision tree. The relevant implementation is:

```elixir
# In Kagi.Application
defmodule Kagi.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Keyring GenServer
      Kagi
    ]

    opts = [strategy: :one_for_one, name: Kagi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Retrieving Configuration Values

To retrieve values from Kagi:

```elixir
# Get LLM API keys (common use case)
openai_key = Kagi.get(:openai_api_key, "default_key")
anthropic_key = Kagi.get(:anthropic_api_key)

# Get any configuration value
model_name = Kagi.get(:model_name, "gpt-4")
temperature = Kagi.get(:temperature, 0.7)
```

### Setting Session Values

Session values provide process-specific configuration overrides. Each process can have its own set of configuration values, which take precedence over environment values:

```elixir
# Override a value for the current process only
Kagi.set_session_value(:openai_api_key, "test_key_for_this_process")

# Set a value for a specific process (not just the current one)
other_pid = spawn(fn -> receive do :ok -> :ok end end)
Kagi.set_session_value(:openai_api_key, "process_specific_key", other_pid)

# Later in the same process
api_key = Kagi.get(:openai_api_key)  # Returns "test_key_for_this_process"
```

### Clearing Session Values

Remove process-specific overrides when no longer needed:

```elixir
# Clear a specific session value for the current process
Kagi.clear_session_value(:openai_api_key)

# Clear a specific session value for another process
Kagi.clear_session_value(:openai_api_key, other_pid)

# Clear all session values for the current process
Kagi.clear_all_session_values()

# Clear all session values for another process
Kagi.clear_all_session_values(other_pid)
```

## Configuration Sources

### Environment Variables with Dotenvy

Kagi uses the Dotenvy library under the hood to load environment variables from multiple sources. It automatically loads variables from several locations in a specific order:

```
./envs/.env                    # Base environment file
./envs/.{environment}.env      # Environment-specific (dev/test/prod)
./envs/.{environment}.overrides.env  # Local overrides (not committed to source control)
System environment variables   # OS-level environment variables
```

#### Livebook Support

Special handling for Livebook environments where variables are prefixed with `LB_`:

```bash
# Environment variables in Livebook
LB_OPENAI_API_KEY=sk-1234567890
LB_ANTHROPIC_API_KEY=sk-ant-1234567890
LB_GOOGLE_AI_API_KEY=AIza1234567890

# Accessed in code as:
Kagi.get(:openai_api_key)     # Returns "sk-1234567890"
Kagi.get(:anthropic_api_key)  # Returns "sk-ant-1234567890"
Kagi.get(:google_ai_api_key)  # Returns "AIza1234567890"
```

Environment variables are converted to atoms by:
1. Converting to lowercase
2. Replacing non-alphanumeric characters with underscores
3. Removing common prefixes like `LB_`

Examples:
```
OPENAI_API_KEY=sk-123456789 → :openai_api_key
LB_ANTHROPIC_API_KEY=sk-ant-123 → :anthropic_api_key
GOOGLE_AI_API_KEY=AIza123 → :google_ai_api_key
```

### Application Environment

Configure values in your `config/config.exs` or environment-specific config files:

```elixir
# In config/config.exs
config :kagi, :keyring, %{
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  model_name: "gpt-4",
  temperature: 0.7
}
```

## Advanced Usage

### Process Isolation for Testing

Session values are isolated to the calling process, making them ideal for testing LLM integrations. Kagi's implementation uses ETS tables to store process-specific values, indexed by the process PID:

```elixir
defmodule MyAITest do
  use ExUnit.Case
  alias Kagi

  setup do
    # Override LLM API keys for this test only
    Kagi.set_session_value(:openai_api_key, "test-openai-key")
    Kagi.set_session_value(:anthropic_api_key, "test-anthropic-key")
    Kagi.set_session_value(:model, "gpt-4-test")
    
    on_exit(fn -> 
      # Clean up after the test
      Kagi.clear_all_session_values()
    end)
    
    :ok
  end
  
  test "AI agent with mocked credentials" do
    # Test code will use the session values for LLM calls
    assert MyAIAgent.process() == :expected_result
  end
end
```

### Named Instances

For more complex applications, you can run multiple Kagi instances (useful for multi-tenant LLM applications):

```elixir
# Start a custom instance for a specific tenant
{:ok, _pid} = Kagi.start_link(name: :tenant_a_kagi, registry: :tenant_a_registry)

# Use the custom instance
api_key = Kagi.get(:tenant_a_kagi, :openai_api_key)
```

### Value Validation

Check if a configuration value is set and non-empty:

```elixir
api_key = Kagi.get(:openai_api_key)

if Kagi.has_value?(api_key) do
  # Proceed with API request
else
  # Handle missing configuration
  {:error, "OpenAI API key not configured"}
end
```

## Debugging Tips

List all available configuration keys:

```elixir
Kagi.list()
# => [:openai_api_key, :anthropic_api_key, :[REDACTED:api-key], ...]
```

Compare environment and session values:

```elixir
# Get the environment value directly
env_value = Kagi.get_env_value(:openai_api_key)

# Get the session value
session_value = Kagi.get_session_value(:openai_api_key)

# Get the effective value (session overrides environment)
effective_value = Kagi.get(:openai_api_key)
```

## Testing Support

Kagi includes a test case template for easier testing with isolated Keyring environments:

```elixir
defmodule MyTest do
  use Kagi.TestSupport.KeyringCase

  test "with environment variable" do
    env(openai_api_key: "test-key-123") do
      # Test code that expects OPENAI_API_KEY environment variable
      assert Kagi.get(:openai_api_key) == "test-key-123"
    end
  end

  test "with session override" do
    session(openai_api_key: "session-key") do
      # Test code that expects session override
      assert_value(:openai_api_key, "session-key")
    end
  end
end
```

## Logger Filter

Kagi includes a logger filter that automatically redacts sensitive information from log output:

```elixir
# In config/config.exs
config :logger, :console,
  format: {Kagi.Filter, :format}
```

The filter automatically identifies and redacts:
- API keys (any key containing "api_key", "apikey", "key")
- Tokens (any key containing "token", "auth", "bearer")
- Passwords and secrets (any key containing "password", "secret", "pass")
- Private keys and certificates (any key containing "private", "cert", "pem")
