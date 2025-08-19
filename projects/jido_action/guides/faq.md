# Frequently Asked Questions

Common questions and solutions for Jido Action development.

## Getting Started

### Q: How is Jido Action different from regular Elixir modules?

**A:** Jido Action provides structured, validated, and observable operations with built-in error handling, AI integration, and workflow composition. Regular modules are great for internal logic, but actions add:

- Automatic parameter validation
- Consistent error handling  
- AI tool compatibility
- Telemetry and observability
- Workflow composition capabilities
- Compensation and retry logic

### Q: When should I use actions vs. regular functions?

**A:** Use actions for:
- External API calls
- Database operations
- File system operations
- AI-integrated functions
- Workflow steps
- Operations that need validation, retries, or compensation

Use regular functions for:
- Pure computational logic
- Internal data transformations
- Helper utilities
- Performance-critical code paths

### Q: Can I convert existing functions to actions?

**A:** Yes! Here's a typical conversion:

```elixir
# Before: Regular function
def process_user_data(name, email, age) do
  if valid_email?(email) do
    {:ok, %{name: name, email: email, age: age, processed_at: DateTime.utc_now()}}
  else
    {:error, "Invalid email"}
  end
end

# After: Jido Action
defmodule MyApp.Actions.ProcessUserData do
  use Jido.Action,
    name: "process_user_data",
    description: "Validates and processes user data",
    schema: [
      name: [type: :string, required: true],
      email: [type: :string, required: true],
      age: [type: :integer, min: 0, max: 150]
    ]

  def run(params, _context) do
    {:ok, %{
      name: params.name,
      email: params.email, 
      age: params.age,
      processed_at: DateTime.utc_now()
    }}
  end
end
```

## Schema and Validation

### Q: How do I validate complex nested data structures?

**A:** Use nested schemas and custom validation:

```elixir
defmodule MyApp.Actions.ProcessOrder do
  use Jido.Action,
    schema: [
      user: [
        type: :map,
        required: true,
        keys: [
          id: [type: :string, required: true],
          email: [type: :string, required: true]
        ]
      ],
      items: [
        type: {:list, :map},
        required: true,
        min_length: 1
      ],
      shipping_address: [
        type: :map,
        required: true,
        keys: [
          street: [type: :string, required: true],
          city: [type: :string, required: true],
          zip: [type: :string, required: true]
        ]
      ]
    ]

  def run(params, _context) do
    with :ok <- validate_items(params.items),
         :ok <- validate_address(params.shipping_address) do
      {:ok, process_order(params)}
    end
  end

  defp validate_items(items) do
    if Enum.all?(items, &valid_item?/1) do
      :ok
    else
      {:error, Jido.Action.Error.validation_error("Invalid items in order")}
    end
  end
end
```

### Q: Can I have conditional required fields?

**A:** Yes, handle this in `on_before_validate_params/1` or custom validation:

```elixir
defmodule MyApp.Actions.ConditionalRequired do
  use Jido.Action,
    schema: [
      type: [type: :atom, in: [:personal, :business], required: true],
      tax_id: [type: :string],  # Required only for business
      personal_id: [type: :string]  # Required only for personal
    ]

  def on_before_validate_params(params) do
    case validate_conditional_fields(params) do
      :ok -> {:ok, params}
      {:error, reason} -> {:error, Jido.Action.Error.validation_error(reason)}
    end
  end

  defp validate_conditional_fields(%{type: :business} = params) do
    if Map.has_key?(params, :tax_id) do
      :ok
    else
      {:error, "tax_id required for business type"}
    end
  end

  defp validate_conditional_fields(%{type: :personal} = params) do
    if Map.has_key?(params, :personal_id) do
      :ok
    else
      {:error, "personal_id required for personal type"}
    end
  end
end
```

## Error Handling

### Q: How do I handle errors from external services?

**A:** Wrap external calls and convert to structured errors:

