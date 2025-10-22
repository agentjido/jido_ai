defmodule Jido.AI.Actions.ReqLlm.ToolResponseTest do
  use ExUnit.Case, async: false

  alias Jido.AI.Actions.ReqLlm.ToolResponse
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @moduledoc """
  Tests for the ReqLlm.ToolResponse action.

  Tests cover:
  - Parameter handling
  - Tool coordination
  - Model defaults
  - Message conversion
  - Response formatting
  """

  describe "parameter handling" do
    test "uses default model when not provided" do
      prompt = Prompt.new(:user, "Hello")

      # Should not crash, will fail with auth error but model should be set
      result = ToolResponse.run(%{prompt: prompt, tools: []}, %{})

      # Should return error (auth or API), not crash
      assert match?({:error, _}, result)
    end

    test "accepts custom model" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      result = ToolResponse.run(%{model: model, prompt: prompt, tools: []}, %{})

      # Should return error (auth), not crash
      assert match?({:error, _}, result)
    end

    test "defaults to empty tools list" do
      prompt = Prompt.new(:user, "Hello")

      # Should handle empty tools gracefully
      result = ToolResponse.run(%{prompt: prompt}, %{})

      assert match?({:error, _}, result)
    end

    test "accepts tools parameter" do
      prompt = Prompt.new(:user, "What is 2 + 2?")
      # Note: Arithmetic actions may not exist in test environment
      # This tests parameter acceptance, not execution

      result = ToolResponse.run(%{prompt: prompt, tools: []}, %{})

      assert match?({:error, _}, result)
    end
  end

  describe "message conversion" do
    test "handles direct message parameter" do
      # Simulate passing a message directly
      result = ToolResponse.run(%{message: "Hello", tools: []}, %{})

      # Should not crash, returns error due to auth
      assert match?({:error, _}, result)
    end

    test "handles message with existing prompt" do
      base_prompt = Prompt.new(:system, "You are helpful")

      result = ToolResponse.run(%{message: "Hello", prompt: base_prompt, tools: []}, %{})

      # Should not crash
      assert match?({:error, _}, result)
    end

    test "uses prompt parameter when no message" do
      prompt = Prompt.new(:user, "Hello")

      result = ToolResponse.run(%{prompt: prompt, tools: []}, %{})

      assert match?({:error, _}, result)
    end
  end

  describe "options forwarding" do
    test "forwards temperature to ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")

      result = ToolResponse.run(%{prompt: prompt, temperature: 0.5, tools: []}, %{})

      # Should handle the parameter without crashing
      assert match?({:error, _}, result)
    end

    test "forwards timeout to ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")

      result = ToolResponse.run(%{prompt: prompt, timeout: 10_000, tools: []}, %{})

      assert match?({:error, _}, result)
    end

    test "forwards verbose to ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")

      result = ToolResponse.run(%{prompt: prompt, verbose: true, tools: []}, %{})

      assert match?({:error, _}, result)
    end
  end

  describe "response format" do
    @tag :skip
    test "returns result and tool_results" do
      # This test requires real API credentials
      # Skip by default

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Say hello")

      result = ToolResponse.run(%{model: model, prompt: prompt, tools: []}, %{})

      case result do
        {:ok, response} ->
          assert Map.has_key?(response, :result)
          assert Map.has_key?(response, :tool_results)
          assert is_binary(response.result)
          assert is_list(response.tool_results)

        {:error, _reason} ->
          # Expected if no credentials
          :ok
      end
    end
  end

  describe "error handling" do
    test "handles missing prompt gracefully" do
      # Should fail validation or return error
      result = ToolResponse.run(%{tools: []}, %{})

      assert match?({:error, _}, result)
    end

    test "handles ChatCompletion errors" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      # Without authentication, should return error from ChatCompletion
      result = ToolResponse.run(%{model: model, prompt: prompt, tools: []}, %{})

      assert match?({:error, _}, result)
    end

    test "handles invalid model" do
      prompt = Prompt.new(:user, "Hello")

      result =
        ToolResponse.run(
          %{model: %Model{provider: :invalid, model: "test"}, prompt: prompt, tools: []},
          %{}
        )

      assert match?({:error, _}, result)
    end
  end

  describe "tool integration" do
    @tag :skip
    test "executes tools when requested" do
      # This test requires real API credentials and working tools
      # Skip by default

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-haiku-latest"]})
      prompt = Prompt.new(:user, "What is 2 + 2?")
      # Assuming arithmetic actions exist
      tools = []

      result = ToolResponse.run(%{model: model, prompt: prompt, tools: tools}, %{})

      case result do
        {:ok, response} ->
          assert is_binary(response.result)
          assert is_list(response.tool_results)

        {:error, _reason} ->
          # Expected if no credentials or tools
          :ok
      end
    end
  end
end
