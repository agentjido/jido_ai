defmodule JidoTest.AI.ReqLLME2EIntegrationTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper
  import Mimic

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Prompt

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :set_mimic_global
  setup :verify_on_exit!

  # =============================================================================
  # End-to-End Model Flow Tests
  # =============================================================================

  describe "complete model flow: creation → registry → ReqLLM" do
    test "tuple model through ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")

      mock_generate_text(mock_chat_response("Hello back!"))

      # Create model from tuple
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      # Use in ChatCompletion
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Hello back!"
      assert is_struct(model, ReqLLM.Model)
    end

    test "string spec model through ChatCompletion" do
      prompt = Prompt.new(:user, "Test message")

      mock_generate_text(mock_chat_response("Response"))

      # Create model from string spec
      {:ok, model} = Model.from("anthropic:claude-3-5-haiku")

      # Use in ChatCompletion
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Response"
      assert model.provider == :anthropic
    end

    test "registry model through ChatCompletion" do
      prompt = Prompt.new(:user, "Registry test")

      mock_generate_text(mock_chat_response("Registry response"))

      # Get models from registry
      {:ok, models} = Registry.list_models(:openai)

      if length(models) > 0 do
        model = hd(models)

        # Use registry model in ChatCompletion
        {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

        assert result.content == "Registry response"
      end
    end

    test "discovered model through ChatCompletion" do
      prompt = Prompt.new(:user, "Discovery test")

      mock_generate_text(mock_chat_response("Discovered response"))

      # Discover models with specific capability
      {:ok, models} = Registry.discover_models(provider: :openai)

      if length(models) > 0 do
        model = hd(models)

        # Use discovered model
        {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

        assert result.content == "Discovered response"
      end
    end
  end

  # =============================================================================
  # Model Conversion Chain Tests
  # =============================================================================

  describe "model conversion chain" do
    test "legacy Jido.AI.Model converts through system" do
      prompt = Prompt.new(:user, "Legacy test")

      mock_generate_text(mock_chat_response("Legacy response"))

      # Start with legacy model
      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      # Use directly - should convert internally
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "Legacy response"
    end

    test "ReqLLM.Model passes through unchanged" do
      prompt = Prompt.new(:user, "Passthrough test")

      mock_generate_text(mock_chat_response("Passthrough response"))

      # Create ReqLLM.Model directly
      reqllm_model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        max_tokens: 1024
      }

      {:ok, result} = ChatCompletion.run(%{model: reqllm_model, prompt: prompt}, %{})

      assert result.content == "Passthrough response"
    end

    test "tuple converts to ReqLLM.Model with metadata" do
      {:ok, model} =
        Model.from(
          {:openai,
           [
             model: "gpt-4",
             max_tokens: 2048,
             temperature: 0.5
           ]}
        )

      assert is_struct(model, ReqLLM.Model)
      assert model.provider == :openai
      assert model.model == "gpt-4"
    end
  end

  # =============================================================================
  # Multi-Provider E2E Tests
  # =============================================================================

  describe "multi-provider end-to-end" do
    test "OpenAI flow complete" do
      prompt = Prompt.new(:user, "OpenAI test")
      mock_generate_text(mock_chat_response("OpenAI response"))

      {:ok, model} = Model.from({:openai, [model: "gpt-4-turbo"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "OpenAI response"
      assert model.provider == :openai
    end

    test "Anthropic flow complete" do
      prompt = Prompt.new(:user, "Anthropic test")
      mock_generate_text(mock_chat_response("Anthropic response"))

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-sonnet"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Anthropic response"
      assert model.provider == :anthropic
    end

    test "Google flow complete" do
      prompt = Prompt.new(:user, "Google test")
      mock_generate_text(mock_chat_response("Google response"))

      {:ok, model} = Model.from({:google, [model: "gemini-pro"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Google response"
      assert model.provider == :google
    end

    test "OpenRouter flow complete" do
      prompt = Prompt.new(:user, "OpenRouter test")
      mock_generate_text(mock_chat_response("OpenRouter response"))

      {:ok, model} = Model.from({:openrouter, [model: "anthropic/claude-3-opus"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "OpenRouter response"
      assert model.provider == :openrouter
    end
  end

  # =============================================================================
  # Registry Integration Tests
  # =============================================================================

  describe "registry integration with actions" do
    test "batch model retrieval and use" do
      prompt = Prompt.new(:user, "Batch test")

      # Get models from multiple providers
      {:ok, results} = Registry.batch_get_models([:openai, :anthropic])

      assert is_list(results)
      assert length(results) == 2

      # Each result should be a tuple with provider and result
      Enum.each(results, fn {provider, result} ->
        assert provider in [:openai, :anthropic]
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)
    end

    test "registry stats reflect available models" do
      {:ok, stats} = Registry.get_registry_stats()

      assert is_map(stats)
      assert stats.total_models > 0
      assert stats.total_providers > 0
      assert is_map(stats.provider_coverage)
    end

    test "model discovery with capability filtering" do
      # Discover models with tool_call capability
      {:ok, models} = Registry.discover_models(capability: :tool_call)

      # All returned models should have the capability
      Enum.each(models, fn model ->
        if model.capabilities do
          assert Map.get(model.capabilities, :tool_call, false) == true
        end
      end)
    end
  end

  # =============================================================================
  # Error Flow Tests
  # =============================================================================

  describe "error flow end-to-end" do
    test "invalid model string returns error" do
      result = Model.from("invalid-format-without-colon")
      assert match?({:error, _}, result)
    end

    test "unknown provider returns error" do
      result = Model.from("nonexistent:model")
      assert match?({:error, _}, result)
    end

    test "ChatCompletion with invalid model returns error" do
      prompt = Prompt.new(:user, "Test")

      result =
        ChatCompletion.run(
          %{
            model: "not-a-model",
            prompt: prompt
          },
          %{}
        )

      assert match?({:error, _}, result)
    end

    test "missing prompt returns error" do
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      result = ChatCompletion.run(%{model: model}, %{})

      assert match?({:error, _}, result)
    end
  end

  # =============================================================================
  # Parameter Flow Tests
  # =============================================================================

  describe "parameter flow end-to-end" do
    test "temperature flows through system" do
      prompt = Prompt.new(:user, "Temperature test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.2
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            temperature: 0.2
          },
          %{}
        )
    end

    test "max_tokens flows through system" do
      prompt = Prompt.new(:user, "Max tokens test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :max_tokens) == 500
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            max_tokens: 500
          },
          %{}
        )
    end

    test "stop sequences flow through system" do
      prompt = Prompt.new(:user, "Stop test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :stop) == ["END"]
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: model,
            prompt: prompt,
            stop: ["END"]
          },
          %{}
        )
    end
  end

  # =============================================================================
  # Tool Flow Tests
  # =============================================================================

  describe "tool flow end-to-end" do
    test "tool calls flow through system" do
      prompt = Prompt.new(:user, "Call a tool")

      response =
        mock_chat_response("I'll use the tool",
          tool_calls: [
            %{name: "search", arguments: %{"query" => "test"}}
          ]
        )

      mock_generate_text(response)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "I'll use the tool"
      assert length(result.tool_results) == 1
      [tool] = result.tool_results
      assert tool.name == "search"
    end

    test "multiple tool calls flow through system" do
      prompt = Prompt.new(:user, "Multiple tools")

      response =
        mock_chat_response("Using tools",
          tool_calls: [
            %{name: "tool1", arguments: %{"a" => 1}},
            %{name: "tool2", arguments: %{"b" => 2}}
          ]
        )

      mock_generate_text(response)

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-sonnet"]})
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert length(result.tool_results) == 2
    end
  end

  # =============================================================================
  # Message Conversion Tests
  # =============================================================================

  describe "message conversion end-to-end" do
    test "Prompt converts to messages correctly" do
      expect_generate_text(fn _model, messages, _opts ->
        assert length(messages) == 1
        [msg] = messages
        assert msg.role == :user
        assert msg.content == "User message"
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      prompt = Prompt.new(:user, "User message")

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end

    test "system and user messages flow correctly" do
      expect_generate_text(fn _model, messages, _opts ->
        assert length(messages) >= 1
        {:ok, mock_chat_response("Response")}
      end)

      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})
      system = Prompt.new(:system, "System instruction")
      prompt = Prompt.add_message(system, :user, "User message")

      {:ok, _result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})
    end
  end
end