```elixir
defmodule MyApp.Actions.CallExternalAPI do
  use Jido.Action,
    schema: [url: [type: :string, required: true]]

  def run(params, _context) do
    case HTTPoison.get(params.url) do
      {:ok, %{status_code: 200, body: body}} ->
        {:ok, %{data: Jason.decode!(body)}}
        
      {:ok, %{status_code: 404}} ->
        {:error, Jido.Action.Error.execution_error("Resource not found")}
        
      {:ok, %{status_code: 500}} ->
        {:error, Jido.Action.Error.execution_error("Server error", %{retry: true})}
        
      {:error, %HTTPoison.Error{reason: :timeout}} ->
        {:error, Jido.Action.Error.timeout_error("Request timeout")}
        
      {:error, %HTTPoison.Error{reason: reason}} ->
        {:error, Jido.Action.Error.execution_error("HTTP error: #{reason}")}
    end
  end
end
```

### Q: When should I use compensation vs. retries?

**A:** 
- **Retries**: For transient failures (network issues, temporary service unavailability)
- **Compensation**: For permanent state changes that need rollback (financial transactions, resource allocation)

```elixir
# Use retries for transient failures
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.FetchData,
  params,
  context,
  max_retries: 3,
  retry_delay: 1000
)

# Use compensation for state changes
defmodule MyApp.Actions.CreateResource do
  use Jido.Action,
    compensation: [enabled: true]

  def run(params, _context) do
    # Create resource
    {:ok, resource} = create_resource(params)
    {:ok, resource}
  end

  def on_error(_params, _error, _context, _opts) do
    # Clean up created resource
    cleanup_resources()
    {:ok, %{compensated: true}}
  end
end
```

## Performance

### Q: Are actions slower than regular function calls?

**A:** Actions have minimal overhead for validation and telemetry. For performance-critical paths:

1. Use actions for boundaries (API endpoints, external calls)
2. Use regular functions for internal computation
3. Profile your specific use case

```elixir
# Performance comparison (rough estimates)
# Regular function call: ~0.1µs  
# Action with validation: ~1-5µs
# Action with execution engine: ~5-10µs
```

### Q: How do I optimize action performance?

**A:** Several strategies:

```elixir
# 1. Disable features you don't need
defmodule MyApp.Actions.FastAction do
  use Jido.Action,
    telemetry: false,      # Disable telemetry
    validate_output: false # Skip output validation

  def run(params, _context) do
    # Fast implementation
    {:ok, result}
  end
end

# 2. Use direct execution for simple cases
{:ok, result} = MyApp.Actions.FastAction.run(params, context)

# 3. Batch operations
{:ok, results} = Jido.Exec.run_async_batch([
  {MyApp.Actions.ProcessItem, item1},
  {MyApp.Actions.ProcessItem, item2},
  {MyApp.Actions.ProcessItem, item3}
], context)
```

### Q: How do I handle large data sets?

**A:** Stream data and use pagination:

```elixir
defmodule MyApp.Actions.ProcessLargeDataset do
  use Jido.Action,
    schema: [
      batch_size: [type: :integer, default: 1000],
      offset: [type: :integer, default: 0]
    ]

  def run(params, _context) do
    # Process in batches
    params.dataset
    |> Stream.chunk_every(params.batch_size)
    |> Stream.with_index(params.offset)
    |> Enum.reduce_while({:ok, []}, fn {batch, index}, {:ok, acc} ->
      case process_batch(batch) do
        {:ok, results} -> {:cont, {:ok, acc ++ results}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
```

## AI Integration

### Q: How do I control which actions AI can access?

**A:** Use allowlists and context-based authorization:

```elixir
defmodule MyApp.AI.ToolRegistry do
  # Define allowed tools per user role
  @user_tools [
    MyApp.Actions.SearchUsers,
    MyApp.Actions.GetWeather,
    Jido.Tools.Arithmetic.Add
  ]

  @admin_tools @user_tools ++ [
    MyApp.Actions.CreateUser,
    MyApp.Actions.DeleteUser,
    MyApp.Actions.SystemStatus
  ]

  def get_available_tools(user_role) do
    case user_role do
      :admin -> @admin_tools
      :user -> @user_tools
      _ -> []
    end
  end

  def can_execute?(action, user_role) do
    action in get_available_tools(user_role)
  end
end

# In your AI handler
def execute_ai_tool(action, params, context) do
  user_role = Map.get(context, :user_role, :guest)
  
  if MyApp.AI.ToolRegistry.can_execute?(action, user_role) do
    Jido.Action.Tool.execute_action(action, params, context)
  else
    {:error, "Action not authorized for user role: #{user_role}"}
  end
end
```

