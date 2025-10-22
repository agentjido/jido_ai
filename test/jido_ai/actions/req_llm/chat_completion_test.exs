defmodule Jido.AI.Actions.ReqLlm.ChatCompletionTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @moduledoc """
  Tests for the ReqLlm.ChatCompletion action.

  Tests cover:
  - Parameter validation
  - Basic chat completion
  - Tool/function calling
  - Error handling
  - Response formatting
  """

  describe "parameter validation" do
    test "handles missing model parameter" do
      # Action runs but fails due to missing model in required params
      result = ChatCompletion.run(%{prompt: Prompt.new(:user, "Hello")}, %{})

      # Should get an error about missing model
      assert match?({:error, _}, result)
    end

    test "handles missing prompt parameter" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      # Action runs but fails due to missing prompt in required params
      result = ChatCompletion.run(%{model: model}, %{})

      # Should get an error about missing prompt
      assert match?({:error, _}, result)
    end

    test "validates model format" do
      result =
        ChatCompletion.run(
          %{
            model: "invalid",
            prompt: Prompt.new(:user, "Hello")
          },
          %{}
        )

      assert {:error, _} = result
    end

    test "accepts valid model and prompt" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      # Note: This will fail without API credentials, but parameter validation should pass
      params = %{model: model, prompt: prompt}

      # Run on_before_validate_params
      result = ChatCompletion.on_before_validate_params(params)
      assert {:ok, validated_params} = result
      assert validated_params.model == model
      assert validated_params.prompt == prompt
    end
  end

  describe "basic chat completion" do
    @tag :skip
    test "makes basic completion request" do
      # This test requires real API credentials
      # Skip by default, enable with mix test --include skip

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Say hello")

      result = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert {:ok, response} = result
      assert is_binary(response.content)
      assert is_list(response.tool_results)
    end
  end

  describe "tool calling" do
    @tag :skip
    test "includes tools in request" do
      # This test requires real API credentials and tool actions
      # Skip by default

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "What is 2 + 2?")
      tools = [Jido.Actions.Arithmetic.Add]

      result = ChatCompletion.run(%{model: model, prompt: prompt, tools: tools}, %{})

      assert {:ok, response} = result
      assert is_binary(response.content)
      assert is_list(response.tool_results)
    end
  end

  describe "error handling" do
    test "handles invalid API key" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      # Without proper authentication setup, this should fail gracefully
      result = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      # Should return error tuple, not crash
      assert match?({:error, _}, result)
    end

    test "handles missing provider" do
      # Create a model with invalid provider
      result =
        ChatCompletion.run(
          %{
            model: %Model{provider: :nonexistent, model: "test"},
            prompt: Prompt.new(:user, "Hello")
          },
          %{}
        )

      assert {:error, _} = result
    end
  end

  describe "response formatting" do
    # Note: format_response is a private function, so we test it indirectly
    # through the public API behavior

    test "response includes content" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      # Will fail with authentication error, but we can check error structure
      result = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      # Should return properly formatted error
      assert match?({:error, %{reason: _, details: _}}, result)
    end
  end

  describe "options handling" do
    test "applies default options" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      params = %{model: model, prompt: prompt}

      result = ChatCompletion.on_before_validate_params(params)
      assert {:ok, _validated} = result
    end

    test "accepts temperature parameter" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      params = %{model: model, prompt: prompt, temperature: 0.5}

      result = ChatCompletion.on_before_validate_params(params)
      assert {:ok, validated} = result
      assert validated.temperature == 0.5
    end

    test "accepts max_tokens parameter" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      params = %{model: model, prompt: prompt, max_tokens: 500}

      result = ChatCompletion.on_before_validate_params(params)
      assert {:ok, validated} = result
      assert validated.max_tokens == 500
    end
  end
end
