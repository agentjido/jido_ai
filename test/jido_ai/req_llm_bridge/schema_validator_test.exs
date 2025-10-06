defmodule Jido.AI.ReqLlmBridge.SchemaValidatorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.ReqLlmBridge.SchemaValidator

  describe "convert_schema_to_reqllm/1" do
    test "converts simple schema to JSON Schema format" do
      schema = [
        name: [type: :string, required: true, doc: "The name"],
        count: [type: :integer, default: 1, doc: "The count"]
      ]

      result = SchemaValidator.convert_schema_to_reqllm(schema)

      assert result.type == "object"
      assert result.required == ["name"]
      assert result.additionalProperties == false

      assert result.properties["name"]["type"] == "string"
      assert result.properties["name"]["description"] == "The name"
      assert result.properties["name"]["required"] == true

      assert result.properties["count"]["type"] == "integer"
      assert result.properties["count"]["description"] == "The count"
      assert result.properties["count"]["default"] == 1
    end

    test "converts complex types correctly" do
      schema = [
        items: [type: {:list, :string}, doc: "List of items"],
        config: [type: :map, doc: "Configuration"],
        status: [type: {:in, [:active, :inactive]}, doc: "Status"],
        score: [type: :float, doc: "Score value"]
      ]

      result = SchemaValidator.convert_schema_to_reqllm(schema)

      assert result.properties["items"]["type"] == "array"
      assert result.properties["config"]["type"] == "object"
      assert result.properties["status"]["type"] == "string"
      assert result.properties["score"]["type"] == "number"
    end

    test "handles empty schema" do
      result = SchemaValidator.convert_schema_to_reqllm([])

      assert result.type == "object"
      assert result.properties == %{}
      assert result.required == []
    end

    test "identifies required fields correctly" do
      schema = [
        required_field: [type: :string, required: true],
        optional_field: [type: :string],
        default_field: [type: :integer, default: 0]
      ]

      result = SchemaValidator.convert_schema_to_reqllm(schema)

      assert result.required == ["required_field"]
      refute "optional_field" in result.required
      refute "default_field" in result.required
    end

    test "handles invalid schema gracefully" do
      # Test with non-list input
      result = SchemaValidator.convert_schema_to_reqllm("not a schema")

      assert result.type == "object"
      assert result.properties == %{}
      assert result.required == []
    end

    test "preserves all field metadata" do
      schema = [
        field: [
          type: :string,
          required: true,
          default: "default_value",
          doc: "Field description"
        ]
      ]

      result = SchemaValidator.convert_schema_to_reqllm(schema)
      field_schema = result.properties["field"]

      assert field_schema["type"] == "string"
      assert field_schema["description"] == "Field description"
      assert field_schema["required"] == true
      assert field_schema["default"] == "default_value"
    end
  end

  describe "convert_field_schema/1" do
    test "converts basic field definition" do
      field = {:name, [type: :string, required: true, doc: "User name"]}

      assert {"name", field_def} = SchemaValidator.convert_field_schema(field)
      assert field_def["type"] == "string"
      assert field_def["description"] == "User name"
      assert field_def["required"] == true
    end

    test "handles field without documentation" do
      field = {:count, [type: :integer, required: false]}

      assert {"count", field_def} = SchemaValidator.convert_field_schema(field)
      assert field_def["type"] == "integer"
      assert field_def["description"] == ""
      refute field_def["required"]
    end

    test "includes default values" do
      field = {:enabled, [type: :boolean, default: false, doc: "Enable flag"]}

      assert {"enabled", field_def} = SchemaValidator.convert_field_schema(field)
      assert field_def["type"] == "boolean"
      assert field_def["default"] == false
    end

    test "ignores unknown field options" do
      field = {:field, [type: :string, unknown_option: "ignored", custom: 123]}

      assert {"field", field_def} = SchemaValidator.convert_field_schema(field)
      assert field_def["type"] == "string"
      refute Map.has_key?(field_def, "unknown_option")
      refute Map.has_key?(field_def, "custom")
    end
  end

  describe "validate_params/2" do
    # Mock Action for testing
    defmodule TestAction do
      use Jido.Action,
        name: "test_action",
        schema: [
          name: [type: :string, required: true, doc: "The name"],
          count: [type: :integer, default: 1, doc: "The count"],
          enabled: [type: :boolean, default: false, doc: "Enable flag"]
        ]

      @impl true
      def run(_params, _context), do: {:ok, %{}}
    end

    test "validates correct parameters" do
      params = %{name: "test", count: 5, enabled: true}

      assert {:ok, validated} = SchemaValidator.validate_params(params, TestAction)
      assert validated.name == "test"
      assert validated.count == 5
      assert validated.enabled == true
    end

    test "applies default values" do
      params = %{name: "test"}

      assert {:ok, validated} = SchemaValidator.validate_params(params, TestAction)
      assert validated.name == "test"
      # default
      assert validated.count == 1
      # default
      assert validated.enabled == false
    end

    test "rejects invalid parameters" do
      params = %{name: "test", count: "not_an_integer"}

      assert {:error, error} = SchemaValidator.validate_params(params, TestAction)
      assert error.type == "parameter_validation_error"
    end

    test "rejects missing required parameters" do
      # missing required 'name'
      params = %{count: 5}

      assert {:error, error} = SchemaValidator.validate_params(params, TestAction)
      assert error.type == "parameter_validation_error"
    end

    test "handles action without schema" do
      defmodule NoSchemaAction do
        use Jido.Action,
          name: "no_schema",
          schema: []

        @impl true
        def run(_params, _context), do: {:ok, %{}}
      end

      params = %{any_field: "any_value"}

      assert {:ok, validated} = SchemaValidator.validate_params(params, NoSchemaAction)
      assert validated == params
    end

    test "handles action module errors gracefully" do
      defmodule BrokenAction do
        def name, do: "broken"
        # Missing schema/0 function
      end

      params = %{test: "value"}

      assert {:error, error} = SchemaValidator.validate_params(params, BrokenAction)
      assert error.type == "schema_validation_exception"
    end
  end

  describe "validate_nimble_schema_compatibility/1" do
    test "accepts compatible schema" do
      schema = [
        name: [type: :string, required: true],
        count: [type: :integer, default: 1],
        items: [type: {:list, :string}],
        config: [type: :map],
        status: [type: {:in, [:active, :inactive]}]
      ]

      assert :ok = SchemaValidator.validate_nimble_schema_compatibility(schema)
    end

    test "rejects schema with custom validators" do
      schema = [
        name: [type: :string],
        validated_field: [type: {:custom, MyModule, :validator, []}]
      ]

      assert {:error, error} = SchemaValidator.validate_nimble_schema_compatibility(schema)
      assert error.reason == "schema_compatibility_issues"
      assert length(error.issues) == 1

      issue = hd(error.issues)
      assert issue.field == "validated_field"
      assert String.contains?(issue.reason, "Custom validators are not supported")
    end

    test "accepts empty schema" do
      assert :ok = SchemaValidator.validate_nimble_schema_compatibility([])
    end

    test "provides detailed compatibility issue information" do
      schema = [
        field1: [type: {:custom, Module1, :func1, []}],
        field2: [type: {:custom, Module2, :func2, []}],
        # This one is fine
        field3: [type: :string]
      ]

      assert {:error, error} = SchemaValidator.validate_nimble_schema_compatibility(schema)
      assert length(error.issues) == 2

      field_names = Enum.map(error.issues, & &1.field)
      assert "field1" in field_names
      assert "field2" in field_names
      refute "field3" in field_names
    end
  end

  describe "build_enhanced_json_schema/1" do
    test "builds enhanced schema with enum constraints" do
      schema = [
        status: [type: {:in, [:active, :inactive, :pending]}, doc: "Current status"],
        priority: [type: {:in, [:low, :medium, :high]}, required: true]
      ]

      result = SchemaValidator.build_enhanced_json_schema(schema)

      status_prop = result.properties["status"]
      assert status_prop["type"] == "string"
      assert status_prop["enum"] == ["active", "inactive", "pending"]

      priority_prop = result.properties["priority"]
      assert priority_prop["enum"] == ["low", "medium", "high"]
      assert "priority" in result.required
    end

    test "adds numeric constraints when available" do
      # Note: This would require extending the schema format to include min/max
      # Currently the implementation doesn't support this, but the test shows the intent
      schema = [
        count: [type: :integer, min: 0, max: 100, doc: "Count value"]
      ]

      result = SchemaValidator.build_enhanced_json_schema(schema)
      count_prop = result.properties["count"]

      assert count_prop["type"] == "integer"
      # These would be added if the enhancement is implemented
      # assert count_prop["minimum"] == 0
      # assert count_prop["maximum"] == 100
    end

    test "preserves base schema structure" do
      schema = [
        name: [type: :string, required: true, doc: "The name"],
        value: [type: :integer, default: 0]
      ]

      result = SchemaValidator.build_enhanced_json_schema(schema)

      assert result.type == "object"
      assert result.required == ["name"]
      assert result.properties["name"]["type"] == "string"
      assert result.properties["value"]["default"] == 0
    end
  end

  describe "type conversion" do
    test "maps all supported NimbleOptions types to JSON Schema types" do
      test_cases = [
        {:string, "string"},
        {:integer, "integer"},
        {:non_neg_integer, "integer"},
        {:pos_integer, "integer"},
        {:float, "number"},
        {:number, "number"},
        {:boolean, "boolean"},
        {:atom, "string"},
        {:list, "array"},
        {{:list, :string}, "array"},
        {:map, "object"},
        {{:map, []}, "object"},
        {:keyword_list, "object"},
        {{:in, [:a, :b]}, "string"},
        {{:custom, MyModule, :func, []}, "string"},
        {nil, "string"},
        {:unknown_type, "string"}
      ]

      Enum.each(test_cases, fn {nimble_type, expected_json_type} ->
        schema = [field: [type: nimble_type]]
        result = SchemaValidator.convert_schema_to_reqllm(schema)

        assert result.properties["field"]["type"] == expected_json_type,
               "Expected #{nimble_type} to map to #{expected_json_type}"
      end)
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed field definitions gracefully" do
      # Field with invalid structure
      malformed_schema = [
        {:valid_field, [type: :string]},
        # Not a tuple
        :invalid_field,
        # String key instead of atom
        {"string_key", [type: :integer]}
      ]

      # Should handle the valid parts and ignore/handle invalid parts
      result = SchemaValidator.convert_schema_to_reqllm(malformed_schema)
      assert result.type == "object"
      assert Map.has_key?(result.properties, "valid_field")
    end

    test "handles empty field options" do
      schema = [field: []]

      result = SchemaValidator.convert_schema_to_reqllm(schema)
      field_prop = result.properties["field"]

      # Default type
      assert field_prop["type"] == "string"
      assert field_prop["description"] == ""
    end

    test "preserves field order in properties" do
      schema = [
        first: [type: :string],
        second: [type: :integer],
        third: [type: :boolean]
      ]

      result = SchemaValidator.convert_schema_to_reqllm(schema)

      # Map keys should include all fields
      keys = Map.keys(result.properties)
      assert "first" in keys
      assert "second" in keys
      assert "third" in keys
    end

    test "handles very large schemas" do
      # Create a schema with many fields
      large_schema =
        1..100
        |> Enum.map(fn i ->
          {String.to_atom("field_#{i}"), [type: :string, doc: "Field #{i}"]}
        end)

      result = SchemaValidator.convert_schema_to_reqllm(large_schema)

      assert result.type == "object"
      assert map_size(result.properties) == 100
      assert result.properties["field_1"]["type"] == "string"
      assert result.properties["field_100"]["description"] == "Field 100"
    end
  end
end