### Q: How do I handle AI-generated invalid parameters?

**A:** Actions automatically validate AI parameters, but you can provide better error feedback:

```elixir
defmodule MyApp.AI.ErrorHandler do
  def execute_with_ai_feedback(action, ai_params, context) do
    case Jido.Action.Tool.execute_action(action, ai_params, context) do
      {:ok, result} ->
        {:ok, result}
        
      {:error, %{type: :validation_error} = error} ->
        # Return detailed error for AI to correct
        {:error, %{
          type: "parameter_validation_failed",
          message: error.message,
          details: error.details,
          schema: action.action_schema(),
          suggestion: "Please check parameter types and constraints"
        }}
        
      {:error, error} ->
        {:error, error}
    end
  end
end
```

## Workflows and Plans

### Q: When should I use chains vs. plans?

**A:**
- **Chains**: Linear workflows where each step depends on the previous
- **Plans**: Complex workflows with parallel execution and multiple dependencies

```elixir
# Use chain for linear workflow
{:ok, result} = Jido.Exec.Chain.chain([
  MyApp.Actions.ValidateInput,
  MyApp.Actions.ProcessData,
  MyApp.Actions.SaveResult
], initial_data, context)

# Use plan for complex workflow
plan = Jido.Plan.new()
|> Jido.Plan.add("validate", MyApp.Actions.ValidateInput, %{}, [])
|> Jido.Plan.add("process_a", MyApp.Actions.ProcessTypeA, %{}, ["validate"])
|> Jido.Plan.add("process_b", MyApp.Actions.ProcessTypeB, %{}, ["validate"])
|> Jido.Plan.add("merge", MyApp.Actions.MergeResults, %{}, ["process_a", "process_b"])
```

### Q: How do I handle conditional execution in workflows?

**A:** Use conditional actions or dynamic plan building:

```elixir
# Option 1: Conditional action
defmodule MyApp.Actions.ConditionalStep do
  use Jido.Action,
    schema: [
      condition: [type: :boolean, required: true],
      data: [type: :any, required: true]
    ]

  def run(%{condition: false}, _context) do
    {:ok, %{skipped: true}}
  end

  def run(%{condition: true, data: data}, context) do
    MyApp.Actions.ActualWork.run(%{data: data}, context)
  end
end

# Option 2: Dynamic plan building
def build_plan(user_type) do
  plan = Jido.Plan.new()
  |> Jido.Plan.add("validate", MyApp.Actions.ValidateUser, %{}, [])
  
  plan = if user_type == :premium do
    plan |> Jido.Plan.add("premium_process", MyApp.Actions.PremiumProcess, %{}, ["validate"])
  else
    plan |> Jido.Plan.add("basic_process", MyApp.Actions.BasicProcess, %{}, ["validate"])
  end
  
  plan |> Jido.Plan.add("finalize", MyApp.Actions.Finalize, %{}, ["premium_process", "basic_process"])
end
```

## Testing

### Q: How do I test actions with external dependencies?

**A:** Use mocking and dependency injection:

```elixir
# In your action
defmodule MyApp.Actions.FetchUserData do
  use Jido.Action,
    schema: [user_id: [type: :string, required: true]]

  def run(params, context) do
    http_client = Map.get(context, :http_client, HTTPoison)
    
    case http_client.get("/users/#{params.user_id}") do
      {:ok, response} -> {:ok, parse_response(response)}
      {:error, error} -> {:error, error}
    end
  end
end

# In tests
test "handles API failure" do
  mock_client = fn _url -> {:error, :network_error} end
  
  assert {:error, :network_error} = MyApp.Actions.FetchUserData.run(
    %{user_id: "123"},
    %{http_client: mock_client}
  )
end
```

### Q: How do I test async actions?

**A:** Use the execution engine's test utilities:

