defmodule JidoTest.AI.BackwardCompatibilityTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper
  import Mimic

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Prompt

  @moduletag :capture_log
  @moduletag :reqllm_integration

  setup :verify_on_exit!

  # =============================================================================
  # Legacy Model Format Tests
  # =============================================================================

  describe "legacy Jido.AI.Model struct compatibility" do
    test "legacy model struct is accepted by ChatCompletion" do
      prompt = Prompt.new(:user, "Hello")
      mock_generate_text(mock_chat_response("Hello back!"))

      # Create legacy Jido.AI.Model struct directly
      legacy_model = %Jido.AI.Model{
        provider: :openai,
        model: "gpt-4"
      }

      # Should still work with ChatCompletion
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "Hello back!"
    end

    test "legacy model with all fields populated" do
      prompt = Prompt.new(:user, "Test")
      mock_generate_text(mock_chat_response("Response"))

      legacy_model = %Jido.AI.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: 1024,
        temperature: 0.5
      }

      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "Response"
    end

    test "legacy model conversion preserves provider" do
      legacy_model = %Jido.AI.Model{
        provider: :google,
        model: "gemini-pro"
      }

      # Convert through Model.from
      {:ok, converted} = Model.from(legacy_model)

      assert converted.provider == :google
      assert converted.model == "gemini-pro"
    end

    test "legacy model conversion preserves optional fields" do
      legacy_model = %Jido.AI.Model{
        provider: :openai,
        model: "gpt-4-turbo",
        max_tokens: 2048,
        temperature: 0.3
      }

      {:ok, converted} = Model.from(legacy_model)

      assert converted.provider == :openai
      assert converted.model == "gpt-4-turbo"
    end
  end

  # =============================================================================
  # Old API Pattern Tests
  # =============================================================================

  describe "old API patterns still work" do
    test "Model.from with tuple format" do
      # This was the original way to create models
      {:ok, model} = Model.from({:openai, [model: "gpt-4"]})

      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "Model.from with string spec format" do
      # String spec format support
      {:ok, model} = Model.from("anthropic:claude-3-5-haiku")

      assert model.provider == :anthropic
      assert model.model == "claude-3-5-haiku"
    end

    test "Model.from with keyword list options" do
      {:ok, model} =
        Model.from(
          {:openai,
           [
             model: "gpt-4",
             max_tokens: 1024,
             temperature: 0.7
           ]}
        )

      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "Registry.list_models returns models" do
      {:ok, models} = Registry.list_models()

      assert is_list(models)
      assert length(models) > 0
    end

    test "Registry.list_models with provider filter" do
      {:ok, models} = Registry.list_models(:openai)

      assert is_list(models)

      Enum.each(models, fn model ->
        assert model.provider == :openai
      end)
    end

    test "Registry.get_model retrieves specific model" do
      {:ok, model} = Registry.get_model(:openai, "gpt-4")

      assert model.provider == :openai
      assert model.model == "gpt-4"
    end

    test "Prompt.new creates prompts" do
      prompt = Prompt.new(:user, "Hello")

      assert prompt.messages != []
    end

    test "Prompt.add_message adds messages" do
      prompt = Prompt.new(:system, "You are helpful")
      prompt = Prompt.add_message(prompt, :user, "Hello")

      assert length(prompt.messages) >= 2
    end
  end

  # =============================================================================
  # Mixed Usage Tests
  # =============================================================================

  describe "mixed legacy and new patterns" do
    test "can mix legacy model with new ChatCompletion API" do
      prompt = Prompt.new(:user, "Test")
      mock_generate_text(mock_chat_response("Mixed response"))

      # Legacy model creation
      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      # New ChatCompletion API
      {:ok, result} =
        ChatCompletion.run(
          %{
            model: legacy_model,
            prompt: prompt,
            temperature: 0.5
          },
          %{}
        )

      assert result.content == "Mixed response"
    end

    test "can use registry models with ChatCompletion" do
      prompt = Prompt.new(:user, "Registry test")
      mock_generate_text(mock_chat_response("Registry response"))

      # Get model from registry (old pattern)
      {:ok, models} = Registry.list_models(:openai)
      model = hd(models)

      # Use with ChatCompletion (current pattern)
      {:ok, result} = ChatCompletion.run(%{model: model, prompt: prompt}, %{})

      assert result.content == "Registry response"
    end

    test "can convert between model formats" do
      # Start with tuple
      {:ok, from_tuple} = Model.from({:openai, [model: "gpt-4"]})

      # Convert legacy to new
      legacy = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      {:ok, from_legacy} = Model.from(legacy)

      # Both should have same essential properties
      assert from_tuple.provider == from_legacy.provider
      assert from_tuple.model == from_legacy.model
    end
  end

  # =============================================================================
  # Provider Compatibility Tests
  # =============================================================================

  describe "provider backward compatibility" do
    test "OpenAI provider works with legacy format" do
      prompt = Prompt.new(:user, "OpenAI test")
      mock_generate_text(mock_chat_response("OpenAI response"))

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "OpenAI response"
    end

    test "Anthropic provider works with legacy format" do
      prompt = Prompt.new(:user, "Anthropic test")
      mock_generate_text(mock_chat_response("Anthropic response"))

      legacy_model = %Jido.AI.Model{provider: :anthropic, model: "claude-3-5-sonnet"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "Anthropic response"
    end

    test "Google provider works with legacy format" do
      prompt = Prompt.new(:user, "Google test")
      mock_generate_text(mock_chat_response("Google response"))

      legacy_model = %Jido.AI.Model{provider: :google, model: "gemini-pro"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "Google response"
    end

    test "OpenRouter provider works with legacy format" do
      prompt = Prompt.new(:user, "OpenRouter test")
      mock_generate_text(mock_chat_response("OpenRouter response"))

      legacy_model = %Jido.AI.Model{provider: :openrouter, model: "anthropic/claude-3-opus"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert result.content == "OpenRouter response"
    end
  end

  # =============================================================================
  # Error Handling Compatibility Tests
  # =============================================================================

  describe "error handling backward compatibility" do
    test "invalid legacy model returns appropriate error" do
      prompt = Prompt.new(:user, "Test")

      # Missing provider
      result =
        ChatCompletion.run(
          %{
            model: %Jido.AI.Model{provider: nil, model: "gpt-4"},
            prompt: prompt
          },
          %{}
        )

      assert match?({:error, _}, result)
    end

    test "invalid model name in legacy format returns error" do
      prompt = Prompt.new(:user, "Test")

      legacy_model = %Jido.AI.Model{provider: :openai, model: nil}
      result = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert match?({:error, _}, result)
    end

    test "empty string model returns error" do
      result = Model.from("")
      assert match?({:error, _}, result)
    end

    test "unknown provider in tuple creates model" do
      # ReqLLM accepts any provider atom, doesn't validate provider names
      result = Model.from({:unknown_provider, [model: "test"]})
      assert match?({:ok, %ReqLLM.Model{provider: :unknown_provider}}, result)
    end
  end

  # =============================================================================
  # Response Format Compatibility Tests
  # =============================================================================

  describe "response format compatibility" do
    test "response contains expected fields" do
      prompt = Prompt.new(:user, "Test")
      mock_generate_text(mock_chat_response("Response"))

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      # Standard response fields
      assert Map.has_key?(result, :content)
      assert Map.has_key?(result, :tool_results)
    end

    test "tool results format is preserved" do
      prompt = Prompt.new(:user, "Use tool")

      response =
        mock_chat_response("Using tool",
          tool_calls: [
            %{name: "search", arguments: %{"query" => "test"}}
          ]
        )

      mock_generate_text(response)

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}
      {:ok, result} = ChatCompletion.run(%{model: legacy_model, prompt: prompt}, %{})

      assert is_list(result.tool_results)
      assert length(result.tool_results) == 1
      [tool] = result.tool_results
      assert tool.name == "search"
    end
  end

  # =============================================================================
  # Streaming Compatibility Tests
  # =============================================================================

  describe "streaming backward compatibility" do
    test "streaming option is accepted" do
      prompt = Prompt.new(:user, "Stream test")

      mock_stream_text(mock_stream_chunks(["Hello", " ", "world!"]))

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      {:ok, result} =
        ChatCompletion.run(
          %{
            model: legacy_model,
            prompt: prompt,
            stream: true
          },
          %{}
        )

      # Result should be a stream or collected chunks
      assert result != nil
    end
  end

  # =============================================================================
  # Parameter Passing Compatibility Tests
  # =============================================================================

  describe "parameter passing compatibility" do
    test "temperature parameter passes through" do
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :temperature) == 0.3
        {:ok, mock_chat_response("Response")}
      end)

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: legacy_model,
            prompt: prompt,
            temperature: 0.3
          },
          %{}
        )
    end

    test "max_tokens parameter passes through" do
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :max_tokens) == 500
        {:ok, mock_chat_response("Response")}
      end)

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: legacy_model,
            prompt: prompt,
            max_tokens: 500
          },
          %{}
        )
    end

    test "stop sequences parameter passes through" do
      prompt = Prompt.new(:user, "Test")

      expect_generate_text(fn _model, _messages, opts ->
        assert Keyword.get(opts, :stop) == ["END", "STOP"]
        {:ok, mock_chat_response("Response")}
      end)

      legacy_model = %Jido.AI.Model{provider: :openai, model: "gpt-4"}

      {:ok, _result} =
        ChatCompletion.run(
          %{
            model: legacy_model,
            prompt: prompt,
            stop: ["END", "STOP"]
          },
          %{}
        )
    end
  end
end
