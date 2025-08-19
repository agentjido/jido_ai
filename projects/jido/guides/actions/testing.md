# Testing Actions

This guide covers comprehensive testing strategies for Jido Actions, including unit testing, property-based testing, integration testing, and testing complex scenarios like compensation and concurrency.

## Core Testing Principles

When testing Actions, focus on:

1. Input validation and parameter handling
2. Core business logic execution
3. Error handling and compensation
4. Context propagation
5. Integration with other system components

## Basic Test Structure

Here's a basic test module structure for Actions:

```elixir
defmodule MyApp.Actions.CalculatorTest do
  use ExUnit.Case, async: true
  alias MyApp.Actions.Calculator

  describe "basic execution" do
    test "adds two numbers correctly" do
      params = %{value: 5, amount: 3}
      assert {:ok, %{result: 8}} = Calculator.run(params, %{})
    end

    test "validates required parameters" do
      params = %{value: 5}
      assert {:error, error} = Calculator.run(params, %{})
      assert error.type == :validation_error
    end
  end
end
```

## Testing Parameter Validation

Test both valid and invalid parameter scenarios:

```elixir
describe "parameter validation" do
  test "accepts valid parameters" do
    params = %{name: "test", count: 42}
    assert {:ok, validated} = MyAction.validate_params(params)
    assert validated.name == "test"
    assert validated.count == 42
  end

  test "rejects invalid parameter types" do
    params = %{name: 123, count: "not a number"}
    assert {:error, error} = MyAction.validate_params(params)
    assert error.type == :validation_error
  end

  test "handles missing required parameters" do
    params = %{name: "test"}
    assert {:error, error} = MyAction.validate_params(params)
    assert error.message =~ "Required key :count not found"
  end

  test "allows additional parameters" do
    params = %{name: "test", count: 42, extra: "data"}
    assert {:ok, validated} = MyAction.validate_params(params)
    assert validated.extra == "data"
  end
end
```

## Testing Error Handling

Test various error scenarios and compensation logic:

```elixir
describe "error handling" do
  test "handles runtime errors" do
    assert {:error, error} = ErrorAction.run(%{error_type: :runtime}, %{})
    assert error.type == :execution_error
  end

  test "handles validation errors" do
    assert {:error, error} = ErrorAction.run(%{error_type: :validation}, %{})
    assert error.type == :validation_error
  end

  test "compensates for failures when enabled" do
    params = %{should_fail: true}
    assert {:error, error} = CompensatingAction.run(params, %{})
    assert {:ok, result} = CompensatingAction.on_error(params, error, %{}, [])
    assert result.compensated == true
  end
end
```

## Testing Asynchronous Actions

For Actions with async operations:

```elixir
describe "async operations" do
  setup do
    # Start any required processes
    {:ok, pid} = start_supervised(MyApp.AsyncProcessor)
    %{processor: pid}
  end

  test "processes async operations", %{processor: pid} do
    params = %{data: "test", processor: pid}
    assert {:ok, result} = AsyncAction.run(params, %{})
    assert_receive {:processing_complete, ^result}, 1000
  end

  test "handles async timeouts", %{processor: pid} do
    params = %{data: "slow", processor: pid}
    assert {:error, error} = AsyncAction.run(params, %{timeout: 50})
    assert error.type == :timeout
  end
end
```

## Property-Based Testing

Use property-based testing for comprehensive input coverage:

```elixir
defmodule CalcActionTest do
  use ExUnit.Case
  use ExUnitProperties

  describe "arithmetic operations" do
    property "addition is commutative" do
      check all(
        x <- integer(),
        y <- integer()
      ) do
        params1 = %{value: x, amount: y}
        params2 = %{value: y, amount: x}

        assert {:ok, result1} = AddAction.run(params1, %{})
        assert {:ok, result2} = AddAction.run(params2, %{})
        assert result1.result == result2.result
      end
    end

    property "multiplication by zero yields zero" do
      check all(x <- integer()) do
        params = %{value: x, amount: 0}
        assert {:ok, %{result: 0}} = MultiplyAction.run(params, %{})
      end
    end
  end
end
```

## Testing Context Propagation

Verify that Actions properly handle and propagate context:

