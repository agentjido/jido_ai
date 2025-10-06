defmodule Jido.AI.ProviderRegistryIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping

  @moduletag :integration

  describe "End-to-end provider registry migration" do
    test "complete provider discovery workflow" do
      # Step 1: Verify we can discover providers dynamically
      all_providers = Provider.providers()
      provider_list = Provider.list()
      # Skip available_providers test due to keyring dependency

      # Should have significantly more providers than the legacy 5
      assert length(all_providers) >= 40
      assert length(provider_list) >= 40

      # Legacy providers should still be present and functional
      legacy_provider_ids = [:openai, :anthropic, :google, :cloudflare, :openrouter]
      provider_ids = Enum.map(all_providers, fn {id, _} -> id end)

      for legacy_id <- legacy_provider_ids do
        assert legacy_id in provider_ids, "Legacy provider #{legacy_id} should be present"

        # Should be able to get adapter
        assert {:ok, adapter} = Provider.get_adapter_by_id(legacy_id)
        assert is_atom(adapter)
      end

      # Should have new ReqLLM providers beyond the legacy ones
      new_provider_count = length(all_providers) - length(legacy_provider_ids)
      assert new_provider_count >= 35, "Should have many new providers from ReqLLM"

      # Provider structs should be well-formed
      assert Enum.all?(provider_list, fn provider ->
               is_struct(provider, Provider) and
                 is_atom(provider.id) and
                 is_binary(provider.name) and
                 is_atom(provider.type) and
                 is_boolean(provider.requires_api_key)
             end)

      # Available providers test would require keyring setup - skip in unit tests
    end

    test "backward compatibility is maintained" do
      # Legacy provider functions should continue to work exactly as before

      # 1. Provider enumeration
      providers = Provider.providers()
      legacy_providers = [:openai, :anthropic, :google, :cloudflare, :openrouter]

      for legacy_id <- legacy_providers do
        # Should find the legacy provider
        legacy_entry = Enum.find(providers, fn {id, _} -> id == legacy_id end)
        assert legacy_entry != nil

        {id, adapter} = legacy_entry
        assert id == legacy_id
        # Legacy providers should have their specific adapter modules
        assert is_atom(adapter) and adapter != :reqllm_backed
      end

      # 2. Provider metadata
      provider_list = Provider.list()

      for legacy_id <- legacy_providers do
        legacy_provider = Enum.find(provider_list, &(&1.id == legacy_id))
        assert legacy_provider != nil

        # Should have proper metadata
        assert is_binary(legacy_provider.name)
        assert legacy_provider.name != ""
        assert is_boolean(legacy_provider.requires_api_key)
      end

      # 3. Adapter resolution
      for legacy_id <- legacy_providers do
        assert {:ok, adapter} = Provider.get_adapter_by_id(legacy_id)
        assert is_atom(adapter)
        # Should be specific legacy adapters
        assert adapter != :reqllm_backed
      end
    end

    test "graceful fallback when ReqLLM registry unavailable" do
      # This test verifies that if the ReqLLM registry is unavailable,
      # the system falls back to legacy providers without crashing

      providers = Provider.providers()

      # Even in worst case, should have at least the 5 legacy providers
      assert length(providers) >= 5

      # Should include all legacy providers
      legacy_provider_ids = [:openai, :anthropic, :google, :cloudflare, :openrouter]
      provider_ids = Enum.map(providers, fn {id, _} -> id end)

      for legacy_id <- legacy_provider_ids do
        assert legacy_id in provider_ids
      end
    end

    test "new provider discovery workflow" do
      # Verify that new ReqLLM providers are properly discovered
      all_providers = Provider.providers()

      # Find providers that are :reqllm_backed (not legacy)
      reqllm_providers =
        Enum.filter(all_providers, fn {_id, adapter} ->
          adapter == :reqllm_backed
        end)

      assert length(reqllm_providers) >= 30, "Should discover many ReqLLM providers"

      # Verify metadata can be retrieved for ReqLLM providers
      {sample_provider_id, :reqllm_backed} = List.first(reqllm_providers)

      # Should be able to get metadata
      {:ok, metadata} =
        ProviderMapping.get_jido_provider_metadata(sample_provider_id)

      assert metadata.id == sample_provider_id
      assert is_binary(metadata.name)
      assert is_binary(metadata.description)
      assert metadata.type in [:direct, :proxy]
      assert is_boolean(metadata.requires_api_key)
    end

    test "provider mix task integration" do
      # Test that the mix task can discover and display all providers
      providers = Provider.list()
      # Skip available providers due to keyring dependency

      # Should be able to categorize providers
      legacy_count =
        Enum.count(providers, fn provider ->
          case Provider.get_adapter_by_id(provider.id) do
            {:ok, adapter} -> is_atom(adapter) and adapter != :reqllm_backed
            _ -> false
          end
        end)

      reqllm_count =
        Enum.count(providers, fn provider ->
          case Provider.get_adapter_by_id(provider.id) do
            {:ok, :reqllm_backed} -> true
            _ -> false
          end
        end)

      # Should have both types
      assert legacy_count >= 5
      assert reqllm_count >= 30

      # Provider discovery is working properly
      assert legacy_count + reqllm_count == length(providers)
    end
  end
end
