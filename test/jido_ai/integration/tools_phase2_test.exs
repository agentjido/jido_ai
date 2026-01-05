defmodule Jido.AI.Integration.ToolsPhase2Test do
  @moduledoc """
  Integration tests for Phase 2 Tool System.

  These tests verify that all Phase 2 components work together correctly:
  - Registry manages both Actions and Tools
  - Executor executes via Registry lookup
  - ReqLLM tool format generation
  - Error handling flows

  Tests use mocked response data and do not make actual API calls.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Tools.Executor
  alias Jido.AI.Tools.Registry
  alias Jido.AI.Tools.Tool

  # ============================================================================
  # Test Actions and Tools
  # ============================================================================

  defmodule TestActions.Calculator do
    use Jido.Action,
      name: "calculator",
      description: "Performs arithmetic calculations",
      schema: [
        operation: [type: :string, required: true, doc: "The operation to perform"],
        a: [type: :integer, required: true, doc: "First operand"],
        b: [type: :integer, required: true, doc: "Second operand"]
      ]

    @impl true
    def run(params, _context) do
      case params.operation do
        "add" -> {:ok, %{result: params.a + params.b}}
        "subtract" -> {:ok, %{result: params.a - params.b}}
        "multiply" -> {:ok, %{result: params.a * params.b}}
        "divide" when params.b != 0 -> {:ok, %{result: div(params.a, params.b)}}
        "divide" -> {:error, "Division by zero"}
        _ -> {:error, "Unknown operation: #{params.operation}"}
      end
    end
  end

  defmodule TestActions.ContextAware do
    use Jido.Action,
      name: "context_aware",
      description: "An action that uses context",
      schema: [
        key: [type: :string, required: true, doc: "Context key to read"]
      ]

    @impl true
    def run(params, context) do
      value = Map.get(context, String.to_atom(params.key), "not found")
      {:ok, %{key: params.key, value: value}}
    end
  end

  defmodule TestActions.FailingAction do
    use Jido.Action,
      name: "failing_action",
      description: "An action that always fails",
      schema: [
        message: [type: :string, required: true, doc: "Error message"]
      ]

    @impl true
    def run(params, _context) do
      {:error, params.message}
    end
  end

  defmodule TestTools.Echo do
    use Tool,
      name: "echo",
      description: "Echoes back the input message"

    @impl true
    def schema do
      [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{echoed: params.message}}
    end
  end

  defmodule TestTools.UpperCase do
    use Tool,
      name: "uppercase",
      description: "Converts text to uppercase"

    @impl true
    def schema do
      [
        text: [type: :string, required: true, doc: "Text to convert"]
      ]
    end

    @impl true
    def run(params, _context) do
      {:ok, %{result: String.upcase(params.text)}}
    end
  end

  defmodule TestTools.ContextReader do
    use Tool,
      name: "context_reader",
      description: "Reads values from context"

    @impl true
    def schema do
      [
        key: [type: :string, required: true, doc: "Key to read from context"]
      ]
    end

    @impl true
    def run(params, context) do
      value = Map.get(context, String.to_atom(params.key))
      {:ok, %{key: params.key, value: value}}
    end
  end

  # ============================================================================
  # Setup
  # ============================================================================

  setup do
    Registry.ensure_started()
    Registry.clear()
    :ok
  end

  # ============================================================================
  # Section 2.5.1: Registry and Executor Integration
  # ============================================================================

  describe "2.5.1 Registry and Executor Integration" do
    test "register action → execute by name → get result" do
      # Register action
      :ok = Registry.register_action(TestActions.Calculator)

      # Verify registration
      {:ok, {:action, TestActions.Calculator}} = Registry.get("calculator")

      # Execute via Executor with string keys (like LLM would provide)
      result = Executor.execute("calculator", %{"operation" => "add", "a" => "5", "b" => "3"}, %{})

      assert {:ok, %{result: 8}} = result
    end

    test "register tool → execute by name → get result" do
      # Register tool
      :ok = Registry.register_tool(TestTools.Echo)

      # Verify registration
      {:ok, {:tool, TestTools.Echo}} = Registry.get("echo")

      # Execute via Executor
      result = Executor.execute("echo", %{"message" => "hello world"}, %{})

      assert {:ok, %{echoed: "hello world"}} = result
    end

    test "mixed actions and tools in registry" do
      # Register both actions and tools
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_action(TestActions.ContextAware)
      :ok = Registry.register_tool(TestTools.Echo)
      :ok = Registry.register_tool(TestTools.UpperCase)

      # Verify all registered
      all = Registry.list_all()
      assert length(all) == 4

      # Verify types
      actions = Registry.list_actions()
      tools = Registry.list_tools()

      assert length(actions) == 2
      assert length(tools) == 2

      # Execute each type
      assert {:ok, %{result: 6}} =
               Executor.execute("calculator", %{"operation" => "multiply", "a" => "2", "b" => "3"}, %{})

      assert {:ok, %{echoed: "test"}} = Executor.execute("echo", %{"message" => "test"}, %{})

      assert {:ok, %{result: "HELLO"}} = Executor.execute("uppercase", %{"text" => "hello"}, %{})
    end

    test "executor handles context for actions" do
      :ok = Registry.register_action(TestActions.ContextAware)

      context = %{user_id: "user_123", role: "admin"}
      result = Executor.execute("context_aware", %{"key" => "user_id"}, context)

      assert {:ok, %{key: "user_id", value: "user_123"}} = result
    end

    test "executor handles context for tools" do
      :ok = Registry.register_tool(TestTools.ContextReader)

      context = %{api_key: "secret_key", environment: "test"}
      result = Executor.execute("context_reader", %{"key" => "environment"}, context)

      assert {:ok, %{key: "environment", value: "test"}} = result
    end
  end

  # ============================================================================
  # Section 2.5.2: ReqLLM Integration
  # ============================================================================

  describe "2.5.2 ReqLLM Integration" do
    test "Registry.to_reqllm_tools returns valid ReqLLM.Tool structs" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      tools = Registry.to_reqllm_tools()

      assert length(tools) == 2
      assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    end

    test "action schemas are properly converted to JSON Schema" do
      :ok = Registry.register_action(TestActions.Calculator)

      [tool] = Registry.to_reqllm_tools()

      assert tool.name == "calculator"
      assert tool.description == "Performs arithmetic calculations"
      assert is_map(tool.parameter_schema)

      # Verify JSON Schema structure
      assert tool.parameter_schema["type"] == "object"
      assert is_map(tool.parameter_schema["properties"])
      assert Map.has_key?(tool.parameter_schema["properties"], "operation")
      assert Map.has_key?(tool.parameter_schema["properties"], "a")
      assert Map.has_key?(tool.parameter_schema["properties"], "b")
    end

    test "tool schemas are properly converted to JSON Schema" do
      :ok = Registry.register_tool(TestTools.UpperCase)

      [tool] = Registry.to_reqllm_tools()

      assert tool.name == "uppercase"
      assert tool.description == "Converts text to uppercase"
      assert is_map(tool.parameter_schema)

      # Verify JSON Schema structure
      assert tool.parameter_schema["type"] == "object"
      assert is_map(tool.parameter_schema["properties"])
      assert Map.has_key?(tool.parameter_schema["properties"], "text")
    end

    test "both Actions and Tools produce compatible formats" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      tools = Registry.to_reqllm_tools()

      # Both should have the same structure
      for tool <- tools do
        assert is_struct(tool, ReqLLM.Tool)
        assert is_binary(tool.name)
        assert is_binary(tool.description)
        assert is_map(tool.parameter_schema)
        assert tool.parameter_schema["type"] == "object"
        assert is_map(tool.parameter_schema["properties"])
      end
    end

    test "required fields are marked in JSON Schema" do
      :ok = Registry.register_action(TestActions.Calculator)

      [tool] = Registry.to_reqllm_tools()

      # All fields in Calculator are required
      assert is_list(tool.parameter_schema["required"])
      assert "operation" in tool.parameter_schema["required"]
      assert "a" in tool.parameter_schema["required"]
      assert "b" in tool.parameter_schema["required"]
    end
  end

  # ============================================================================
  # Section 2.5.3: End-to-End Tool Calling
  # ============================================================================

  describe "2.5.3 End-to-End Tool Calling" do
    test "executor handles tool not found gracefully" do
      result = Executor.execute("nonexistent_tool", %{}, %{})

      assert {:error, error} = result
      assert error.type == :not_found
      assert error.tool_name == "nonexistent_tool"
      assert String.contains?(error.error, "not found")
    end

    test "executor handles tool execution errors gracefully" do
      :ok = Registry.register_action(TestActions.FailingAction)

      result = Executor.execute("failing_action", %{"message" => "Something went wrong"}, %{})

      assert {:error, error} = result
      assert error.type == :execution_error
      assert error.tool_name == "failing_action"
      assert error.error == "Something went wrong"
    end

    test "executor handles validation errors for missing required params" do
      :ok = Registry.register_action(TestActions.Calculator)

      # Missing required parameters
      result = Executor.execute("calculator", %{}, %{})

      assert {:error, error} = result
      assert error.type == :execution_error
      assert String.contains?(error.error, "required")
    end

    test "executor normalizes string keys to atom keys" do
      :ok = Registry.register_action(TestActions.Calculator)

      # LLM provides string keys
      result = Executor.execute("calculator", %{"operation" => "add", "a" => 10, "b" => 20}, %{})

      assert {:ok, %{result: 30}} = result
    end

    test "executor parses string numbers to integers" do
      :ok = Registry.register_action(TestActions.Calculator)

      # LLM might provide numbers as strings
      result = Executor.execute("calculator", %{"operation" => "add", "a" => "15", "b" => "25"}, %{})

      assert {:ok, %{result: 40}} = result
    end

    test "executor respects timeout configuration" do
      defmodule SlowTool do
        use Tool,
          name: "slow_tool",
          description: "A slow tool for testing timeouts"

        @impl true
        def schema, do: [delay: [type: :integer, required: true]]

        @impl true
        def run(params, _context) do
          Process.sleep(params.delay)
          {:ok, %{completed: true}}
        end
      end

      :ok = Registry.register_tool(SlowTool)

      # Should complete within timeout
      assert {:ok, %{completed: true}} =
               Executor.execute("slow_tool", %{"delay" => "50"}, %{}, timeout: 1000)

      # Should timeout
      result = Executor.execute("slow_tool", %{"delay" => "500"}, %{}, timeout: 100)

      assert {:error, error} = result
      assert error.type == :timeout
      assert error.tool_name == "slow_tool"
    end

    test "complete simulated tool calling flow" do
      # 1. Register tools
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.UpperCase)

      # 2. Get ReqLLM tools (would be passed to LLM)
      reqllm_tools = Registry.to_reqllm_tools()
      assert length(reqllm_tools) == 2

      # 3. Simulate LLM returning a tool call
      simulated_tool_call = %{
        id: "call_abc123",
        name: "calculator",
        arguments: %{"operation" => "multiply", "a" => "7", "b" => "8"}
      }

      # 4. Execute the tool call
      result =
        Executor.execute(
          simulated_tool_call.name,
          simulated_tool_call.arguments,
          %{}
        )

      assert {:ok, %{result: 56}} = result

      # 5. Format result for LLM (would be added back to conversation)
      formatted = Executor.format_result(elem(result, 1))
      assert formatted == %{result: 56}
    end

    test "sequential tool calls maintain state correctly" do
      :ok = Registry.register_action(TestActions.Calculator)

      # First tool call
      {:ok, result1} =
        Executor.execute(
          "calculator",
          %{"operation" => "add", "a" => "10", "b" => "20"},
          %{}
        )

      assert result1.result == 30

      # Second tool call using previous result
      {:ok, result2} =
        Executor.execute(
          "calculator",
          %{"operation" => "multiply", "a" => Integer.to_string(result1.result), "b" => "2"},
          %{}
        )

      assert result2.result == 60
    end

    test "error during tool execution returns structured error" do
      :ok = Registry.register_action(TestActions.Calculator)

      # Division by zero
      result =
        Executor.execute(
          "calculator",
          %{"operation" => "divide", "a" => "10", "b" => "0"},
          %{}
        )

      assert {:error, error} = result
      assert error.type == :execution_error
      assert error.tool_name == "calculator"
      assert error.error == "Division by zero"
    end
  end

  # ============================================================================
  # Additional Integration Scenarios
  # ============================================================================

  describe "registry lifecycle" do
    test "clear removes all registered items" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      assert length(Registry.list_all()) == 2

      Registry.clear()

      assert Registry.list_all() == []
    end

    test "unregister removes specific item" do
      :ok = Registry.register_action(TestActions.Calculator)
      :ok = Registry.register_tool(TestTools.Echo)

      :ok = Registry.unregister("calculator")

      assert length(Registry.list_all()) == 1
      assert {:error, :not_found} = Registry.get("calculator")
      assert {:ok, _} = Registry.get("echo")
    end

    test "re-registration overwrites previous entry" do
      defmodule CalculatorV1 do
        use Jido.Action,
          name: "calculator",
          description: "Version 1",
          schema: []

        @impl true
        def run(_params, _context), do: {:ok, %{version: 1}}
      end

      defmodule CalculatorV2 do
        use Jido.Action,
          name: "calculator",
          description: "Version 2",
          schema: []

        @impl true
        def run(_params, _context), do: {:ok, %{version: 2}}
      end

      :ok = Registry.register_action(CalculatorV1)
      {:ok, {:action, CalculatorV1}} = Registry.get("calculator")

      :ok = Registry.register_action(CalculatorV2)
      {:ok, {:action, CalculatorV2}} = Registry.get("calculator")

      # Execute should use V2
      {:ok, result} = Executor.execute("calculator", %{}, %{})
      assert result.version == 2
    end
  end

  describe "telemetry integration" do
    test "executor emits telemetry events for successful execution" do
      test_pid = self()

      :telemetry.attach_many(
        "integration-test-handler",
        [
          [:jido, :ai, :tool, :execute, :start],
          [:jido, :ai, :tool, :execute, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      :ok = Registry.register_action(TestActions.Calculator)

      Executor.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "1"}, %{})

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :start], %{system_time: _}, %{tool_name: "calculator"}}

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _}, %{tool_name: "calculator"}}

      :telemetry.detach("integration-test-handler")
    end

    test "executor emits stop telemetry for not_found errors" do
      test_pid = self()

      :telemetry.attach(
        "integration-stop-error-handler",
        [:jido, :ai, :tool, :execute, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Execute nonexistent tool - this emits a stop event, not exception
      Executor.execute("nonexistent", %{}, %{})

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _},
                      %{tool_name: "nonexistent", result: {:error, %{type: :not_found}}}}

      :telemetry.detach("integration-stop-error-handler")
    end
  end
end
