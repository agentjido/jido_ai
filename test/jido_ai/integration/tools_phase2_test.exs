defmodule Jido.AI.Integration.ToolsPhase2Test do
  @moduledoc """
  Integration tests for Phase 2 Tool System.

  These tests verify that all Phase 2 components work together correctly:
  - Registry manages Actions
  - Turn executes tools via Registry lookup
  - ReqLLM tool format generation
  - Error handling flows

  Tests use mocked response data and do not make actual API calls.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.ToolAdapter
  alias Jido.AI.Turn

  # ============================================================================
  # Test Actions
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

  defmodule TestActions.Echo do
    use Jido.Action,
      name: "echo",
      description: "Echoes back the input message",
      schema: [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{echoed: params.message}}
    end
  end

  defmodule TestActions.UpperCase do
    use Jido.Action,
      name: "uppercase",
      description: "Converts text to uppercase",
      schema: [
        text: [type: :string, required: true, doc: "Text to convert"]
      ]

    @impl true
    def run(params, _context) do
      {:ok, %{result: String.upcase(params.text)}}
    end
  end

  defmodule TestActions.ContextReader do
    use Jido.Action,
      name: "context_reader",
      description: "Reads values from context",
      schema: [
        key: [type: :string, required: true, doc: "Key to read from context"]
      ]

    @impl true
    def run(params, context) do
      value = Map.get(context, String.to_atom(params.key))
      {:ok, %{key: params.key, value: value}}
    end
  end

  defmodule TestActions.SlowAction do
    use Jido.Action,
      name: "slow_action",
      description: "A slow action for testing timeouts",
      schema: [
        delay: [type: :integer, required: true, doc: "Delay in milliseconds"]
      ]

    @impl true
    def run(params, _context) do
      Process.sleep(params.delay)
      {:ok, %{completed: true}}
    end
  end

  defmodule TestActions.CalculatorV1 do
    use Jido.Action,
      name: "calculator",
      description: "Version 1",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{version: 1}}
  end

  defmodule TestActions.CalculatorV2 do
    use Jido.Action,
      name: "calculator",
      description: "Version 2",
      schema: []

    @impl true
    def run(_params, _context), do: {:ok, %{version: 2}}
  end

  # ============================================================================
  # Setup - Build tools map for each test
  # ============================================================================

  setup do
    tools_map =
      Turn.build_tools_map([
        TestActions.Calculator,
        TestActions.ContextAware,
        TestActions.FailingAction,
        TestActions.Echo,
        TestActions.UpperCase,
        TestActions.ContextReader
      ])

    {:ok, tools: tools_map}
  end

  # ============================================================================
  # Section 2.5.1: Tools Map and Turn Integration
  # ============================================================================

  describe "2.5.1 Tools Map and Turn Integration" do
    test "build tools map → execute by name → get result", %{tools: tools} do
      # Verify tools map has calculator
      assert Map.has_key?(tools, "calculator")
      assert tools["calculator"] == TestActions.Calculator

      # Execute via Turn with string keys (like LLM would provide)
      result =
        Turn.execute("calculator", %{"operation" => "add", "a" => "5", "b" => "3"}, %{}, tools: tools)

      assert {:ok, %{result: 8}, []} = result
    end

    test "build tools map → execute echo → get result", %{tools: tools} do
      # Verify tools map has echo
      assert Map.has_key?(tools, "echo")
      assert tools["echo"] == TestActions.Echo

      # Execute via Turn
      result = Turn.execute("echo", %{"message" => "hello world"}, %{}, tools: tools)

      assert {:ok, %{echoed: "hello world"}, []} = result
    end

    test "multiple actions in tools map", %{tools: tools} do
      # Verify all registered
      assert map_size(tools) == 6

      # Execute each action
      assert {:ok, %{result: 6}, []} =
               Turn.execute(
                 "calculator",
                 %{"operation" => "multiply", "a" => "2", "b" => "3"},
                 %{},
                 tools: tools
               )

      assert {:ok, %{echoed: "test"}, []} =
               Turn.execute("echo", %{"message" => "test"}, %{}, tools: tools)

      assert {:ok, %{result: "HELLO"}, []} =
               Turn.execute("uppercase", %{"text" => "hello"}, %{}, tools: tools)
    end

    test "turn execution handles context for actions", %{tools: tools} do
      context = %{user_id: "user_123", role: "admin"}
      result = Turn.execute("context_aware", %{"key" => "user_id"}, context, tools: tools)

      assert {:ok, %{key: "user_id", value: "user_123"}, []} = result
    end

    test "turn execution handles context for context reader action", %{tools: tools} do
      context = %{api_key: "secret_key", environment: "test"}
      result = Turn.execute("context_reader", %{"key" => "environment"}, context, tools: tools)

      assert {:ok, %{key: "environment", value: "test"}, []} = result
    end
  end

  # ============================================================================
  # Section 2.5.2: ReqLLM Integration
  # ============================================================================

  describe "2.5.2 ReqLLM Integration" do
    test "ToolAdapter.from_action returns valid ReqLLM.Tool structs" do
      tools = [
        ToolAdapter.from_action(TestActions.Calculator),
        ToolAdapter.from_action(TestActions.Echo)
      ]

      assert length(tools) == 2
      assert Enum.all?(tools, &is_struct(&1, ReqLLM.Tool))
    end

    test "action schemas are properly converted to JSON Schema" do
      tool = ToolAdapter.from_action(TestActions.Calculator)

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

    test "uppercase action schema is properly converted to JSON Schema" do
      tool = ToolAdapter.from_action(TestActions.UpperCase)

      assert tool.name == "uppercase"
      assert tool.description == "Converts text to uppercase"
      assert is_map(tool.parameter_schema)

      # Verify JSON Schema structure
      assert tool.parameter_schema["type"] == "object"
      assert is_map(tool.parameter_schema["properties"])
      assert Map.has_key?(tool.parameter_schema["properties"], "text")
    end

    test "all actions produce compatible formats" do
      tools = [
        ToolAdapter.from_action(TestActions.Calculator),
        ToolAdapter.from_action(TestActions.Echo)
      ]

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
      tool = ToolAdapter.from_action(TestActions.Calculator)

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
    test "executor handles tool not found gracefully", %{tools: tools} do
      result = Turn.execute("nonexistent_tool", %{}, %{}, tools: tools)

      assert {:error, error, []} = result
      assert error.type == :not_found
      assert error.tool_name == "nonexistent_tool"
      assert String.contains?(error.error, "not found")
    end

    test "executor handles tool execution errors gracefully", %{tools: tools} do
      result =
        Turn.execute("failing_action", %{"message" => "Something went wrong"}, %{}, tools: tools, timeout: 50)

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert error.tool_name == "failing_action"
      assert error.error == "Something went wrong"
    end

    test "executor handles validation errors for missing required params", %{tools: tools} do
      # Missing required parameters
      result = Turn.execute("calculator", %{}, %{}, tools: tools)

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert String.contains?(error.error, "required")
    end

    test "executor normalizes string keys to atom keys", %{tools: tools} do
      # LLM provides string keys
      result =
        Turn.execute("calculator", %{"operation" => "add", "a" => 10, "b" => 20}, %{}, tools: tools)

      assert {:ok, %{result: 30}, []} = result
    end

    test "executor parses string numbers to integers", %{tools: tools} do
      # LLM might provide numbers as strings
      result =
        Turn.execute("calculator", %{"operation" => "add", "a" => "15", "b" => "25"}, %{}, tools: tools)

      assert {:ok, %{result: 40}, []} = result
    end

    test "executor respects timeout configuration" do
      slow_tools = Turn.build_tools_map([TestActions.SlowAction])

      # Should complete within timeout
      assert {:ok, %{completed: true}, []} =
               Turn.execute("slow_action", %{"delay" => "20"}, %{},
                 tools: slow_tools,
                 timeout: 200
               )

      # Should timeout
      result =
        Turn.execute("slow_action", %{"delay" => "120"}, %{}, tools: slow_tools, timeout: 30)

      assert {:error, error, []} = result
      assert error.type == :timeout
      assert error.tool_name == "slow_action"
    end

    test "complete simulated tool calling flow", %{tools: tools} do
      # 1. Build ReqLLM tools (would be passed to LLM)
      reqllm_tools = [
        ToolAdapter.from_action(TestActions.Calculator),
        ToolAdapter.from_action(TestActions.UpperCase)
      ]

      assert length(reqllm_tools) == 2

      # 2. Simulate LLM returning a tool call
      simulated_tool_call = %{
        id: "call_abc123",
        name: "calculator",
        arguments: %{"operation" => "multiply", "a" => "7", "b" => "8"}
      }

      # 3. Execute the tool call
      result =
        Turn.execute(
          simulated_tool_call.name,
          simulated_tool_call.arguments,
          %{},
          tools: tools
        )

      assert {:ok, %{result: 56}, []} = result

      # 4. Format result for tool message content (would be added back to conversation)
      formatted = Turn.format_tool_result_content(result)
      assert formatted == "{\"result\":56}"
    end

    test "sequential tool calls maintain state correctly", %{tools: tools} do
      # First tool call
      {:ok, result1, []} =
        Turn.execute(
          "calculator",
          %{"operation" => "add", "a" => "10", "b" => "20"},
          %{},
          tools: tools
        )

      assert result1.result == 30

      # Second tool call using previous result
      {:ok, result2, []} =
        Turn.execute(
          "calculator",
          %{"operation" => "multiply", "a" => Integer.to_string(result1.result), "b" => "2"},
          %{},
          tools: tools
        )

      assert result2.result == 60
    end

    test "error during tool execution returns structured error", %{tools: tools} do
      # Division by zero
      result =
        Turn.execute(
          "calculator",
          %{"operation" => "divide", "a" => "10", "b" => "0"},
          %{},
          tools: tools,
          timeout: 50
        )

      assert {:error, error, []} = result
      assert error.type == :execution_error
      assert error.tool_name == "calculator"
      assert error.error == "Division by zero"
    end
  end

  # ============================================================================
  # Additional Integration Scenarios
  # ============================================================================

  describe "tools map lifecycle" do
    test "build_tools_map creates map with correct entries" do
      tools = Turn.build_tools_map([TestActions.Calculator, TestActions.Echo])

      assert map_size(tools) == 2
      assert Map.has_key?(tools, "calculator")
      assert Map.has_key?(tools, "echo")
    end

    test "tools map can be modified by rebuilding" do
      tools1 = Turn.build_tools_map([TestActions.Calculator, TestActions.Echo])
      assert map_size(tools1) == 2

      # Build new map without calculator
      tools2 = Turn.build_tools_map([TestActions.Echo])
      assert map_size(tools2) == 1
      refute Map.has_key?(tools2, "calculator")
      assert Map.has_key?(tools2, "echo")
    end

    test "later module with same name overwrites in tools map" do
      # Later entry wins in build_tools_map
      tools = Turn.build_tools_map([TestActions.CalculatorV1, TestActions.CalculatorV2])
      assert tools["calculator"] == TestActions.CalculatorV2

      # Execute should use V2
      {:ok, result, []} = Turn.execute("calculator", %{}, %{}, tools: tools)
      assert result.version == 2
    end
  end

  describe "telemetry integration" do
    test "turn execution emits telemetry events for successful execution", %{tools: tools} do
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

      Turn.execute("calculator", %{"operation" => "add", "a" => "1", "b" => "1"}, %{}, tools: tools)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :start], %{system_time: _}, %{tool_name: "calculator"}}

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _}, %{tool_name: "calculator"}}

      :telemetry.detach("integration-test-handler")
    end

    test "turn execution emits stop telemetry for not_found errors", %{tools: tools} do
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
      Turn.execute("nonexistent", %{}, %{}, tools: tools)

      assert_receive {:telemetry, [:jido, :ai, :tool, :execute, :stop], %{duration: _},
                      %{tool_name: "nonexistent", result: {:error, %{type: :not_found}, []}}}

      :telemetry.detach("integration-stop-error-handler")
    end
  end
end
