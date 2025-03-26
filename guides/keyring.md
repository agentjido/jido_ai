# Jido AI Keyring

## Overview

The Jido AI Keyring helps manage LLM API Keys. It provides a centralized system for managing environment variables, API keys, and configuration settings across different environments and execution contexts with a hierarchical, context-aware approach.

### Key Features

- **Hierarchical Configuration**: Values are loaded with explicit precedence rules
- **Process-Specific Overrides**: Isolate configuration changes to specific processes with per-PID session values
- **Runtime Configuration**: Change settings without application restarts
- **Default Fallbacks**: Specify fallback values for missing configurations
- **Consistent API Provider Integration**: Seamless integration with various AI provider configurations
- **Automatic Startup**: Started automatically by `Jido.AI.Application`

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

The Keyring is automatically started by the `Jido.AI.Application` module, so you don't need to add it to your application's supervision tree. The relevant implementation is:

```elixir
# In Jido.AI.Application
defmodule Jido.AI.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Keyring GenServer
      Jido.AI.Keyring
    ]

    opts = [strategy: :one_for_one, name: Jido.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Retrieving Configuration Values

To retrieve values from the Keyring:

```elixir
# Basic usage with default value
api_key = Jido.AI.Keyring.get(:openai_api_key, "default_key")

# Without a default (returns nil if not found)
model_name = Jido.AI.Keyring.get(:model_name)

# High-level API convenience function
api_key = Jido.AI.get(:anthropic_api_key)
```

### Setting Session Values

Session values provide process-specific configuration overrides. Each process can have its own set of configuration values, which take precedence over environment values:

```elixir
# Override a value for the current process only
Jido.AI.Keyring.set_session_value(:openai_api_key, "test_key_for_this_process")

# Using high-level API
Jido.AI.set_session_value(:anthropic_api_key, "my_session_key")

# Set a value for a specific process (not just the current one)
other_pid = spawn(fn -> receive do :ok -> :ok end end)
Jido.AI.Keyring.set_session_value(:openai_api_key, "process_specific_key", other_pid)

# Later in the same process
api_key = Jido.AI.Keyring.get(:openai_api_key)  # Returns "test_key_for_this_process"
```

### Clearing Session Values

Remove process-specific overrides when no longer needed:

```elixir
# Clear a specific session value for the current process
Jido.AI.Keyring.clear_session_value(:openai_api_key)

# Clear a specific session value for another process
Jido.AI.Keyring.clear_session_value(:openai_api_key, other_pid)

# Clear all session values for the current process
Jido.AI.Keyring.clear_all_session_values()

# Clear all session values for another process
Jido.AI.Keyring.clear_all_session_values(other_pid)

# Using high-level API (always operates on current process)
Jido.AI.clear_session_value(:anthropic_api_key)
Jido.AI.clear_all_session_values()
```

## Configuration Sources

### Environment Variables with Dotenvy

The Keyring uses the Dotenvy library under the hood to load environment variables from multiple sources. It automatically loads variables from several locations in a specific order:

```
./envs/.env                    # Base environment file
./envs/.{environment}.env      # Environment-specific (dev/test/prod)
./envs/.{environment}.overrides.env  # Local overrides (not committed to source control)
System environment variables   # OS-level environment variables
```

Dotenvy handles type conversion, with all values loaded as strings by default. For more complex types, use the application environment configuration.

Environment variables are converted to atoms by:
1. Converting to lowercase
2. Replacing non-alphanumeric characters with underscores

Example:
```
OPENAI_API_KEY=sk-123456789 → :openai_api_key
```

Here's how the implementation loads environment variables:

```elixir
defp load_from_env do
  env_dir_prefix = Path.expand("./envs/")

  Dotenvy.source!([
    Path.join(File.cwd!(), ".env"),
    Path.absname(".env", env_dir_prefix),
    Path.absname(".#{Mix.env()}.env", env_dir_prefix),
    Path.absname(".#{Mix.env()}.overrides.env", env_dir_prefix),
    System.get_env()
  ])
  |> Enum.reduce(%{}, fn {key, value}, acc ->
    atom_key = env_var_to_atom(key)
    Map.put(acc, atom_key, value)
  end)
end
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

## Integration with AI Providers

The Keyring is designed to seamlessly work with various AI providers in the Jido ecosystem. It's a critical component for the `Model` module and provider adapters:

