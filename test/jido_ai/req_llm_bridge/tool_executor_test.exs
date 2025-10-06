defmodule Jido.AI.ReqLlmBridge.ToolExecutorTest do
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.ReqLlmBridge.{ErrorHandler, ParameterConverter, ToolExecutor}

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Mock Action for testing
    defmodule TestAction do
      use Jido.Action,
        name: "test_action",
        description: "A test action for tool execution",
        schema: [
          name: [type: :string, required: true, doc: "The name parameter"],
          count: [type: :integer, default: 1, doc: "The count parameter"],
          enabled: [type: :boolean, default: false, doc: "Enable flag"]
        ]

      @impl true
      def run(params, _context) do
        {:ok,
         %{
           message: "Hello #{params.name}",
           count: params.count,
           enabled: params.enabled,
           timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
         }}
      end
    end

    # Action that takes time (for timeout testing)
    defmodule SlowAction do
      use Jido.Action,
        name: "slow_action",
        description: "An action that takes time",
        schema: [
          delay: [type: :integer, default: 100, doc: "Delay in milliseconds"]
        ]

      @impl true
      def run(%{delay: delay}, _context) do
        Process.sleep(delay)
        {:ok, %{completed: true, delay: delay}}
      end
    end

    # Action that always fails
    defmodule FailingAction do
      use Jido.Action,
        name: "failing_action",
        description: "An action that always fails",
        schema: []

      @impl true
      def run(_params, _context) do
        {:error, "This action always fails"}
      end
    end

    # Action that raises exceptions
    defmodule ExceptionAction do
      use Jido.Action,
        name: "exception_action",
        description: "An action that raises exceptions",
        schema: []

      @impl true
      def run(_params, _context) do
        raise "Simulated exception"
      end
    end

    # Action that returns non-serializable data
    defmodule NonSerializableAction do
      use Jido.Action,
        name: "non_serializable",
        description: "Returns non-serializable data",
        schema: []

      @impl true
      def run(_params, _context) do
        {:ok, %{pid: self(), ref: make_ref(), function: fn -> :ok end}}
      end
    end

    {:ok,
     %{
       test_action: TestAction,
       slow_action: SlowAction,
       failing_action: FailingAction,
       exception_action: ExceptionAction,
       non_serializable_action: NonSerializableAction
     }}
  end

  describe "create_callback/2" do
    test "creates a function that executes action correctly", %{test_action: action} do
      callback = ToolExecutor.create_callback(action)
      assert is_function(callback, 1)

      params = %{"name" => "Pascal", "count" => "5", "enabled" => "true"}
      assert {:ok, result} = callback.(params)

      assert result.message == "Hello Pascal"
      assert result.count == 5
      assert result.enabled == true
      assert is_binary(result.timestamp)
    end

    test "creates callback with context", %{test_action: action} do
      context = %{user_id: 123, session: "test_session"}
      callback = ToolExecutor.create_callback(action, context)

      params = %{"name" => "test"}
      assert {:ok, result} = callback.(params)
      assert is_map(result)
    end

    test "callback handles parameter validation errors", %{test_action: action} do
      callback = ToolExecutor.create_callback(action)

      # Missing required parameter
      invalid_params = %{"count" => "5"}
      assert {:error, error} = callback.(invalid_params)
      assert error.type == "parameter_validation_error"
    end

    test "callback handles type conversion", %{test_action: action} do
      callback = ToolExecutor.create_callback(action)

      # String values that need conversion
      params = %{"name" => "test", "count" => "42", "enabled" => "true"}
      assert {:ok, result} = callback.(params)

      assert result.name == "test"
      assert result.count == 42
      assert result.enabled == true
    end
  end

  describe "execute_tool/4" do
    test "successfully executes action with valid parameters", %{test_action: action} do
      params = %{"name" => "Pascal", "count" => "3"}
      context = %{user_id: 123}

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, context)
      assert result.message == "Hello Pascal"
      assert result.count == 3
    end

    test "handles parameter validation failures", %{test_action: action} do
      invalid_params = %{"invalid_field" => "value"}

      assert {:error, error} = ToolExecutor.execute_tool(action, invalid_params, %{})
      assert error.type == "parameter_validation_error"
    end

    test "handles action execution failures", %{failing_action: action} do
      params = %{}

      assert {:error, error} = ToolExecutor.execute_tool(action, params, %{})
      assert error.type == "action_error"
      assert String.contains?(error.message, "Action execution failed")
    end

    test "handles action exceptions", %{exception_action: action} do
      params = %{}

      assert {:error, error} = ToolExecutor.execute_tool(action, params, %{})
      assert error.type == "exception"
      assert String.contains?(error.message, "Simulated exception")
    end

    test "handles execution timeout", %{slow_action: action} do
      # 5 seconds
      params = %{"delay" => "5000"}
      # 100ms timeout
      timeout = 100

      assert {:error, error} = ToolExecutor.execute_tool(action, params, %{}, timeout)
      assert error.type == "execution_timeout"
    end

    test "handles non-serializable results", %{non_serializable_action: action} do
      params = %{}

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, %{})
      # Should either sanitize or provide fallback
      assert is_map(result)
      # PIDs should be converted to strings or have serialization fallback
      assert Map.has_key?(result, :pid) or Map.has_key?(result, :serialization_fallback)
    end

    test "respects custom timeout", %{slow_action: action} do
      params = %{"delay" => "200"}
      # Should complete within this timeout
      timeout = 300

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, %{}, timeout)
      assert result.completed == true
      assert result.delay == 200
    end

    test "validates input parameters", %{test_action: action} do
      # Test with non-map params
      assert {:error, error} = ToolExecutor.execute_tool(action, "invalid", %{})
      assert error.type == "parameter_validation_error"

      # Test with non-atom action
      assert_raise FunctionClauseError, fn ->
        ToolExecutor.execute_tool("not_an_atom", %{}, %{})
      end
    end
  end

  describe "execute_with_circuit_breaker/4" do
    test "executes normally when circuit is closed", %{test_action: action} do
      params = %{"name" => "test"}

      assert {:ok, result} = ToolExecutor.execute_with_circuit_breaker(action, params, %{})
      assert is_map(result)
    end

    test "handles circuit breaker activation" do
      # Note: The current implementation always returns :closed
      # In a real implementation, this would test actual circuit breaker logic
      params = %{"name" => "test"}

      # Should work normally since circuit breaker is simplified
      assert {:ok, _result} = ToolExecutor.execute_with_circuit_breaker(TestAction, params, %{})
    end
  end

  describe "parameter conversion and validation" do
    test "converts string parameters to correct types", %{test_action: action} do
      params = %{
        "name" => "Pascal",
        "count" => "42",
        "enabled" => "true"
      }

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, %{})
      assert result.name == "Pascal"
      assert result.count == 42
      assert result.enabled == true
    end

    test "applies default values for missing optional parameters", %{test_action: action} do
      # count and enabled should get defaults
      params = %{"name" => "test"}

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, %{})
      # default value
      assert result.count == 1
      # default value
      assert result.enabled == false
    end

    test "handles mixed parameter formats", %{test_action: action} do
      params = %{
        "name" => "test",
        # already an integer
        "count" => 5,
        # already a boolean
        "enabled" => true
      }

      assert {:ok, result} = ToolExecutor.execute_tool(action, params, %{})
      assert result.count == 5
      assert result.enabled == true
    end
  end

  describe "error handling and sanitization" do
    test "sanitizes error data for security" do
      sensitive_error = %{
        password: "secret123",
        api_key: "sk-1234567890",
        message: "Authentication failed"
      }

      sanitized = ErrorHandler.sanitize_error_for_logging(sensitive_error)
      assert sanitized.password == "[REDACTED]"
      assert sanitized.api_key == "[REDACTED]"
      assert sanitized.message == "Authentication failed"
    end

    test "preserves non-sensitive error information" do
      error_data = %{
        type: "validation_error",
        field: "name",
        message: "Required field missing"
      }

      sanitized = ErrorHandler.sanitize_error_for_logging(error_data)
      assert sanitized == error_data
    end
  end

  describe "performance and resource management" do
    test "handles concurrent tool executions", %{test_action: action} do
      tasks =
        1..10
        |> Enum.map(fn i ->
          Task.async(fn ->
            params = %{"name" => "User#{i}", "count" => "#{i}"}
            ToolExecutor.execute_tool(action, params, %{})
          end)
        end)

      results = Task.await_many(tasks, 5_000)

      # All executions should succeed
      assert length(results) == 10

      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      # Results should have correct user names
      names = Enum.map(results, fn {:ok, result} -> result.message end)
      assert "Hello User1" in names
      assert "Hello User10" in names
    end

    test "cleans up resources on timeout", %{slow_action: action} do
      params = %{"delay" => "1000"}
      timeout = 50

      # Should timeout and clean up properly
      assert {:error, error} = ToolExecutor.execute_tool(action, params, %{}, timeout)
      assert error.type == "execution_timeout"

      # Process should not be left hanging
      # (This is handled by Task.shutdown in the implementation)
    end
  end

  describe "logging and monitoring" do
    test "logs execution success when logging enabled" do
      # Enable logging for this test
      Application.put_env(:jido_ai, :enable_req_llm_logging, true)

      params = %{"name" => "test"}

      # Should complete without errors and log appropriately
      assert {:ok, _result} = ToolExecutor.execute_tool(TestAction, params, %{})

      # Cleanup
      Application.put_env(:jido_ai, :enable_req_llm_logging, false)
    end

    test "logs execution failures when logging enabled" do
      Application.put_env(:jido_ai, :enable_req_llm_logging, true)

      invalid_params = %{"invalid" => "params"}

      # Should fail and log appropriately
      assert {:error, _error} = ToolExecutor.execute_tool(TestAction, invalid_params, %{})

      Application.put_env(:jido_ai, :enable_req_llm_logging, false)
    end
  end
end
