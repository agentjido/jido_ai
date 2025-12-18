defmodule Jido.AI.Actions.ReqLlm.ToolResponseTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper
  import Mimic

  alias Jido.AI.Actions.ReqLlm.ToolResponse
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :verify_on_exit!

  describe "basic tool response" do
    test "returns result and tool_results with mocked response" do
      prompt = Prompt.new(:user, "What is 2+2?")

      mock_generate_text(mock_chat_response("The answer is 4"))

      {:ok, response} = ToolResponse.run(%{prompt: prompt}, %{})

      assert Map.has_key?(response, :result)
      assert Map.has_key?(response, :tool_results)
      assert response.result == "The answer is 4"
      assert is_list(response.tool_results)
    end

    test "uses default model when not provided" do
      prompt = Prompt.new(:user, "Hello")

      expect_generate_text(fn model_spec, _messages, _opts ->
        # Default model should be Claude 3.5 Haiku
        assert model_spec == "anthropic:claude-3-5-haiku-latest"
        {:ok, mock_chat_response("Hi there!")}
      end)

      {:ok, response} = ToolResponse.run(%{prompt: prompt}, %{})

      assert response.result == "Hi there!"
    end

    test "accepts custom model" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "Hello")

      expect_generate_text(fn model_spec, _messages, _opts ->
        assert model_spec == "openai:gpt-4"
        {:ok, mock_chat_response("Hello from GPT-4")}
      end)

      {:ok, response} = ToolResponse.run(%{model: model, prompt: prompt}, %{})

      assert response.result == "Hello from GPT-4"
    end
  end

  describe "tool handling" do
    test "includes tool calls in response" do
      prompt = Prompt.new(:user, "Search for weather")

      response =
        mock_chat_response("I'll search",
          tool_calls: [
            %{name: "search", arguments: %{"query" => "weather"}}
          ]
        )

      mock_generate_text(response)

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert result.result == "I'll search"
      assert length(result.tool_results) == 1
      [tool] = result.tool_results
      assert tool.name == "search"
    end

    test "handles multiple tool calls" do
      prompt = Prompt.new(:user, "Calculate and search")

      response =
        mock_chat_response("Running tools",
          tool_calls: [
            %{name: "calculate", arguments: %{"expr" => "2+2"}},
            %{name: "search", arguments: %{"q" => "test"}}
          ]
        )

      mock_generate_text(response)

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert length(result.tool_results) == 2
    end

    test "returns empty tool_results when no tools called" do
      prompt = Prompt.new(:user, "Just chat")

      mock_generate_text(mock_chat_response("Just chatting"))

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert result.tool_results == []
    end
  end

  describe "message conversion" do
    test "handles direct message parameter" do
      mock_generate_text(mock_chat_response("Response"))

      {:ok, result} = ToolResponse.run(%{message: "Hello"}, %{})

      assert result.result == "Response"
    end

    test "handles message with existing prompt" do
      base_prompt = Prompt.new(:system, "You are helpful")

      expect_generate_text(fn _model, messages, _opts ->
        # Should have both system and user messages
        assert length(messages) >= 2
        {:ok, mock_chat_response("Helpful response")}
      end)

      {:ok, result} =
        ToolResponse.run(
          %{
            message: "Hello",
            prompt: base_prompt
          },
          %{}
        )

      assert result.result == "Helpful response"
    end

    test "uses prompt parameter when no message" do
      prompt = Prompt.new(:user, "Test prompt")

      expect_generate_text(fn _model, messages, _opts ->
        assert length(messages) == 1
        [msg] = messages
        assert msg.content == "Test prompt"
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} = ToolResponse.run(%{prompt: prompt}, %{})
    end
  end

  describe "options forwarding" do
    test "forwards temperature to ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.2
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} =
        ToolResponse.run(
          %{
            prompt: prompt,
            temperature: 0.2
          },
          %{}
        )
    end

    test "uses default temperature of 0.7" do
      prompt = Prompt.new(:user, "Hello")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.7
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, _result} = ToolResponse.run(%{prompt: prompt}, %{})
    end
  end

  describe "error handling" do
    test "handles missing prompt gracefully" do
      result = ToolResponse.run(%{tools: []}, %{})

      assert match?({:error, _}, result)
    end

    test "propagates ChatCompletion errors" do
      prompt = Prompt.new(:user, "Hello")

      stub(ReqLLM, :generate_text, fn _model, _messages, _opts ->
        {:error, %{reason: :api_error, message: "API failure"}}
      end)

      {:error, error} = ToolResponse.run(%{prompt: prompt}, %{})

      assert error.reason == :api_error
    end

    test "handles invalid model" do
      prompt = Prompt.new(:user, "Hello")

      result =
        ToolResponse.run(
          %{
            model: %Model{provider: :invalid, model: "test"},
            prompt: prompt
          },
          %{}
        )

      assert match?({:error, _}, result)
    end
  end

  describe "response format" do
    test "formats response correctly" do
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(%{
        content: "Formatted content",
        tool_calls: []
      })

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert result.result == "Formatted content"
      assert result.tool_results == []
    end

    test "handles empty content" do
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(%{content: "", tool_calls: []})

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert result.result == ""
    end
  end

  describe "different providers" do
    test "works with Anthropic default" do
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("Anthropic response"))

      {:ok, result} = ToolResponse.run(%{prompt: prompt}, %{})

      assert result.result == "Anthropic response"
    end

    test "works with OpenAI" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4-turbo"]})
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("OpenAI response"))

      {:ok, result} = ToolResponse.run(%{model: model, prompt: prompt}, %{})

      assert result.result == "OpenAI response"
    end

    test "works with Google" do
      {:ok, model} = Model.from({:google, [model: "gemini-pro"]})
      prompt = Prompt.new(:user, "Test")

      mock_generate_text(mock_chat_response("Google response"))

      {:ok, result} = ToolResponse.run(%{model: model, prompt: prompt}, %{})

      assert result.result == "Google response"
    end
  end
end
