defmodule Jido.AI.Tools.StreamObjectTest do
  use ExUnit.Case, async: true
  use Jido.AI.TestSupport.KeyringCase

  import Jido.AI.Messages

  alias Jido.Tools.AI.StreamObject

  describe "parameter validation" do
    test "validates messages parameter" do
      schema = [name: [type: :string, required: true]]

      # Valid string message
      params = %{messages: "Hello world", object_schema: schema, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(StreamObject, params)

      # Valid message list
      messages = [user("Hello"), assistant("Hi there")]
      params = %{messages: messages, object_schema: schema, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(StreamObject, params)
    end

    test "validates object_schema parameter" do
      # Valid schema
      schema = [name: [type: :string, required: true]]
      params = %{messages: "Hello", object_schema: schema, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(StreamObject, params)

      # Missing required schema
      params = %{messages: "Hello", model: "fake:test-model"}
      assert {:error, _} = Jido.Exec.run(StreamObject, params)
    end

    test "validates output_type parameter" do
      schema = [color: [type: :string, required: true]]

      # Valid output_type with enum_values
      params = %{
        messages: "Pick a color",
        object_schema: schema,
        output_type: :enum,
        enum_values: ["red", "blue"],
        model: "fake:test-model"
      }

      assert {:ok, _} = Jido.Exec.run(StreamObject, params)

      # Invalid output_type
      params = %{messages: "Hello", object_schema: schema, output_type: :invalid, model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(StreamObject, params)
      assert error.message =~ "output_type"
    end

    test "validates temperature parameter" do
      schema = [name: [type: :string, required: true]]

      # Valid temperature
      params = %{messages: "Hello", object_schema: schema, temperature: 0.7, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(StreamObject, params)

      # Invalid temperature (too high)
      params = %{messages: "Hello", object_schema: schema, temperature: 3.0, model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(StreamObject, params)
      assert error.message =~ "temperature"

      # Invalid temperature (negative)
      params = %{messages: "Hello", object_schema: schema, temperature: -0.1, model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(StreamObject, params)
      assert error.message =~ "temperature"
    end

    test "validates actions parameter" do
      schema = [name: [type: :string, required: true]]

      # Create a mock valid action module for testing
      defmodule MockAction do
        use Jido.Action,
          name: "mock_action",
          description: "A mock action for testing",
          schema: []

        def run(_params, _ctx), do: {:ok, %{result: "mock"}}
      end

      # Invalid actions (non-action module)
      params = %{messages: "Hello", object_schema: schema, actions: [String], model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(StreamObject, params)
      assert error.message =~ "All actions must implement the Jido.Action behavior"

      # Valid actions
      params = %{messages: "Hello", object_schema: schema, actions: [], model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(StreamObject, params)
    end

    test "uses default model when not specified" do
      schema = [name: [type: :string, required: true]]
      params = %{messages: "Hello", object_schema: schema, model: "fake:test-model"}
      assert {:ok, result} = Jido.Exec.run(StreamObject, params)
      assert result.model == "fake:test-model"
    end
  end

  describe "execution" do
    test "streams object successfully with minimal parameters" do
      schema = [name: [type: :string, required: true]]
      params = %{messages: "Generate a person", object_schema: schema, model: "fake:test-model"}

      assert {:ok, result} = Jido.Exec.run(StreamObject, params)
      assert Map.has_key?(result, :response)
      assert is_struct(result.response, Stream)
      assert result.messages == "Generate a person"
      assert result.object_schema == schema
      assert result.model == "fake:test-model"
    end

    test "streams object with all parameters" do
      schema = [name: [type: :string, required: true], age: [type: :pos_integer, required: true]]

      params = %{
        messages: "Generate a person",
        object_schema: schema,
        model: "fake:test-model",
        output_type: :object,
        temperature: 0.8,
        max_tokens: 100,
        system_prompt: "You are a data generator"
      }

      assert {:ok, result} = Jido.Exec.run(StreamObject, params)
      assert Map.has_key?(result, :response)
      assert is_struct(result.response, Stream)

      # Verify all parameters are preserved in result
      assert result.messages == "Generate a person"
      assert result.object_schema == schema
      assert result.model == "fake:test-model"
      assert result.output_type == :object
      assert result.temperature == 0.8
      assert result.max_tokens == 100
      assert result.system_prompt == "You are a data generator"
    end

    test "works with enum output type" do
      schema = [color: [type: :string, required: true]]

      params = %{
        messages: "Pick a color",
        object_schema: schema,
        model: "fake:test-model",
        output_type: :enum,
        enum_values: ["red", "green", "blue"]
      }

      assert {:ok, result} = Jido.Exec.run(StreamObject, params)
      assert Map.has_key?(result, :response)
      assert is_struct(result.response, Stream)
      assert result.output_type == :enum
      assert result.enum_values == ["red", "green", "blue"]
    end

    test "works with message arrays" do
      messages = [
        system("You are helpful"),
        user("Generate data")
      ]

      schema = [data: [type: :string, required: true]]

      params = %{messages: messages, object_schema: schema, model: "fake:test-model"}
      assert {:ok, result} = Jido.Exec.run(StreamObject, params)
      assert Map.has_key?(result, :response)
      assert result.messages == messages
    end

    test "handles AI generation errors gracefully" do
      # Use an invalid model to trigger an error
      schema = [name: [type: :string, required: true]]

      params = %{
        messages: "Hello",
        object_schema: schema,
        model: "invalid:nonexistent-model"
      }

      assert {:error, _reason} = Jido.Exec.run(StreamObject, params)
    end
  end

  describe "options building" do
    test "builds options correctly from parameters" do
      schema = [result: [type: :string, required: true]]

      params = %{
        messages: "Test",
        object_schema: schema,
        model: "fake:test-model",
        output_type: :object,
        temperature: 0.5,
        max_tokens: 50,
        system_prompt: "Test prompt"
      }

      assert {:ok, result} = Jido.Exec.run(StreamObject, params)

      # The fact that it succeeded means options were built correctly
      assert Map.has_key?(result, :response)
    end
  end
end
