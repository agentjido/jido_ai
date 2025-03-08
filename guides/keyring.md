# Jido AI Keyring

## Overview

The Keyring module provides a robust configuration management solution for Elixir applications built with Jido AI. It solves the common challenge of managing environment variables, API keys, and configuration settings across different environments and contexts.

### Key Features

- **Hierarchical Configuration**: Values are loaded with clear precedence rules
- **Process-Specific Overrides**: Isolate configuration changes to specific processes
- **Runtime Configuration**: Change settings without application restarts
- **Default Fallbacks**: Specify fallback values for missing configurations

## Conceptual Model

The Keyring implements a hierarchical lookup system with the following precedence (highest to lowest):

1. **Session Values**: Process-specific overrides
2. **Environment Variables**: System-wide environment settings
3. **Application Environment**: Configuration in your application
4. **Default Values**: Fallbacks for missing configurations

```
Session Values → Environment Variables → Application Environment → Default Values
                         (highest)                                    (lowest)
```

## Basic Usage

### Installation

Ensure the Keyring is started as part of your application's supervision tree:

```elixir
# In your application.ex
def start(_type, _args) do
  children = [
    Jido.AI.Keyring
    # other children...
  ]

  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Retrieving Configuration Values

To retrieve values from the Keyring:

```elixir
# Basic usage with default value
api_key = Jido.AI.Keyring.get(:openai_api_key, "default_key")

# Without a default (returns nil if not found)
model_name = Jido.AI.Keyring.get(:model_name)
```

### Setting Session Values

Session values provide process-specific configuration overrides:

```elixir
# Override a value for the current process only
Jido.AI.Keyring.set_session_value(:openai_api_key, "test_key_for_this_process")

# Later in the same process
api_key = Jido.AI.Keyring.get(:openai_api_key)  # Returns "test_key_for_this_process"
```

### Clearing Session Values

Remove process-specific overrides when no longer needed:

```elixir
# Clear a specific session value
Jido.AI.Keyring.clear_session_value(:openai_api_key)

# Clear all session values for the current process
Jido.AI.Keyring.clear_all_session_values()
```

## Configuration Sources

### Environment Variables

The Keyring automatically loads variables from several locations:

```
./envs/.env                    # Base environment file
./envs/.dev.env                # Environment-specific (dev/test/prod)
./envs/.dev.overrides.env      # Local overrides (not committed to source control)
System environment variables   # OS-level environment variables
```

Environment variables are converted to atoms by:
1. Converting to lowercase
2. Replacing non-alphanumeric characters with underscores

Example:
```
OPENAI_API_KEY=sk-123456789 → :openai_api_key
```

### Application Environment

Configure values in your `config/config.exs` or environment-specific config files:

```elixir
# In config/config.exs
config :jido_ai, :keyring, %{
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  model_name: "gpt-4",
  temperature: 0.7
}
```

## Advanced Usage

### Process Isolation

Session values are isolated to the calling process, making them ideal for:

- Testing with different configurations
- Request-specific settings
- Temporary overrides without affecting other parts of the system

```elixir
# In Process A
Jido.AI.Keyring.set_session_value(:model_name, "gpt-4")

# In Process B (will not see Process A's override)
model = Jido.AI.Keyring.get(:model_name)  # Returns the environment or application value
```

### Named Instances

For more complex applications, you can run multiple Keyring instances:

```elixir
# Start a custom Keyring instance
{:ok, _pid} = Jido.AI.Keyring.start_link(name: :custom_keyring)

# Use the custom instance
api_key = Jido.AI.Keyring.get(:custom_keyring, :openai_api_key)
```

### Value Validation

Check if a configuration value is set and non-empty:

```elixir
api_key = Jido.AI.Keyring.get(:openai_api_key)

if Jido.AI.Keyring.has_value?(api_key) do
  # Proceed with API request
else
  # Handle missing configuration
  {:error, "OpenAI API key not configured"}
end
```

## Testing Strategies

The Keyring's process isolation makes it ideal for testing:

```elixir
defmodule MyTest do
  use ExUnit.Case
  alias Jido.AI.Keyring

  setup do
    # Override configuration for this test
    Keyring.set_session_value(:openai_api_key, "test_key")
    Keyring.set_session_value(:model_name, "test_model")
    
    on_exit(fn -> 
      # Clean up after the test
      Keyring.clear_all_session_values()
    end)
    
    :ok
  end
  
  test "my feature with custom configuration" do
    # Test code will use the session values
    assert MyModule.process() == :expected_result
  end
end
```

## Common Patterns

### Feature Flags

Use the Keyring to implement simple feature flags:

```elixir
def process_with_experimental_feature(data) do
  if Jido.AI.Keyring.get(:enable_experimental_feature, false) do
    process_with_new_algorithm(data)
  else
    process_with_standard_algorithm(data)
  end
end
```

### Multi-tenant Configurations

For multi-tenant applications, use session values in tenant-specific processes:

```elixir
defmodule TenantManager do
  def with_tenant_config(tenant_id, fun) do
    # Set tenant-specific configuration
    tenant_config = load_tenant_config(tenant_id)
    Enum.each(tenant_config, fn {key, value} ->
      Jido.AI.Keyring.set_session_value(key, value)
    end)
    
    try do
      # Execute function with tenant configuration
      fun.()
    after
      # Clean up
      Jido.AI.Keyring.clear_all_session_values()
    end
  end
end

# Usage
TenantManager.with_tenant_config("tenant-123", fn ->
  MyModule.process_for_tenant()
end)
```

## Common Questions

### How does the Keyring handle environment variable types?

By default, all values are loaded as strings. For more complex types, use the application environment to define typed values:

```elixir
# In config/config.exs
config :jido_ai, :keyring, %{
  max_tokens: 2048,  # integer
  temperature: 0.7,  # float
  use_cache: true    # boolean
}
```

### Can I modify environment values at runtime?

The Keyring primarily focuses on reading environment values, but you can simulate updates using session values for the current process.

### What happens if a process terminates?

Session values are automatically cleaned up when a process terminates, preventing memory leaks.

## Debugging Tips

List all available configuration keys:

```elixir
Jido.AI.Keyring.list()
# => [:openai_api_key, :anthropic_api_key, :model_name, ...]
```

Compare environment and session values:

```elixir
# Get the environment value directly
env_value = Jido.AI.Keyring.get_env_value(:openai_api_key)

# Get the session value
session_value = Jido.AI.Keyring.get_session_value(:openai_api_key)

# Get the effective value (session overrides environment)
effective_value = Jido.AI.Keyring.get(:openai_api_key)
```

## Integration with Other Jido AI Components

The Keyring provides the foundation for configuration management across all Jido AI components:

```elixir
defmodule MyAI do
  use JidoAI.Actions.Instructor
  
  def generate_content(prompt) do
    # The Keyring provides the API key automatically
    # No need to pass it explicitly
    run_prompt(prompt)
  end
end
```