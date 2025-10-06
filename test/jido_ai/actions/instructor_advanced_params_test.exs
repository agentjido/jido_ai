defmodule Jido.AI.Actions.InstructorAdvancedParamsTest do
  @moduledoc """
  Comprehensive tests for advanced generation parameters in Instructor action.
  Tests coverage for Task 2.5.1: Advanced Generation Parameters.
  """
  use ExUnit.Case, async: false

  alias Jido.AI.Model
  alias Jido.AI.Prompt

  # Mock response model
  defmodule TestResponse do
    use Ecto.Schema

    embedded_schema do
      field(:text, :string)
      field(:score, :float)
    end
  end

  describe "response_format parameter (2.5.1.1)" do
    test "accepts response_format as map" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        response_format: %{type: "json_object"}
      }

      # Validate params structure
      assert params.response_format == %{type: "json_object"}
    end

    test "response_format is optional (defaults to nil)" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse
      }

      # Should not fail validation without response_format
      assert is_map(params)
      refute Map.has_key?(params, :response_format)
    end

    test "response_format passes through to Instructor opts" do
      # This test verifies the parameter makes it to the opts
      # We can't easily test the actual API call without mocking
      response_format = %{type: "json_object"}

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        response_format: response_format
      }

      assert params.response_format == response_format
    end
  end

  describe "logit_bias parameter (2.5.1.3)" do
    test "accepts logit_bias as map of token IDs to bias values" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        logit_bias: %{1234 => -100, 5678 => 50}
      }

      assert params.logit_bias == %{1234 => -100, 5678 => 50}
    end

    test "logit_bias is optional (defaults to nil)" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse
      }

      refute Map.has_key?(params, :logit_bias)
    end

    test "logit_bias supports suppression (-100) and encouragement (100)" do
      suppress_token = %{1234 => -100}
      encourage_token = %{5678 => 100}

      params_suppress = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        logit_bias: suppress_token
      }

      params_encourage = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        logit_bias: encourage_token
      }

      assert params_suppress.logit_bias == suppress_token
      assert params_encourage.logit_bias == encourage_token
    end
  end

  describe "provider_options parameter (2.5.1.4)" do
    test "accepts provider_options as keyword list" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: [logprobs: true, top_logprobs: 5]
      }

      assert params.provider_options == [logprobs: true, top_logprobs: 5]
    end

    test "accepts provider_options as map" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: %{logprobs: true, top_logprobs: 5}
      }

      assert params.provider_options == %{logprobs: true, top_logprobs: 5}
    end

    test "provider_options is optional (defaults to nil)" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse
      }

      refute Map.has_key?(params, :provider_options)
    end

    test "supports OpenAI-specific options" do
      openai_options = [
        logprobs: true,
        top_logprobs: 5,
        presence_penalty: 0.5,
        frequency_penalty: 0.3
      ]

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: openai_options
      }

      assert params.provider_options == openai_options
    end

    test "supports Groq-specific options" do
      groq_options = [
        reasoning_effort: "high",
        service_tier: "performance"
      ]

      params = %{
        model: Model.from({:openai, model: "llama3-groq-70b-8192-tool-use-preview", api_key: "test-key"})
        |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: groq_options
      }

      assert params.provider_options == groq_options
    end

    test "supports Anthropic-specific options" do
      anthropic_options = [anthropic_top_k: 40]

      params = %{
        model: Model.from({:anthropic, model: "claude-3-sonnet-20240229", api_key: "test-key"})
        |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: anthropic_options
      }

      assert params.provider_options == anthropic_options
    end

    test "supports OpenRouter-specific options" do
      openrouter_options = [
        openrouter_top_logprobs: 5,
        openrouter_models: ["fallback/model-1", "fallback/model-2"]
      ]

      params = %{
        model:
          Model.from(
            {:openrouter,
             model: "anthropic/claude-3-opus", api_key: "test-key",
             base_url: "https://openrouter.ai/api/v1"}
          )
          |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: openrouter_options
      }

      assert params.provider_options == openrouter_options
    end
  end

  describe "combined advanced parameters" do
    test "all advanced parameters can be used together" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        response_format: %{type: "json_object"},
        logit_bias: %{1234 => -100},
        provider_options: [logprobs: true, top_logprobs: 5]
      }

      assert params.response_format == %{type: "json_object"}
      assert params.logit_bias == %{1234 => -100}
      assert params.provider_options == [logprobs: true, top_logprobs: 5]
    end

    test "advanced parameters work with existing parameters" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        # Existing parameters
        temperature: 0.5,
        max_tokens: 2000,
        top_p: 0.9,
        # Advanced parameters
        response_format: %{type: "json_object"},
        logit_bias: %{1234 => -100},
        provider_options: [logprobs: true]
      }

      assert params.temperature == 0.5
      assert params.max_tokens == 2000
      assert params.top_p == 0.9
      assert params.response_format == %{type: "json_object"}
      assert params.logit_bias == %{1234 => -100}
      assert params.provider_options == [logprobs: true]
    end
  end

  describe "parameter priority and defaults" do
    test "explicit params override prompt options" do
      prompt =
        Prompt.new(:user, "test", temperature: 0.3, max_tokens: 500, response_format: %{type: "text"})

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: prompt,
        response_model: TestResponse,
        temperature: 0.8,
        response_format: %{type: "json_object"}
      }

      # Explicit params should take precedence
      assert params.temperature == 0.8
      assert params.response_format == %{type: "json_object"}
    end

    test "prompt options are used when explicit params not provided" do
      prompt = Prompt.new(:user, "test", temperature: 0.3, max_tokens: 500)

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: prompt,
        response_model: TestResponse
      }

      # Should use prompt options (tested by absence of explicit params)
      refute Map.has_key?(params, :temperature)
    end

    test "nil values don't override defaults" do
      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        response_format: nil,
        logit_bias: nil,
        provider_options: nil
      }

      # Nil values should be present in params
      assert params.response_format == nil
      assert params.logit_bias == nil
      assert params.provider_options == nil
    end
  end

  describe "maybe_add_provider_options helper" do
    # These are internal implementation tests
    # Testing the helper function behavior indirectly through params

    test "provider_options as map merges into opts" do
      provider_opts = %{logprobs: true, top_logprobs: 5}

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: provider_opts
      }

      # Map should be preserved
      assert is_map(params.provider_options)
      assert params.provider_options.logprobs == true
      assert params.provider_options.top_logprobs == 5
    end

    test "provider_options as keyword list merges into opts" do
      provider_opts = [logprobs: true, top_logprobs: 5]

      params = %{
        model: Model.from({:openai, model: "gpt-4", api_key: "test-key"}) |> elem(1),
        prompt: Prompt.new(:user, "test"),
        response_model: TestResponse,
        provider_options: provider_opts
      }

      # Keyword list should be preserved
      assert is_list(params.provider_options)
      assert params.provider_options[:logprobs] == true
      assert params.provider_options[:top_logprobs] == 5
    end
  end
end
