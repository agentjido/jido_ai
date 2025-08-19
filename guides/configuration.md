# Configuration Guide

**Prerequisites**: Basic Elixir configuration knowledge

Configure Jido Action's runtime behavior, timeouts, telemetry, and application-specific settings for your environment.

## Application Configuration

### Basic Setup

Add to your `config/config.exs`:

```elixir
import Config

config :jido_action,
  # Global timeouts (milliseconds)
  default_timeout: 5_000,
  default_async_timeout: 30_000,
  
  # Retry configuration
  default_max_retries: 3,
  default_retry_delay: 1_000,
  default_retry_backoff: 2.0,
  default_retry_jitter: 0.1,
  
  # Telemetry settings
  telemetry_enabled: true,
  telemetry_events: [:start, :stop, :exception],
  
  # Validation settings
  strict_validation: true,
  validate_outputs: false
```

### Environment-Specific Configuration

```elixir
# config/dev.exs
import Config

config :jido_action,
  default_timeout: 10_000,        # Longer timeouts in dev
  validate_outputs: true,         # Enable output validation
  telemetry_enabled: true

# config/test.exs  
import Config

config :jido_action,
  default_timeout: 1_000,         # Faster timeouts in tests
  default_max_retries: 0,         # No retries in tests
  telemetry_enabled: false        # Reduce noise in tests

# config/prod.exs
import Config

config :jido_action,
  default_timeout: 5_000,
  default_max_retries: 5,         # More retries in production
  strict_validation: true,
  telemetry_enabled: true
```

## Runtime Configuration

### Per-Action Configuration

Actions can override global defaults:

```elixir
defmodule MyApp.Actions.SlowOperation do
  use Jido.Action,
    name: "slow_operation",
    # Override global timeout for this action
    default_timeout: 30_000,
    schema: [data: [type: :string, required: true]]

  def run(params, _context) do
    # Long-running operation
    :timer.sleep(20_000)
    {:ok, %{processed: params.data}}
  end
end
```

### Execution-Time Configuration

Override settings when executing actions:

```elixir
# Override timeout and retries for specific execution
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.SlowOperation,
  %{data: "input"},
  %{},
  timeout: 60_000,           # 60 second timeout
  max_retries: 10,           # 10 retries
  retry_delay: 2_000,        # 2 second initial delay
  retry_backoff: 1.5         # 1.5x backoff multiplier
)
```

### Configuration Access

Access configuration in your actions:

```elixir
defmodule MyApp.Actions.ConfigAware do
  use Jido.Action

  def run(params, _context) do
    # Get application configuration
    timeout = Application.get_env(:jido_action, :default_timeout, 5_000)
    api_key = Application.get_env(:my_app, :api_key)
    
    # Use configuration in business logic
    case make_api_call(params, api_key, timeout) do
      {:ok, result} -> {:ok, result}
      {:error, reason} -> {:error, reason}
    end
  end
end
```

## Telemetry Configuration

### Event Configuration

Control which telemetry events are emitted:

```elixir
config :jido_action,
  telemetry_enabled: true,
  telemetry_events: [
    :start,        # Action execution starts
    :stop,         # Action execution completes
    :exception,    # Action execution fails
    :validation,   # Parameter validation events
    :compensation  # Compensation events
  ]
```

### Custom Telemetry Handlers

Set up telemetry handlers for monitoring:

