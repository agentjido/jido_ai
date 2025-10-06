defmodule Jido.AI.Actions.InstructorAdvancedParamsIntegrationTest do
  @moduledoc """
  Integration tests for advanced generation parameters in Instructor action.
  Tests verify that parameters are properly passed through to Instructor.chat_completion.
  """
  use ExUnit.Case, async: false
  use Mimic
  @moduletag :capture_log

  alias Jido.AI.Actions.Instructor, as: InstructorAction
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

  setup do
    Mimic.verify!(Instructor)
    :ok
  end

  setup :set_mimic_global

  describe "response_format parameter integration" do
    test "passes response_format through to Instructor.chat_completion" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "List cities")
      response_format = %{type: "json_object"}

      expect(Instructor, :chat_completion, fn opts, config ->
        # Verify response_format is passed through
        assert opts[:response_format] == response_format
        assert opts[:model] == "gpt-4"
        assert config[:adapter] == Instructor.Adapters.OpenAI
        {:ok, %TestResponse{text: "test", score: 0.9}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        response_format: response_format
      }

      assert {:ok, %{result: %TestResponse{}}, %{}} = InstructorAction.run(params, %{})
    end

    test "works with nil response_format" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        # response_format should not be in opts when nil
        refute Keyword.has_key?(opts, :response_format)
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "different response format types" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      # Test with different format specifications
      formats = [
        %{type: "json_object"},
        %{type: "json_schema", schema: %{type: "object"}},
        %{type: "text"}
      ]

      for format <- formats do
        expect(Instructor, :chat_completion, fn opts, _config ->
          assert opts[:response_format] == format
          {:ok, %TestResponse{}}
        end)

        params = %{
          model: model,
          prompt: prompt,
          response_model: TestResponse,
          response_format: format
        }

        assert {:ok, _, %{}} = InstructorAction.run(params, %{})
      end
    end
  end

  describe "logit_bias parameter integration" do
    test "passes logit_bias through to Instructor.chat_completion" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Write response")
      logit_bias = %{1234 => -100, 5678 => 50}

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Verify logit_bias is passed through
        assert opts[:logit_bias] == logit_bias
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        logit_bias: logit_bias
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "supports token suppression with -100 bias" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:logit_bias] == %{50256 => -100}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        logit_bias: %{50256 => -100}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "supports token encouragement with positive bias" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:logit_bias] == %{1234 => 100}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        logit_bias: %{1234 => 100}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "works with nil logit_bias" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        refute Keyword.has_key?(opts, :logit_bias)
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end

  describe "provider_options parameter integration" do
    test "passes provider_options as keyword list to Instructor" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")
      provider_opts = [logprobs: true, top_logprobs: 5]

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Verify provider options are merged into opts
        assert opts[:logprobs] == true
        assert opts[:top_logprobs] == 5
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: provider_opts
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "passes provider_options as map to Instructor" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")
      provider_opts = %{logprobs: true, top_logprobs: 5}

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Map should be converted to keyword list entries
        assert opts[:logprobs] == true
        assert opts[:top_logprobs] == 5
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: provider_opts
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "OpenAI-specific options pass through correctly" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      openai_opts = [
        logprobs: true,
        top_logprobs: 5,
        presence_penalty: 0.5,
        frequency_penalty: 0.3
      ]

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:logprobs] == true
        assert opts[:top_logprobs] == 5
        assert opts[:presence_penalty] == 0.5
        assert opts[:frequency_penalty] == 0.3
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: openai_opts
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "Groq-specific options pass through correctly" do
      model = %Model{
        provider: :openai,
        model: "llama3-groq-70b-8192-tool-use-preview",
        api_key: "test-key"
      }

      prompt = Prompt.new(:user, "Test")

      groq_opts = [reasoning_effort: "high", service_tier: "performance"]

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:reasoning_effort] == "high"
        assert opts[:service_tier] == "performance"
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: groq_opts
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "works with nil provider_options" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Standard opts should be present
        assert opts[:model] == "gpt-4"
        # But no extra provider options
        refute Keyword.has_key?(opts, :logprobs)
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end

  describe "combined advanced parameters" do
    test "all advanced parameters work together" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Generate data")

      response_format = %{type: "json_object"}
      logit_bias = %{1234 => -100}
      provider_opts = [logprobs: true, top_logprobs: 5]

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Verify all parameters are present
        assert opts[:response_format] == response_format
        assert opts[:logit_bias] == logit_bias
        assert opts[:logprobs] == true
        assert opts[:top_logprobs] == 5
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        response_format: response_format,
        logit_bias: logit_bias,
        provider_options: provider_opts
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "advanced parameters work with existing parameters" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Existing parameters
        assert opts[:temperature] == 0.5
        assert opts[:max_tokens] == 2000
        assert opts[:top_p] == 0.9
        # Advanced parameters
        assert opts[:response_format] == %{type: "json_object"}
        assert opts[:logit_bias] == %{1234 => -100}
        assert opts[:logprobs] == true
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        temperature: 0.5,
        max_tokens: 2000,
        top_p: 0.9,
        response_format: %{type: "json_object"},
        logit_bias: %{1234 => -100},
        provider_options: [logprobs: true]
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end

  describe "parameter priority with advanced params" do
    test "explicit response_format overrides prompt options" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}

      # Prompt has response_format option using with_options
      prompt =
        Prompt.new(:user, "Test")
        |> Prompt.with_options(response_format: %{type: "text"}, temperature: 0.3)

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Explicit param should win
        assert opts[:response_format] == %{type: "json_object"}
        # But prompt option still used for temperature
        assert opts[:temperature] == 0.3
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        response_format: %{type: "json_object"}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "explicit logit_bias overrides prompt options" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}

      prompt =
        Prompt.new(:user, "Test")
        |> Prompt.with_options(logit_bias: %{1111 => 50})

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Explicit param should win
        assert opts[:logit_bias] == %{9999 => -100}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        logit_bias: %{9999 => -100}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "uses prompt options when explicit params not provided" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}

      prompt =
        Prompt.new(:user, "Test")
        |> Prompt.with_options(
          response_format: %{type: "json_object"},
          logit_bias: %{1234 => -50}
        )

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Should use prompt options
        assert opts[:response_format] == %{type: "json_object"}
        assert opts[:logit_bias] == %{1234 => -50}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end

  describe "error handling with advanced parameters" do
    test "handles Instructor errors with advanced params" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn _opts, _config ->
        {:error, "Invalid response_format"}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        response_format: %{type: "invalid"}
      }

      assert {:error, "Invalid response_format", %{}} = InstructorAction.run(params, %{})
    end

    test "handles nil response from Instructor" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn _opts, _config ->
        nil
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        logit_bias: %{1234 => -100}
      }

      assert {:error, "Instructor chat completion returned nil", %{}} =
               InstructorAction.run(params, %{})
    end

    test "handles unexpected response from Instructor" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn _opts, _config ->
        "unexpected string response"
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: [logprobs: true]
      }

      assert {:error, error_msg, %{}} = InstructorAction.run(params, %{})
      assert error_msg =~ "Unexpected response from Instructor"
    end
  end

  describe "streaming with advanced parameters" do
    test "advanced params work with streaming" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        # Verify streaming is enabled
        assert opts[:stream] == true
        # Advanced params should also be present
        assert opts[:response_format] == %{type: "json_object"}
        assert opts[:logit_bias] == %{1234 => -100}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        stream: true,
        response_format: %{type: "json_object"},
        logit_bias: %{1234 => -100}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "partial streaming with advanced params" do
      model = %Model{provider: :openai, model: "gpt-4", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:stream] == true
        # partial is used to determine response_model format, not passed as separate option
        assert opts[:response_model] == {:partial, TestResponse}
        assert opts[:logprobs] == true
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        stream: true,
        partial: true,
        provider_options: [logprobs: true]
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end

  describe "provider adapter configuration" do
    test "Anthropic provider receives advanced params" do
      model = %Model{provider: :anthropic, model: "claude-3-sonnet-20240229", api_key: "test-key"}
      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, config ->
        # Verify Anthropic adapter
        assert config[:adapter] == Instructor.Adapters.Anthropic
        assert config[:api_key] == "test-key"
        # Advanced params should be present
        assert opts[:response_format] == %{type: "json_object"}
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        response_format: %{type: "json_object"}
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end

    test "OpenRouter provider receives advanced params" do
      model = %Model{
        provider: :openrouter,
        model: "anthropic/claude-3-opus",
        api_key: "test-key",
        base_url: "https://openrouter.ai/api/v1"
      }

      prompt = Prompt.new(:user, "Test")

      expect(Instructor, :chat_completion, fn opts, config ->
        # Verify OpenAI adapter with custom URL
        assert config[:adapter] == Instructor.Adapters.OpenAI
        assert config[:openai][:api_key] == "test-key"
        assert config[:openai][:api_url] == "https://openrouter.ai/api/v1"
        # Provider-specific options
        assert opts[:openrouter_models] == ["fallback/model"]
        {:ok, %TestResponse{}}
      end)

      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse,
        provider_options: [openrouter_models: ["fallback/model"]]
      }

      assert {:ok, _, %{}} = InstructorAction.run(params, %{})
    end
  end
end
