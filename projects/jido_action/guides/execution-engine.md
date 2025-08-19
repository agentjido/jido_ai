# Execution Engine

**Prerequisites**: [Actions Guide](actions-guide.md)

The execution engine (`Jido.Exec`) provides robust, production-ready action execution with timeouts, retries, telemetry, and proper error handling.

## Basic Execution

### Synchronous Execution

```elixir
# Simple execution
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.ProcessData,
  %{data: "input"},
  %{user_id: "123"}
)

# With options
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.ProcessData,
  %{data: "input"},
  %{user_id: "123"},
  timeout: 10_000,          # 10 second timeout
  max_retries: 3,           # Retry 3 times on failure
  retry_delay: 1000         # Wait 1 second between retries
)
```

### Asynchronous Execution

```elixir
# Start async execution
async_ref = Jido.Exec.run_async(
  MyApp.Actions.LongRunning,
  %{data: "large_dataset"},
  %{user_id: "123"}
)

# Await result
{:ok, result} = Jido.Exec.await(async_ref, 30_000)

# Cancel if needed
:ok = Jido.Exec.cancel(async_ref)

# Check status without blocking
case Jido.Exec.status(async_ref) do
  :pending -> IO.puts("Still running...")
  {:ok, result} -> IO.puts("Completed: #{inspect(result)}")
  {:error, reason} -> IO.puts("Failed: #{inspect(reason)}")
end
```

## Execution Features

### Timeout Management

```elixir
# Action-level timeout
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.ApiCall,
  %{url: "https://slow-api.com/data"},
  %{},
  timeout: 5000  # Times out after 5 seconds
)

# Handle timeout errors
case Jido.Exec.run(action, params, context, timeout: 1000) do
  {:ok, result} -> 
    handle_success(result)
  {:error, %{type: :timeout_error}} -> 
    handle_timeout()
  {:error, error} -> 
    handle_other_error(error)
end
```

### Retry Logic

The execution engine uses exponential backoff with jitter for retries:

```elixir
# Configure retry behavior
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.UnreliableOperation,
  params,
  context,
  max_retries: 5,           # Try up to 5 times
  retry_delay: 1000,        # Start with 1 second delay
  retry_backoff: 2.0,       # Double delay each time
  retry_jitter: 0.1         # Add 10% random jitter
)

# Retry progression: 1s → 2s → 4s → 8s → 16s (with jitter)
```

### Custom Retry Logic

```elixir
defmodule MyApp.Actions.SmartRetry do
  use Jido.Action,
    name: "smart_retry",
    schema: [operation: [type: :string, required: true]]

  def run(params, context) do
    case perform_operation(params.operation) do
      {:ok, result} -> {:ok, result}
      {:error, :rate_limited} -> 
        # Don't retry rate limit errors immediately
        {:error, Jido.Action.Error.execution_error("Rate limited", retry: false)}
      {:error, :temporary_failure} ->
        # Retry these errors
        {:error, Jido.Action.Error.execution_error("Temporary failure", retry: true)}
      {:error, reason} ->
        {:error, Jido.Action.Error.execution_error("Operation failed: #{reason}")}
    end
  end
end
```

## Chaining Actions

Sequential execution with data flow between actions:

### Basic Chaining

```elixir
# Chain actions with data flow
{:ok, final_result} = Jido.Exec.Chain.chain([
  MyApp.Actions.ValidateInput,
  {MyApp.Actions.ProcessData, %{format: "json"}},  # Extra params
  MyApp.Actions.SaveResult
], %{input: "data"}, %{user_id: "123"})

# Data flows: input → validate → process → save → final_result
```

### Advanced Chaining

```elixir
# Chain with interrupt function
interrupt_fn = fn result, context ->
  cond do
    result.status == :error -> 
      {:halt, result}  # Stop chain on error
    result.user_blocked? -> 
      {:halt, {:error, "User blocked"}}  # Conditional halt
    true -> 
      {:cont, result}  # Continue chain
  end
end

{:ok, result} = Jido.Exec.Chain.chain(
  instructions,
  initial_params,
  context,
  interrupt_fn
)
```

### Chain Error Handling

```elixir
case Jido.Exec.Chain.chain(instructions, params, context) do
  {:ok, result} ->
    handle_success(result)
  
  {:error, {action, error, partial_results}} ->
    # Know which action failed and what completed
    Logger.error("Chain failed at #{action}: #{error.message}")
    handle_partial_completion(partial_results)
end
```

## Closures

Create reusable execution units with preset configuration:

```elixir
# Create closure with preset params and context
process_closure = Jido.Exec.Closure.closure(
  MyApp.Actions.ProcessData,
  %{format: "json", validate: true},  # Preset params
  %{user_id: "123"}                   # Preset context
)

# Execute with additional params
{:ok, result} = process_closure.(%{data: "input"})

# Async closure
async_closure = Jido.Exec.Closure.async_closure(
  MyApp.Actions.LongRunning,
  %{timeout: 30_000},
  %{}
)

async_ref = async_closure.(%{data: "large_dataset"})
{:ok, result} = Jido.Exec.await(async_ref)
```

## Telemetry & Observability

The execution engine emits comprehensive telemetry events:

### Built-in Events

```elixir
# Attach telemetry handlers
:telemetry.attach_many(
  "jido-exec-handler",
  [
    [:jido, :exec, :start],
    [:jido, :exec, :stop],
    [:jido, :exec, :exception]
  ],
  &handle_telemetry/4,
  %{}
)

def handle_telemetry(event, measurements, metadata, _config) do
  case event do
    [:jido, :exec, :start] ->
      Logger.info("Action started", 
        action: metadata.action,
        params: metadata.params
      )
    
    [:jido, :exec, :stop] ->
      Logger.info("Action completed", 
        action: metadata.action,
        duration: measurements.duration
      )
    
    [:jido, :exec, :exception] ->
      Logger.error("Action failed",
        action: metadata.action,
        error: metadata.error,
        duration: measurements.duration
      )
  end
end
```

### Custom Metrics

```elixir
# In your action
def run(params, context) do
  start_time = System.monotonic_time()
  
  result = perform_work(params)
  
  duration = System.monotonic_time() - start_time
  :telemetry.execute(
    [:my_app, :action, :custom_metric],
    %{duration: duration, size: byte_size(params.data)},
    %{action: __MODULE__, user_id: context.user_id}
  )
  
  {:ok, result}
end
```

## Error Handling

### Error Types

The execution engine normalizes all errors to structured types:

```elixir
case Jido.Exec.run(action, params, context) do
  {:ok, result} -> 
    result
  
  {:error, %{type: :validation_error} = error} ->
    handle_validation_error(error)
  
  {:error, %{type: :execution_error} = error} ->
    handle_execution_error(error)
  
  {:error, %{type: :timeout_error} = error} ->
    handle_timeout_error(error)
  
  {:error, %{type: :internal_error} = error} ->
    handle_internal_error(error)
end
```

### Error Recovery

```elixir
defmodule MyApp.RobustExecution do
  def execute_with_fallback(action, params, context) do
    case Jido.Exec.run(action, params, context, max_retries: 3) do
      {:ok, result} -> 
        {:ok, result}
      
      {:error, %{type: :timeout_error}} ->
        # Try with longer timeout
        Jido.Exec.run(action, params, context, timeout: 30_000)
      
      {:error, %{type: :execution_error}} ->
        # Try fallback action
        Jido.Exec.run(MyApp.Actions.FallbackAction, params, context)
      
      {:error, error} ->
        {:error, error}
    end
  end
end
```

## Performance Considerations

### Resource Management

```elixir
# Pool expensive resources
defmodule MyApp.ResourcePool do
  def execute_with_pool(action, params, context) do
    :poolboy.transaction(:my_pool, fn worker ->
      enhanced_context = Map.put(context, :worker, worker)
      Jido.Exec.run(action, params, enhanced_context)
    end)
  end
end
```

### Async Patterns

```elixir
# Fan-out pattern
defmodule MyApp.FanOut do
  def process_batch(items, context) do
    # Start all async
    async_refs = Enum.map(items, fn item ->
      Jido.Exec.run_async(
        MyApp.Actions.ProcessItem,
        %{item: item},
        context
      )
    end)
    
    # Await all results
    results = Enum.map(async_refs, fn ref ->
      Jido.Exec.await(ref, 10_000)
    end)
    
    {:ok, results}
  end
end
```

## Best Practices

### Timeouts
- Set reasonable timeouts for all operations
- Use shorter timeouts for user-facing operations
- Increase timeouts for background processing

### Retries
- Only retry transient failures
- Use exponential backoff to avoid overwhelming services
- Set maximum retry limits to prevent infinite loops

### Error Handling
- Match on specific error types for appropriate handling
- Log errors with sufficient context for debugging
- Provide meaningful error messages to users

### Async Execution
- Use async for I/O-bound operations
- Limit concurrent async operations to prevent resource exhaustion
- Always await or cancel async operations

## Next Steps

**→ [Instructions & Plans](instructions-plans.md)** - Workflow composition  
**→ [Error Handling Guide](error-handling.md)** - Advanced error patterns  
**→ [Configuration Guide](configuration.md)** - Performance optimization

---
← [Actions Guide](actions-guide.md) | **Next: [Instructions & Plans](instructions-plans.md)** →