```elixir
# In your application.ex
def start(_type, _args) do
  # Attach telemetry handlers
  :telemetry.attach_many(
    "jido-action-handlers",
    [
      [:jido, :exec, :start],
      [:jido, :exec, :stop], 
      [:jido, :exec, :exception]
    ],
    &MyApp.Telemetry.handle_event/4,
    %{}
  )
  
  # Start your supervision tree
  children = [...]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

### Telemetry Handler Implementation

```elixir
defmodule MyApp.Telemetry do
  require Logger

  def handle_event([:jido, :exec, :start], _measurements, metadata, _config) do
    Logger.info("Action started",
      action: metadata.action,
      instruction_id: metadata.instruction_id
    )
  end

  def handle_event([:jido, :exec, :stop], measurements, metadata, _config) do
    Logger.info("Action completed",
      action: metadata.action,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
    
    # Send metrics to monitoring system
    :telemetry.execute(
      [:my_app, :action, :duration],
      %{duration: measurements.duration},
      %{action: metadata.action}
    )
  end

  def handle_event([:jido, :exec, :exception], measurements, metadata, _config) do
    Logger.error("Action failed",
      action: metadata.action,
      error: metadata.error.message,
      duration_ms: System.convert_time_unit(measurements.duration, :native, :millisecond)
    )
    
    # Send error metrics
    :telemetry.execute(
      [:my_app, :action, :error],
      %{count: 1},
      %{action: metadata.action, error_type: metadata.error.type}
    )
  end
end
```

## Security Configuration

### Input Validation

Configure strict validation rules:

```elixir
config :jido_action,
  # Strict validation rejects unknown parameters
  strict_validation: true,
  
  # Maximum parameter size (prevents DoS)
  max_param_size: 1_000_000,  # 1MB
  
  # Maximum nesting depth
  max_nesting_depth: 10
```

### Resource Limits

Control resource usage:

```elixir
config :jido_action,
  # Maximum concurrent async executions
  max_concurrent_executions: 100,
  
  # Memory limits for large operations
  max_memory_per_action: 100_000_000,  # 100MB
  
  # File system restrictions
  allow_file_operations: false,
  allowed_file_paths: ["/tmp", "/var/data"]
```

### Action Allowlists

Restrict which actions can be executed:

```elixir
config :jido_action,
  # Only allow specific actions in production
  allowed_actions: [
    MyApp.Actions.SafeOperation,
    MyApp.Actions.ValidatedProcess,
    # Built-in tools
    Jido.Tools.Arithmetic.Add,
    Jido.Tools.Basic.Sleep
  ],
  
  # Deny dangerous actions
  denied_actions: [
    MyApp.Actions.DangerousOperation
  ]
```

## Environment Variables

Support runtime configuration via environment variables:

```elixir
# config/runtime.exs
import Config

config :jido_action,
  default_timeout: String.to_integer(System.get_env("JIDO_DEFAULT_TIMEOUT", "5000")),
  default_max_retries: String.to_integer(System.get_env("JIDO_MAX_RETRIES", "3")),
  telemetry_enabled: System.get_env("JIDO_TELEMETRY_ENABLED", "true") == "true"

# Database connection for actions that need it
config :my_app,
  database_url: System.get_env("DATABASE_URL"),
  api_key: System.get_env("API_KEY"),
  redis_url: System.get_env("REDIS_URL")
```

### Environment Variable Validation

Validate required environment variables:

```elixir
defmodule MyApp.Config do
  def validate_config! do
    required_env_vars = [
      "DATABASE_URL",
      "API_KEY",
      "SECRET_KEY_BASE"
    ]
    
    missing = Enum.filter(required_env_vars, fn var ->
      System.get_env(var) == nil
    end)
    
    unless Enum.empty?(missing) do
      raise "Missing required environment variables: #{Enum.join(missing, ", ")}"
    end
    
    :ok
  end
end

# In application.ex
def start(_type, _args) do
  MyApp.Config.validate_config!()
  # ... rest of startup
end
```

## Custom Configuration Modules

Create configuration modules for complex settings:

```elixir
defmodule MyApp.Config.Actions do
  @default_timeout 5_000
  @default_retries 3

  def get_timeout(action_module) do
    case action_module do
      MyApp.Actions.SlowOperation -> 30_000
      MyApp.Actions.QuickCheck -> 1_000
      _ -> Application.get_env(:jido_action, :default_timeout, @default_timeout)
    end
  end

  def get_retries(action_module) do
    case action_module do
      MyApp.Actions.CriticalOperation -> 10
      MyApp.Actions.BestEffort -> 1
      _ -> Application.get_env(:jido_action, :default_max_retries, @default_retries)
    end
  end

  def get_circuit_breaker_config(action_module) do
    %{
      failure_threshold: 5,
      recovery_time: 30_000,
      timeout: get_timeout(action_module)
    }
  end
end
```

## Testing Configuration

### Test-Specific Settings

```elixir
# test/support/test_config.ex
defmodule MyApp.TestConfig do
  def setup_test_env do
    # Override configuration for tests
    Application.put_env(:jido_action, :default_timeout, 1_000)
    Application.put_env(:jido_action, :default_max_retries, 0)
    Application.put_env(:jido_action, :telemetry_enabled, false)
    
    # Mock external services
    Application.put_env(:my_app, :api_base_url, "http://localhost:4002")
    Application.put_env(:my_app, :use_real_services, false)
  end
end

# In test_helper.exs
MyApp.TestConfig.setup_test_env()
```

### Configuration in Tests

```elixir
defmodule MyApp.Actions.ConfigurableTest do
  use ExUnit.Case
  
  setup do
    # Save original config
    original_timeout = Application.get_env(:jido_action, :default_timeout)
    
    on_exit(fn ->
      # Restore original config
      Application.put_env(:jido_action, :default_timeout, original_timeout)
    end)
    
    %{original_timeout: original_timeout}
  end
  
  test "respects custom timeout configuration" do
    # Set test-specific timeout
    Application.put_env(:jido_action, :default_timeout, 100)
    
    # Test action behavior with short timeout
    assert {:error, %{type: :timeout_error}} = 
      Jido.Exec.run(MyApp.Actions.SlowOperation, %{}, %{})
  end
end
```

## Best Practices

### Configuration Organization
- **Environment Separation**: Different configs for dev/test/prod
- **Validation**: Validate required configuration at startup
- **Defaults**: Provide sensible defaults for optional settings
- **Documentation**: Document all configuration options

### Security
- **Environment Variables**: Use env vars for sensitive data
- **Validation**: Validate configuration values
- **Least Privilege**: Only grant necessary permissions
- **Audit**: Log configuration changes

### Performance
- **Timeouts**: Set appropriate timeouts for different environments
- **Retries**: Configure retries based on expected failure rates
- **Resources**: Limit resource usage to prevent system overload
- **Monitoring**: Monitor configuration effectiveness

### Deployment
- **Runtime Config**: Support runtime configuration changes when possible
- **Health Checks**: Include configuration in health checks
- **Rollback**: Plan for configuration rollback scenarios
- **Testing**: Test configuration changes in staging first

## Next Steps

**→ [Security Guide](security.md)** - Security best practices and resource limits  
**→ [Testing Guide](testing.md)** - Testing configurations and environments  
**→ [FAQ](faq.md)** - Common configuration questions

---
← [Error Handling Guide](error-handling.md) | **Next: [Security Guide](security.md)** →
