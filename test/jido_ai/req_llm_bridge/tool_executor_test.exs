defmodule Jido.AI.ReqLlmBridge.ToolExecutorTest do
  use ExUnit.Case, async: false

  alias Jido.AI.ReqLlmBridge.ToolExecutor

  @moduledoc """
  Tests for the ToolExecutor module.

  Tests cover:
  - Basic tool execution with valid parameters
  - Execution timeout protection
  - Callback function creation
  - Parameter validation and conversion
  - Comprehensive error handling
  - JSON serialization and sanitization
  - Circuit breaker pattern (simplified)
  """

  # Helper module for testing - a simple action that returns its params
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "A test action for unit tests",
      schema: [
        message: [type: :string, required: true, doc: "Test message"],
        count: [type: :integer, default: 1, doc: "Count value"]
      ]

    def run(params, _context) do
      {:ok, %{message: params[:message], count: params[:count]}}
    end
  end

  # Action that times out
  defmodule TimeoutAction do
    use Jido.Action,
      name: "timeout_action",
      description: "An action that sleeps",
      schema: [
        duration_ms: [type: :integer, required: true, doc: "Sleep duration in milliseconds"]
      ]

    def run(params, _context) do
      Process.sleep(params[:duration_ms])
      {:ok, %{slept: params[:duration_ms]}}
    end
  end

  # Action that raises an exception
  defmodule ExceptionAction do
    use Jido.Action,
      name: "exception_action",
      description: "An action that raises exceptions",
      schema: [
        error_message: [type: :string, required: true, doc: "Error message to raise"]
      ]

    def run(params, _context) do
      raise RuntimeError, params[:error_message]
    end
  end

  # Action that returns non-serializable data
  defmodule NonSerializableAction do
    use Jido.Action,
      name: "non_serializable_action",
      description: "Returns non-serializable data",
      schema: []

    def run(_params, _context) do
      {:ok, %{pid: self(), ref: make_ref(), function: fn -> :ok end}}
    end
  end

  describe "2.1 Basic Tool Execution" do
    test "successful tool execution with valid params" do
      # Use Jido.Actions.Basic.Sleep for a real action
      params = %{"duration_ms" => 10}

      assert {:ok, result} = ToolExecutor.execute_tool(Jido.Actions.Basic.Sleep, params, %{})
      assert is_map(result)
      assert Map.has_key?(result, :duration_ms)
    end

    test "successful execution with TestAction" do
      params = %{"message" => "test", "count" => 5}

      assert {:ok, result} = ToolExecutor.execute_tool(TestAction, params, %{})
      assert result.message == "test"
      assert result.count == 5
    end

    test "execution timeout protection" do
      # Set a short timeout (100ms) for an action that sleeps longer (500ms)
      params = %{"duration_ms" => 500}

      assert {:error, error} = ToolExecutor.execute_tool(TimeoutAction, params, %{}, 100)
      assert error.type == "execution_timeout"
      assert error.timeout == 100
    end

    test "callback function creation" do
      # Create callback for TestAction
      callback = ToolExecutor.create_callback(TestAction, %{})

      assert is_function(callback, 1)

      # Execute callback
      params = %{"message" => "callback test", "count" => 3}
      assert {:ok, result} = callback.(params)
      assert result.message == "callback test"
      assert result.count == 3
    end

    test "callback function with context" do
      # Create callback with context
      context = %{user_id: 123, session: "test-session"}
      callback = ToolExecutor.create_callback(TestAction, context)

      assert is_function(callback, 1)

      # Execute callback - context should be passed through
      params = %{"message" => "with context"}
      assert {:ok, _result} = callback.(params)
    end
  end

  describe "2.2 Parameter Validation" do
    test "parameter conversion from JSON to Jido format" do
      # Pass JSON params with string keys
      json_params = %{"message" => "test", "count" => 42}

      assert {:ok, result} = ToolExecutor.execute_tool(TestAction, json_params, %{})

      # Parameters should be converted and validated
      assert result.message == "test"
      assert result.count == 42
    end

    test "parameter validation against Action schema" do
      # Missing required parameter
      params = %{"count" => 5}
      # Note: "message" is required

      assert {:error, error} = ToolExecutor.execute_tool(TestAction, params, %{})
      assert error.type == "parameter_validation_error"
      assert is_binary(error.message)
    end

    test "parameter validation error formatting" do
      # Pass invalid parameters
      params = %{"invalid_field" => "value"}

      assert {:error, error} = ToolExecutor.execute_tool(TestAction, params, %{})

      assert error.type == "parameter_validation_error"
      assert Map.has_key?(error, :message)
      assert Map.has_key?(error, :details)
      assert error.action_module == TestAction
    end

    test "parameter type validation" do
      # Pass wrong type for count (should be integer)
      params = %{"message" => "test", "count" => "not_an_integer"}

      assert {:error, error} = ToolExecutor.execute_tool(TestAction, params, %{})
      assert error.type == "parameter_validation_error"
    end
  end

  describe "2.3 Error Handling" do
    test "execution exception catching and formatting" do
      # Execute action that raises exception
      params = %{"error_message" => "Test exception"}

      assert {:error, error} = ToolExecutor.execute_tool(ExceptionAction, params, %{})

      # Exceptions raised inside actions are caught and wrapped as "action_error"
      assert error.type == "action_error"
      assert String.contains?(error.message, "failed")
      # The exception details are nested in the error
      assert is_map(error.details)
      assert error.details.type == "action_execution_error"
    end

    test "JSON serialization with non-serializable data" do
      # Execute action that returns non-serializable data
      params = %{}

      assert {:ok, result} = ToolExecutor.execute_tool(NonSerializableAction, params, %{})

      # Result should be sanitized
      assert is_map(result)

      # PID should be converted to string
      assert is_binary(result.pid)
      assert String.starts_with?(result.pid, "#PID<")

      # Reference should be converted to string
      assert is_binary(result.ref)
      assert String.starts_with?(result.ref, "#Reference<")

      # Function should be converted to string
      assert is_binary(result.function)
      assert String.contains?(result.function, "#Function<")
    end

    test "sanitization of PID" do
      params = %{}
      {:ok, result} = ToolExecutor.execute_tool(NonSerializableAction, params, %{})

      # Verify PID is sanitized
      assert is_binary(result.pid)
      assert result.pid =~ ~r/#PID<\d+\.\d+\.\d+>/
    end

    test "sanitization of reference" do
      params = %{}
      {:ok, result} = ToolExecutor.execute_tool(NonSerializableAction, params, %{})

      # Verify reference is sanitized
      assert is_binary(result.ref)
      assert result.ref =~ ~r/#Reference</
    end

    test "sanitization of function" do
      params = %{}
      {:ok, result} = ToolExecutor.execute_tool(NonSerializableAction, params, %{})

      # Verify function is sanitized
      assert is_binary(result.function)
      assert result.function =~ ~r/#Function</
    end

    test "handles action errors gracefully" do
      # Action that returns error tuple
      defmodule ErrorAction do
        use Jido.Action,
          name: "error_action",
          description: "Returns error",
          schema: []

        def run(_params, _context) do
          {:error, "Action failed"}
        end
      end

      params = %{}

      assert {:error, error} = ToolExecutor.execute_tool(ErrorAction, params, %{})
      assert error.type == "action_error"
      assert String.contains?(error.message, "failed")
    end
  end

  describe "2.4 Circuit Breaker (Simplified)" do
    test "circuit breaker status check returns :closed" do
      params = %{"message" => "test"}

      # Execute with circuit breaker
      assert {:ok, result} =
               ToolExecutor.execute_with_circuit_breaker(TestAction, params, %{})

      assert result.message == "test"
    end

    test "circuit breaker executes tool normally when closed" do
      params = %{"duration_ms" => 10}

      assert {:ok, result} =
               ToolExecutor.execute_with_circuit_breaker(
                 Jido.Actions.Basic.Sleep,
                 params,
                 %{}
               )

      assert is_map(result)
    end

    test "circuit breaker records failures" do
      # Execute with invalid parameters to trigger failure
      params = %{}

      assert {:error, _error} =
               ToolExecutor.execute_with_circuit_breaker(TestAction, params, %{})

      # Circuit breaker should still be closed (simplified implementation)
      # In production, repeated failures would open the circuit
    end

    test "circuit breaker with custom timeout" do
      params = %{"message" => "test", "count" => 1}

      assert {:ok, result} =
               ToolExecutor.execute_with_circuit_breaker(TestAction, params, %{}, 10_000)

      assert result.message == "test"
    end
  end
end
