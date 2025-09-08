defmodule ReqLLM.ToolTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Tool

  describe "struct creation" do
    test "creates tool with required fields" do
      callback = fn _args -> {:ok, "result"} end

      tool = %Tool{
        name: "test_tool",
        description: "A test tool",
        parameter_schema: [location: [type: :string]],
        callback: callback
      }

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
      assert tool.parameter_schema == [location: [type: :string]]
      assert tool.callback == callback
      assert tool.compiled == nil
    end
  end

  describe "new/1" do
    test "creates tool with valid params" do
      params = [
        name: "get_weather",
        description: "Get weather information",
        parameter_schema: [
          location: [type: :string, required: true],
          units: [type: :string, default: "celsius"]
        ],
        callback: fn args -> {:ok, "Weather: #{args[:location]}"} end
      ]

      {:ok, tool} = Tool.new(params)
      assert tool.name == "get_weather"
      assert tool.description == "Get weather information"
      assert is_function(tool.callback, 1)
    end

    test "validates tool name format" do
      params = [
        name: "invalid name with spaces",
        description: "Test tool",
        callback: fn _args -> {:ok, "result"} end
      ]

      assert {:error, _error} = Tool.new(params)
    end

    test "validates callback format" do
      params = [
        name: "test_tool",
        description: "Test tool",
        callback: "not a function"
      ]

      assert {:error, _error} = Tool.new(params)
    end

    test "supports MFA callback" do
      defmodule TestModule do
        def test_function(args), do: {:ok, "MFA result: #{inspect(args)}"}
      end

      params = [
        name: "mfa_tool",
        description: "MFA test tool",
        callback: {TestModule, :test_function, []}
      ]

      {:ok, tool} = Tool.new(params)
      assert tool.callback == {TestModule, :test_function, []}
    end

    test "defaults parameter_schema to empty list" do
      params = [
        name: "simple_tool",
        description: "Simple tool with no params",
        callback: fn _args -> {:ok, "simple"} end
      ]

      {:ok, tool} = Tool.new(params)
      assert tool.parameter_schema == []
    end
  end

  describe "execute/2" do
    test "executes function callback" do
      callback = fn args -> {:ok, "Result for #{args[:name]}"} end

      tool = %Tool{
        name: "test_tool",
        description: "Test",
        callback: callback
      }

      assert {:ok, "Result for John"} = Tool.execute(tool, %{name: "John"})
    end

    test "executes MFA callback" do
      defmodule ExecuteTestModule do
        def process_args(args), do: {:ok, "Processed: #{inspect(args)}"}
      end

      tool = %Tool{
        name: "mfa_tool",
        description: "MFA test",
        callback: {ExecuteTestModule, :process_args, []}
      }

      assert {:ok, "Processed: %{data: \"test\"}"} =
               Tool.execute(tool, %{data: "test"})
    end

    test "handles callback errors" do
      callback = fn _args -> raise "Something went wrong" end

      tool = %Tool{
        name: "error_tool",
        description: "Error test",
        callback: callback
      }

      assert {:error, _error} = Tool.execute(tool, %{})
    end

    test "handles callback returning error tuple" do
      callback = fn _args -> {:error, "Invalid input"} end

      tool = %Tool{
        name: "error_tool",
        description: "Returns error",
        callback: callback
      }

      assert {:error, "Invalid input"} = Tool.execute(tool, %{})
    end
  end

  describe "to_schema/2" do
    test "returns Anthropic format by default" do
      tool = %Tool{
        name: "test_tool",
        description: "A test tool",
        parameter_schema: [name: [type: :string]],
        callback: fn _args -> {:ok, "result"} end
      }

      schema = Tool.to_schema(tool, :anthropic)

      assert schema["name"] == "test_tool"
      assert schema["description"] == "A test tool"
      assert is_map(schema["input_schema"])
    end

    test "returns Anthropic format" do
      tool = %Tool{
        name: "test_tool",
        description: "A test tool",
        parameter_schema: [name: [type: :string]],
        callback: fn _args -> {:ok, "result"} end
      }

      schema = Tool.to_schema(tool, :anthropic)

      assert schema["name"] == "test_tool"
      assert schema["description"] == "A test tool"
      assert is_map(schema["input_schema"])
      refute Map.has_key?(schema, "type")
      refute Map.has_key?(schema, "function")
    end

    test "raises for unknown provider" do
      tool = %Tool{
        name: "test_tool",
        description: "Test",
        callback: fn _args -> {:ok, "result"} end
      }

      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Tool.to_schema(tool, :unknown_provider)
      end
    end
  end

  describe "to_json_schema/1 (backward compatibility)" do
    test "defaults to Anthropic format" do
      tool = %Tool{
        name: "compat_tool",
        description: "Backward compatibility test",
        parameter_schema: [value: [type: :integer]],
        callback: fn _args -> {:ok, 42} end
      }

      anthropic_schema = Tool.to_schema(tool, :anthropic)
      compat_schema = Tool.to_json_schema(tool)

      assert anthropic_schema == compat_schema
    end
  end

  describe "parameter schema compilation" do
    test "handles empty parameter schema" do
      tool = %Tool{
        name: "no_params",
        description: "No parameters",
        parameter_schema: [],
        callback: fn _args -> {:ok, "done"} end
      }

      schema = Tool.to_schema(tool, :anthropic)
      params = schema["input_schema"]

      assert params["type"] == "object"
      assert params["properties"] == %{}
    end

    test "handles complex parameter schema" do
      tool = %Tool{
        name: "complex_tool",
        description: "Complex parameters",
        parameter_schema: [
          location: [type: :string, required: true],
          options: [
            type: :keyword_list,
            keys: [
              units: [type: :string, default: "celsius"],
              days: [type: :pos_integer, default: 5]
            ]
          ]
        ],
        callback: fn _args -> {:ok, "result"} end
      }

      schema = Tool.to_schema(tool, :anthropic)
      params = schema["input_schema"]

      assert params["type"] == "object"
      assert is_map(params["properties"]["location"])
      assert is_map(params["properties"]["options"])
    end
  end

  describe "edge cases" do
    test "handles tool with metadata" do
      callback = fn _args -> {:ok, "result"} end

      tool = %Tool{
        name: "meta_tool",
        description: "Tool with metadata",
        parameter_schema: [],
        callback: callback,
        compiled: nil
      }

      assert tool.compiled == nil
      assert Tool.execute(tool, %{}) == {:ok, "result"}
    end

    test "handles anonymous function callbacks" do
      tool = %Tool{
        name: "anon_tool",
        description: "Anonymous function",
        callback: fn args -> {:ok, Map.get(args, :result, "default")} end
      }

      assert {:ok, "custom"} = Tool.execute(tool, %{result: "custom"})
      assert {:ok, "default"} = Tool.execute(tool, %{})
    end
  end
end
