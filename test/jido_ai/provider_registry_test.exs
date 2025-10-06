defmodule Jido.AI.ProviderRegistryTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias ReqLLM.Provider.Generated.ValidProviders

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Code)
    copy(ReqLlmBridge)
    copy(ValidProviders)
    :ok
  end

  describe "Provider.providers/0 - dynamic provider discovery" do
    test "returns legacy providers when ReqLLM is not available" do
      # Mock ReqLLM unavailable
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:error, :nofile}
      end)

      providers = Provider.providers()

      # Should return the legacy providers
      assert is_list(providers)
      assert length(providers) >= 5

      # Check for known legacy providers
      provider_ids = Enum.map(providers, fn {id, _} -> id end)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      assert :google in provider_ids
      assert :cloudflare in provider_ids
      assert :openrouter in provider_ids
    end

    test "merges ReqLLM providers with legacy providers" do
      # Mock ReqLLM available with additional providers
      reqllm_providers = [:openai, :anthropic, :mistral, :cohere, :groq, :perplexity]

      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      stub(ValidProviders, :list, fn -> reqllm_providers end)

      providers = Provider.providers()

      # Should include both legacy and ReqLLM providers
      assert is_list(providers)
      provider_ids = Enum.map(providers, fn {id, _} -> id end)

      # Legacy providers should be present
      assert :openai in provider_ids
      assert :anthropic in provider_ids

      # New ReqLLM providers should be added
      assert :mistral in provider_ids
      assert :cohere in provider_ids
      assert :groq in provider_ids

      # Legacy adapters should be preserved for known providers
      openai_entry = Enum.find(providers, fn {id, _} -> id == :openai end)
      assert {_, Jido.AI.Provider.OpenAI} = openai_entry
    end

    test "handles ReqLLM module loading errors gracefully" do
      # Mock ReqLLM loading throws an error
      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        raise "Module loading error"
      end)

      # Should not crash, but return legacy providers
      providers = Provider.providers()

      assert is_list(providers)
      assert length(providers) >= 5
    end
  end

  describe "Provider.list/0 - provider metadata listing" do
    test "builds provider structs for legacy providers" do
      providers = Provider.list()

      assert is_list(providers)
      assert Enum.all?(providers, &is_struct(&1, Provider))

      # Find a known provider
      openai = Enum.find(providers, &(&1.id == :openai))
      assert openai != nil
      assert openai.name == "OpenAI"
      assert openai.requires_api_key == true
      assert openai.type in [:direct, :proxy]
    end

    test "builds provider structs for ReqLLM-backed providers" do
      # Mock ReqLLM with additional providers
      reqllm_providers = [:openai, :mistral, :groq]

      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      stub(ValidProviders, :list, fn -> reqllm_providers end)

      providers = Provider.list()

      # Find a ReqLLM-only provider
      mistral = Enum.find(providers, &(&1.id == :mistral))
      assert mistral != nil
      assert mistral.name != nil
      assert mistral.description != nil
      assert mistral.requires_api_key == true
    end

    test "filters out nil provider structs" do
      # Even if building fails for some providers, list should not contain nils
      providers = Provider.list()

      assert Enum.all?(providers, &(&1 != nil))
      assert Enum.all?(providers, &is_struct(&1, Provider))
    end
  end

  describe "ReqLlmBridge.list_available_providers/0 - provider availability" do
    test "lists providers with API key availability" do
      # Mock some providers with keys available
      stub(ReqLlmBridge, :validate_provider_key, fn provider ->
        case provider do
          :openai -> {:ok, :environment}
          :anthropic -> {:ok, :config}
          _ -> {:error, :missing_key}
        end
      end)

      available = ReqLlmBridge.list_available_providers()

      assert is_list(available)
      assert Enum.all?(available, &is_map/1)

      # Only providers with keys should be listed
      provider_ids = Enum.map(available, & &1.provider)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      # No key available
      refute :mistral in provider_ids
    end

    test "uses ReqLLM registry when available" do
      # Mock ReqLLM with many providers
      all_providers = [:openai, :anthropic, :google, :mistral, :cohere, :groq]

      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      stub(ValidProviders, :list, fn -> all_providers end)

      stub(ReqLlmBridge, :validate_provider_key, fn _provider ->
        # All have keys for testing
        {:ok, :environment}
      end)

      available = ReqLlmBridge.list_available_providers()

      # Should include all ReqLLM providers
      provider_ids = Enum.map(available, & &1.provider)
      assert length(provider_ids) == length(all_providers)
      assert :mistral in provider_ids
      assert :cohere in provider_ids
      assert :groq in provider_ids
    end

    test "falls back to legacy providers when ReqLLM unavailable" do
      # Mock ReqLLM unavailable
      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:error, :nofile}
      end)

      stub(ReqLlmBridge, :validate_provider_key, fn _provider ->
        {:ok, :environment}
      end)

      available = ReqLlmBridge.list_available_providers()

      # Should return legacy providers
      provider_ids = Enum.map(available, & &1.provider)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      assert :google in provider_ids
      assert :cloudflare in provider_ids
      assert :openrouter in provider_ids
      # Only legacy providers
      assert length(provider_ids) == 5
    end
  end

  describe "ProviderMapping - metadata bridging" do
    test "supported_providers/0 returns ReqLLM registry providers" do
      # Mock ReqLLM registry
      expected_providers = [:openai, :anthropic, :mistral, :cohere, :groq]

      stub(ValidProviders, :list, fn -> expected_providers end)

      providers = ProviderMapping.supported_providers()

      assert providers == expected_providers
    end

    test "supported_providers/0 falls back on error" do
      # Mock ReqLLM error
      stub(ValidProviders, :list, fn -> raise "Registry error" end)

      # Should not crash, returns fallback
      providers = ProviderMapping.supported_providers()

      assert is_list(providers)
      assert :openai in providers
      assert :anthropic in providers
    end

    test "get_jido_provider_metadata/1 returns proper metadata structure" do
      {:ok, metadata} = ProviderMapping.get_jido_provider_metadata(:openai)

      assert metadata.id == :openai
      # Humanized
      assert metadata.name == "Openai"
      assert metadata.description != nil
      assert metadata.type in [:direct, :proxy]
      assert metadata.requires_api_key == true
      # Loaded dynamically
      assert metadata.models == []
      assert metadata.api_base_url == "https://api.openai.com/v1"
    end

    test "get_jido_provider_metadata/1 handles unknown providers" do
      {:ok, metadata} = ProviderMapping.get_jido_provider_metadata(:unknown_provider)

      assert metadata.id == :unknown_provider
      # Humanized
      assert metadata.name == "Unknown Provider"
      assert metadata.description =~ "ReqLLM"
      assert metadata.requires_api_key == true
    end

    test "provider_implemented?/1 checks ReqLLM registry" do
      stub(ValidProviders, :list, fn -> [:openai, :anthropic, :mistral] end)

      assert ProviderMapping.provider_implemented?(:openai) == true
      assert ProviderMapping.provider_implemented?(:mistral) == true
      assert ProviderMapping.provider_implemented?(:unknown) == false
    end

    test "metadata correctly identifies proxy providers" do
      {:ok, openrouter_meta} = ProviderMapping.get_jido_provider_metadata(:openrouter)
      {:ok, openai_meta} = ProviderMapping.get_jido_provider_metadata(:openai)

      assert openrouter_meta.type == :proxy
      assert openai_meta.type == :direct
    end

    test "metadata correctly identifies providers not requiring API keys" do
      {:ok, ollama_meta} = ProviderMapping.get_jido_provider_metadata(:ollama)
      {:ok, openai_meta} = ProviderMapping.get_jido_provider_metadata(:openai)

      assert ollama_meta.requires_api_key == false
      assert openai_meta.requires_api_key == true
    end
  end

  describe "backward compatibility" do
    test "Provider.get_adapter_module/1 works with legacy providers" do
      provider = %Provider{id: :openai, name: "OpenAI"}

      assert {:ok, Jido.AI.Provider.OpenAI} = Provider.get_adapter_module(provider)
    end

    test "Provider.get_adapter_module/1 returns :reqllm_backed for new providers" do
      # Mock a ReqLLM-only provider
      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      stub(ValidProviders, :list, fn -> [:mistral] end)

      provider = %Provider{id: :mistral, name: "Mistral"}

      assert {:ok, :reqllm_backed} = Provider.get_adapter_module(provider)
    end

    test "Provider.get_adapter_by_id/1 works with both legacy and new providers" do
      # Legacy provider
      assert {:ok, Jido.AI.Provider.OpenAI} = Provider.get_adapter_by_id(:openai)

      # New provider via ReqLLM
      stub(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      stub(ValidProviders, :list, fn -> [:mistral] end)

      assert {:ok, :reqllm_backed} = Provider.get_adapter_by_id(:mistral)
    end

    test "existing provider enumeration APIs remain functional" do
      # All existing APIs should work without modification
      providers = Provider.providers()
      assert is_list(providers)

      provider_list = Provider.list()
      assert is_list(provider_list)
      assert Enum.all?(provider_list, &is_struct(&1, Provider))

      available = ReqLlmBridge.list_available_providers()
      assert is_list(available)
      assert Enum.all?(available, &is_map/1)
    end
  end
end
