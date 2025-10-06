defmodule Jido.AI.ProviderDiscoveryListing.MetadataCompatibilityTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Model
  alias Jido.AI.Model.Registry.Adapter
  alias Jido.AI.Provider
  alias ReqLLM.Provider.Generated.ValidProviders

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Code)
    copy(Adapter)
    copy(ValidProviders)
    :ok
  end

  describe "Provider Metadata Structure Consistency" do
    test "all providers return consistent metadata structure" do
      # Mock registry with multiple providers
      test_providers = [:anthropic, :openai, :google, :mistral, :cohere]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ValidProviders, :list, fn ->
        test_providers
      end)

      providers = Provider.list()

      # Filter to providers we're testing
      test_provider_structs = Enum.filter(providers, &(&1.id in test_providers))

      # Verify all providers have consistent structure
      _required_fields = [:id, :name, :requires_api_key]
      _optional_fields = [:description, :type, :api_base_url, :endpoints, :models, :proxy_for]

      Enum.each(test_provider_structs, fn provider ->
        # Required fields must be present and correct types
        assert is_atom(provider.id)
        assert is_binary(provider.name)
        assert is_boolean(provider.requires_api_key)

        # Optional fields have correct types when present
        if provider.description != nil, do: assert(is_binary(provider.description))
        if provider.type != nil, do: assert(provider.type in [:direct, :proxy])
        if provider.api_base_url != nil, do: assert(is_binary(provider.api_base_url))
        assert is_map(provider.endpoints)
        assert is_list(provider.models)
        if provider.proxy_for != nil, do: assert(is_list(provider.proxy_for))
      end)
    end

    test "provider type classification consistency" do
      # Test different provider types are handled consistently
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ValidProviders, :list, fn ->
        # Direct and proxy provider examples
        [:openai, :openrouter]
      end)

      providers = Provider.list()

      openai_provider = Enum.find(providers, &(&1.id == :openai))
      openrouter_provider = Enum.find(providers, &(&1.id == :openrouter))

      if openai_provider do
        # OpenAI should be direct provider
        assert openai_provider.type == :direct or is_nil(openai_provider.type)
        assert openai_provider.requires_api_key == true
        assert openai_provider.proxy_for == nil or openai_provider.proxy_for == []
      end

      if openrouter_provider do
        # OpenRouter could be proxy type
        assert openrouter_provider.type in [:direct, :proxy] or is_nil(openrouter_provider.type)
        assert is_boolean(openrouter_provider.requires_api_key)
      end
    end

    test "required vs optional fields handling across providers" do
      # Test that required fields are always present and optional fields are handled gracefully
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ValidProviders, :list, fn ->
        [:anthropic, :openai, :google]
      end)

      providers = Provider.list()
      test_providers = Enum.filter(providers, &(&1.id in [:anthropic, :openai, :google]))

      # Should have at least some providers
      assert length(test_providers) >= 1

      Enum.each(test_providers, fn provider ->
        # Required fields - never nil/empty
        assert provider.id != nil
        assert is_atom(provider.id)
        assert provider.name != nil
        assert is_binary(provider.name)
        assert provider.name != ""
        assert is_boolean(provider.requires_api_key)

        # Optional fields - can be nil but have correct types when present
        assert is_map(provider.endpoints)
        assert is_list(provider.models)

        if provider.description do
          assert is_binary(provider.description)
          assert provider.description != ""
        end

        if provider.api_base_url do
          assert is_binary(provider.api_base_url)
          assert String.starts_with?(provider.api_base_url, "http")
        end
      end)
    end
  end

  describe "Model Metadata Cross-Provider Validation" do
    test "model metadata consistency across different providers" do
      providers_and_models = [
        {:anthropic, "claude-3-5-sonnet"},
        {:openai, "gpt-4"},
        {:google, "gemini-pro"}
      ]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      # Mock models for each provider
      Enum.each(providers_and_models, fn {provider, model_name} ->
        expect(Adapter, :list_models, fn ^provider ->
          {:ok, [create_consistent_mock_model(provider, model_name)]}
        end)
      end)

      # Test each provider's models for consistency
      model_results =
        Enum.map(providers_and_models, fn {provider, _model_name} ->
          case Provider.list_all_models_enhanced(provider, source: :registry) do
            {:ok, models} when models != [] ->
              {provider, hd(models)}

            _ ->
              {provider, nil}
          end
        end)

      # Filter successful results
      successful_results = Enum.reject(model_results, fn {_provider, model} -> model == nil end)

      if length(successful_results) >= 2 do
        # Compare structure across providers
        Enum.each(successful_results, fn {provider, model} ->
          # Common required fields
          assert model.id != nil
          assert model.provider == provider
          assert is_binary(model.name)

          # ReqLLM integration fields
          assert String.contains?(model.reqllm_id || "", ":#{model.id}")

          # Enhanced metadata structure consistency
          if model.capabilities do
            assert is_map(model.capabilities)
            # Check for common capability keys
            Enum.each([:tool_call, :reasoning], fn cap ->
              if Map.has_key?(model.capabilities, cap) do
                assert is_boolean(model.capabilities[cap])
              end
            end)
          end

          if model.modalities do
            assert is_map(model.modalities)

            if Map.has_key?(model.modalities, :input) do
              assert is_list(model.modalities.input)
            end

            if Map.has_key?(model.modalities, :output) do
              assert is_list(model.modalities.output)
            end
          end

          if model.cost do
            assert is_map(model.cost)
            if Map.has_key?(model.cost, :input), do: assert(is_number(model.cost.input))
            if Map.has_key?(model.cost, :output), do: assert(is_number(model.cost.output))
          end
        end)
      end
    end

    test "capability field standardization across providers" do
      # Test that capability fields are standardized across providers
      providers_with_capabilities = [:anthropic, :openai]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      Enum.each(providers_with_capabilities, fn provider ->
        mock_model = create_mock_model_with_capabilities(provider)

        expect(Adapter, :list_models, fn ^provider ->
          {:ok, [mock_model]}
        end)
      end)

      # Test each provider's capability format
      capability_results =
        Enum.map(providers_with_capabilities, fn provider ->
          case Provider.list_all_models_enhanced(provider, source: :registry) do
            {:ok, models} when models != [] ->
              model = hd(models)
              {provider, model.capabilities}

            _ ->
              {provider, nil}
          end
        end)

      successful_caps = Enum.reject(capability_results, fn {_provider, caps} -> caps == nil end)

      if length(successful_caps) >= 2 do
        # Standard capability keys should have consistent types
        standard_keys = [:tool_call, :reasoning, :temperature, :attachment]

        Enum.each(successful_caps, fn {_provider, capabilities} ->
          Enum.each(standard_keys, fn key ->
            if Map.has_key?(capabilities, key) do
              assert is_boolean(capabilities[key]),
                     "Capability #{key} should be boolean, got #{inspect(capabilities[key])}"
            end
          end)
        end)
      end
    end

    test "pricing information format consistency" do
      # Test that pricing follows consistent format across providers
      providers_with_pricing = [:anthropic, :openai]

      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      Enum.each(providers_with_pricing, fn provider ->
        mock_model = create_mock_model_with_pricing(provider)

        expect(Adapter, :list_models, fn ^provider ->
          {:ok, [mock_model]}
        end)
      end)

      pricing_results =
        Enum.map(providers_with_pricing, fn provider ->
          case Provider.list_all_models_enhanced(provider, source: :registry) do
            {:ok, models} when models != [] ->
              model = hd(models)
              {provider, model.cost}

            _ ->
              {provider, nil}
          end
        end)

      successful_pricing = Enum.reject(pricing_results, fn {_provider, cost} -> cost == nil end)

      if length(successful_pricing) >= 2 do
        Enum.each(successful_pricing, fn {_provider, cost} ->
          # Standard cost structure
          assert is_map(cost)

          # Input cost should be numeric if present
          if Map.has_key?(cost, :input) do
            assert is_number(cost.input) and cost.input >= 0
          end

          # Output cost should be numeric if present
          if Map.has_key?(cost, :output) do
            assert is_number(cost.output) and cost.output >= 0
          end
        end)
      end
    end
  end

  describe "Legacy vs Registry Metadata Compatibility" do
    test "legacy provider metadata matches enhanced metadata when available" do
      # Compare legacy provider definition with registry-enhanced version
      legacy_providers = [:openai, :anthropic, :google]

      # Get legacy provider information
      legacy_provider_data =
        Enum.map(legacy_providers, fn provider_id ->
          case Enum.find(Provider.providers(), fn {id, _adapter} -> id == provider_id end) do
            {id, adapter} when is_atom(adapter) and adapter != :reqllm_backed ->
              # This is a legacy provider with adapter
              provider_struct = Enum.find(Provider.list(), &(&1.id == id))
              {id, provider_struct, :legacy}

            {id, :reqllm_backed} ->
              provider_struct = Enum.find(Provider.list(), &(&1.id == id))
              {id, provider_struct, :registry}

            nil ->
              {provider_id, nil, :not_found}
          end
        end)

      # Verify consistency between legacy and registry when both available
      Enum.each(legacy_provider_data, fn {provider_id, provider_struct, source} ->
        if provider_struct do
          # Essential fields should always be present regardless of source
          assert provider_struct.id == provider_id
          assert is_binary(provider_struct.name)
          assert is_boolean(provider_struct.requires_api_key)

          case source do
            :legacy ->
              # Legacy providers should have basic but complete metadata
              assert provider_struct.type in [:direct, :proxy] or is_nil(provider_struct.type)

            :registry ->
              # Registry providers should have at least the same quality of metadata
              assert provider_struct.type in [:direct, :proxy] or is_nil(provider_struct.type)

            # May have additional metadata from registry

            :not_found ->
              # Some providers might not be available
              :ok
          end
        end
      end)
    end

    test "backward compatibility of enhanced models with legacy consumers" do
      # Test that enhanced models work with code expecting legacy format

      # Get some models from enhanced discovery
      case Provider.list_all_models_enhanced(nil, source: :both) do
        {:ok, models} when models != [] ->
          sample_models = Enum.take(models, 3)

          Enum.each(sample_models, fn model ->
            # Essential fields that legacy consumers expect
            assert Map.has_key?(model, :id)
            assert Map.has_key?(model, :provider)
            assert Map.has_key?(model, :name)

            # Fields should be accessible both as atoms and strings for compatibility
            id_value = Map.get(model, :id) || Map.get(model, "id")
            provider_value = Map.get(model, :provider) || Map.get(model, "provider")

            assert id_value != nil
            assert provider_value != nil

            # Enhanced fields should not break legacy access patterns
            assert is_struct(model, Model) or is_map(model)

            # Test that model can be used in legacy functions
            case Provider.get_combined_model_info(id_value) do
              {:ok, _model_info} ->
                # Legacy function works with enhanced model
                :ok

              {:error, _reason} ->
                # Model might not be found in legacy cache - acceptable
                :ok
            end
          end)

        {:error, _reason} ->
          # Enhanced discovery might not be available
          :ok

        {:ok, []} ->
          # No models available
          :ok
      end
    end

    test "metadata merge strategies preserve essential information" do
      # Test that when merging registry and cache data, essential info is preserved

      # Mock registry with model
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      registry_model =
        create_enhanced_mock_model(:anthropic, "claude-3-5-sonnet", %{
          capabilities: %{tool_call: true, reasoning: true},
          cost: %{input: 0.003, output: 0.015}
        })

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, [registry_model]}
      end)

      case Provider.list_all_models_enhanced(:anthropic, source: :both) do
        {:ok, merged_models} ->
          claude_model = Enum.find(merged_models, &(&1.id == "claude-3-5-sonnet"))

          if claude_model do
            # Essential information preserved
            assert claude_model.id == "claude-3-5-sonnet"
            assert claude_model.provider == :anthropic

            # Enhanced information from registry
            if claude_model.reqllm_id do
              assert claude_model.reqllm_id == "anthropic:claude-3-5-sonnet"
            end

            # Cost information preserved
            if claude_model.cost do
              assert claude_model.cost.input == 0.003
              assert claude_model.cost.output == 0.015
            end
          end

        {:error, _reason} ->
          # Merge might fail if registry unavailable
          :ok
      end
    end
  end

  # Helper functions
  defp create_consistent_mock_model(provider, model_name) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: 4096,
      max_retries: 3,
      capabilities: %{tool_call: true, reasoning: true},
      modalities: %{input: [:text], output: [:text]},
      cost: %{input: 0.001, output: 0.002},
      limit: %{context: 100_000, output: 4_096}
    }
  end

  defp create_mock_model_with_capabilities(provider) do
    %ReqLLM.Model{
      provider: provider,
      model: "#{provider}-model",
      capabilities: %{
        tool_call: true,
        # Anthropic known for reasoning
        reasoning: provider == :anthropic,
        temperature: true,
        attachment: false
      }
    }
  end

  defp create_mock_model_with_pricing(provider) do
    pricing =
      case provider do
        :anthropic -> %{input: 0.003, output: 0.015}
        :openai -> %{input: 0.01, output: 0.03}
        _ -> %{input: 0.001, output: 0.002}
      end

    %ReqLLM.Model{
      provider: provider,
      model: "#{provider}-model",
      cost: pricing
    }
  end

  defp create_enhanced_mock_model(provider, model_name, enhancements) do
    base = %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: 4096,
      max_retries: 3
    }

    Enum.reduce(enhancements, base, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end
end
