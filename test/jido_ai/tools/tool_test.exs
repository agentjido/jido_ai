defmodule Jido.AI.Tools.ToolTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Tools.Tool

  # Define test tools
  defmodule CalculatorTool do
    use Jido.AI.Tools.Tool,
      name: "calculator",
      description: "Performs basic arithmetic operations"

    @impl true
    def schema do
      [
        a: [type: :number, required: true, doc: "First operand"],
        b: [type: :number, required: true, doc: "Second operand"],
        operation: [type: :string, required: true, doc: "Operation to perform"]
      ]
    end

    @impl true
    def run(params, _context) do
      result =
        case params.operation do
          "add" -> params.a + params.b
          "subtract" -> params.a - params.b
          "multiply" -> params.a * params.b
          "divide" when params.b != 0 -> params.a / params.b
          "divide" -> {:error, "Division by zero"}
          op -> {:error, "Unknown operation: #{op}"}
        end

      case result do
        {:error, reason} -> {:error, reason}
        value -> {:ok, %{result: value}}
      end
    end
  end

  defmodule EchoTool do
    use Jido.AI.Tools.Tool,
      name: "echo",
      description: "Echoes back the input message"

    @impl true
    def schema do
      [
        message: [type: :string, required: true, doc: "Message to echo"]
      ]
    end

    @impl true
    def run(params, context) do
      {:ok, %{
        message: params.message,
        context_keys: Map.keys(context)
      }}
    end
  end

  defmodule OverriddenTool do
    use Jido.AI.Tools.Tool,
      name: "original_name",
      description: "Original description"

    @impl true
    def name, do: "overridden_name"

    @impl true
    def description, do: "Overridden description"

    @impl true
    def schema do
      [value: [type: :string]]
    end

    @impl true
    def run(params, _context) do
      {:ok, params}
    end
  end

  describe "behavior callbacks" do
    test "name/0 returns the tool name" do
      assert CalculatorTool.name() == "calculator"
      assert EchoTool.name() == "echo"
    end

    test "description/0 returns the tool description" do
      assert CalculatorTool.description() == "Performs basic arithmetic operations"
      assert EchoTool.description() == "Echoes back the input message"
    end

    test "schema/0 returns the parameter schema" do
      schema = CalculatorTool.schema()
      assert is_list(schema)
      assert Keyword.has_key?(schema, :a)
      assert Keyword.has_key?(schema, :b)
      assert Keyword.has_key?(schema, :operation)
    end

    test "callbacks can be overridden" do
      assert OverriddenTool.name() == "overridden_name"
      assert OverriddenTool.description() == "Overridden description"
    end
  end

  describe "__using__ macro" do
    test "injects @behaviour" do
      # The module compiles successfully with @behaviour
      assert function_exported?(CalculatorTool, :name, 0)
      assert function_exported?(CalculatorTool, :description, 0)
      assert function_exported?(CalculatorTool, :schema, 0)
      assert function_exported?(CalculatorTool, :run, 2)
    end

    test "provides default name/0 from opts" do
      assert CalculatorTool.name() == "calculator"
    end

    test "provides default description/0 from opts" do
      assert CalculatorTool.description() == "Performs basic arithmetic operations"
    end

    test "generates to_reqllm_tool/0 function" do
      assert function_exported?(CalculatorTool, :to_reqllm_tool, 0)
    end

    test "raises if name not provided" do
      assert_raise ArgumentError, ~r/Tool requires :name option/, fn ->
        defmodule MissingNameTool do
          use Jido.AI.Tools.Tool,
            description: "Missing name"

          def schema, do: []
          def run(_, _), do: {:ok, %{}}
        end
      end
    end

    test "raises if description not provided" do
      assert_raise ArgumentError, ~r/Tool requires :description option/, fn ->
        defmodule MissingDescTool do
          use Jido.AI.Tools.Tool,
            name: "missing_desc"

          def schema, do: []
          def run(_, _), do: {:ok, %{}}
        end
      end
    end
  end

  describe "run/2 execution" do
    test "executes calculator add operation" do
      params = %{a: 5, b: 3, operation: "add"}
      assert {:ok, %{result: 8}} = CalculatorTool.run(params, %{})
    end

    test "executes calculator subtract operation" do
      params = %{a: 10, b: 4, operation: "subtract"}
      assert {:ok, %{result: 6}} = CalculatorTool.run(params, %{})
    end

    test "executes calculator multiply operation" do
      params = %{a: 6, b: 7, operation: "multiply"}
      assert {:ok, %{result: 42}} = CalculatorTool.run(params, %{})
    end

    test "executes calculator divide operation" do
      params = %{a: 20, b: 4, operation: "divide"}
      assert {:ok, %{result: 5.0}} = CalculatorTool.run(params, %{})
    end

    test "returns error for division by zero" do
      params = %{a: 10, b: 0, operation: "divide"}
      assert {:error, "Division by zero"} = CalculatorTool.run(params, %{})
    end

    test "returns error for unknown operation" do
      params = %{a: 1, b: 2, operation: "unknown"}
      assert {:error, "Unknown operation: unknown"} = CalculatorTool.run(params, %{})
    end

    test "receives context in run/2" do
      params = %{message: "Hello"}
      context = %{user_id: "123", session: "abc"}

      {:ok, result} = EchoTool.run(params, context)
      assert result.message == "Hello"
      assert :user_id in result.context_keys
      assert :session in result.context_keys
    end
  end

  describe "to_reqllm_tool/1" do
    test "creates valid ReqLLM.Tool struct" do
      tool = Tool.to_reqllm_tool(CalculatorTool)

      assert %ReqLLM.Tool{} = tool
      assert tool.name == "calculator"
      assert tool.description == "Performs basic arithmetic operations"
    end

    test "includes parameter schema" do
      tool = Tool.to_reqllm_tool(CalculatorTool)

      assert is_map(tool.parameter_schema)
      assert tool.parameter_schema["type"] == "object"
      assert is_map(tool.parameter_schema["properties"])
      assert Map.has_key?(tool.parameter_schema["properties"], "a")
      assert Map.has_key?(tool.parameter_schema["properties"], "b")
      assert Map.has_key?(tool.parameter_schema["properties"], "operation")
    end

    test "includes required fields in schema" do
      tool = Tool.to_reqllm_tool(CalculatorTool)

      required = tool.parameter_schema["required"]
      assert is_list(required)
      assert "a" in required
      assert "b" in required
      assert "operation" in required
    end

    test "has noop callback" do
      tool = Tool.to_reqllm_tool(CalculatorTool)

      assert is_function(tool.callback, 1)
      assert {:error, :not_executed_via_callback} = tool.callback.(%{})
    end

    test "works with module-level to_reqllm_tool/0" do
      tool = CalculatorTool.to_reqllm_tool()

      assert %ReqLLM.Tool{} = tool
      assert tool.name == "calculator"
    end
  end

  describe "schema to JSON Schema conversion" do
    test "converts number types" do
      tool = Tool.to_reqllm_tool(CalculatorTool)
      props = tool.parameter_schema["properties"]

      # Jido.Action.Schema maps :number to "integer" in JSON Schema
      assert props["a"]["type"] == "integer"
      assert props["b"]["type"] == "integer"
    end

    test "converts string types" do
      tool = Tool.to_reqllm_tool(CalculatorTool)
      props = tool.parameter_schema["properties"]

      assert props["operation"]["type"] == "string"
    end

    test "includes doc as description" do
      tool = Tool.to_reqllm_tool(CalculatorTool)
      props = tool.parameter_schema["properties"]

      assert props["a"]["description"] == "First operand"
      assert props["operation"]["description"] == "Operation to perform"
    end
  end
end
