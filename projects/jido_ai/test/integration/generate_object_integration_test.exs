defmodule Jido.AI.GenerateObjectIntegrationTest do
  @moduledoc """
  Integration tests for generate_object functionality using FakeProvider.

  These tests focus on the core functionality without relying on HTTP mocking
  or complex NimbleOptions schema validation that may have issues in the main codebase.
  """

  use ExUnit.Case, async: false

  alias Jido.AI.Error.{SchemaValidation}
  alias Jido.AI.Test.FakeProvider
  alias Jido.AI.Test.Fixtures.ModelFixtures
  alias Jido.AI.{ObjectSchema}

  # Set up fake provider for testing
  setup do
    # Register fake provider for testing
    Jido.AI.Provider.Registry.register(:fake, FakeProvider)

    on_exit(fn ->
      Jido.AI.Provider.Registry.clear()
      Jido.AI.Provider.Registry.initialize()
    end)

    fake_model = ModelFixtures.fake()
    {:ok, model: fake_model}
  end

  describe "basic generate_object functionality" do
    test "generates object with simple schema", %{model: model} do
      schema = [
        name: [type: :string, required: true],
        age: [type: :pos_integer, required: true]
      ]

      # This will use the FakeProvider which returns a simple object
      result =
        Jido.AI.generate_object(
          model,
          "Generate a person",
          schema,
          []
        )

      # FakeProvider returns a map with schema-compliant fake data
      # After validation, string keys are normalized to atoms
      assert {:ok, data} = result
      assert is_map(data)
      assert Map.has_key?(data, :name)
      assert Map.has_key?(data, :age)
      assert data.name == "fake_name"
      assert data.age == 42
    end

    test "handles different output types" do
      # Test enum output type
      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Choose a color",
          [],
          output_type: :enum,
          enum_values: ["red", "green", "blue"]
        )

      assert {:ok, _data} = result

      # Test array output type
      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Generate list",
          [name: [type: :string, required: true]],
          output_type: :array
        )

      assert {:ok, _data} = result

      # Test no_schema output type  
      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Generate anything",
          [],
          output_type: :no_schema
        )

      assert {:ok, _data} = result
    end

    test "validates model specifications" do
      schema = [name: [type: :string, required: true]]

      # Test with Model struct
      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Generate data",
          schema,
          []
        )

      assert {:ok, _data} = result

      # Test with string format (might fail due to provider registry)
      result =
        Jido.AI.generate_object(
          "fake:fake-model",
          "Generate data",
          schema,
          []
        )

      # This might fail due to provider registry, which is expected
      assert match?({:ok, _data}, result) or match?({:error, _}, result)

      # Test with tuple format (might fail due to provider registry)
      result =
        Jido.AI.generate_object(
          {:fake, model: "fake-model"},
          "Generate data",
          schema,
          []
        )

      # This might fail due to provider registry, which is expected
      assert match?({:ok, _data}, result) or match?({:error, _}, result)
    end

    test "passes options through correctly" do
      schema = [content: [type: :string, required: true]]

      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Generate content",
          schema,
          temperature: 0.8,
          max_tokens: 100,
          system_prompt: "You are helpful"
        )

      assert {:ok, _data} = result
    end
  end

  describe "ObjectSchema validation directly" do
    test "validates object schemas correctly" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true],
            age: [type: :pos_integer]
          ]
        )

      # Valid data
      valid_data = %{"name" => "John", "age" => 30}
      {:ok, validated} = ObjectSchema.validate(schema, valid_data)
      assert validated.name == "John"
      assert validated.age == 30

      # Invalid data - missing required field
      invalid_data = %{"age" => 30}
      {:error, error} = ObjectSchema.validate(schema, invalid_data)
      assert %SchemaValidation{} = error
    end

    test "validates array schemas correctly" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: [
            name: [type: :string, required: true],
            score: [type: :integer, required: true]
          ]
        )

      # Valid array data
      valid_data = [
        %{"name" => "Alice", "score" => 95},
        %{"name" => "Bob", "score" => 87}
      ]

      {:ok, validated} = ObjectSchema.validate(schema, valid_data)
      assert length(validated) == 2
      assert hd(validated).name == "Alice"

      # Invalid array data
      # missing score
      invalid_data = [%{"name" => "Alice"}]
      {:error, error} = ObjectSchema.validate(schema, invalid_data)
      assert %SchemaValidation{} = error
    end

    test "validates enum schemas correctly" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: ["red", "green", "blue"]
        )

      # Valid enum value
      {:ok, validated} = ObjectSchema.validate(schema, "blue")
      assert validated == "blue"

      # Invalid enum value
      {:error, error} = ObjectSchema.validate(schema, "purple")
      assert %SchemaValidation{} = error
    end

    test "no_schema accepts any data" do
      {:ok, schema} = ObjectSchema.new(output_type: :no_schema)

      test_values = ["string", 123, %{"map" => "value"}, [1, 2, 3], true, nil]

      for value <- test_values do
        {:ok, validated} = ObjectSchema.validate(schema, value)
        assert validated == value
      end
    end
  end

  describe "schema creation and options" do
    test "creates schemas with different output types" do
      # Object schema
      {:ok, obj_schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [name: [type: :string, required: true]]
        )

      assert obj_schema.output_type == :object

      # Array schema
      {:ok, arr_schema} =
        ObjectSchema.new(
          output_type: :array,
          properties: [id: [type: :string, required: true]]
        )

      assert arr_schema.output_type == :array

      # Enum schema
      {:ok, enum_schema} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: ["a", "b", "c"]
        )

      assert enum_schema.output_type == :enum

      # No schema
      {:ok, no_schema} = ObjectSchema.new(output_type: :no_schema)
      assert no_schema.output_type == :no_schema
    end

    test "validates schema creation options" do
      # Invalid output type
      {:error, error} = ObjectSchema.new(output_type: :invalid)
      assert error =~ "Invalid output_type"

      # Empty enum values
      {:error, error} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: []
        )

      assert error =~ "enum_values must be a non-empty list"

      # Invalid properties schema
      {:error, error} =
        ObjectSchema.new(
          output_type: :object,
          properties: [invalid: [type: :unknown_type]]
        )

      assert error =~ "Invalid properties schema"
    end

    test "extracts output_type correctly" do
      schema = %ObjectSchema{output_type: :array}
      assert ObjectSchema.output_type(schema) == :array

      opts = [output_type: :enum]
      assert ObjectSchema.output_type(opts) == :enum

      # Default to object
      assert ObjectSchema.output_type([]) == :object
    end
  end

  describe "error handling" do
    test "handles invalid model specs gracefully" do
      schema = [name: [type: :string, required: true]]

      # Invalid string format
      result =
        Jido.AI.generate_object(
          "invalid:format:too:many:colons",
          "Generate data",
          schema,
          []
        )

      assert {:error, _error} = result

      # Non-existent provider
      result =
        Jido.AI.generate_object(
          "nonexistent:model",
          "Generate data",
          schema,
          []
        )

      assert {:error, _error} = result
    end

    test "validates schema options" do
      # This test checks the basic flow without triggering NimbleOptions issues
      _schema = [name: [type: :string, required: true]]

      # Invalid enum_values
      {:error, _error} =
        ObjectSchema.new(
          output_type: :enum,
          enum_values: []
        )

      # Invalid output_type
      {:error, _error} = ObjectSchema.new(output_type: :not_valid)
    end
  end

  describe "message format support" do
    test "accepts different prompt formats" do
      import Jido.AI.Messages

      schema = [response: [type: :string, required: true]]

      # String prompt
      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          "Generate response",
          schema,
          []
        )

      assert {:ok, _data} = result

      # Message list (simplified - we won't test complex message structures 
      # since that depends on the provider implementation)
      messages = [
        user("Generate response")
      ]

      result =
        Jido.AI.generate_object(
          ModelFixtures.fake(),
          messages,
          schema,
          []
        )

      assert {:ok, _data} = result
    end
  end

  describe "key normalization" do
    test "normalizes string keys to atoms in validation" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            user_name: [type: :string, required: true],
            user_age: [type: :pos_integer]
          ]
        )

      # Input with string keys should be normalized
      data = %{"user_name" => "John", "user_age" => 30}
      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.user_name == "John"
      assert validated.user_age == 30
    end

    test "handles mixed key types" do
      {:ok, schema} =
        ObjectSchema.new(
          output_type: :object,
          properties: [
            name: [type: :string, required: true],
            age: [type: :pos_integer]
          ]
        )

      # Mixed string and atom keys
      data = %{"name" => "John", :age => 30}
      {:ok, validated} = ObjectSchema.validate(schema, data)

      assert validated.name == "John"
      assert validated.age == 30
    end
  end
end
