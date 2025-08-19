# Testing Guide

**Prerequisites**: [Actions Guide](actions-guide.md) • [Error Handling Guide](error-handling.md)

Comprehensive testing strategies for actions, workflows, error scenarios, and AI integrations using ExUnit and property-based testing.

## Basic Action Testing

### Unit Testing Actions

```elixir
defmodule MyApp.Actions.ProcessUserTest do
  use ExUnit.Case

  alias MyApp.Actions.ProcessUser

  describe "process_user/2" do
    test "processes valid user data" do
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }
      
      assert {:ok, result} = ProcessUser.run(params, %{})
      assert result.name == "John Doe"
      assert result.email == "john@example.com"
      assert result.processed_at
    end

    test "rejects invalid email format" do
      params = %{
        name: "John Doe",
        email: "invalid-email",
        age: 30
      }
      
      assert {:error, error} = ProcessUser.run(params, %{})
      assert error.type == :validation_error
      assert error.message =~ "Invalid email"
    end

    test "applies default values" do
      params = %{
        name: "John Doe",
        email: "john@example.com"
        # age not provided, should use default
      }
      
      assert {:ok, result} = ProcessUser.run(params, %{})
      assert result.age == 18  # default value
    end

    test "validates required parameters" do
      params = %{name: "John Doe"}  # missing email
      
      assert {:error, error} = ProcessUser.run(params, %{})
      assert error.type == :validation_error
    end
  end

  describe "context handling" do
    test "uses context for business logic" do
      params = %{
        name: "John Doe",
        email: "john@example.com",
        age: 30
      }
      
      context = %{user_id: "admin_123", role: :admin}
      
      assert {:ok, result} = ProcessUser.run(params, context)
      assert result.processed_by == "admin_123"
    end

    test "handles missing context gracefully" do
      params = %{
        name: "John Doe", 
        email: "john@example.com",
        age: 30
      }
      
      # Empty context should still work
      assert {:ok, result} = ProcessUser.run(params, %{})
      refute Map.has_key?(result, :processed_by)
    end
  end
end
```

### Testing Lifecycle Hooks

```elixir
defmodule MyApp.Actions.LifecycleActionTest do
  use ExUnit.Case

  # Test action with all lifecycle hooks
  defmodule TestAction do
    use Jido.Action,
      schema: [input: [type: :string, required: true]]

    def on_before_validate_params(params) do
      # Add test marker
      {:ok, Map.put(params, :preprocessed, true)}
    end

    def run(params, _context) do
      {:ok, %{result: params.input, preprocessed: params.preprocessed}}
    end

    def on_after_run(result) do
      # Add post-processing marker
      {:ok, Map.put(result, :postprocessed, true)}
    end

    def on_error(_params, _error, _context, _opts) do
      {:ok, %{error_handled: true}}
    end
  end

  test "lifecycle hooks are called in order" do
    assert {:ok, result} = TestAction.run(%{input: "test"}, %{})
    
    # Check preprocessing happened
    assert result.preprocessed == true
    
    # Check post-processing happened  
    assert result.postprocessed == true
    
    # Check main logic ran
    assert result.result == "test"
  end

  test "error hook is called on failure" do
    # This would need to be tested with an action that can fail
    # and has compensation enabled
  end
end
```

## Testing with Execution Engine

### Testing Timeouts

```elixir
defmodule MyApp.Actions.TimeoutTest do
  use ExUnit.Case

  defmodule SlowAction do
    use Jido.Action,
      schema: [delay_ms: [type: :integer, default: 1000]]

    def run(%{delay_ms: delay}, _context) do
      :timer.sleep(delay)
      {:ok, %{completed_after: delay}}
    end
  end

  test "respects timeout configuration" do
    # Should complete within timeout
    assert {:ok, result} = Jido.Exec.run(
      SlowAction,
      %{delay_ms: 100},
      %{},
      timeout: 500
    )
    
    assert result.completed_after == 100
  end

  test "times out when execution exceeds limit" do
    assert {:error, error} = Jido.Exec.run(
      SlowAction,
      %{delay_ms: 1000},
      %{},
      timeout: 500
    )
    
    assert error.type == :timeout_error
  end
end
```

### Testing Retries