```elixir
describe "context handling" do
  test "propagates context through execution" do
    context = %{user_id: "user_123", tenant: "tenant_456"}
    params = %{operation: "test"}

    assert {:ok, result} = ContextAwareAction.run(params, context)
    assert result.user_id == "user_123"
    assert result.tenant == "tenant_456"
  end

  test "enriches context during execution" do
    initial_context = %{request_id: "req_123"}
    params = %{add_timestamp: true}

    assert {:ok, result} = ContextAction.run(params, initial_context)
    assert result.context.request_id == "req_123"
    assert is_integer(result.context.timestamp)
  end
end
```

## Testing Complex Workflows

Test Actions as part of larger workflows:

```elixir
describe "workflow integration" do
  test "executes in workflow chain" do
    {:ok, result} = Jido.Workflow.run_chain(
      [
        ValidateAction,
        ProcessAction,
        NotifyAction
      ],
      %{input: "test data"},
      %{context_key: "value"}
    )

    assert result.validated == true
    assert result.processed == true
    assert result.notified == true
  end

  test "handles workflow failures" do
    {:error, error} = Jido.Workflow.run_chain(
      [
        ValidateAction,
        FailingAction,
        NotifyAction
      ],
      %{input: "test data"}
    )

    assert error.type == :execution_error
    assert error.message =~ "Workflow failed"
  end
end
```

## Testing Concurrent Operations

For Actions that perform concurrent operations:

```elixir
describe "concurrent operations" do
  test "processes items concurrently" do
    inputs = [1, 2, 3, 4, 5]
    assert {:ok, %{results: results}} =
      ConcurrentAction.run(%{inputs: inputs}, %{})

    assert length(results) == 5
    assert Enum.all?(results, fn r -> is_integer(r) end)
  end

  test "handles partial failures in concurrent operations" do
    inputs = [1, :error, 3, :error, 5]
    assert {:ok, %{results: results, errors: errors}} =
      ConcurrentAction.run(%{inputs: inputs}, %{})

    assert length(results) == 3
    assert length(errors) == 2
  end
end
```

## Testing Helper Functions

Common test helpers for Action testing:

```elixir
defmodule ActionTestHelper do
  def assert_validation_error(result, expected_message) do
    assert {:error, error} = result
    assert error.type == :validation_error
    assert error.message =~ expected_message
  end

  def assert_execution_error(result, expected_message) do
    assert {:error, error} = result
    assert error.type == :execution_error
    assert error.message =~ expected_message
  end

  def with_timeout(timeout, fun) do
    Task.await(Task.async(fun), timeout)
  end
end
```

## Best Practices

1. **Test Organization**

   - Group related tests using `describe` blocks
   - Use meaningful test names that describe behavior
   - Keep test cases focused and isolated

2. **Validation Testing**

   - Test all schema constraints
   - Include edge cases and boundary values
   - Test optional parameter handling

3. **Error Handling**

   - Test all error paths
   - Verify error types and messages
   - Test compensation logic when enabled

4. **Asynchronous Testing**

   - Use appropriate timeouts
   - Test timeout handling
   - Clean up resources in `on_exit` callbacks

5. **Context Management**
   - Test context propagation
   - Verify context modifications
   - Test context-dependent behavior

## Common Issues and Solutions

1. **Flaky Tests**

   ```elixir
   # Bad - timing dependent
   test "processes async operation" do
     {:ok, pid} = AsyncAction.run(params, %{})
     Process.sleep(100)
     assert Process.alive?(pid)
   end

   # Good - use assertions with timeouts
   test "processes async operation" do
     {:ok, pid} = AsyncAction.run(params, %{})
     assert_receive {:operation_complete, ^pid}, 1000
   end
   ```

2. **Resource Cleanup**

   ```elixir
   describe "file operations" do
     setup do
       path = "/tmp/test_#{:rand.uniform(1000)}"
       on_exit(fn -> File.rm_rf!(path) end)
       {:ok, path: path}
     end

     test "writes file", %{path: path} do
       assert {:ok, _} = FileAction.run(%{path: path}, %{})
     end
   end
   ```

3. **Context Isolation**
   ```elixir
   # Use setup blocks for shared context
   setup do
     context = %{
       request_id: "req_#{System.unique_integer()}",
       timestamp: System.system_time()
     }
     {:ok, context: context}
   end
   ```

## See Also

- [Actions Overview](actions/overview.md)
- [Workflow Testing](workflow/testing.md)
- [ExUnit Documentation](https://hexdocs.pm/ex_unit/)
- [StreamData Documentation](https://hexdocs.pm/stream_data/)