```elixir
test "async action completes successfully" do
  async_ref = Jido.Exec.run_async(
    MyApp.Actions.LongRunning,
    %{data: "test"},
    %{}
  )
  
  # Wait for completion
  assert {:ok, result} = Jido.Exec.await(async_ref, 5000)
  assert result.processed == true
end

test "async action can be cancelled" do
  async_ref = Jido.Exec.run_async(
    MyApp.Actions.VeryLongRunning,
    %{data: "test"},
    %{}
  )
  
  # Cancel before completion
  assert :ok = Jido.Exec.cancel(async_ref)
  
  # Should return cancelled status
  assert {:error, :cancelled} = Jido.Exec.await(async_ref, 1000)
end
```

## Deployment and Production

### Q: How do I monitor actions in production?

**A:** Use telemetry and structured logging:

```elixir
# Set up comprehensive telemetry
:telemetry.attach_many(
  "production-monitoring",
  [
    [:jido, :exec, :start],
    [:jido, :exec, :stop],
    [:jido, :exec, :exception]
  ],
  &MyApp.Telemetry.handle_event/4,
  %{}
)

defmodule MyApp.Telemetry do
  def handle_event([:jido, :exec, :stop], measurements, metadata, _) do
    # Send metrics to monitoring system
    duration_ms = System.convert_time_unit(measurements.duration, :native, :millisecond)
    
    :telemetry.execute(
      [:my_app, :action, :duration],
      %{duration: duration_ms},
      %{action: metadata.action}
    )
    
    # Log slow actions
    if duration_ms > 5000 do
      Logger.warning("Slow action detected",
        action: metadata.action,
        duration_ms: duration_ms,
        params: sanitize_params(metadata.params)
      )
    end
  end
end
```

### Q: How do I handle secrets in actions?

**A:** Use environment variables and context:

```elixir
defmodule MyApp.Actions.SecureAPI do
  use Jido.Action,
    schema: [operation: [type: :string, required: true]]

  def run(params, context) do
    # Get API key from context or environment
    api_key = Map.get(context, :api_key) || System.get_env("API_KEY")
    
    if api_key do
      make_api_call(params.operation, api_key)
    else
      {:error, Jido.Action.Error.config_error("API key not configured")}
    end
  end

  # Never log the API key
  defp make_api_call(operation, api_key) do
    Logger.info("Making API call", operation: operation)
    # Use api_key in request...
  end
end
```

## Troubleshooting

### Q: Why is my action hanging?

**A:** Common causes and solutions:

1. **Missing timeout**: Always set timeouts
2. **Blocking operations**: Use async for I/O
3. **Infinite loops**: Check your logic
4. **Deadlocks**: Avoid circular dependencies

```elixir
# Debug hanging actions
{:ok, result} = Jido.Exec.run(
  MyApp.Actions.SuspiciousAction,
  params,
  context,
  timeout: 10_000  # Always set timeout
)

# Check telemetry for start events without corresponding stop events
```

### Q: How do I debug validation errors?

**A:** Enable detailed validation logging:

```elixir
# In your action
def on_before_validate_params(params) do
  Logger.debug("Validating params", params: params, action: __MODULE__)
  {:ok, params}
end

# Or use a validation helper
def run(params, context) do
  case validate_params_detailed(params) do
    {:ok, validated} -> process(validated)
    {:error, details} -> 
      Logger.error("Validation failed", details: details)
      {:error, Jido.Action.Error.validation_error("Invalid parameters", details)}
  end
end
```

### Q: My workflows are failing - how do I debug?

**A:** Use plan execution debugging:

```elixir
# Enable detailed plan logging
{:ok, results} = Jido.Tools.ActionPlan.run(%{
  plan: plan,
  initial_data: data,
  debug: true  # Enable debug output
}, context)

# Check partial results on failure
case Jido.Tools.ActionPlan.run(%{plan: plan}, context) do
  {:ok, results} -> results
  {:error, {failed_step, error, partial_results}} ->
    Logger.error("Plan failed at step #{failed_step}",
      error: error.message,
      completed_steps: Map.keys(partial_results)
    )
end
```

Need help with something not covered here? Check the [GitHub Issues](https://github.com/agentjido/jido_action/issues) or create a new issue with your question.

---
← [Testing Guide](testing.md) | **Next: [CHANGELOG](../CHANGELOG.md)** →
