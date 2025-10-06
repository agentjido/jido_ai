defmodule Jido.AI.ReqLlmBridge.ProviderMappingTest do
  use ExUnit.Case, async: true
  alias Jido.AI.ReqLlmBridge.ProviderMapping

  describe "get_reqllm_provider/1" do
    test "maps known providers correctly" do
      assert ProviderMapping.get_reqllm_provider(:openai) == :openai
      assert ProviderMapping.get_reqllm_provider(:anthropic) == :anthropic
      assert ProviderMapping.get_reqllm_provider(:google) == :google
      assert ProviderMapping.get_reqllm_provider(:openrouter) == :openrouter
      assert ProviderMapping.get_reqllm_provider(:cloudflare) == :cloudflare
    end

    test "returns unknown providers as-is" do
      assert ProviderMapping.get_reqllm_provider(:unknown) == :unknown
      assert ProviderMapping.get_reqllm_provider(:newprovider) == :newprovider
    end
  end

  describe "normalize_model_name/1" do
    test "applies known normalizations" do
      assert ProviderMapping.normalize_model_name("models/gemini-2.0-flash") == "gemini-2.0-flash"
      assert ProviderMapping.normalize_model_name("models/gemini-1.5-pro") == "gemini-1.5-pro"
    end

    test "preserves already normalized names" do
      assert ProviderMapping.normalize_model_name("gpt-4o") == "gpt-4o"
      assert ProviderMapping.normalize_model_name("claude-3-5-haiku") == "claude-3-5-haiku"
    end

    test "trims whitespace" do
      assert ProviderMapping.normalize_model_name("  gpt-4o  ") == "gpt-4o"
      assert ProviderMapping.normalize_model_name("\tgemini-2.0-flash\n") == "gemini-2.0-flash"
    end

    test "handles empty and invalid inputs gracefully" do
      assert ProviderMapping.normalize_model_name("") == ""
    end
  end

  describe "check_model_deprecation/1" do
    test "returns ok for current models" do
      assert ProviderMapping.check_model_deprecation("gpt-4o") == {:ok, "gpt-4o"}

      assert ProviderMapping.check_model_deprecation("claude-3-5-haiku") ==
               {:ok, "claude-3-5-haiku"}

      assert ProviderMapping.check_model_deprecation("gemini-2.0-flash") ==
               {:ok, "gemini-2.0-flash"}
    end

    test "returns deprecated status with replacement for deprecated models" do
      assert ProviderMapping.check_model_deprecation("claude-2") ==
               {:deprecated, "claude-3-5-haiku"}

      assert ProviderMapping.check_model_deprecation("claude-1") ==
               {:deprecated, "claude-3-5-haiku"}

      assert ProviderMapping.check_model_deprecation("gpt-3.5-turbo-0301") ==
               {:deprecated, "gpt-3.5-turbo"}
    end
  end

  describe "validate_model_availability/2" do
    test "validates known providers as available" do
      {:ok, result} = ProviderMapping.validate_model_availability("openai:gpt-4o")

      assert result.provider == :openai
      assert result.model == "gpt-4o"
      assert result.available == true
      assert result.reqllm_id == "openai:gpt-4o"
      assert %DateTime{} = result.validated_at
    end

    test "validates other supported providers" do
      {:ok, result} = ProviderMapping.validate_model_availability("anthropic:claude-3-5-haiku")
      assert result.provider == :anthropic
      assert result.model == "claude-3-5-haiku"
      assert result.available == true

      {:ok, result} = ProviderMapping.validate_model_availability("google:gemini-2.0-flash")
      assert result.provider == :google
      assert result.model == "gemini-2.0-flash"
      assert result.available == true
    end

    test "rejects unsupported providers" do
      {:error, reason} = ProviderMapping.validate_model_availability("unsupported:model")
      assert reason =~ "Unsupported provider"
    end

    test "rejects invalid ReqLLM ID formats" do
      {:error, reason} = ProviderMapping.validate_model_availability("invalid-format")
      assert reason =~ "Invalid ReqLLM ID format"

      {:error, reason} = ProviderMapping.validate_model_availability("too:many:colons")
      assert reason =~ "Invalid ReqLLM ID format"
    end
  end

  describe "build_reqllm_config/3" do
    test "builds complete config for valid provider and model" do
      {:ok, config} = ProviderMapping.build_reqllm_config(:openai, "gpt-4o")

      assert config.jido_provider == :openai
      assert config.reqllm_provider == :openai
      assert config.original_model == "gpt-4o"
      assert config.normalized_model == "gpt-4o"
      assert config.final_model == "gpt-4o"
      assert config.reqllm_id == "openai:gpt-4o"
      assert config.available == true
      assert config.deprecation_status == :current
      assert %DateTime{} = config.validated_at
    end

    test "handles model normalization" do
      {:ok, config} = ProviderMapping.build_reqllm_config(:google, "models/gemini-2.0-flash")

      assert config.original_model == "models/gemini-2.0-flash"
      assert config.normalized_model == "gemini-2.0-flash"
      assert config.final_model == "gemini-2.0-flash"
      assert config.reqllm_id == "google:gemini-2.0-flash"
    end

    test "handles deprecated models with replacement" do
      {:deprecated, config} = ProviderMapping.build_reqllm_config(:anthropic, "claude-2")

      assert config.original_model == "claude-2"
      assert config.normalized_model == "claude-2"
      assert config.final_model == "claude-3-5-haiku"
      assert config.reqllm_id == "anthropic:claude-3-5-haiku"
      assert config.deprecation_status == :deprecated
    end

    test "returns error for unsupported providers" do
      # This would fail at validation step
      {:error, reason} = ProviderMapping.build_reqllm_config(:unsupported, "model")
      assert reason =~ "Unsupported provider"
    end
  end

  describe "supported_providers/0" do
    test "returns list of supported providers" do
      providers = ProviderMapping.supported_providers()

      assert is_list(providers)
      assert :openai in providers
      assert :anthropic in providers
      assert :google in providers
      assert :openrouter in providers
      assert :cloudflare in providers
    end

    test "returned providers are unique" do
      providers = ProviderMapping.supported_providers()
      assert length(providers) == length(Enum.uniq(providers))
    end
  end

  describe "log_mapping_operation/3" do
    test "returns ok when called" do
      result = ProviderMapping.log_mapping_operation(:info, "test operation", %{test: true})
      assert result == :ok
    end

    test "handles different log levels" do
      assert ProviderMapping.log_mapping_operation(:debug, "debug test") == :ok
      assert ProviderMapping.log_mapping_operation(:warning, "warning test") == :ok
      assert ProviderMapping.log_mapping_operation(:error, "error test") == :ok
    end
  end
end