```elixir
defmodule MyAI do
  alias Jido.AI.Model
  
  def generate_response(prompt) do
    # The API key is automatically retrieved from Keyring
    {:ok, model} = Model.from({:anthropic, [model: "claude-3-opus"]})
    
    # Use the model with automatic API key management
    ChatClient.generate(model, prompt)
  end
end
```

### Provider Keys

The Keyring looks for provider-specific keys in the following formats:

- OpenAI: `:openai_api_key` or `OPENAI_API_KEY`
- Anthropic: `:anthropic_api_key` or `ANTHROPIC_API_KEY`
- OpenRouter: `:openrouter_api_key` or `OPENROUTER_API_KEY`
- Cloudflare: `:cloudflare_api_key` or `CLOUDFLARE_API_KEY`
- Google: `:google_api_key` or `GOOGLE_API_KEY`

## Advanced Usage

### Process Isolation for Testing

Session values are isolated to the calling process, making them ideal for testing. The Keyring's implementation uses ETS tables to store process-specific values, indexed by the process PID:

```elixir
defmodule MyTest do
  use ExUnit.Case
  alias Jido.AI.Keyring

  setup do
    # Override configuration for this test only
    Keyring.set_session_value(:anthropic_api_key, "test_key")
    Keyring.set_session_value(:model, "test-model-name")
    
    on_exit(fn -> 
      # Clean up after the test
      Keyring.clear_all_session_values()
    end)
    
    :ok
  end
  
  test "my feature with mocked API key" do
    # Test code will use the session values
    assert MyModule.process() == :expected_result
  end
end
```

Under the hood, the session storage works by inserting values into an ETS table with the process PID as part of the key:

```elixir
def set_session_value(server \\ @default_name, key, value, pid \\ self()) when is_atom(key) do
  registry = GenServer.call(server, :get_registry)
  :ets.insert(registry, {{pid, key}, value})
  :ok
end
```

### Named Instances

For more complex applications, you can run multiple Keyring instances:

```elixir
# Start a custom Keyring instance
{:ok, _pid} = Jido.AI.Keyring.start_link(name: :custom_keyring, registry: :custom_registry)

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

The Keyring provides a helper function to check if values are valid:

```elixir
@spec has_value?(term()) :: boolean()
def has_value?(nil), do: false
def has_value?(""), do: false
def has_value?(value) when is_binary(value), do: true
def has_value?(_), do: false
```

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

## Implementation Details

### ETS Table for Session Storage

The Keyring uses ETS (Erlang Term Storage) for session values, providing:

- Efficient key-value lookups
- Process-specific storage
- Automatic cleanup when processes terminate

### Loading from Environment Files

The implementation leverages Dotenvy for sophisticated environment file loading:

```elixir
env_dir_prefix = Path.expand("./envs/")

Dotenvy.source!([
  Path.join(File.cwd!(), ".env"),
  Path.absname(".env", env_dir_prefix),
  Path.absname(".#{Mix.env()}.env", env_dir_prefix),
  Path.absname(".#{Mix.env()}.overrides.env", env_dir_prefix),
  System.get_env()
])
```

### Conversion of Environment Variables

Environment variables are automatically converted to atom keys for consistent access:

```elixir
defp env_var_to_atom(env_var) do
  env_var
  |> String.downcase()
  |> String.replace(~r/[^a-z0-9_]/, "_")
  |> String.to_atom()
end
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

### How does the Keyring handle multiple environments?

The Keyring loads environment-specific files based on the current Mix environment:

```elixir
Path.absname(".#{Mix.env()}.env", env_dir_prefix)
```

This allows for different configurations in development, test, and production environments.

## Common Questions

### How does the Keyring handle environment variable types?

The Keyring uses Dotenvy under the hood, which loads values as strings by default. For typed values, use the application environment configuration:

```elixir
# In config/config.exs
config :jido_ai, :keyring, %{
  max_tokens: 2048,  # integer
  temperature: 0.7,  # float
  use_cache: true    # boolean
}
```

### What happens if a process terminates?

Session values are automatically cleaned up when a process terminates, as they're stored in an ETS table with the process PID as part of the key. This prevents memory leaks.

### Can I get values for other processes?

Yes, the Keyring supports specifying a PID when getting session values:

```elixir
# Get a value for another process
other_pid = spawn(fn -> receive do :ok -> :ok end end)
value = Jido.AI.Keyring.get_session_value(:my_key, other_pid)
```

### Is the Keyring thread-safe?

Yes, the Keyring uses ETS for session storage and GenServer for environment values, both of which are thread-safe in Elixir's concurrent environment.