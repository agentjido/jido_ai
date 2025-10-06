defmodule Jido.AI.ProviderRegistrySimpleTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping

  describe "Provider registry functionality" do
    test "Provider.providers/0 returns a list of provider tuples" do
      providers = Provider.providers()

      assert is_list(providers)
      assert length(providers) > 5

      # Should include legacy providers
      provider_ids = Enum.map(providers, fn {id, _} -> id end)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      assert :google in provider_ids
    end

    test "Provider.list/0 returns provider structs" do
      providers = Provider.list()

      assert is_list(providers)
      assert Enum.all?(providers, &is_struct(&1, Provider))

      # Find a known provider
      openai = Enum.find(providers, &(&1.id == :openai))
      assert openai != nil
      assert openai.name == "OpenAI"
      assert is_boolean(openai.requires_api_key)
    end

    test "Provider.get_adapter_by_id/1 works with legacy providers" do
      assert {:ok, Jido.AI.Provider.OpenAI} = Provider.get_adapter_by_id(:openai)
    end

    test "ProviderMapping.supported_providers/0 returns ReqLLM providers" do
      providers = ProviderMapping.supported_providers()

      assert is_list(providers)
      # ReqLLM has many providers
      assert length(providers) > 30

      # Should include expected providers
      assert :openai in providers
      assert :anthropic in providers
      assert :mistral in providers
    end

    test "ProviderMapping.get_jido_provider_metadata/1 returns metadata" do
      {:ok, metadata} = ProviderMapping.get_jido_provider_metadata(:openai)

      assert metadata.id == :openai
      assert is_binary(metadata.name)
      assert is_binary(metadata.description)
      assert metadata.type in [:direct, :proxy]
      assert is_boolean(metadata.requires_api_key)
    end

    test "ProviderMapping.provider_implemented?/1 checks implementation" do
      # Known implemented provider
      assert ProviderMapping.provider_implemented?(:openai) == true

      # Less likely to be implemented
      assert ProviderMapping.provider_implemented?(:nonexistent_provider) == false
    end
  end
end
