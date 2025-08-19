# Error Handling Guide

**Prerequisites**: [Actions Guide](actions-guide.md)

Jido Action uses structured error handling with the Splode library, providing consistent error types, compensation mechanisms, and recovery patterns.

## Error Types

All errors are normalized to `Jido.Action.Error` structs with consistent structure:

```elixir
%Jido.Action.Error{
  type: :validation_error,           # Error category
  message: "Invalid parameter",      # Human-readable message
  details: %{field: :age, value: -5} # Additional context
}
```

### Core Error Types

#### Validation Errors
Parameter validation failures:

```elixir
# Schema validation failure
{:error, %Jido.Action.Error{
  type: :validation_error,
  message: "Required parameter missing: email",
  details: %{missing: [:email]}
}}

# Type validation failure
{:error, %Jido.Action.Error{
  type: :validation_error,
  message: "Invalid type: expected integer, got string",
  details: %{field: :age, expected: :integer, got: :string}
}}
```

#### Execution Errors
Runtime failures during action execution:

```elixir
# Business logic failure
{:error, %Jido.Action.Error{
  type: :execution_error,
  message: "Database connection failed",
  details: %{reason: :timeout, host: "db.example.com"}
}}

# External service failure
{:error, %Jido.Action.Error{
  type: :execution_error,
  message: "API request failed: 503 Service Unavailable",
  details: %{status: 503, url: "https://api.example.com"}
}}
```

#### Timeout Errors
Operation timeouts:

```elixir
{:error, %Jido.Action.Error{
  type: :timeout_error,
  message: "Action exceeded timeout of 5000ms",
  details: %{timeout: 5000, elapsed: 6234}
}}
```

#### Configuration Errors
Missing or invalid configuration:

```elixir
{:error, %Jido.Action.Error{
  type: :config_error,
  message: "Missing required configuration",
  details: %{missing: [:api_key, :secret]}
}}
```

#### Internal Errors
Unexpected system errors:

```elixir
{:error, %Jido.Action.Error{
  type: :internal_error,
  message: "Unexpected error occurred",
  details: %{original: %RuntimeError{message: "Something went wrong"}}
}}
```

## Error Creation

Use helper functions for consistent error creation:

```elixir
defmodule MyApp.Actions.Example do
  use Jido.Action

  def run(params, _context) do
    case validate_business_rules(params) do
      :ok -> 
        {:ok, process_data(params)}
        
      {:error, :insufficient_funds} ->
        {:error, Jido.Action.Error.execution_error(
          "Insufficient funds for transaction",
          %{required: 100, available: 50}
        )}
        
      {:error, :invalid_account} ->
        {:error, Jido.Action.Error.execution_error(
          "Account not found or inactive",
          %{account_id: params.account_id}
        )}
    end
  end
end
```

### Helper Functions

```elixir
# Validation errors
Jido.Action.Error.validation_error("Invalid email format")

# Execution errors
Jido.Action.Error.execution_error("Database connection failed", %{timeout: 5000})

# Timeout errors
Jido.Action.Error.timeout_error("Operation timed out", %{limit: 5000})

# Configuration errors
Jido.Action.Error.config_error("Missing API key", %{missing: [:api_key]})

# Internal errors
Jido.Action.Error.internal_error("Unexpected system error", exception)
```

## Error Handling Patterns

### With Statement Pattern

Clean error handling with `with` statements:

```elixir
def run(params, context) do
  with {:ok, validated} <- validate_input(params),
       {:ok, user} <- fetch_user(validated.user_id),
       {:ok, authorized} <- check_authorization(user, context),
       {:ok, processed} <- process_data(validated),
       {:ok, saved} <- save_result(processed) do
    {:ok, saved}
  else
    {:error, %Jido.Action.Error{} = error} ->
      {:error, error}
      
    {:error, reason} when is_binary(reason) ->
      {:error, Jido.Action.Error.execution_error(reason)}
      
    {:error, reason} ->
      {:error, Jido.Action.Error.execution_error("Operation failed: #{inspect(reason)}")}
      
    error ->
      {:error, Jido.Action.Error.internal_error("Unexpected error", error)}
  end
end
```

### Try-Rescue Pattern

Handle exceptions and convert to structured errors:

```elixir
def run(params, _context) do
  try do
    result = dangerous_operation(params)
    {:ok, result}
  rescue
    exception in [ArgumentError] ->
      {:error, Jido.Action.Error.validation_error(
        "Invalid argument: #{exception.message}"
      )}
      
    exception in [RuntimeError] ->
      {:error, Jido.Action.Error.execution_error(
        "Runtime error: #{exception.message}"
      )}
      
    exception ->
      {:error, Jido.Action.Error.internal_error(
        "Unexpected exception",
        exception
      )}
  end
end
```

