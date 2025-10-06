defmodule Jido.AI.ProviderDiscoveryListing.ApiPreservationTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge
  alias ReqLLM.Provider.Generated.ValidProviders

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Code)
    copy(ReqLlmBridge)
    copy(ValidProviders)
    :ok
  end

  describe "Provider API Response Format Consistency" do
    test "Provider.list/0 maintains legacy response structure" do
      # Mock ReqLLM unavailable to test legacy path
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:error, :nofile}
      end)

      providers = Provider.list()

      # Verify response structure
      assert is_list(providers)
      # At least legacy providers
      assert length(providers) >= 5

      # Verify each provider has required fields and types
      Enum.each(providers, fn provider ->
        assert %Provider{} = provider
        assert is_atom(provider.id)
        assert is_binary(provider.name)
        assert is_atom(provider.type) or is_nil(provider.type)
        assert is_boolean(provider.requires_api_key)
        assert is_map(provider.endpoints)
        assert is_list(provider.models)
      end)

      # Verify known legacy providers exist
      provider_ids = Enum.map(providers, & &1.id)
      assert :openai in provider_ids
      assert :anthropic in provider_ids
      assert :google in provider_ids
      assert :cloudflare in provider_ids
      assert :openrouter in provider_ids
    end

    test "Provider.list/0 maintains response structure with ReqLLM available" do
      # Mock ReqLLM available with extended providers
      extended_providers = [:openai, :anthropic, :google, :mistral, :cohere, :groq]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      expect(ValidProviders, :list, fn ->
        extended_providers
      end)

      # Mock successful provider list - metadata will be looked up internally
      # No need to mock get_provider_info as it doesn't exist in the ReqLlmBridge

      providers = Provider.list()

      # Verify enhanced response maintains structure
      assert is_list(providers)
      # Should have more than legacy
      assert length(providers) > 5

      # Verify structure consistency
      Enum.each(providers, fn provider ->
        assert %Provider{} = provider
        assert is_atom(provider.id)
        assert is_binary(provider.name)
        assert provider.type in [:direct, :proxy] or is_nil(provider.type)
        assert is_boolean(provider.requires_api_key)
        assert is_map(provider.endpoints)
        assert is_list(provider.models)
      end)

      # Verify extended providers are included
      provider_ids = Enum.map(providers, & &1.id)
      assert :mistral in provider_ids
      assert :cohere in provider_ids
      assert :groq in provider_ids
    end

    test "Provider.providers/0 maintains tuple format" do
      # Mock ReqLLM unavailable
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:error, :nofile}
      end)

      providers = Provider.providers()

      # Verify tuple format preserved
      assert is_list(providers)
      assert length(providers) >= 5

      Enum.each(providers, fn provider ->
        assert is_tuple(provider)
        assert tuple_size(provider) == 2
        {id, adapter} = provider
        assert is_atom(id)
        assert is_atom(adapter) or (is_atom(adapter) and adapter == :reqllm_backed)
      end)
    end

    test "Provider.get_adapter_module/1 maintains return format" do
      provider = %Provider{id: :openai, name: "OpenAI"}

      result = Provider.get_adapter_module(provider)

      # Should return {:ok, module} or {:error, reason} tuple
      case result do
        {:ok, module} ->
          assert is_atom(module)

        {:error, reason} ->
          assert is_binary(reason) or is_atom(reason)

        other ->
          flunk("Expected {:ok, module} or {:error, reason} tuple, got: #{inspect(other)}")
      end
    end
  end

  describe "Model API Response Format Consistency" do
    test "Provider.list_all_cached_models/0 maintains response structure" do
      models = Provider.list_all_cached_models()

      assert is_list(models)

      # If models exist, verify structure
      if models != [] do
        Enum.each(models, fn model ->
          # Should be a map or struct with required fields
          assert is_map(model)

          # Check for ID field (either :id or "id")
          assert Map.has_key?(model, :id) or Map.has_key?(model, "id")

          # Check for provider field
          assert Map.has_key?(model, :provider) or Map.has_key?(model, "provider")
        end)
      end
    end

    test "Provider.get_combined_model_info/1 maintains response format" do
      # Test with a known model that should exist
      test_models = ["gpt-4", "claude-3", "gemini-pro"]

      Enum.each(test_models, fn model_name ->
        result = Provider.get_combined_model_info(model_name)

        # Should return {:ok, model_info} or {:error, reason}
        case result do
          {:ok, model_info} ->
            assert is_map(model_info)
            # Verify essential fields exist
            assert Map.has_key?(model_info, :id) or Map.has_key?(model_info, "id")
            assert Map.has_key?(model_info, :provider) or Map.has_key?(model_info, "provider")

          {:error, reason} ->
            # Error is acceptable if model not found
            assert is_binary(reason)

          other ->
            flunk("Expected {:ok, model} or {:error, reason}, got: #{inspect(other)}")
        end
      end)
    end

    test "Provider.models/2 maintains response structure when available" do
      # Test with legacy providers
      legacy_providers = [:openai, :anthropic, :google]

      Enum.each(legacy_providers, fn provider_id ->
        result = Provider.models(provider_id, %{})

        case result do
          {:ok, models} ->
            assert is_list(models)
            # Verify model structure if models exist
            if models != [] do
              Enum.each(models, fn model ->
                assert is_map(model)
                assert Map.has_key?(model, :id) or Map.has_key?(model, "id")
              end)
            end

          {:error, reason} ->
            # Error is acceptable
            assert reason != nil

          other ->
            flunk("Expected {:ok, models} or {:error, reason}, got: #{inspect(other)}")
        end
      end)
    end
  end

  describe "Bridge Layer API Consistency" do
    test "ReqLlmBridge functions maintain expected signatures" do
      # Test that bridge functions exist and have proper signatures

      # Test get_provider_key/1 (a function that actually exists)
      result = ReqLlmBridge.get_provider_key(:openai)
      # This function returns the key directly or nil, so just verify it doesn't crash
      assert result == nil or is_binary(result)
    end

    test "Provider metadata structure consistency" do
      # Mock ReqLLM available
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        {:module, ValidProviders}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic]
      end)

      # Metadata will be looked up internally by the provider module
      # No mocking needed for get_provider_info since it doesn't exist

      providers = Provider.list()

      # Verify metadata structure is consistent across providers
      provider_structs = Enum.filter(providers, &(&1.id in [:openai, :anthropic]))

      Enum.each(provider_structs, fn provider ->
        assert provider.name != nil
        assert is_boolean(provider.requires_api_key)
        assert provider.type in [:direct, :proxy] or is_nil(provider.type)
      end)
    end

    test "Error response format preservation" do
      # Mock ReqLLM error scenarios
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
        raise "Network error"
      end)

      # Should gracefully fall back to legacy without raising
      providers = Provider.providers()

      # Should still return valid providers (legacy fallback)
      assert is_list(providers)
      # Legacy providers
      assert length(providers) >= 5
    end
  end

  describe "Backward Compatibility Validation" do
    test "All legacy provider IDs remain accessible" do
      # Ensure these critical provider IDs are always available
      required_legacy_ids = [:openai, :anthropic, :google, :cloudflare, :openrouter]

      # Test both with and without ReqLLM
      test_scenarios = [
        # ReqLLM unavailable
        fn ->
          expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
            {:error, :nofile}
          end)
        end,
        # ReqLLM available
        fn ->
          expect(Code, :ensure_loaded, fn ReqLLM.Provider.Generated.ValidProviders ->
            {:module, ValidProviders}
          end)

          expect(ValidProviders, :list, fn ->
            [:openai, :anthropic, :google, :mistral, :cohere]
          end)

          # No need to stub get_provider_info as it doesn't exist
        end
      ]

      Enum.each(test_scenarios, fn setup_mock ->
        setup_mock.()

        provider_ids = Provider.providers() |> Enum.map(fn {id, _} -> id end)

        Enum.each(required_legacy_ids, fn legacy_id ->
          assert legacy_id in provider_ids,
                 "Required legacy provider #{legacy_id} not found in provider list"
        end)
      end)
    end

    test "Function return types remain consistent" do
      # Test that all major API functions return expected types

      # Provider.list/0 -> [%Provider{}]
      providers = Provider.list()
      assert is_list(providers)

      if length(providers) > 0 do
        assert %Provider{} = hd(providers)
      end

      # Provider.providers/0 -> [{atom(), atom()}]
      providers_tuples = Provider.providers()
      assert is_list(providers_tuples)

      if length(providers_tuples) > 0 do
        {id, adapter} = hd(providers_tuples)
        assert is_atom(id)
        assert is_atom(adapter)
      end

      # Provider.list_all_cached_models/0 -> [map()]
      cached_models = Provider.list_all_cached_models()
      assert is_list(cached_models)
    end

    test "No breaking changes to public API signatures" do
      # Verify that essential function exports exist with correct arities

      # Provider module exports
      provider_exports = Provider.__info__(:functions)

      # Essential functions that must exist
      required_functions = [
        {:list, 0},
        {:providers, 0},
        {:list_all_cached_models, 0},
        {:get_combined_model_info, 1},
        {:get_adapter_module, 1},
        {:base_dir, 0}
      ]

      Enum.each(required_functions, fn {func, arity} ->
        assert {func, arity} in provider_exports,
               "Required function #{func}/#{arity} not found in Provider exports"
      end)
    end
  end
end
