defmodule ReqAI.ToolTest do
  use ExUnit.Case, async: true

  alias ReqAI.Error
  alias ReqAI.Tool

  describe "new/1" do
    test "creates tool with minimal options" do
      assert {:ok, tool} =
               Tool.new(
                 name: "test_tool",
                 description: "A test tool",
                 callback: fn _input -> {:ok, "result"} end
               )

      assert tool.name == "test_tool"
      assert tool.description == "A test tool"
      assert tool.parameters == []
      assert is_function(tool.callback, 1)
      assert tool.schema == nil
    end

    test "creates tool with parameters" do
      assert {:ok, tool} =
               Tool.new(
                 name: "weather_tool",
                 description: "Get weather",
                 parameters: [
                   location: [type: :string, required: true, doc: "City name"],
                   units: [type: :string, default: "celsius"]
                 ],
                 callback: {Enum, :count}
               )

      assert tool.name == "weather_tool"
      assert tool.description == "Get weather"
      assert tool.parameters[:location][:required] == true
      assert tool.parameters[:units][:default] == "celsius"
      assert tool.callback == {Enum, :count}
      assert tool.schema != nil
    end

    test "validates required fields" do
      assert {:error, error} = Tool.new([])
      assert %Error.Validation.Error{} = error
      assert error.reason =~ "name"

      assert {:error, error} = Tool.new(name: "test")
      assert %Error.Validation.Error{} = error
      assert error.reason =~ "description"

      assert {:error, error} = Tool.new(name: "test", description: "desc")
      assert %Error.Validation.Error{} = error
      assert error.reason =~ "callback"
    end

    test "validates tool name format" do
      valid_names = [
        "get_weather",
        "calculate_sum",
        "_private_tool",
        "tool123",
        # 63 chars total
        "a" <> String.duplicate("b", 62)
      ]

      for name <- valid_names do
        assert {:ok, _} =
                 Tool.new(
                   name: name,
                   description: "Test",
                   callback: fn _ -> {:ok, "ok"} end
                 )
      end

      invalid_names = [
        # starts with number
        "123invalid",
        # contains hyphen
        "tool-name",
        # contains space
        "tool name",
        # empty
        "",
        # too long
        String.duplicate("a", 65)
      ]

      for name <- invalid_names do
        assert {:error, error} =
                 Tool.new(
                   name: name,
                   description: "Test",
                   callback: fn _ -> {:ok, "ok"} end
                 )

        assert %Error.Invalid.Parameter{} = error
        assert error.parameter =~ "Invalid tool name"
      end
    end

    test "validates callback formats" do
      # Valid MFA - 2 tuple
      assert {:ok, _} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: {Enum, :count}
               )

      # Valid MFA - 3 tuple
      assert {:ok, _} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: {String, :split, ["."]}
               )

      # Valid function
      assert {:ok, _} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: fn _ -> {:ok, "result"} end
               )

      # Invalid callback
      assert {:error, error} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: "invalid"
               )

      assert %Error.Invalid.Parameter{} = error
    end

    test "validates parameter schema" do
      assert {:error, error} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 parameters: [
                   invalid_param: [type: :invalid_type]
                 ],
                 callback: fn _ -> {:ok, "ok"} end
               )

      assert %Error.Invalid.Parameter{} = error
      assert error.parameter =~ "Invalid parameter schema"
    end

    test "rejects non-keyword list options" do
      assert {:error, error} = Tool.new("invalid")
      assert %Error.Invalid.Parameter{} = error
      assert error.parameter =~ "keyword list"
    end
  end

  describe "new!/1" do
    test "creates tool successfully" do
      tool =
        Tool.new!(
          name: "test_tool",
          description: "A test tool",
          callback: fn _ -> {:ok, "result"} end
        )

      assert tool.name == "test_tool"
    end

    test "raises on error" do
      assert_raise Error.Invalid.Parameter, fn ->
        Tool.new!(name: "invalid-name", description: "Test", callback: fn _ -> {:ok, "ok"} end)
      end
    end
  end

  describe "execute/2" do
    setup do
      {:ok, simple_tool} =
        Tool.new(
          name: "echo",
          description: "Echo input",
          callback: fn input -> {:ok, input} end
        )

      {:ok, math_tool} =
        Tool.new(
          name: "add",
          description: "Add two numbers",
          parameters: [
            a: [type: :integer, required: true],
            b: [type: :integer, required: true]
          ],
          callback: fn %{a: a, b: b} -> {:ok, a + b} end
        )

      {:ok, mfa_tool} =
        Tool.new(
          name: "count",
          description: "Count list items",
          parameters: [
            list: [type: {:list, :integer}, required: true]
          ],
          callback: fn %{list: list} -> {:ok, Enum.count(list)} end
        )

      %{
        simple_tool: simple_tool,
        math_tool: math_tool,
        mfa_tool: mfa_tool
      }
    end

    test "executes simple tool", %{simple_tool: tool} do
      assert {:ok, result} = Tool.execute(tool, %{message: "hello"})
      assert result == %{message: "hello"}
    end

    test "validates parameters", %{math_tool: tool} do
      assert {:ok, result} = Tool.execute(tool, %{a: 5, b: 3})
      assert result == 8

      # Missing required parameter
      assert {:error, error} = Tool.execute(tool, %{a: 5})
      assert %Error.Validation.Error{} = error

      # Wrong parameter type
      assert {:error, error} = Tool.execute(tool, %{a: "not_integer", b: 3})
      assert %Error.Validation.Error{} = error
    end

    test "executes MFA callback", %{mfa_tool: tool} do
      assert {:ok, result} = Tool.execute(tool, %{list: [1, 2, 3, 4]})
      assert result == 4
    end

    test "handles callback errors" do
      {:ok, failing_tool} =
        Tool.new(
          name: "fail",
          description: "Always fails",
          callback: fn _ -> raise "boom" end
        )

      assert {:error, error} = Tool.execute(failing_tool, %{})
      assert is_binary(error)
      assert error =~ "Callback execution failed"
    end

    test "validates input is a map", %{simple_tool: tool} do
      assert {:error, error} = Tool.execute(tool, "not a map")
      assert %Error.Invalid.Parameter{} = error
      assert error.parameter =~ "Input must be a map"
    end

    test "normalizes string keys to atoms", %{math_tool: tool} do
      assert {:ok, result} = Tool.execute(tool, %{"a" => 5, "b" => 3})
      assert result == 8
    end
  end

  describe "execute!/2" do
    test "returns result on success" do
      {:ok, tool} =
        Tool.new(
          name: "echo",
          description: "Echo input",
          callback: fn input -> {:ok, input} end
        )

      result = Tool.execute!(tool, %{message: "hello"})
      assert result == %{message: "hello"}
    end

    test "raises on error" do
      {:ok, tool} =
        Tool.new(
          name: "echo",
          description: "Echo input",
          callback: fn input -> {:ok, input} end
        )

      assert_raise Error.Invalid.Parameter, fn ->
        Tool.execute!(tool, "not a map")
      end
    end
  end

  describe "to_json_schema/1" do
    test "generates basic schema" do
      {:ok, tool} =
        Tool.new(
          name: "simple_tool",
          description: "A simple tool",
          callback: fn _ -> {:ok, "ok"} end
        )

      schema = Tool.to_json_schema(tool)

      expected = %{
        "type" => "function",
        "function" => %{
          "name" => "simple_tool",
          "description" => "A simple tool",
          "parameters" => %{
            "type" => "object",
            "properties" => %{}
          }
        }
      }

      assert schema == expected
    end

    test "generates schema with parameters" do
      {:ok, tool} =
        Tool.new(
          name: "weather_tool",
          description: "Get weather information",
          parameters: [
            location: [type: :string, required: true, doc: "City name"],
            units: [type: :string, default: "celsius", doc: "Temperature units"],
            days: [type: :pos_integer, doc: "Number of days"]
          ],
          callback: fn _ -> {:ok, "weather"} end
        )

      schema = Tool.to_json_schema(tool)

      expected = %{
        "type" => "function",
        "function" => %{
          "name" => "weather_tool",
          "description" => "Get weather information",
          "parameters" => %{
            "type" => "object",
            "properties" => %{
              "location" => %{"type" => "string", "description" => "City name"},
              "units" => %{"type" => "string", "description" => "Temperature units"},
              "days" => %{"type" => "integer", "minimum" => 1, "description" => "Number of days"}
            },
            "required" => ["location"]
          }
        }
      }

      assert schema == expected
    end

    test "handles various parameter types" do
      {:ok, tool} =
        Tool.new(
          name: "complex_tool",
          description: "Tool with various types",
          parameters: [
            text: [type: :string],
            count: [type: :integer],
            score: [type: :float],
            active: [type: :boolean],
            tags: [type: {:list, :string}],
            numbers: [type: {:list, :integer}],
            metadata: [type: :map]
          ],
          callback: fn _ -> {:ok, "ok"} end
        )

      schema = Tool.to_json_schema(tool)
      properties = schema["function"]["parameters"]["properties"]

      assert properties["text"]["type"] == "string"
      assert properties["count"]["type"] == "integer"
      assert properties["score"]["type"] == "number"
      assert properties["active"]["type"] == "boolean"
      assert properties["tags"] == %{"type" => "array", "items" => %{"type" => "string"}}
      assert properties["numbers"] == %{"type" => "array", "items" => %{"type" => "integer"}}
      assert properties["metadata"]["type"] == "object"
    end
  end

  describe "valid_name?/1" do
    test "accepts valid names" do
      valid_names = [
        "get_weather",
        "calculate_sum",
        "_private_tool",
        "tool123",
        "a",
        String.duplicate("a", 64)
      ]

      for name <- valid_names do
        assert Tool.valid_name?(name), "#{name} should be valid"
      end
    end

    test "rejects invalid names" do
      invalid_names = [
        # starts with number
        "123invalid",
        # contains hyphen
        "tool-name",
        # contains space
        "tool name",
        # contains dot
        "tool.name",
        # empty
        "",
        # too long
        String.duplicate("a", 65),
        # not a string
        nil,
        # not a string
        123
      ]

      for name <- invalid_names do
        refute Tool.valid_name?(name), "#{inspect(name)} should be invalid"
      end
    end
  end

  # Test module for MFA callbacks
  defmodule TestModule do
    def simple_callback(input), do: {:ok, "processed: #{inspect(input)}"}

    def callback_with_args(prefix, suffix, input),
      do: {:ok, "#{prefix}_#{inspect(input)}_#{suffix}"}
  end

  describe "MFA callback execution" do
    test "executes {module, function} callback" do
      {:ok, tool} =
        Tool.new(
          name: "test",
          description: "Test MFA",
          callback: {TestModule, :simple_callback}
        )

      assert {:ok, result} = Tool.execute(tool, %{test: "data"})
      assert result == "processed: %{test: \"data\"}"
    end

    test "executes {module, function, args} callback" do
      {:ok, tool} =
        Tool.new(
          name: "test",
          description: "Test MFA with args",
          callback: {TestModule, :callback_with_args, ["start", "end"]}
        )

      assert {:ok, result} = Tool.execute(tool, %{test: "data"})
      assert result == "start_%{test: \"data\"}_end"
    end

    test "validates MFA function exists" do
      assert {:error, error} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: {TestModule, :nonexistent}
               )

      assert %Error.Invalid.Parameter{} = error
      assert error.parameter =~ "does not exist"

      assert {:error, error} =
               Tool.new(
                 name: "test",
                 description: "Test",
                 callback: {TestModule, :callback_with_args, [:single_arg]}
               )

      assert %Error.Invalid.Parameter{} = error
      assert error.parameter =~ "does not exist"
    end
  end
end