### Multi-Step Validation

```elixir
defmodule MyApp.Actions.ComplexValidation do
  use Jido.Action,
    schema: [
      email: [type: :string, required: true],
      age: [type: :integer, required: true],
      terms: [type: :boolean, required: true]
    ]

  def run(params, _context) do
    with :ok <- validate_email(params.email),
         :ok <- validate_age(params.age),
         :ok <- validate_terms(params.terms) do
      {:ok, %{validated: true}}
    end
  end

  defp validate_email(email) do
    if String.contains?(email, "@") do
      :ok
    else
      {:error, Jido.Action.Error.validation_error(
        "Invalid email format",
        %{email: email}
      )}
    end
  end

  defp validate_age(age) do
    cond do
      age < 13 -> 
        {:error, Jido.Action.Error.validation_error(
          "Age must be at least 13",
          %{age: age, minimum: 13}
        )}
      age > 120 ->
        {:error, Jido.Action.Error.validation_error(
          "Age seems unrealistic",
          %{age: age, maximum: 120}
        )}
      true -> 
        :ok
    end
  end

  defp validate_terms(false) do
    {:error, Jido.Action.Error.validation_error("Terms must be accepted")}
  end
  defp validate_terms(true), do: :ok
end
```

## Compensation

Actions can define compensation logic for error recovery and cleanup:

### Enabling Compensation

```elixir
defmodule MyApp.Actions.TransferFunds do
  use Jido.Action,
    name: "transfer_funds",
    compensation: [enabled: true, max_retries: 3],
    schema: [
      from_account: [type: :string, required: true],
      to_account: [type: :string, required: true],
      amount: [type: :integer, required: true]
    ]

  def run(params, context) do
    with {:ok, _} <- debit_account(params.from_account, params.amount),
         {:ok, _} <- credit_account(params.to_account, params.amount) do
      {:ok, %{
        transaction_id: generate_id(),
        from: params.from_account,
        to: params.to_account,
        amount: params.amount
      }}
    end
  end

  # Compensation callback
  @impl true
  def on_error(failed_params, error, context, _opts) do
    case error.type do
      :execution_error ->
        # Attempt to reverse any partial transactions
        case reverse_transaction(failed_params) do
          :ok -> 
            {:ok, %{compensated: true, reversed: true}}
          {:error, reason} ->
            # Log compensation failure
            Logger.error("Compensation failed: #{reason}")
            {:ok, %{compensated: false, reason: reason}}
        end
        
      _ ->
        # No compensation for validation or other errors
        {:ok, %{compensated: false}}
    end
  end

  defp reverse_transaction(params) do
    # Implement reversal logic
    # This might involve crediting back the from_account
    # and debiting the to_account if the credit succeeded
    :ok
  end
end
```

### Compensation Patterns

#### Resource Cleanup

```elixir
defmodule MyApp.Actions.ProcessFile do
  use Jido.Action,
    compensation: [enabled: true]

  def run(params, _context) do
    temp_file = create_temp_file()
    
    try do
      result = process_file(params.file_path, temp_file)
      {:ok, result}
    rescue
      exception ->
        {:error, Jido.Action.Error.execution_error("Processing failed: #{exception.message}")}
    end
  end

  def on_error(_failed_params, _error, context, _opts) do
    # Clean up temporary files
    temp_files = Map.get(context, :temp_files, [])
    Enum.each(temp_files, &File.rm/1)
    {:ok, %{temp_files_cleaned: length(temp_files)}}
  end
end
```

#### External Resource Cleanup

```elixir
defmodule MyApp.Actions.ReserveSeat do
  use Jido.Action,
    compensation: [enabled: true]

  def run(params, _context) do
    case reserve_seat_in_system(params.seat_id) do
      {:ok, reservation} -> {:ok, reservation}
      {:error, reason} -> {:error, Jido.Action.Error.execution_error(reason)}
    end
  end

  def on_error(failed_params, _error, _context, _opts) do
    # Release the seat reservation
    case release_seat(failed_params.seat_id) do
      :ok -> {:ok, %{seat_released: true}}
      {:error, _} -> {:ok, %{seat_released: false}}
    end
  end
end
```

## Error Recovery Strategies

### Retry with Backoff

