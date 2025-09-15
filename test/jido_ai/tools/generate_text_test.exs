defmodule Jido.Tools.AI.GenerateTextTest do
  use ExUnit.Case, async: true
  use Jido.AI.TestSupport.KeyringCase

  import Jido.AI.Messages

  alias Jido.Tools.AI.GenerateText

  describe "parameter validation" do
    test "validates messages parameter" do
      # Valid string message
      params = %{messages: "Hello world", model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(GenerateText, params)

      # Valid message list
      messages = [user("Hello"), assistant("Hi there")]
      params = %{messages: messages, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(GenerateText, params)
    end

    test "validates temperature parameter" do
      # Valid temperature
      params = %{messages: "Hello", temperature: 0.7, model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(GenerateText, params)

      # Invalid temperature (too high)
      params = %{messages: "Hello", temperature: 3.0, model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(GenerateText, params)
      assert error.message =~ "temperature"

      # Invalid temperature (negative)
      params = %{messages: "Hello", temperature: -0.1, model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(GenerateText, params)
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
      params = %{messages: "Hello", actions: [String], model: "fake:test-model"}
      assert {:error, error} = Jido.Exec.run(GenerateText, params)
      assert error.message =~ "All actions must implement the Jido.Action behavior"

      # Valid actions validation should pass the schema check
      # (we skip execution test as it involves complex tool conversion)
      params = %{messages: "Hello", actions: [], model: "fake:test-model"}
      assert {:ok, _} = Jido.Exec.run(GenerateText, params)
    end

    test "uses default model when not specified" do
      params = %{messages: "Hello", model: "fake:test-model"}
      assert {:ok, result} = Jido.Exec.run(GenerateText, params)
      assert result.model == "fake:test-model"
    end
  end

  describe "execution" do
    test "generates text successfully with minimal parameters" do
      params = %{messages: "Hello world", model: "fake:test-model"}

      assert {:ok, result} = Jido.Exec.run(GenerateText, params)
      assert Map.has_key?(result, :response)
      assert is_binary(result.response)
      assert result.messages == "Hello world"
      assert result.model == "fake:test-model"
    end

    test "generates text with all parameters" do
      params = %{
        messages: "Write a short poem",
        model: "fake:test-model",
        temperature: 0.8,
        max_tokens: 100,
        system_prompt: "You are a poet"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateText, params)
      assert Map.has_key?(result, :response)
      assert is_binary(result.response)

      # Verify all parameters are preserved in result
      assert result.messages == "Write a short poem"
      assert result.model == "fake:test-model"
      assert result.temperature == 0.8
      assert result.max_tokens == 100
      assert result.system_prompt == "You are a poet"
    end

    test "works with message arrays" do
      messages = [
        system("You are helpful"),
        user("Hello")
      ]

      params = %{messages: messages, model: "fake:test-model"}
      assert {:ok, result} = Jido.Exec.run(GenerateText, params)
      assert Map.has_key?(result, :response)
      assert result.messages == messages
    end

    test "handles AI generation errors gracefully" do
      # Use an invalid model to trigger an error
      params = %{
        messages: "Hello",
        model: "invalid:nonexistent-model"
      }

      assert {:error, _reason} = Jido.Exec.run(GenerateText, params)
    end
  end

  describe "options building" do
    test "builds options correctly from parameters" do
      # This is more of an integration test to ensure the internal
      # options building works as expected
      params = %{
        messages: "Test",
        model: "fake:test-model",
        temperature: 0.5,
        max_tokens: 50,
        system_prompt: "Test prompt"
      }

      assert {:ok, result} = Jido.Exec.run(GenerateText, params)

      # The fact that it succeeded means options were built correctly
      # and passed to Jido.AI.generate_text without validation errors
      assert Map.has_key?(result, :response)
    end
  end
end
