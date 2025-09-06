defmodule ReqAI.ObjectSchemaTest do
  use ExUnit.Case, async: true
  doctest ReqAI.ObjectSchema

  import ReqAI.Test.{Factory, Macros}

  alias ReqAI.ObjectSchema

  describe "constructors" do
    test "creates object schema" do
      opts = [output_type: :object, properties: [name: [type: :string, required: true]]]
      assert_ok(ObjectSchema.new(opts))
      {:ok, schema} = ObjectSchema.new(opts)
      assert schema.output_type == :object
    end

    test "creates array schema" do
      opts = [output_type: :array, properties: [id: [type: :string, required: true]]]
      assert_ok(ObjectSchema.new(opts))
      {:ok, schema} = ObjectSchema.new(opts)
      assert schema.output_type == :array
    end

    test "creates enum schema" do
      opts = [output_type: :enum, enum_values: ["red", "green", "blue"]]
      assert_ok(ObjectSchema.new(opts))
      {:ok, schema} = ObjectSchema.new(opts)
      assert schema.output_type == :enum
    end

    test "creates no_schema type" do
      opts = [output_type: :no_schema]
      assert_ok(ObjectSchema.new(opts))
      {:ok, schema} = ObjectSchema.new(opts)
      assert schema.output_type == :no_schema
    end
  end

  describe "validation" do
    test "object validation with valid and invalid data" do
      schema = simple_schema()
      valid_data = simple_data()

      assert_ok(ObjectSchema.validate(schema, valid_data))
      {:ok, validated} = ObjectSchema.validate(schema, valid_data)
      assert validated.name == "John Doe"

      assert_error(ObjectSchema.validate(schema, %{"age" => 30}))
      assert_error(ObjectSchema.validate(schema, %{"name" => "John", "age" => "thirty"}))
    end

    test "array validation with valid and invalid data" do
      schema = array_schema()
      valid_data = [%{"name" => "Alice", "value" => 1}, %{"name" => "Bob", "value" => 2}]

      assert_ok(ObjectSchema.validate(schema, valid_data))
      {:ok, validated} = ObjectSchema.validate(schema, valid_data)
      assert length(validated) == 2

      assert_error(ObjectSchema.validate(schema, [%{"name" => "Alice"}, %{}]))
      assert_error(ObjectSchema.validate(schema, "not an array"))
    end

    test "enum validation" do
      schema = enum_schema(["small", "medium", "large"])

      assert_ok(ObjectSchema.validate(schema, "medium"), "medium")
      assert_error(ObjectSchema.validate(schema, "extra-large"))
    end

    test "nested object validation" do
      properties = [
        name: [type: :string, required: true],
        address: [
          type: :map,
          keys: [
            street: [type: :string, required: true, doc: "Street address"],
            city: [type: :string, required: true, doc: "City name"]
          ]
        ]
      ]

      {:ok, schema} = ObjectSchema.new(output_type: :object, properties: properties)

      valid_data = %{
        name: "John Doe",
        address: %{street: "123 Main St", city: "Anytown"}
      }

      assert_ok(ObjectSchema.validate(schema, valid_data), valid_data)
      assert schema.properties[:address][:keys][:street][:doc] == "Street address"
    end
  end

  describe "serialization" do
    test "converts to JSON schema format" do
      schema =
        simple_schema(
          properties: [
            name: [type: :string, required: true, doc: "Full name"],
            age: [type: :integer]
          ]
        )

      json_schema = ObjectSchema.to_json_schema(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["name"]["description"] == "Full name"
      assert json_schema["required"] == ["name"]
    end
  end
end
