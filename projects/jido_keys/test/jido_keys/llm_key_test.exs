defmodule JidoKeys.LlmKeyTest do
  use ExUnit.Case, async: true

  describe "to_llm_atom/1" do
    test "converts known LLM keys to atoms" do
      # OpenAI keys
      assert JidoKeys.to_llm_atom("openai_api_key") == :openai_api_key
      assert JidoKeys.to_llm_atom("openai_api_key_base") == :openai_api_key_base

      # Anthropic keys
      assert JidoKeys.to_llm_atom("anthropic_api_key") == :anthropic_api_key
      assert JidoKeys.to_llm_atom("claude_api_key") == :claude_api_key

      # Other LLM providers
      assert JidoKeys.to_llm_atom("cohere_api_key") == :cohere_api_key
      assert JidoKeys.to_llm_atom("huggingface_api_key") == :huggingface_api_key
      assert JidoKeys.to_llm_atom("replicate_api_key") == :replicate_api_key
      assert JidoKeys.to_llm_atom("together_api_key") == :together_api_key
      assert JidoKeys.to_llm_atom("groq_api_key") == :groq_api_key
      assert JidoKeys.to_llm_atom("mistral_api_key") == :mistral_api_key
      assert JidoKeys.to_llm_atom("perplexity_api_key") == :perplexity_api_key

      # Google keys
      assert JidoKeys.to_llm_atom("gemini_api_key") == :gemini_api_key
      assert JidoKeys.to_llm_atom("palm_api_key") == :palm_api_key
      assert JidoKeys.to_llm_atom("vertex_api_key") == :vertex_api_key

      # Azure OpenAI keys
      assert JidoKeys.to_llm_atom("azure_openai_api_key") == :azure_openai_api_key
      assert JidoKeys.to_llm_atom("azure_openai_endpoint") == :azure_openai_endpoint
      assert JidoKeys.to_llm_atom("azure_openai_deployment") == :azure_openai_deployment

      # AWS Bedrock keys
      assert JidoKeys.to_llm_atom("aws_bedrock_access_key") == :aws_bedrock_access_key
      assert JidoKeys.to_llm_atom("aws_bedrock_secret_key") == :aws_bedrock_secret_key
      assert JidoKeys.to_llm_atom("aws_bedrock_region") == :aws_bedrock_region
    end

    test "returns string for unknown keys" do
      assert JidoKeys.to_llm_atom("unknown_key") == "unknown_key"
      assert JidoKeys.to_llm_atom("custom_api_key") == "custom_api_key"
      assert JidoKeys.to_llm_atom("my_secret") == "my_secret"
      assert JidoKeys.to_llm_atom("") == ""
    end

    test "handles edge cases safely" do
      # Non-string input should raise FunctionClauseError
      assert_raise FunctionClauseError, fn ->
        JidoKeys.to_llm_atom(:already_atom)
      end

      assert_raise FunctionClauseError, fn ->
        JidoKeys.to_llm_atom(123)
      end

      assert_raise FunctionClauseError, fn ->
        JidoKeys.to_llm_atom(nil)
      end
    end

    test "prevents memory leaks by not using String.to_atom/1" do
      # This test ensures we're not using String.to_atom/1 which could cause memory leaks
      # We verify that unknown keys return as strings, not atoms
      unknown_key = "definitely_not_in_allowlist_#{System.unique_integer()}"

      result = JidoKeys.to_llm_atom(unknown_key)
      assert is_binary(result)
      assert result == unknown_key
      refute is_atom(result)
    end

    test "allowslist is comprehensive for common LLM providers" do
      # Test that we have coverage for major LLM providers
      major_providers = [
        "openai_api_key",
        "anthropic_api_key",
        "claude_api_key",
        "cohere_api_key",
        "huggingface_api_key",
        "replicate_api_key",
        "together_api_key",
        "groq_api_key",
        "mistral_api_key",
        "perplexity_api_key",
        "gemini_api_key",
        "palm_api_key",
        "vertex_api_key"
      ]

      for key <- major_providers do
        result = JidoKeys.to_llm_atom(key)
        assert is_atom(result), "Expected #{key} to convert to atom, got #{inspect(result)}"
        assert result == String.to_atom(key)
      end
    end
  end

  describe "integration with key normalization" do
    test "works with normalized keys from environment" do
      # Simulate how keys would be normalized from environment variables
      env_key = "OPENAI_API_KEY"

      normalized_key =
        env_key
        |> String.downcase()
        |> String.replace(~r/[^a-z0-9_]/, "_")

      assert normalized_key == "openai_api_key"
      assert JidoKeys.to_llm_atom(normalized_key) == :openai_api_key
    end

    test "handles mixed case and special characters in environment keys" do
      test_cases = [
        {"OPENAI-API-KEY", "openai_api_key"},
        {"Anthropic_API_Key", "anthropic_api_key"},
        {"cohere.api.key", "cohere_api_key"},
        {"HuggingFace-API-Key", "huggingface_api_key"}
      ]

      for {env_key, expected_normalized} <- test_cases do
        normalized =
          env_key
          |> String.downcase()
          |> String.replace(~r/[^a-z0-9_]/, "_")

        assert normalized == expected_normalized
        assert JidoKeys.to_llm_atom(normalized) == String.to_atom(expected_normalized)
      end
    end
  end
end