```elixir
defmodule MyApp.Actions.ReliableHttpCall do
  use Jido.Action,
    schema: [url: [type: :string, required: true]]

  def run(params, _context) do
    case make_http_request(params.url) do
      {:ok, response} -> 
        {:ok, response}
        
      {:error, :rate_limited} ->
        # Don't retry rate limit errors immediately
        {:error, Jido.Action.Error.execution_error(
          "Rate limited",
          %{retry: false}
        )}
        
      {:error, :timeout} ->
        # Retry timeout errors
        {:error, Jido.Action.Error.execution_error(
          "Request timeout",
          %{retry: true}
        )}
        
      {:error, reason} ->
        {:error, Jido.Action.Error.execution_error("HTTP request failed: #{reason}")}
    end
  end
end

# Use with execution engine retries
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.ReliableHttpCall,
  %{url: "https://api.example.com/data"},
  %{},
  max_retries: 3,
  retry_delay: 1000
)
```

### Fallback Actions

```elixir
defmodule MyApp.Actions.FetchWithFallback do
  def execute(params, context) do
    case Jido.Exec.run(MyApp.Actions.FetchFromPrimary, params, context) do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, %{type: :execution_error}} ->
        # Try fallback source
        Jido.Exec.run(MyApp.Actions.FetchFromCache, params, context)
        
      {:error, error} ->
        {:error, error}
    end
  end
end
```

### Circuit Breaker Pattern

```elixir
defmodule MyApp.CircuitBreaker do
  use GenServer
  
  def call_with_breaker(action, params, context) do
    case :ets.lookup(:circuit_breaker, action) do
      [{^action, :open, last_failure}] ->
        if circuit_should_retry?(last_failure) do
          attempt_call(action, params, context)
        else
          {:error, Jido.Action.Error.execution_error("Circuit breaker open")}
        end
        
      _ ->
        attempt_call(action, params, context)
    end
  end
  
  defp attempt_call(action, params, context) do
    case Jido.Exec.run(action, params, context) do
      {:ok, result} ->
        :ets.insert(:circuit_breaker, {action, :closed, nil})
        {:ok, result}
        
      {:error, error} ->
        :ets.insert(:circuit_breaker, {action, :open, DateTime.utc_now()})
        {:error, error}
    end
  end
end
```

## Error Monitoring & Alerting

### Telemetry Integration

```elixir
# Attach error telemetry
:telemetry.attach(
  "error-monitoring",
  [:jido, :exec, :exception],
  &handle_error_telemetry/4,
  %{}
)

def handle_error_telemetry(_event, _measurements, metadata, _config) do
  error = metadata.error
  
  case error.type do
    :execution_error when error.details[:critical] ->
      send_alert(error)
      
    :timeout_error ->
      increment_timeout_counter(metadata.action)
      
    _ ->
      log_error(error)
  end
end
```

### Error Aggregation

```elixir
defmodule MyApp.ErrorAggregator do
  use GenServer

  def record_error(action, error) do
    GenServer.cast(__MODULE__, {:error, action, error})
  end

  def handle_cast({:error, action, error}, state) do
    new_state = update_error_counts(state, action, error)
    
    # Alert if error rate exceeds threshold
    if error_rate_exceeded?(new_state, action) do
      send_error_rate_alert(action, new_state)
    end
    
    {:noreply, new_state}
  end
end
```

## Best Practices

### Error Message Design
- **Be Specific**: Include relevant context and suggested actions
- **User-Friendly**: Write messages that help users understand what went wrong
- **Developer-Friendly**: Include technical details in the `details` field
- **Actionable**: Suggest what the user can do to fix the issue

### Error Categorization
- **Validation Errors**: Input problems that users can fix
- **Execution Errors**: Business logic or external service failures
- **Timeout Errors**: Performance or availability issues
- **Configuration Errors**: Setup or deployment problems
- **Internal Errors**: Unexpected system problems

### Compensation Guidelines
- **Enable for Critical Operations**: Financial transactions, external bookings
- **Keep It Simple**: Compensation should be straightforward and reliable
- **Log Everything**: Record compensation attempts and results
- **Handle Compensation Failures**: What happens if compensation itself fails?

### Recovery Strategies
- **Fail Fast**: Don't retry operations that will obviously fail
- **Exponential Backoff**: Increase delays between retries
- **Circuit Breakers**: Prevent cascade failures
- **Graceful Degradation**: Provide reduced functionality when possible

## Next Steps

**→ [Configuration Guide](configuration.md)** - Environment and runtime configuration  
**→ [Testing Guide](testing.md)** - Testing error scenarios  
**→ [Security Guide](security.md)** - Secure error handling

---
← [Instructions & Plans](instructions-plans.md) | **Next: [Configuration Guide](configuration.md)** →
