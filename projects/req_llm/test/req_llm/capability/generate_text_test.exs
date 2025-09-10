defmodule ReqLLM.Capability.GenerateTextTest do
  @moduledoc """
  Unit tests for ReqLLM.Capability.GenerateText capability verification.

  Tests the GenerateText capability module's interface compliance and basic behavior.
  Note: These tests avoid making real API calls by mocking at the appropriate level.
  """

  use ReqLLM.Test.CapabilityCase

  alias ReqLLM.Capability.GenerateText

  describe "id/0" do
    test "returns the correct capability identifier" do
      assert GenerateText.id() == :generate_text
    end
  end

  describe "advertised?/1" do
    test "returns true for all provider types" do
      test_providers = [
        {:openai, "gpt-4"},
        {:anthropic, "claude-3-sonnet"},
        {:fake_provider, "fake-model"},
        {:custom, "custom-model"}
      ]

      for {provider, model_name} <- test_providers do
        model = test_model(to_string(provider), model_name)

        assert GenerateText.advertised?(model) == true,
               "Expected advertised?(#{provider}:#{model_name}) to be true"
      end
    end
  end

  describe "verify/2" do
    test "successful verification across different response scenarios" do
      test_scenarios = [
        {"Basic response", "Hello! How can I help you today?", 32,
         "Hello! How can I help you today?"},
        {"Unicode content", "Hello! 👋 こんにちは 🌟", 16, "Hello! 👋 こんにちは 🌟"},
        {"Response with trailing whitespace", "Hello world!   \n", 16, "Hello world!   \n"},
        {"Long response truncation", String.duplicate("This is a long response. ", 10), 250,
         String.slice(String.duplicate("This is a long response. ", 10), 0, 50)},
        {"Exactly 50 chars", String.duplicate("x", 50), 50, String.duplicate("x", 50)},
        {"Over 50 chars", String.duplicate("y", 75), 75, String.duplicate("y", 50)}
      ]

      for {description, response_text, expected_length, expected_preview} <- test_scenarios do
        model = test_model("openai", "gpt-4")

        Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, _opts ->
          {:ok, response_text}
        end)

        result = GenerateText.verify(model, [])

        assert {:ok, response_data} = result, "Test '#{description}' should pass"
        assert response_data.model_id == "openai:gpt-4"

        assert response_data.response_length == expected_length,
               "Length mismatch for '#{description}'"

        assert response_data.response_preview == expected_preview,
               "Preview mismatch for '#{description}'"
      end
    end

    test "passes timeout configuration to generate_text!" do
      model = test_model("openai", "gpt-4")
      custom_timeout = 5_000

      Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, opts ->
        provider_opts = Keyword.get(opts, :provider_options, %{})
        assert provider_opts.timeout == custom_timeout
        assert provider_opts.receive_timeout == custom_timeout
        {:ok, "Response with custom timeout"}
      end)

      result = GenerateText.verify(model, timeout: custom_timeout)

      assert {:ok, response_data} = result
      assert response_data.response_preview == "Response with custom timeout"
    end

    test "generates correct model_id format across providers" do
      test_cases = [
        {:openai, "gpt-4", "openai:gpt-4"},
        {:anthropic, "claude-3-sonnet", "anthropic:claude-3-sonnet"},
        {:fake_provider, "fake-model-v2", "fake_provider:fake-model-v2"}
      ]

      for {provider, model_name, expected_id} <- test_cases do
        model = test_model(to_string(provider), model_name)

        Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, _opts ->
          {:ok, "Test response"}
        end)

        result = GenerateText.verify(model, [])

        assert {:ok, response_data} = result
        assert response_data.model_id == expected_id
      end
    end

    test "handles error cases appropriately" do
      error_scenarios = [
        {"Empty response", {:ok, ""}, "Empty response"},
        {"Whitespace-only response", {:ok, "   \n\t   "}, "Empty response"},
        {"API error", {:error, "Network timeout"}, "Network timeout"}
      ]

      for {description, mock_response, expected_error} <- error_scenarios do
        model = test_model("openai", "gpt-4")

        Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, _opts ->
          mock_response
        end)

        result = GenerateText.verify(model, [])
        assert {:error, ^expected_error} = result, "Error case '#{description}' failed"
      end
    end
  end

  describe "behavior compliance" do
    test "implements ReqLLM.Capability.Adapter behavior" do
      assert function_exported?(GenerateText, :id, 0)
      assert function_exported?(GenerateText, :advertised?, 1)
      assert function_exported?(GenerateText, :verify, 2)
    end

    test "verify/2 returns proper result format" do
      model = test_model("openai", "gpt-4")

      # Test success format
      Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, _opts ->
        {:ok, "Test response"}
      end)

      result = GenerateText.verify(model, [])

      assert {:ok, data} = result
      assert is_map(data)
      assert Map.has_key?(data, :model_id)
      assert Map.has_key?(data, :response_length)
      assert Map.has_key?(data, :response_preview)
      assert is_binary(data.model_id)
      assert is_integer(data.response_length)
      assert is_binary(data.response_preview)

      # Test error format
      Mimic.stub(ReqLLM, :generate_text!, fn _model, _message, _opts ->
        {:error, "Network error"}
      end)

      result = GenerateText.verify(model, [])

      assert {:error, reason} = result
      assert is_binary(reason)
      assert reason == "Network error"
    end
  end
end