```elixir
defmodule MyApp.Actions.RetryTest do
  use ExUnit.Case

  defmodule FlakyAction do
    use Jido.Action,
      schema: [fail_count: [type: :integer, default: 0]]

    def run(%{fail_count: fail_count}, context) do
      attempt = Map.get(context, :attempt, 1)
      
      if attempt <= fail_count do
        {:error, Jido.Action.Error.execution_error("Simulated failure")}
      else
        {:ok, %{succeeded_on_attempt: attempt}}
      end
    end
  end

  test "retries on failure and eventually succeeds" do
    # Should fail twice, succeed on third attempt
    assert {:ok, result} = Jido.Exec.run(
      FlakyAction,
      %{fail_count: 2},
      %{},
      max_retries: 3,
      retry_delay: 10  # Fast retries for tests
    )
    
    assert result.succeeded_on_attempt == 3
  end

  test "gives up after max retries" do
    assert {:error, error} = Jido.Exec.run(
      FlakyAction,
      %{fail_count: 10},  # Always fails
      %{},
      max_retries: 2,
      retry_delay: 10
    )
    
    assert error.type == :execution_error
  end
end
```

## Testing Workflows

### Testing Chains

```elixir
defmodule MyApp.Workflows.ChainTest do
  use ExUnit.Case

  defmodule Step1 do
    use Jido.Action,
      schema: [input: [type: :string, required: true]]

    def run(%{input: input}, _context) do
      {:ok, %{step1_output: "processed_#{input}"}}
    end
  end

  defmodule Step2 do
    use Jido.Action,
      schema: [step1_output: [type: :string, required: true]]

    def run(%{step1_output: input}, _context) do
      {:ok, %{final_result: "final_#{input}"}}
    end
  end

  test "chain executes steps in sequence" do
    {:ok, result} = Jido.Exec.Chain.chain([
      Step1,
      Step2
    ], %{input: "test"}, %{})
    
    assert result.final_result == "final_processed_test"
  end

  test "chain stops on first error" do
    defmodule FailingStep do
      use Jido.Action
      def run(_params, _context) do
        {:error, Jido.Action.Error.execution_error("Step failed")}
      end
    end

    assert {:error, {FailingStep, error, partial_results}} = 
      Jido.Exec.Chain.chain([
        Step1,
        FailingStep,
        Step2  # Should not execute
      ], %{input: "test"}, %{})
    
    assert error.message == "Step failed"
    # Partial results should include Step1 output
    assert partial_results["Step1"].step1_output == "processed_test"
  end
end
```

### Testing Plans

```elixir
defmodule MyApp.Workflows.PlanTest do
  use ExUnit.Case

  describe "plan execution" do
    test "executes phases in correct order" do
      plan = Jido.Plan.new()
      |> Jido.Plan.add("input", InputAction, %{}, [])
      |> Jido.Plan.add("process_a", ProcessA, %{}, ["input"])
      |> Jido.Plan.add("process_b", ProcessB, %{}, ["input"])
      |> Jido.Plan.add("merge", MergeAction, %{}, ["process_a", "process_b"])
      
      {:ok, results} = Jido.Tools.ActionPlan.run(%{
        plan: plan,
        initial_data: %{data: "test"}
      }, %{})
      
      # Verify all steps executed
      assert Map.has_key?(results, "input")
      assert Map.has_key?(results, "process_a")
      assert Map.has_key?(results, "process_b")
      assert Map.has_key?(results, "merge")
    end

    test "handles dependency failures" do
      plan = Jido.Plan.new()
      |> Jido.Plan.add("step1", SuccessAction, %{}, [])
      |> Jido.Plan.add("step2", FailingAction, %{}, ["step1"])
      |> Jido.Plan.add("step3", SuccessAction, %{}, ["step2"])  # Should not run
      
      assert {:error, {failed_id, error, partial_results}} = 
        Jido.Tools.ActionPlan.run(%{
          plan: plan,
          initial_data: %{}
        }, %{})
      
      assert failed_id == "step2"
      assert Map.has_key?(partial_results, "step1")
      refute Map.has_key?(partial_results, "step3")
    end
  end
end
```

## Property-Based Testing

### Using StreamData

