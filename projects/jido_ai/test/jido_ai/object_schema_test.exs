defmodule Jido.AI.ObjectSchemaTest do
  @moduledoc """
  Tests for ObjectSchema module functionality.

  Tests schema creation, validation logic, different output types,
  error handling, and schema transformation functionality.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  import StreamData

  alias Jido.AI.Error.SchemaValidation
  alias Jido.AI.ObjectSchema

  describe "new/1" do
    test "creates object schema with properties" do
      opts = [
        output_type: :object,
        properties: [
          name: [type: :string, required: true],
          age: [type: :pos_integer, default: 0]
        ]
      ]

      {:ok, schema} = ObjectSchema.new(opts)

      assert schema.output_type == :object
      assert schema.properties == opts[:properties]
      assert schema.enum_values == []
      assert schema.schema != nil
    end

    test "creates array schema with properties" do
      opts = [
        output_type: :array,
        properties: [
          id: [type: :string, required: true],
          value: [type: :float]
        ]
      ]

      {:ok, schema} = ObjectSchema.new(opts)

      assert schema.output_type == :array
      assert schema.properties == opts[:properties]
      assert schema.enum_values == []
      assert schema.schema != nil
    end

    test "creates enum schema with values" do
      opts = [
        output_type: :enum,
        enum_values: ["red", "green", "blue"]
      ]

      {:ok, schema} = ObjectSchema.new(opts)

      assert schema.output_type == :enum
      assert schema.properties == []
      assert schema.enum_values == ["red", "green", "blue"]
      # No NimbleOptions schema for enums
      assert schema.schema == nil
    end

    test "creates no_schema type" do
      opts = [output_type: :no_schema]

      {:ok, schema} = ObjectSchema.new(opts)

      assert schema.output_type == :no_schema
      assert schema.properties == []
      assert schema.enum_values == []
      assert schema.schema == nil
    end

    test "defaults to object output_type" do
      opts = [
        properties: [
          name: [type: :string, required: true]
        ]
      ]

      {:ok, schema} = ObjectSchema.new(opts)

      assert schema.output_type == :object
    end

    test "accepts existing ObjectSchema struct" do
      original = %ObjectSchema{
        output_type: :array,
        properties: [name: [type: :string]],
        enum_values: [],
        schema: nil
      }

      {:ok, schema} = ObjectSchema.new(original)

      assert schema == original
    end

    test "returns error for invalid output_type" do
      opts = [output_type: :invalid_type]

      {:error, error} = ObjectSchema.new(opts)

      assert error =~ "Invalid output_type"
      assert error =~ ":invalid_type"
    end

    test "returns error for empty enum_values" do
      opts = [
        output_type: :enum,
        enum_values: []
      ]

      {:error, error} = ObjectSchema.new(opts)

      assert error =~ "enum_values must be a non-empty list"
    end

    test "returns error for invalid properties schema" do
      opts = [
        output_type: :object,
        properties: [
          # Invalid NimbleOptions type
          invalid: [type: :invalid_nimble_type]
        ]
      ]

      {:error, error} = ObjectSchema.new(opts)

      assert error =~ "Invalid properties schema"
    end

    test "returns error for non-keyword list input" do
      {:error, error} = ObjectSchema.new("invalid")

      assert error =~ "Schema options must be a keyword list or ObjectSchema struct"
    end
  end

  describe "new!/1" do
    test "returns schema on success" do
      opts = [
        output_type: :object,
        properties: [name: [type: :string, required: true]]
      ]

      schema = ObjectSchema.new!(opts)

      assert %ObjectSchema{} = schema
      assert schema.output_type == :object
    end

    test "raises on error" do
      opts = [output_type: :invalid_type]

      assert_raise ArgumentError, ~r/Invalid output_type/, fn ->
        ObjectSchema.new!(opts)
      end
    end
  end

  describe "validate/2 - object schemas" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true],
            age: [type: :pos_integer],
            tags: [type: {:list, :string}, default: []]
          ]
        )

      {:ok, schema: schema}
    end

    test "validates valid object data", %{schema: schema} do
      data = %{"name" => "John", "age" => 30, "tags" => ["developer"]}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.name == "John"
      assert validated.age == 30
      assert validated.tags == ["developer"]
    end

    test "validates object with atom keys", %{schema: schema} do
      data = %{name: "John", age: 30}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.name == "John"
      assert validated.age == 30
    end

    test "applies default values", %{schema: schema} do
      data = %{"name" => "John"}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.name == "John"
      # Default value applied
      assert validated.tags == []
    end

    test "returns error for missing required field", %{schema: schema} do
      # Missing required 'name'
      data = %{"age" => 30}

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors != nil
    end

    test "returns error for invalid field type", %{schema: schema} do
      # age should be integer
      data = %{"name" => "John", "age" => "thirty"}

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors != nil
    end

    test "returns error for non-map data", %{schema: schema} do
      data = "not a map"

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors == ["Expected object (map), got: \"not a map\""]
    end

    test "validates object with no properties schema" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: []
        )

      data = %{"any" => "value", "works" => true}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated == data
    end
  end

  describe "validate/2 - array schemas" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: [
            name: [type: :string, required: true],
            score: [type: :integer, required: true]
          ]
        )

      {:ok, schema: schema}
    end

    test "validates valid array data", %{schema: schema} do
      data = [
        %{"name" => "Alice", "score" => 95},
        %{"name" => "Bob", "score" => 87}
      ]

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert length(validated) == 2
      assert hd(validated).name == "Alice"
      assert hd(validated).score == 95
      assert Enum.at(validated, 1).name == "Bob"
      assert Enum.at(validated, 1).score == 87
    end

    test "validates empty array", %{schema: schema} do
      data = []

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated == []
    end

    test "returns error for invalid array item", %{schema: schema} do
      data = [
        %{"name" => "Alice", "score" => 95},
        # Missing required 'score'
        %{"name" => "Bob"}
      ]

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors != nil
      assert Enum.any?(error.validation_errors, &String.contains?(&1, "Item 2"))
    end

    test "returns error for non-map array item", %{schema: schema} do
      data = [
        %{"name" => "Alice", "score" => 95},
        "not a map"
      ]

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors != nil
      assert Enum.any?(error.validation_errors, &String.contains?(&1, "Expected map"))
    end

    test "returns error for non-array data", %{schema: schema} do
      # Object instead of array
      data = %{"name" => "Alice", "score" => 95}

      {:error, error} = ObjectSchema.validate(schema, data)

      assert %SchemaValidation{} = error
      assert error.validation_errors == ["Expected array, got: #{inspect(data)}"]
    end

    test "validates array with no properties schema" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: []
        )

      data = [1, 2, 3, "any", %{"mixed" => "types"}]

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated == data
    end
  end

  describe "validate/2 - enum schemas" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: ["red", "green", "blue", "yellow"]
        )

      {:ok, schema: schema}
    end

    test "validates valid enum value", %{schema: schema} do
      {:ok, validated} = ObjectSchema.validate(schema, "blue")

      assert validated == "blue"
    end

    test "returns error for invalid enum value", %{schema: schema} do
      {:error, error} = ObjectSchema.validate(schema, "purple")

      assert %SchemaValidation{} = error
      assert error.validation_errors == [~s(Value "purple" is not one of: ["red", "green", "blue", "yellow"])]
    end

    test "returns error for non-string enum value", %{schema: schema} do
      {:error, error} = ObjectSchema.validate(schema, 123)

      assert %SchemaValidation{} = error
      assert Enum.any?(error.validation_errors, &String.contains?(&1, "123"))
    end
  end

  describe "validate/2 - no_schema type" do
    setup do
      {:ok, schema} = ObjectSchema.new(output_type: :no_schema)
      {:ok, schema: schema}
    end

    test "accepts any data type", %{schema: schema} do
      test_cases = [
        "string",
        123,
        %{"object" => "value"},
        [1, 2, 3],
        true,
        nil
      ]

      for data <- test_cases do
        {:ok, validated} = ObjectSchema.validate(schema, data)
        assert validated == data
      end
    end
  end

  describe "validate!/2" do
    test "returns validated data on success" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [name: [type: :string, required: true]]
        )

      data = %{"name" => "John"}

      validated = ObjectSchema.validate!(schema, data)

      assert validated.name == "John"
    end

    test "raises SchemaValidation error on failure" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [name: [type: :string, required: true]]
        )

      # Missing required field
      data = %{}

      assert_raise SchemaValidation, fn ->
        ObjectSchema.validate!(schema, data)
      end
    end
  end

  describe "output_type/1" do
    test "extracts output_type from ObjectSchema struct" do
      schema = %ObjectSchema{output_type: :array}

      assert ObjectSchema.output_type(schema) == :array
    end

    test "extracts output_type from keyword list" do
      opts = [output_type: :enum]

      assert ObjectSchema.output_type(opts) == :enum
    end

    test "returns default :object for empty options" do
      assert ObjectSchema.output_type([]) == :object
    end

    test "returns default :object when output_type not specified" do
      opts = [properties: [name: [type: :string]]]

      assert ObjectSchema.output_type(opts) == :object
    end
  end

  describe "key normalization" do
    test "normalizes string keys to atoms for validation" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            user_name: [type: :string, required: true],
            user_age: [type: :pos_integer]
          ]
        )

      # Input with string keys
      data = %{"user_name" => "John", "user_age" => 30}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      # Output should use atom keys
      assert validated.user_name == "John"
      assert validated.user_age == 30
    end

    test "handles mixed string and atom keys" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true],
            age: [type: :pos_integer]
          ]
        )

      # Mixed keys
      data = %{"name" => "John", :age => 30}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.name == "John"
      assert validated.age == 30
    end

    test "creates new atoms safely" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            new_field: [type: :string, required: true]
          ]
        )

      data = %{"new_field" => "value"}

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.new_field == "value"
    end
  end

  describe "complex schema scenarios" do
    test "nested map validation" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            user: [
              type: :any,
              required: true
            ]
          ]
        )

      data = %{
        "user" => %{
          "name" => "John",
          "contact" => %{
            "email" => "john@example.com",
            "phone" => "123-456-7890"
          }
        }
      }

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.user["name"] == "John"
      assert validated.user["contact"]["email"] == "john@example.com"
      assert validated.user["contact"]["phone"] == "123-456-7890"
    end

    test "list validation with specific types" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            tags: [type: {:list, :string}, required: true],
            scores: [type: {:list, :pos_integer}, default: []]
          ]
        )

      data = %{
        "tags" => ["elixir", "ai", "testing"],
        "scores" => [95, 87, 92]
      }

      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.tags == ["elixir", "ai", "testing"]
      assert validated.scores == [95, 87, 92]
    end
  end

  describe "property-based testing" do
    property "validates any enum value from provided list" do
      check all(
              enum_values <- list_of(string(:alphanumeric), min_length: 1, max_length: 10),
              enum_values = Enum.uniq(enum_values),
              chosen_value <- member_of(enum_values)
            ) do
        {:ok, schema} =
          ObjectSchema.new(
            output_type: :enum,
            enum_values: enum_values
          )

        {:ok, validated} = ObjectSchema.validate(schema, chosen_value)
        assert validated == chosen_value
      end
    end

    property "rejects enum values not in the provided list" do
      check all(
              enum_values <- list_of(string(:alphanumeric), min_length: 1, max_length: 5),
              enum_values = Enum.uniq(enum_values),
              invalid_value <- string(:alphanumeric, min_length: 1),
              invalid_value not in enum_values
            ) do
        {:ok, schema} =
          ObjectSchema.new(
            output_type: :enum,
            enum_values: enum_values
          )

        {:error, error} = ObjectSchema.validate(schema, invalid_value)
        assert %SchemaValidation{} = error
      end
    end

    property "no_schema accepts any data" do
      check all(
              data <-
                one_of([
                  string(:alphanumeric),
                  integer(),
                  boolean(),
                  list_of(integer()),
                  map_of(string(:alphanumeric), integer())
                ])
            ) do
        {:ok, schema} = ObjectSchema.new(output_type: :no_schema)

        {:ok, validated} = ObjectSchema.validate(schema, data)
        assert validated == data
      end
    end

    property "array validation works with various list sizes" do
      check all(
              list_size <- integer(0..10),
              names <- list_of(string(:alphanumeric, min_length: 1), length: list_size),
              ages <- list_of(positive_integer(), length: list_size)
            ) do
        {:ok, schema} =
          ObjectSchema.new(
            output_type: :array,
            properties: [
              name: [type: :string, required: true],
              age: [type: :pos_integer, required: true]
            ]
          )

        data =
          Enum.zip_with(names, ages, fn name, age ->
            %{"name" => name, "age" => age}
          end)

        {:ok, validated} = ObjectSchema.validate(schema, data)
        assert length(validated) == list_size

        Enum.zip(validated, Enum.zip(names, ages))
        |> Enum.each(fn {item, {expected_name, expected_age}} ->
          assert item.name == expected_name
          assert item.age == expected_age
        end)
      end
    end
  end

  describe "error message formatting" do
    test "formats validation errors clearly for objects" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true],
            age: [type: :pos_integer, required: true]
          ]
        )

      {:error, error} = ObjectSchema.validate(schema, %{})

      assert %SchemaValidation{} = error
      assert is_list(error.validation_errors)
      refute Enum.empty?(error.validation_errors)

      error_message = SchemaValidation.message(error)
      assert error_message =~ "Schema validation failed"
    end

    test "formats validation errors clearly for arrays" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: [
            name: [type: :string, required: true]
          ]
        )

      {:error, error} = ObjectSchema.validate(schema, [%{}, %{"name" => 123}])

      assert %SchemaValidation{} = error
      assert is_list(error.validation_errors)

      error_message = SchemaValidation.message(error)
      assert error_message =~ "Schema validation failed"
    end

    test "formats validation errors clearly for enums" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: ["a", "b", "c"]
        )

      {:error, error} = ObjectSchema.validate(schema, "invalid")

      assert %SchemaValidation{} = error
      assert error.validation_errors == [~s(Value "invalid" is not one of: ["a", "b", "c"])]

      error_message = SchemaValidation.message(error)
      assert error_message =~ "Schema validation failed"
      assert error_message =~ "Value \"invalid\" is not one of"
    end
  end
end
