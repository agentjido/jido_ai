defmodule Jido.AI.Model.Registry.MetadataBridgeTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Model
  alias Jido.AI.Model.Registry.MetadataBridge
  alias Jido.AI.Model.{Architecture, Endpoint, Pricing}

  describe "MetadataBridge.to_jido_model/1" do
    test "converts ReqLLM model to Jido AI model format" do
      reqllm_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: 4096,
        max_retries: 3,
        capabilities: %{tool_call: true, reasoning: true, temperature: true, attachment: false},
        modalities: %{input: [:text], output: [:text]},
        cost: %{input: 0.003, output: 0.015},
        limit: %{context: 200_000, output: 4_096}
      }

      jido_model = MetadataBridge.to_jido_model(reqllm_model)

      # Check basic fields
      assert jido_model.id == "claude-3-5-sonnet"
      assert jido_model.name == "Claude 3 5 Sonnet"
      assert jido_model.provider == :anthropic
      assert jido_model.reqllm_id == "anthropic:claude-3-5-sonnet"

      # Check ReqLLM-specific fields
      assert jido_model.capabilities == reqllm_model.capabilities
      assert jido_model.modalities == reqllm_model.modalities
      assert jido_model.cost == reqllm_model.cost

      # Check derived fields
      assert jido_model.model == "claude-3-5-sonnet"
      # from limit.output
      assert jido_model.max_tokens == 4_096
      assert jido_model.max_retries == 3
      # default
      assert jido_model.temperature == 0.7
      assert jido_model.base_url == "https://api.anthropic.com"

      # Check architecture
      assert %Architecture{} = jido_model.architecture
      assert jido_model.architecture.modality == "text"
      assert jido_model.architecture.tokenizer == "claude"
      assert jido_model.architecture.instruct_type == "chat"

      # Check endpoints
      assert length(jido_model.endpoints) == 1
      endpoint = hd(jido_model.endpoints)
      assert %Endpoint{} = endpoint
      assert endpoint.name == "claude-3-5-sonnet"
      assert endpoint.provider_name == "anthropic"
      assert endpoint.context_length == 200_000
      assert endpoint.max_completion_tokens == 4_096
    end

    test "handles model with minimal metadata" do
      reqllm_model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        max_tokens: nil,
        max_retries: nil,
        capabilities: nil,
        modalities: nil,
        cost: nil,
        limit: nil
      }

      jido_model = MetadataBridge.to_jido_model(reqllm_model)

      # Should still create valid model with defaults
      assert jido_model.id == "gpt-4"
      assert jido_model.name == "Gpt 4"
      assert jido_model.provider == :openai
      assert jido_model.reqllm_id == "openai:gpt-4"

      # Should have reasonable defaults
      # default when no limit provided
      assert jido_model.max_tokens == 1024
      assert jido_model.max_retries == 3
      assert jido_model.temperature == 0.7

      # Should create default endpoint
      assert length(jido_model.endpoints) == 1
      endpoint = hd(jido_model.endpoints)
      # conservative default
      assert endpoint.context_length == 8192
    end

    test "infers provider-specific attributes correctly" do
      # Test OpenAI model
      openai_model = %ReqLLM.Model{provider: :openai, model: "gpt-4"}
      jido_openai = MetadataBridge.to_jido_model(openai_model)

      assert jido_openai.base_url == "https://api.openai.com/v1"
      assert jido_openai.architecture.tokenizer == "gpt"
      assert jido_openai.architecture.instruct_type == "chat"

      # Test Google model
      google_model = %ReqLLM.Model{provider: :google, model: "gemini-pro"}
      jido_google = MetadataBridge.to_jido_model(google_model)

      assert jido_google.base_url == "https://generativelanguage.googleapis.com"
      assert jido_google.architecture.tokenizer == "gemini"

      # Test unknown provider
      unknown_model = %ReqLLM.Model{provider: :unknown_provider, model: "test-model"}
      jido_unknown = MetadataBridge.to_jido_model(unknown_model)

      assert jido_unknown.base_url == nil
      assert jido_unknown.architecture.tokenizer == "unknown"
    end

    test "handles multimodal models correctly" do
      multimodal_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        modalities: %{input: [:text, :image], output: [:text]}
      }

      jido_model = MetadataBridge.to_jido_model(multimodal_model)

      assert jido_model.architecture.modality == "multimodal"
      assert jido_model.modalities == %{input: [:text, :image], output: [:text]}
    end
  end

  describe "MetadataBridge.enhance_with_registry_data/2" do
    test "enhances existing model with ReqLLM metadata" do
      existing_model = %Model{
        id: "claude-3-5-sonnet",
        name: "Claude 3.5 Sonnet",
        provider: :anthropic,
        temperature: 0.5,
        max_tokens: 2048
      }

      registry_data = %{
        capabilities: %{tool_call: true, reasoning: true},
        modalities: %{input: [:text], output: [:text]},
        cost: %{input: 0.003, output: 0.015},
        limit: %{context: 200_000, output: 4_096}
      }

      enhanced_model = MetadataBridge.enhance_with_registry_data(existing_model, registry_data)

      # Should preserve existing fields
      assert enhanced_model.id == "claude-3-5-sonnet"
      assert enhanced_model.name == "Claude 3.5 Sonnet"
      assert enhanced_model.provider == :anthropic
      assert enhanced_model.temperature == 0.5
      assert enhanced_model.max_tokens == 2048

      # Should add new registry data
      assert enhanced_model.capabilities == registry_data.capabilities
      assert enhanced_model.modalities == registry_data.modalities
      assert enhanced_model.cost == registry_data.cost
      assert enhanced_model.reqllm_id == "anthropic:claude-3-5-sonnet"
    end

    test "sets ReqLLM ID when missing" do
      model_without_id = %Model{
        id: "gpt-4",
        provider: :openai,
        reqllm_id: nil
      }

      enhanced_model = MetadataBridge.enhance_with_registry_data(model_without_id, %{})

      assert enhanced_model.reqllm_id == "openai:gpt-4"
    end

    test "updates endpoints with limit information" do
      existing_model = %Model{
        id: "test-model",
        provider: :test,
        endpoints: [
          %Endpoint{
            name: "test-model",
            context_length: 8192,
            max_completion_tokens: 1024
          }
        ]
      }

      registry_data = %{
        limit: %{context: 100_000, output: 4_096}
      }

      enhanced_model = MetadataBridge.enhance_with_registry_data(existing_model, registry_data)

      endpoint = hd(enhanced_model.endpoints)
      assert endpoint.context_length == 100_000
      assert endpoint.max_completion_tokens == 4_096
    end
  end

  describe "MetadataBridge.to_reqllm_model/1" do
    test "converts Jido AI model back to ReqLLM format" do
      jido_model = %Model{
        id: "claude-3-5-sonnet",
        name: "Claude 3.5 Sonnet",
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        max_tokens: 4096,
        max_retries: 3,
        capabilities: %{tool_call: true, reasoning: true},
        modalities: %{input: [:text], output: [:text]},
        cost: %{input: 0.003, output: 0.015},
        endpoints: [
          %Endpoint{context_length: 200_000, max_completion_tokens: 4_096}
        ]
      }

      reqllm_model = MetadataBridge.to_reqllm_model(jido_model)

      assert %ReqLLM.Model{} = reqllm_model
      assert reqllm_model.provider == :anthropic
      assert reqllm_model.model == "claude-3-5-sonnet"
      assert reqllm_model.max_tokens == 4096
      assert reqllm_model.max_retries == 3
      assert reqllm_model.capabilities == jido_model.capabilities
      assert reqllm_model.modalities == jido_model.modalities
      assert reqllm_model.cost == jido_model.cost
      assert reqllm_model.limit == %{context: 200_000, output: 4_096}
    end

    test "handles model with missing model field by using id" do
      jido_model = %Model{
        id: "gpt-4",
        provider: :openai,
        model: nil
      }

      reqllm_model = MetadataBridge.to_reqllm_model(jido_model)

      assert reqllm_model.model == "gpt-4"
      assert reqllm_model.provider == :openai
    end
  end

  describe "MetadataBridge.validate_compatibility/1" do
    test "validates ReqLLM model compatibility" do
      valid_reqllm_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet"
      }

      assert {:ok, :compatible} = MetadataBridge.validate_compatibility(valid_reqllm_model)
    end

    test "validates Jido AI model compatibility" do
      valid_jido_model = %Model{
        id: "claude-3-5-sonnet",
        provider: :anthropic
      }

      assert {:ok, :compatible} = MetadataBridge.validate_compatibility(valid_jido_model)
    end

    test "detects invalid ReqLLM model" do
      invalid_reqllm_model = %ReqLLM.Model{
        provider: nil,
        model: ""
      }

      {:error, errors} = MetadataBridge.validate_compatibility(invalid_reqllm_model)

      assert "Invalid provider: must be non-nil atom" in errors
      assert "Invalid model name: must be non-empty string" in errors
    end

    test "detects invalid Jido AI model" do
      invalid_jido_model = %Model{
        id: nil,
        provider: "not_an_atom"
      }

      {:error, errors} = MetadataBridge.validate_compatibility(invalid_jido_model)

      assert "Invalid provider: must be non-nil atom" in errors
      assert "Invalid model identifier: must be non-empty string" in errors
    end

    test "rejects unsupported model format" do
      unsupported_model = %{some: "random", data: true}

      {:error, errors} = MetadataBridge.validate_compatibility(unsupported_model)

      assert "Unsupported model format" in errors
    end
  end

  describe "pricing conversion" do
    test "formats numeric pricing correctly" do
      reqllm_model = %ReqLLM.Model{
        provider: :anthropic,
        model: "claude-3-5-sonnet",
        cost: %{input: 0.003, output: 0.015}
      }

      jido_model = MetadataBridge.to_jido_model(reqllm_model)

      endpoint = hd(jido_model.endpoints)
      assert %Pricing{} = endpoint.pricing
      assert endpoint.pricing.prompt == "$3.0 / 1M tokens"
      assert endpoint.pricing.completion == "$15.0 / 1M tokens"
    end

    test "handles nil pricing gracefully" do
      reqllm_model = %ReqLLM.Model{
        provider: :openai,
        model: "gpt-4",
        cost: nil
      }

      jido_model = MetadataBridge.to_jido_model(reqllm_model)

      endpoint = hd(jido_model.endpoints)
      assert endpoint.pricing.prompt == nil
      assert endpoint.pricing.completion == nil
    end

    test "preserves string pricing format" do
      reqllm_model = %ReqLLM.Model{
        provider: :test,
        model: "test-model",
        cost: %{input: "$0.005 per 1K tokens", output: "$0.010 per 1K tokens"}
      }

      jido_model = MetadataBridge.to_jido_model(reqllm_model)

      endpoint = hd(jido_model.endpoints)
      assert endpoint.pricing.prompt == "$0.005 per 1K tokens"
      assert endpoint.pricing.completion == "$0.010 per 1K tokens"
    end
  end

  describe "name humanization" do
    test "humanizes model names correctly" do
      test_cases = [
        {"claude-3-5-sonnet", "Claude 3 5 Sonnet"},
        {"gpt-4-turbo", "Gpt 4 Turbo"},
        {"gemini_pro_vision", "Gemini Pro Vision"},
        {"simple-model", "Simple Model"},
        {"ModelWithoutHyphens", "ModelWithoutHyphens"}
      ]

      for {input, expected} <- test_cases do
        reqllm_model = %ReqLLM.Model{provider: :test, model: input}
        jido_model = MetadataBridge.to_jido_model(reqllm_model)

        assert jido_model.name == expected,
               "Expected #{input} to become #{expected}, got #{jido_model.name}"
      end
    end
  end

  describe "architecture inference" do
    test "infers instruct type from model name" do
      test_cases = [
        {"claude-3-instruct", "instruct"},
        {"gpt-4-chat", "chat"},
        # Anthropic defaults to chat
        {"claude-3-5-sonnet", "chat"},
        # OpenAI defaults to chat
        {"gpt-4", "chat"},
        {"mistral-7b-instruct", "instruct"}
      ]

      for {model_name, expected_type} <- test_cases do
        provider = if String.contains?(model_name, "claude"), do: :anthropic, else: :openai
        reqllm_model = %ReqLLM.Model{provider: provider, model: model_name}
        jido_model = MetadataBridge.to_jido_model(reqllm_model)

        assert jido_model.architecture.instruct_type == expected_type,
               "Expected #{model_name} to have instruct_type #{expected_type}, got #{jido_model.architecture.instruct_type}"
      end
    end
  end
end
