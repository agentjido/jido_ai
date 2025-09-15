defmodule ReqLLM.ToolTest do
  use ExUnit.Case, async: true

  alias ReqLLM.Tool

  # Test fixtures
  defmodule TestModule do
    def simple_callback(args), do: {:ok, "Simple: #{inspect(args)}"}
    def error_callback(_args), do: {:error, "Intentional error"}
    def exception_callback(_args), do: raise("Boom!")

    def multi_arg_callback(extra1, extra2, args),
      do: {:ok, "Multi: #{extra1}, #{extra2}, #{inspect(args)}"}
  end

  describe "struct creation" do
    test "creates tool with all fields and defaults" do
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
    test "creates tool with minimal params" do
      params = [
        name: "minimal_tool",
        description: "Minimal tool",
        callback: fn _args -> {:ok, "minimal"} end
      ]

      {:ok, tool} = Tool.new(params)

      assert tool.name == "minimal_tool"
      assert tool.description == "Minimal tool"
      assert tool.parameter_schema == []
      assert tool.compiled == nil
      assert is_function(tool.callback, 1)
    end

    test "creates tool with full params and compiles schema" do
      params = [
        name: "weather_tool",
        description: "Get weather information",
        parameter_schema: [
          location: [type: :string, required: true],
          units: [type: :string, default: "celsius"]
        ],
        callback: fn args -> {:ok, "Weather: #{args[:location]}"} end
      ]

      {:ok, tool} = Tool.new(params)

      assert tool.name == "weather_tool"
      assert tool.description == "Get weather information"
      assert Keyword.keyword?(tool.parameter_schema)
      assert tool.compiled != nil
      assert is_function(tool.callback, 1)
    end

    test "supports various MFA callback formats" do
      # MFA without extra args
      {:ok, tool1} =
        Tool.new(
          name: "mfa_tool",
          description: "MFA test",
          callback: {TestModule, :simple_callback}
        )

      assert tool1.callback == {TestModule, :simple_callback}

      # MFA with extra args
      {:ok, tool2} =
        Tool.new(
          name: "mfa_args_tool",
          description: "MFA with args",
          callback: {TestModule, :multi_arg_callback, ["arg1", "arg2"]}
        )

      assert tool2.callback == {TestModule, :multi_arg_callback, ["arg1", "arg2"]}
    end

    test "validates tool name format" do
      # Invalid names
      invalid_names = [
        "invalid name with spaces",
        "123starts_with_number",
        "special-chars",
        "emoji😊",
        "",
        # > 64 chars
        String.duplicate("a", 65)
      ]

      for name <- invalid_names do
        params = [name: name, description: "Test", callback: fn _ -> {:ok, "ok"} end]
        assert {:error, _} = Tool.new(params)
      end

      # Valid names  
      valid_names = ["valid_name", "CamelCase", "_underscore", "a1b2c3", "get_weather_info"]

      for name <- valid_names do
        params = [name: name, description: "Test", callback: fn _ -> {:ok, "ok"} end]
        assert {:ok, _} = Tool.new(params)
      end
    end

    test "validates callback format" do
      base_params = [name: "test", description: "Test"]

      # Invalid callbacks
      invalid_callbacks = [
        "string",
        123,
        {NotAModule, :function},
        {TestModule, :nonexistent},
        {TestModule, :simple_callback, "not_a_list"}
      ]

      for callback <- invalid_callbacks do
        params = base_params ++ [callback: callback]
        assert {:error, _} = Tool.new(params)
      end
    end

    test "validates required fields" do
      assert {:error, _} = Tool.new([])
      assert {:error, _} = Tool.new(name: "test")
      assert {:error, _} = Tool.new(description: "test")
      assert {:error, _} = Tool.new(name: "test", description: "test")
    end

    test "validates non-keyword input" do
      assert {:error, error} = Tool.new("not a keyword list")
      assert Exception.message(error) =~ "keyword list"

      assert {:error, error} = Tool.new(%{name: "test"})
      assert Exception.message(error) =~ "keyword list"
    end
  end

  describe "new!/1" do
    test "returns tool on success" do
      params = [
        name: "bang_tool",
        description: "Success test",
        callback: fn _ -> {:ok, "ok"} end
      ]

      tool = Tool.new!(params)
      assert %Tool{} = tool
      assert tool.name == "bang_tool"
    end

    test "raises on error" do
      assert_raise ReqLLM.Error.Invalid.Parameter, fn ->
        Tool.new!(name: "invalid name", description: "Test", callback: fn _ -> {:ok, "ok"} end)
      end
    end
  end

  describe "execute/2" do
    setup do
      {:ok, simple_tool} =
        Tool.new(
          name: "simple",
          description: "Simple tool",
          callback: {TestModule, :simple_callback}
        )

      {:ok, parameterized_tool} =
        Tool.new(
          name: "parameterized",
          description: "Tool with params",
          parameter_schema: [
            required_field: [type: :string, required: true],
            optional_field: [type: :integer, default: 42]
          ],
          callback: fn args -> {:ok, "Got: #{inspect(args)}"} end
        )

      %{simple_tool: simple_tool, parameterized_tool: parameterized_tool}
    end

    test "executes function callback", %{simple_tool: tool} do
      assert {:ok, "Simple: %{name: \"John\"}"} = Tool.execute(tool, %{name: "John"})
      assert {:ok, "Simple: %{}"} = Tool.execute(tool, %{})
    end

    test "executes MFA callback without extra args" do
      {:ok, tool} =
        Tool.new(
          name: "mfa_simple",
          description: "MFA test",
          callback: {TestModule, :simple_callback}
        )

      assert {:ok, "Simple: %{data: \"test\"}"} = Tool.execute(tool, %{data: "test"})
    end

    test "executes MFA callback with extra args" do
      {:ok, tool} =
        Tool.new(
          name: "mfa_multi",
          description: "MFA with args",
          callback: {TestModule, :multi_arg_callback, ["extra1", "extra2"]}
        )

      assert {:ok, "Multi: extra1, extra2, %{data: \"input\"}"} =
               Tool.execute(tool, %{data: "input"})
    end

    test "validates parameters against schema", %{parameterized_tool: tool} do
      # Valid input
      assert {:ok, _} = Tool.execute(tool, %{required_field: "value"})
      assert {:ok, _} = Tool.execute(tool, %{required_field: "value", optional_field: 100})

      # String keys get normalized
      assert {:ok, _} = Tool.execute(tool, %{"required_field" => "value"})

      # Missing required field
      assert {:error, _} = Tool.execute(tool, %{optional_field: 100})
      assert {:error, _} = Tool.execute(tool, %{})

      # Wrong type
      assert {:error, _} = Tool.execute(tool, %{required_field: 123})
    end

    test "handles callback errors gracefully" do
      {:ok, error_tool} =
        Tool.new(
          name: "error_tool",
          description: "Error test",
          callback: {TestModule, :error_callback}
        )

      {:ok, exception_tool} =
        Tool.new(
          name: "exception_tool",
          description: "Exception test",
          callback: {TestModule, :exception_callback}
        )

      # Error tuple
      assert {:error, "Intentional error"} = Tool.execute(error_tool, %{})

      # Exception
      assert {:error, error_msg} = Tool.execute(exception_tool, %{})
      assert error_msg =~ "Callback execution failed"
    end

    test "validates input type" do
      {:ok, tool} =
        Tool.new(
          name: "type_test",
          description: "Type validation",
          callback: fn _ -> {:ok, "ok"} end
        )

      assert {:error, error} = Tool.execute(tool, "not a map")
      assert Exception.message(error) =~ "Input must be a map"

      assert {:error, error} = Tool.execute(tool, [:not, :a, :map])
      assert Exception.message(error) =~ "Input must be a map"
    end
  end

  describe "to_schema/2" do
    setup do
      {:ok, simple_tool} =
        Tool.new(
          name: "simple_tool",
          description: "Simple description",
          parameter_schema: [],
          callback: fn _ -> {:ok, "ok"} end
        )

      {:ok, complex_tool} =
        Tool.new(
          name: "complex_tool",
          description: "Complex with parameters",
          parameter_schema: [
            location: [type: :string, required: true, doc: "City name"],
            units: [type: :string, default: "celsius", doc: "Temperature units"],
            days: [type: :pos_integer, default: 7]
          ],
          callback: fn _ -> {:ok, "weather"} end
        )

      %{simple_tool: simple_tool, complex_tool: complex_tool}
    end

    test "generates anthropic schema", %{simple_tool: tool} do
      schema = Tool.to_schema(tool, :anthropic)

      assert schema["name"] == "simple_tool"
      assert schema["description"] == "Simple description"
      assert is_map(schema["input_schema"])

      # Anthropic format doesn't have these fields
      refute Map.has_key?(schema, "type")
      refute Map.has_key?(schema, "function")
    end

    test "handles complex parameter schemas", %{complex_tool: tool} do
      schema = Tool.to_schema(tool, :anthropic)
      input_schema = schema["input_schema"]

      assert input_schema["type"] == "object"
      assert is_map(input_schema["properties"])

      # Should have location, units, days properties
      assert Map.has_key?(input_schema["properties"], "location")
      assert Map.has_key?(input_schema["properties"], "units")
      assert Map.has_key?(input_schema["properties"], "days")
    end

    test "handles empty parameter schema", %{simple_tool: tool} do
      schema = Tool.to_schema(tool, :anthropic)
      input_schema = schema["input_schema"]

      assert input_schema["type"] == "object"
      assert input_schema["properties"] == %{}
    end

    test "defaults to openai provider", %{simple_tool: tool} do
      default_schema = Tool.to_schema(tool)
      openai_schema = Tool.to_schema(tool, :openai)

      assert default_schema == openai_schema
    end

    test "raises for unknown provider", %{simple_tool: tool} do
      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Tool.to_schema(tool, :unknown_provider)
      end

      assert_raise ArgumentError, ~r/Unknown provider/, fn ->
        Tool.to_schema(tool, :unknown_provider_2)
      end
    end
  end

  describe "to_json_schema/1 (backward compatibility)" do
    test "defaults to openai format" do
      {:ok, tool} =
        Tool.new(
          name: "compat_tool",
          description: "Backward compatibility",
          parameter_schema: [value: [type: :integer, required: true]],
          callback: fn _ -> {:ok, 42} end
        )

      compat_schema = Tool.to_json_schema(tool)
      openai_schema = Tool.to_schema(tool, :openai)

      assert compat_schema == openai_schema
    end
  end

  describe "valid_name?/1" do
    test "validates tool names" do
      # Valid names
      valid_names = [
        "simple_name",
        "CamelCase",
        "_underscore_start",
        "name_with_123",
        "a",
        "get_weather_info_v2",
        # exactly 64 chars
        String.duplicate("a", 64)
      ]

      for name <- valid_names do
        assert Tool.valid_name?(name), "#{name} should be valid"
      end

      # Invalid names
      invalid_names = [
        "name with spaces",
        "123starts_with_number",
        "kebab-case",
        "special@chars",
        "emoji😊name",
        "",
        # > 64 chars
        String.duplicate("a", 65),
        nil,
        :atom,
        123
      ]

      for name <- invalid_names do
        refute Tool.valid_name?(name), "#{inspect(name)} should be invalid"
      end
    end
  end

  describe "edge cases and error conditions" do
    test "handles deeply nested parameter schemas" do
      {:ok, tool} =
        Tool.new(
          name: "nested_tool",
          description: "Tool with nested params",
          parameter_schema: [
            config: [
              type: :keyword_list,
              keys: [
                database: [
                  type: :keyword_list,
                  keys: [
                    host: [type: :string, required: true],
                    port: [type: :pos_integer, default: 5432]
                  ]
                ],
                cache: [type: :boolean, default: true]
              ]
            ]
          ],
          callback: fn _ -> {:ok, "configured"} end
        )

      schema = Tool.to_schema(tool, :anthropic)
      assert schema["name"] == "nested_tool"
      assert is_map(schema["input_schema"]["properties"]["config"])
    end

    test "handles parameter validation edge cases" do
      {:ok, tool} =
        Tool.new(
          name: "validation_test",
          description: "Validation edge cases",
          parameter_schema: [
            string_field: [type: :string],
            integer_field: [type: :integer],
            boolean_field: [type: :boolean]
          ],
          callback: fn args -> {:ok, args} end
        )

      # Empty map should work (no required fields)
      assert {:ok, _} = Tool.execute(tool, %{})

      # Mixed string/atom keys
      assert {:ok, _} = Tool.execute(tool, %{"string_field" => "value", integer_field: 42})
    end

    test "callback normalization handles all formats consistently" do
      # Test all callback formats produce same result structure
      test_input = %{test: "input"}

      callbacks = [
        fn _args -> {:ok, "function result"} end,
        {TestModule, :simple_callback},
        {TestModule, :multi_arg_callback, ["prefix", "arg"]}
      ]

      for callback <- callbacks do
        {:ok, tool} =
          Tool.new(
            name: "callback_test",
            description: "Test callback format",
            callback: callback
          )

        case Tool.execute(tool, test_input) do
          {:ok, result} ->
            # All callbacks should return some result containing relevant info
            assert is_binary(result)

          {:error, _} = error ->
            flunk("Unexpected error: #{inspect(error)}")
        end
      end
    end
  end
end