```elixir
defmodule MyApp.Actions.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  alias MyApp.Actions.Calculator

  property "addition is commutative" do
    check all a <- integer(),
              b <- integer() do
      {:ok, result1} = Calculator.Add.run(%{value: a, amount: b}, %{})
      {:ok, result2} = Calculator.Add.run(%{value: b, amount: a}, %{})
      
      assert result1.result == result2.result
    end
  end

  property "string processing handles all valid inputs" do
    check all input <- string(:alphanumeric, min_length: 1, max_length: 100) do
      case MyApp.Actions.ProcessString.run(%{text: input}, %{}) do
        {:ok, result} ->
          # Result should always be a string
          assert is_binary(result.processed)
          # Result should not be empty
          assert String.length(result.processed) > 0
          
        {:error, error} ->
          # If it fails, should be a validation error
          assert error.type == :validation_error
      end
    end
  end

  property "user age validation" do
    check all age <- integer() do
      case MyApp.Actions.ValidateUser.run(%{
        name: "Test User",
        email: "test@example.com", 
        age: age
      }, %{}) do
        {:ok, result} when age >= 13 and age <= 150 ->
          assert result.age == age
          
        {:error, error} when age < 13 or age > 150 ->
          assert error.type == :validation_error
          assert error.message =~ "age"
      end
    end
  end
end
```

## Testing Error Scenarios

### Testing Error Types

```elixir
defmodule MyApp.Actions.ErrorHandlingTest do
  use ExUnit.Case

  describe "validation errors" do
    test "missing required parameter" do
      assert {:error, error} = MyAction.run(%{}, %{})
      assert error.type == :validation_error
      assert error.message =~ "required"
    end

    test "invalid parameter type" do
      assert {:error, error} = MyAction.run(%{age: "not_a_number"}, %{})
      assert error.type == :validation_error
      assert error.message =~ "type"
    end

    test "parameter out of range" do
      assert {:error, error} = MyAction.run(%{age: -5}, %{})
      assert error.type == :validation_error
      assert error.message =~ "range"
    end
  end

  describe "execution errors" do
    test "external service failure" do
      # Mock external service to fail
      expect(ExternalService, :call, fn _ -> {:error, :service_unavailable} end)
      
      assert {:error, error} = MyAction.run(%{valid: "params"}, %{})
      assert error.type == :execution_error
      assert error.message =~ "service"
    end

    test "database connection failure" do
      # Test with database down
      assert {:error, error} = DatabaseAction.run(%{query: "SELECT 1"}, %{})
      assert error.type == :execution_error
    end
  end

  describe "compensation" do
    test "compensation runs on error" do
      # Action that creates resource then fails
      assert {:error, _} = CreateAndFailAction.run(%{}, %{})
      
      # Verify compensation cleaned up the resource
      refute resource_exists?("test_resource")
    end
  end
end
```

## Testing AI Integration

### Testing Tool Conversion

```elixir
defmodule MyApp.Actions.AIIntegrationTest do
  use ExUnit.Case

  test "action converts to valid tool definition" do
    tool_def = MyApp.Actions.SearchUsers.to_tool()
    
    assert tool_def["type"] == "function"
    assert is_map(tool_def["function"])
    
    function = tool_def["function"]
    assert function["name"] == "search_users"
    assert is_binary(function["description"])
    assert is_map(function["parameters"])
    
    params = function["parameters"]
    assert params["type"] == "object"
    assert is_map(params["properties"])
    assert is_list(params["required"])
  end

  test "tool execution from AI parameters" do
    ai_params = %{
      "query" => "john@example.com",
      "limit" => 5,
      "include_inactive" => false
    }
    
    {:ok, result} = Jido.Action.Tool.execute_action(
      MyApp.Actions.SearchUsers,
      ai_params,
      %{}
    )
    
    assert is_list(result.users)
    assert result.count <= 5
  end

  test "handles invalid AI parameters" do
    invalid_params = %{
      "query" => nil,  # Required parameter missing
      "limit" => "not_a_number"
    }
    
    assert {:error, error} = Jido.Action.Tool.execute_action(
      MyApp.Actions.SearchUsers,
      invalid_params,
      %{}
    )
    
    assert error.type == :validation_error
  end
end
```

## Testing Helpers and Utilities

### Custom Test Helpers

