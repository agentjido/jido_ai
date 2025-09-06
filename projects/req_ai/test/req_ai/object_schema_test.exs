defmodule ReqAI.ObjectSchemaTest do
  use ExUnit.Case, async: true
  doctest ReqAI.ObjectSchema

  alias ReqAI.ObjectSchema
  alias ReqAI.Error.SchemaValidation

  describe "constructor tests" do
    test "creates object schema" do
      opts = [output_type: :object, properties: [name: [type: :string, required: true]]]
      assert {:ok, %ObjectSchema{output_type: :object}} = ObjectSchema.new(opts)
    end

    test "creates array schema" do
      opts = [output_type: :array, properties: [id: [type: :string, required: true]]]
      assert {:ok, %ObjectSchema{output_type: :array}} = ObjectSchema.new(opts)
    end

    test "creates enum schema" do
      opts = [output_type: :enum, enum_values: ["red", "green", "blue"]]
      assert {:ok, %ObjectSchema{output_type: :enum}} = ObjectSchema.new(opts)
    end

    test "creates no_schema type" do
      opts = [output_type: :no_schema]
      assert {:ok, %ObjectSchema{output_type: :no_schema}} = ObjectSchema.new(opts)
    end
  end

  describe "object validation" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true, doc: "Full name"],
            age: [type: :pos_integer]
          ]
        )

      %{schema: schema}
    end

    test "validates valid object", %{schema: schema} do
      data = %{"name" => "John", "age" => 30}
      assert {:ok, validated} = ObjectSchema.validate(schema, data)
      assert validated.name == "John"
      assert validated.age == 30
    end

    test "returns error for missing required field", %{schema: schema} do
      data = %{"age" => 30}
      assert {:error, %SchemaValidation{}} = ObjectSchema.validate(schema, data)
    end

    test "returns error for wrong type", %{schema: schema} do
      data = %{"name" => "John", "age" => "thirty"}
      assert {:error, %SchemaValidation{}} = ObjectSchema.validate(schema, data)
    end
  end

  describe "array validation" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: [name: [type: :string, required: true]]
        )

      %{schema: schema}
    end

    test "validates valid array", %{schema: schema} do
      data = [%{"name" => "Alice"}, %{"name" => "Bob"}]
      assert {:ok, validated} = ObjectSchema.validate(schema, data)
      assert length(validated) == 2
    end

    test "returns error for invalid item", %{schema: schema} do
      # missing required name
      data = [%{"name" => "Alice"}, %{}]
      assert {:error, %SchemaValidation{}} = ObjectSchema.validate(schema, data)
    end

    test "returns error for non-list", %{schema: schema} do
      assert {:error, %SchemaValidation{}} = ObjectSchema.validate(schema, "not an array")
    end
  end

  describe "enum validation" do
    setup do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: ["small", "medium", "large"]
        )

      %{schema: schema}
    end

    test "validates valid enum value", %{schema: schema} do
      assert {:ok, "medium"} = ObjectSchema.validate(schema, "medium")
    end

    test "returns error for invalid enum value", %{schema: schema} do
      assert {:error, %SchemaValidation{}} = ObjectSchema.validate(schema, "extra-large")
    end
  end

  describe "nested object support" do
    test "supports nested objects with doc fields" do
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

      assert {:ok, ^valid_data} = ObjectSchema.validate(schema, valid_data)
      assert schema.properties[:address][:keys][:street][:doc] == "Street address"
    end
  end

  describe "to_json_schema/1" do
    test "converts object schema to JSON schema format" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
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
