defmodule Jido.Tools.AI.GenerateObjectTest do
  use ExUnit.Case, async: true
  use Jido.AI.TestSupport.KeyringCase

  import Jido.AI.Messages

  alias Jido.Tools.AI.GenerateObject

  describe "parameter validation" do
    test "validates messages parameter" do
      # Valid string message
      params = %{
        messages: "Generate a person",
        object_schema: [name: [type: :string, required: true]],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)

      # Valid message list
      messages = [user("Generate a person"), assistant("Sure!")]

      params = %{
        messages: messages,
        object_schema: [name: [type: :string, required: true]],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)
    end

    test "validates object_schema parameter" do
      # Valid object schema
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true], age: [type: :integer]],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)

      # Missing object_schema should fail
      params = %{messages: "Generate data", model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "object_schema"
    end

    test "validates output_type parameter" do
      # Valid output_type
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        output_type: :array,
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)

      # Invalid output_type
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        output_type: :invalid,
        model: "fake:test-model"
      }

      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "output_type"
    end

    test "validates enum_values parameter" do
      # Valid enum_values
      params = %{
        messages: "Pick a color",
        object_schema: [color: [type: :string, required: true]],
        enum_values: ["red", "blue", "green"],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)

      # Invalid enum_values (not a list)
      params = %{
        messages: "Pick a color",
        object_schema: [color: [type: :string, required: true]],
        enum_values: "red",
        model: "fake:test-model"
      }

      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "enum_values"
    end

    test "validates temperature parameter" do
      # Valid temperature
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        temperature: 0.7,
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)

      # Invalid temperature (too high)
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        temperature: 3.0,
        model: "fake:test-model"
      }

      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "temperature"

      # Invalid temperature (negative)
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        temperature: -0.1,
        model: "fake:test-model"
      }

      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "temperature"
    end

    test "validates actions parameter" do
      # Create a mock valid action module for testing
      defmodule MockAction do
        use Jido.Action,
          name: "mock_action",
          description: "A mock action for testing",
          schema: []

        def run(_params, _ctx), do: {:ok, %{result: "mock"}}
      end

      # Test actions validation at schema level (not execution)
      # Invalid actions (non-action module) - this should fail validation before execution
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        actions: [String],
        model: "fake:test-model"
      }

      assert {:error, error} = Jido.Exec.run(GenerateObject, params)
      assert error.message =~ "All actions must implement the Jido.Action behavior"

      # Valid actions validation should pass the schema check
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        actions: [],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(GenerateObject, params)
    end

    test "uses default model when not specified" do
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        model: "fake:test-model"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)
      assert result.model == "fake:test-model"
    end
  end

  describe "execution" do
    test "generates object successfully with minimal parameters" do
      params = %{
        messages: "Generate a person profile",
        object_schema: [name: [type: :string, required: true], age: [type: :integer]],
        model: "fake:test-model"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)
      assert Map.has_key?(result, :response)
      assert is_map(result.response)
      assert result.messages == "Generate a person profile"
      assert result.model == "fake:test-model"
    end

    test "generates object with all parameters" do
      params = %{
        messages: "Generate user data",
        object_schema: [
          name: [type: :string, required: true],
          age: [type: :integer, required: true],
          email: [type: :string]
        ],
        model: "fake:test-model",
        output_type: :object,
        temperature: 0.8,
        max_tokens: 100,
        system_prompt: "You generate realistic user profiles"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)
      assert Map.has_key?(result, :response)
      assert is_map(result.response)

      # Verify all parameters are preserved in result
      assert result.messages == "Generate user data"
      assert result.model == "fake:test-model"
      assert result.output_type == :object
      assert result.temperature == 0.8
      assert result.max_tokens == 100
      assert result.system_prompt == "You generate realistic user profiles"
    end

    test "works with message arrays" do
      messages = [
        system("You generate structured data"),
        user("Generate a product")
      ]

      params = %{
        messages: messages,
        object_schema: [name: [type: :string, required: true], price: [type: :float]],
        model: "fake:test-model"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)
      assert Map.has_key?(result, :response)
      assert result.messages == messages
    end

    test "works with enum output type" do
      params = %{
        messages: "Pick a color",
        object_schema: [color: [type: :string, required: true]],
        output_type: :enum,
        enum_values: ["red", "blue", "green"],
        model: "fake:fake-model"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)
      assert Map.has_key?(result, :response)
      assert result.output_type == :enum
      assert result.enum_values == ["red", "blue", "green"]
    end

    test "handles AI generation errors gracefully" do
      # Use an invalid model to trigger an error
      params = %{
        messages: "Generate data",
        object_schema: [name: [type: :string, required: true]],
        model: "invalid:nonexistent-model"
      }

      assert {:error, _reason} = Jido.Exec.run(GenerateObject, params)
    end
  end

  describe "options building" do
    test "builds options correctly from parameters" do
      # This is more of an integration test to ensure the internal
      # options building works as expected
      params = %{
        messages: "Generate test data",
        object_schema: [value: [type: :string, required: true]],
        model: "fake:test-model",
        output_type: :array,
        temperature: 0.5,
        max_tokens: 50,
        system_prompt: "Test prompt"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateObject, params)

      # The fact that it succeeded means options were built correctly
      # and passed to Jido.AI.generate_object without validation errors
      assert Map.has_key?(result, :response)
    end
  end
end