```elixir
defmodule MyApp.TestHelpers do
  @moduledoc "Utilities for testing actions"

  def assert_success(result) do
    case result do
      {:ok, data} -> data
      {:error, error} -> 
        ExUnit.Assertions.flunk("Expected success, got error: #{inspect(error)}")
    end
  end

  def assert_error(result, expected_type \\ nil) do
    case result do
      {:error, error} ->
        if expected_type do
          assert error.type == expected_type, 
            "Expected error type #{expected_type}, got #{error.type}"
        end
        error
      
      {:ok, data} ->
        ExUnit.Assertions.flunk("Expected error, got success: #{inspect(data)}")
    end
  end

  def with_timeout(action, params, context, timeout_ms) do
    Jido.Exec.run(action, params, context, timeout: timeout_ms)
  end

  def run_async_and_wait(action, params, context, timeout_ms \\ 5000) do
    async_ref = Jido.Exec.run_async(action, params, context)
    Jido.Exec.await(async_ref, timeout_ms)
  end
end

# Use in tests
defmodule MyApp.Actions.SomeTest do
  use ExUnit.Case
  import MyApp.TestHelpers

  test "action succeeds" do
    result = assert_success(MyAction.run(%{valid: "params"}, %{}))
    assert result.processed == true
  end

  test "action fails with validation error" do
    error = assert_error(MyAction.run(%{}, %{}), :validation_error)
    assert error.message =~ "required"
  end
end
```

### Test Configuration

```elixir
# test/support/test_config.ex
defmodule MyApp.TestConfig do
  def setup_test_environment do
    # Configure for fast tests
    Application.put_env(:jido_action, :default_timeout, 1_000)
    Application.put_env(:jido_action, :default_max_retries, 0)
    Application.put_env(:jido_action, :telemetry_enabled, false)
    
    # Mock external dependencies
    Application.put_env(:my_app, :external_api_base_url, "http://localhost:4002")
    Application.put_env(:my_app, :use_real_database, false)
  end

  def cleanup_test_environment do
    # Cleanup any test data
    File.rm_rf("/tmp/test_files")
    :ets.delete_all_objects(:test_cache)
  end
end

# In test_helper.exs
MyApp.TestConfig.setup_test_environment()

ExUnit.configure(exclude: [:integration, :slow])
ExUnit.start()
```

## Integration Testing

### Testing with External Services

```elixir
defmodule MyApp.Actions.IntegrationTest do
  use ExUnit.Case

  @moduletag :integration

  setup_all do
    # Start test server or ensure external services are available
    {:ok, server} = start_test_server(port: 4002)
    on_exit(fn -> stop_test_server(server) end)
    %{server: server}
  end

  test "real HTTP API integration" do
    {:ok, result} = MyApp.Actions.FetchUserProfile.run(%{
      user_id: "test_user_123"
    }, %{})
    
    assert result.user_id == "test_user_123"
    assert is_binary(result.name)
    assert is_binary(result.email)
  end

  test "database integration" do
    # Use test database
    {:ok, result} = MyApp.Actions.CreateUser.run(%{
      name: "Test User",
      email: "test@example.com"
    }, %{})
    
    # Verify user was actually created in database
    user = MyApp.Repo.get_by(User, email: "test@example.com")
    assert user.name == "Test User"
    
    # Cleanup
    MyApp.Repo.delete(user)
  end
end
```

## Best Practices

### Test Organization
- **Unit Tests**: Test actions in isolation
- **Integration Tests**: Test with real external dependencies
- **Property Tests**: Test with generated inputs
- **Error Tests**: Test all error scenarios

### Test Data
- **Fixtures**: Use consistent test data
- **Factories**: Generate test data programmatically
- **Mocking**: Mock external dependencies in unit tests
- **Cleanup**: Clean up test data after tests

### Performance
- **Fast Tests**: Keep unit tests fast (< 100ms)
- **Parallel Execution**: Run tests in parallel when possible
- **Selective Running**: Tag slow tests for selective execution
- **Resource Management**: Avoid resource leaks in tests

### Coverage
- **Happy Path**: Test successful execution
- **Error Cases**: Test all error conditions
- **Edge Cases**: Test boundary conditions
- **Lifecycle Hooks**: Test all lifecycle callbacks

## Next Steps

**→ [FAQ](faq.md)** - Common testing questions and solutions  
**→ [Configuration Guide](configuration.md)** - Test configuration  
**→ [Security Guide](security.md)** - Security testing

---
← [AI Integration](ai-integration.md) | **Next: [FAQ](faq.md)** →
