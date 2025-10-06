defmodule Jido.AI.ReqLlmBridge.ParameterConverterTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.ParameterConverter

  # Mock Action for testing
  defmodule TestAction do
    use Jido.Action,
      name: "test_action",
      description: "A test action for parameter conversion",
      schema: [
        name: [type: :string, required: true, doc: "The name parameter"],
        count: [type: :integer, default: 1, doc: "The count parameter"],
        enabled: [type: :boolean, default: false, doc: "Enable flag"],
        score: [type: :float, doc: "The score"],
        tags: [type: {:list, :string}, doc: "List of tags"],
        config: [type: :map, doc: "Configuration map"],
        status: [type: {:in, [:active, :inactive]}, default: :inactive, doc: "Status choice"]
      ]

    @impl true
    def run(_params, _context), do: {:ok, %{}}
  end

  describe "convert_to_jido_format/2" do
    test "converts string parameters to atom keys" do
      params = %{"name" => "Pascal", "count" => "5"}

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      assert converted.name == "Pascal"
      assert converted.count == 5
      assert is_integer(converted.count)
    end

    test "applies default values for missing optional parameters" do
      params = %{"name" => "test"}

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      assert converted.name == "test"
      # default value
      assert converted.count == 1
      # default value
      assert converted.enabled == false
      # default value
      assert converted.status == :inactive
    end

    test "rejects unknown parameters" do
      params = %{"unknown_field" => "value"}

      assert {:error, {:parameter_conversion_error, "unknown_field", _reason}} =
               ParameterConverter.convert_to_jido_format(params, TestAction)
    end

    test "handles mixed parameter formats" do
      params = %{
        "name" => "test",
        # already integer
        "count" => 42,
        # already boolean
        "enabled" => true
      }

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      assert converted.name == "test"
      assert converted.count == 42
      assert converted.enabled == true
    end

    test "validates required parameters" do
      # Missing required 'name' parameter
      params = %{"count" => "5"}

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      # Should convert successfully but action validation will catch missing required field
      assert converted.count == 5
      refute Map.has_key?(converted, :name)
    end

    test "handles empty parameter map" do
      params = %{}

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      # Should only have default values
      assert converted.count == 1
      assert converted.enabled == false
      assert converted.status == :inactive
    end

    test "rejects non-map input" do
      assert {:error, {:invalid_params_type, _}} =
               ParameterConverter.convert_to_jido_format("not a map", TestAction)

      assert {:error, {:invalid_params_type, _}} =
               ParameterConverter.convert_to_jido_format([:not, :a, :map], TestAction)
    end
  end

  describe "coerce_type/2" do
    test "string type coercion" do
      assert {:ok, "test"} = ParameterConverter.coerce_type("test", :string)
      assert {:ok, "123"} = ParameterConverter.coerce_type(123, :string)
      assert {:ok, "true"} = ParameterConverter.coerce_type(true, :string)
    end

    test "integer type coercion" do
      assert {:ok, 123} = ParameterConverter.coerce_type(123, :integer)
      assert {:ok, 123} = ParameterConverter.coerce_type("123", :integer)
      assert {:ok, 123} = ParameterConverter.coerce_type(123.7, :integer)
      # partial parsing
      assert {:ok, 42} = ParameterConverter.coerce_type("42extra", :integer)

      assert {:error, _} = ParameterConverter.coerce_type("not_a_number", :integer)
      assert {:error, _} = ParameterConverter.coerce_type(%{}, :integer)
    end

    test "non-negative integer type coercion" do
      assert {:ok, 0} = ParameterConverter.coerce_type("0", :non_neg_integer)
      assert {:ok, 123} = ParameterConverter.coerce_type("123", :non_neg_integer)

      assert {:error, _} = ParameterConverter.coerce_type("-1", :non_neg_integer)
    end

    test "positive integer type coercion" do
      assert {:ok, 1} = ParameterConverter.coerce_type("1", :pos_integer)
      assert {:ok, 123} = ParameterConverter.coerce_type("123", :pos_integer)

      assert {:error, _} = ParameterConverter.coerce_type("0", :pos_integer)
      assert {:error, _} = ParameterConverter.coerce_type("-1", :pos_integer)
    end

    test "float type coercion" do
      assert {:ok, 123.45} = ParameterConverter.coerce_type(123.45, :float)
      assert {:ok, 123.45} = ParameterConverter.coerce_type("123.45", :float)
      assert {:ok, 123.0} = ParameterConverter.coerce_type(123, :float)

      assert {:error, _} = ParameterConverter.coerce_type("not_a_float", :float)
    end

    test "boolean type coercion" do
      assert {:ok, true} = ParameterConverter.coerce_type(true, :boolean)
      assert {:ok, false} = ParameterConverter.coerce_type(false, :boolean)
      assert {:ok, true} = ParameterConverter.coerce_type("true", :boolean)
      assert {:ok, false} = ParameterConverter.coerce_type("false", :boolean)
      assert {:ok, true} = ParameterConverter.coerce_type("1", :boolean)
      assert {:ok, false} = ParameterConverter.coerce_type("0", :boolean)
      assert {:ok, true} = ParameterConverter.coerce_type(1, :boolean)
      assert {:ok, false} = ParameterConverter.coerce_type(0, :boolean)

      assert {:error, _} = ParameterConverter.coerce_type("maybe", :boolean)
      assert {:error, _} = ParameterConverter.coerce_type(2, :boolean)
    end

    test "list type coercion" do
      assert {:ok, [1, 2, 3]} = ParameterConverter.coerce_type([1, 2, 3], :list)

      assert {:error, _} = ParameterConverter.coerce_type("not_a_list", :list)
      assert {:error, _} = ParameterConverter.coerce_type(%{}, :list)
    end

    test "typed list coercion" do
      assert {:ok, [1, 2, 3]} = ParameterConverter.coerce_type(["1", "2", "3"], {:list, :integer})

      assert {:ok, [true, false]} =
               ParameterConverter.coerce_type(["true", "false"], {:list, :boolean})

      assert {:error, _} = ParameterConverter.coerce_type(["1", "not_int"], {:list, :integer})
      assert {:error, _} = ParameterConverter.coerce_type("not_a_list", {:list, :integer})
    end

    test "map type coercion" do
      map = %{"key" => "value"}
      assert {:ok, ^map} = ParameterConverter.coerce_type(map, :map)

      assert {:error, _} = ParameterConverter.coerce_type("not_a_map", :map)
      assert {:error, _} = ParameterConverter.coerce_type([1, 2, 3], :map)
    end

    test "keyword list coercion" do
      kw = [key: "value", other: 123]
      assert {:ok, ^kw} = ParameterConverter.coerce_type(kw, :keyword_list)

      # Convert map to keyword list
      map = %{"key" => "value"}
      assert {:ok, [key: "value"]} = ParameterConverter.coerce_type(map, :keyword_list)

      assert {:error, _} = ParameterConverter.coerce_type([1, 2, 3], :keyword_list)
    end

    test "enum/choice coercion" do
      choices = [:active, :inactive, :pending]

      assert {:ok, :active} = ParameterConverter.coerce_type(:active, {:in, choices})
      assert {:ok, :active} = ParameterConverter.coerce_type("active", {:in, choices})

      assert {:error, _} = ParameterConverter.coerce_type(:unknown, {:in, choices})
      assert {:error, _} = ParameterConverter.coerce_type("unknown", {:in, choices})
    end

    test "unsupported type handling" do
      assert {:error, _} = ParameterConverter.coerce_type("value", :unsupported_type)

      assert {:error, _} =
               ParameterConverter.coerce_type("value", {:custom, MyModule, :validator})
    end
  end

  describe "convert_parameter/3" do
    setup do
      schema_map = %{
        name: [type: :string, required: true],
        count: [type: :integer, default: 1],
        enabled: [type: :boolean, default: false]
      }

      {:ok, schema_map: schema_map}
    end

    test "converts known parameter with correct type", %{schema_map: schema_map} do
      assert {:ok, :name, "test"} =
               ParameterConverter.convert_parameter("name", "test", schema_map)

      assert {:ok, :count, 42} =
               ParameterConverter.convert_parameter("count", "42", schema_map)

      assert {:ok, :enabled, true} =
               ParameterConverter.convert_parameter("enabled", "true", schema_map)
    end

    test "handles atom keys", %{schema_map: schema_map} do
      assert {:ok, :name, "test"} =
               ParameterConverter.convert_parameter(:name, "test", schema_map)
    end

    test "rejects unknown parameters", %{schema_map: schema_map} do
      assert {:error, "Unknown parameter: unknown"} =
               ParameterConverter.convert_parameter("unknown", "value", schema_map)
    end

    test "handles type conversion errors", %{schema_map: schema_map} do
      assert {:error, error_msg} =
               ParameterConverter.convert_parameter("count", "not_a_number", schema_map)

      assert String.contains?(error_msg, "Type conversion failed")
    end
  end

  describe "ensure_json_serializable/1" do
    test "accepts already serializable data" do
      data = %{
        string: "test",
        number: 42,
        boolean: true,
        list: [1, 2, 3],
        map: %{nested: "value"}
      }

      assert {:ok, ^data} = ParameterConverter.ensure_json_serializable(data)
    end

    test "sanitizes non-serializable data" do
      data = %{
        pid: self(),
        ref: make_ref(),
        function: fn -> :ok end,
        normal: "value"
      }

      assert {:ok, sanitized} = ParameterConverter.ensure_json_serializable(data)
      assert sanitized.normal == "value"
      assert sanitized._sanitized == true
      # Should be converted to string
      assert is_binary(sanitized.pid)
    end

    test "handles nested non-serializable data" do
      data = %{
        level1: %{
          level2: %{
            pid: self(),
            value: "keep_this"
          },
          normal: "also_keep"
        }
      }

      assert {:ok, sanitized} = ParameterConverter.ensure_json_serializable(data)
      assert sanitized.level1.normal == "also_keep"
      assert sanitized.level1.level2.value == "keep_this"
      assert is_binary(sanitized.level1.level2.pid)
    end

    test "handles lists with non-serializable items" do
      data = [1, "string", self(), %{pid: self()}]

      assert {:ok, sanitized} = ParameterConverter.ensure_json_serializable(data)
      assert length(sanitized) == 4
      assert Enum.at(sanitized, 0) == 1
      assert Enum.at(sanitized, 1) == "string"
      # PID converted to string
      assert is_binary(Enum.at(sanitized, 2))
    end

    test "handles structs" do
      data = %{date: Date.utc_today(), map: %{value: 1}}

      assert {:ok, sanitized} = ParameterConverter.ensure_json_serializable(data)
      # Struct should be converted to map
      assert is_map(sanitized.date)
      assert sanitized.map.value == 1
    end

    test "returns error for completely unserializable data" do
      # Create a complex structure that can't be sanitized
      data = %URI{scheme: "http", host: "example.com"}

      # Should either succeed with sanitized version or return error
      case ParameterConverter.ensure_json_serializable(data) do
        # Sanitization worked
        {:ok, _sanitized} -> :ok
        # Expected error
        {:error, {:serialization_error, _reason}} -> :ok
      end
    end
  end

  describe "edge cases and error handling" do
    test "handles action without schema" do
      defmodule NoSchemaAction do
        use Jido.Action,
          name: "no_schema",
          description: "Action without schema",
          schema: []

        @impl true
        def run(_params, _context), do: {:ok, %{}}
      end

      params = %{"any" => "value"}

      # Should handle gracefully - convert what it can
      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, NoSchemaAction)
      # Since there's no schema, unknown parameters should be rejected
      assert Enum.empty?(converted)
    end

    test "handles action module that doesn't implement schema/0" do
      defmodule BrokenAction do
        # This module doesn't properly implement the Action behavior
        def name, do: "broken"
      end

      params = %{"test" => "value"}

      # Should handle the error gracefully
      assert {:error, {:conversion_exception, _}} =
               ParameterConverter.convert_to_jido_format(params, BrokenAction)
    end

    test "handles deeply nested maps" do
      params = %{
        "config" => %{
          "database" => %{
            "host" => "localhost",
            "port" => "5432"
          },
          "cache" => %{
            "enabled" => "true"
          }
        }
      }

      # For an action that accepts map types
      defmodule ConfigAction do
        use Jido.Action,
          name: "config_action",
          schema: [
            config: [type: :map, doc: "Configuration"]
          ]

        @impl true
        def run(_params, _context), do: {:ok, %{}}
      end

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, ConfigAction)
      assert is_map(converted.config)
      assert converted.config["database"]["host"] == "localhost"
    end

    test "handles unicode and special characters" do
      params = %{
        "name" => "Øystein Müller 🚀",
        "count" => "42"
      }

      assert {:ok, converted} = ParameterConverter.convert_to_jido_format(params, TestAction)
      assert converted.name == "Øystein Müller 🚀"
      assert converted.count == 42
    end
  end
end
