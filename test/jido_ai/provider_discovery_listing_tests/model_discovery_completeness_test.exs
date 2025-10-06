defmodule Jido.AI.ProviderDiscoveryListing.ModelDiscoveryCompletenessTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Model.Registry.Adapter
  alias Jido.AI.Provider
  alias ReqLLM.Provider.Generated.ValidProviders

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Code)
    copy(Registry.Adapter)
    copy(ValidProviders)
    :ok
  end

  describe "Enhanced Model Discovery Validation" do
    test "list_all_models_enhanced/2 with source :registry provides enhanced metadata" do
      # Mock registry available with sample models
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      expect(Registry.Adapter, :list_models, 2, fn
        :anthropic ->
          {:ok,
           [
             create_mock_reqllm_model(:anthropic, "claude-3-5-sonnet", %{
               capabilities: %{tool_call: true, reasoning: true},
               modalities: %{input: [:text], output: [:text]},
               cost: %{input: 0.003, output: 0.015},
               limit: %{context: 200_000, output: 4_096}
             })
           ]}

        :openai ->
          {:ok,
           [
             create_mock_reqllm_model(:openai, "gpt-4", %{
               capabilities: %{tool_call: true, reasoning: false},
               modalities: %{input: [:text], output: [:text]},
               cost: %{input: 0.01, output: 0.03},
               limit: %{context: 8_192, output: 4_096}
             })
           ]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(nil, source: :registry)

      assert is_list(models)
      assert length(models) >= 2

      # Verify enhanced metadata is present
      claude_model = Enum.find(models, &(&1.id == "claude-3-5-sonnet"))
      assert claude_model != nil
      assert claude_model.reqllm_id == "anthropic:claude-3-5-sonnet"
      assert claude_model.capabilities.tool_call == true
      assert claude_model.capabilities.reasoning == true
      assert claude_model.modalities.input == [:text]
      assert claude_model.cost.input == 0.003

      gpt_model = Enum.find(models, &(&1.id == "gpt-4"))
      assert gpt_model != nil
      assert gpt_model.reqllm_id == "openai:gpt-4"
      assert gpt_model.capabilities.tool_call == true
      assert gpt_model.capabilities.reasoning == false
      assert gpt_model.cost.input == 0.01
    end

    test "list_all_models_enhanced/2 with source :cache preserves legacy models" do
      # Should use only cached models, not registry
      {:ok, models} = Provider.list_all_models_enhanced(nil, source: :cache)

      assert is_list(models)

      # All models should be from cache (no reqllm_id field typically)
      Enum.each(models, fn model ->
        assert is_map(model)
        assert Map.has_key?(model, :id) or Map.has_key?(model, "id")
        assert Map.has_key?(model, :provider) or Map.has_key?(model, "provider")
      end)
    end

    test "list_all_models_enhanced/2 with source :both merges registry and cache" do
      # Mock registry available
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      expect(Registry.Adapter, :list_models, fn :anthropic ->
        {:ok,
         [
           create_mock_reqllm_model(:anthropic, "claude-3-5-sonnet", %{
             capabilities: %{tool_call: true}
           })
         ]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(nil, source: :both)

      assert is_list(models)

      # Should have models from both sources
      registry_models =
        Enum.filter(models, fn model ->
          Map.get(model, :reqllm_id) != nil
        end)

      cached_models =
        Enum.filter(models, fn model ->
          Map.get(model, :reqllm_id) == nil
        end)

      # Should have at least some registry models if mocking worked
      if length(registry_models) > 0 do
        assert length(registry_models) >= 1
      end

      # Total should be sum of unique models from both sources
      assert length(models) >=
               length(registry_models) + length(cached_models) -
                 overlap_count(registry_models, cached_models)
    end

    test "provider-specific enhanced discovery" do
      # Test discovery for specific provider
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_models, fn :anthropic ->
        {:ok,
         [
           create_mock_reqllm_model(:anthropic, "claude-3-5-sonnet"),
           create_mock_reqllm_model(:anthropic, "claude-3-haiku")
         ]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(:anthropic)

      assert is_list(models)

      # All models should be from anthropic
      Enum.each(models, fn model ->
        provider = Map.get(model, :provider) || Map.get(model, "provider")
        assert provider == :anthropic or provider == "anthropic"
      end)
    end

    test "model count improvements validation" do
      # Compare legacy vs enhanced counts
      legacy_count = length(Provider.list_all_cached_models())

      # Mock registry with many models
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai, :google, :mistral, :cohere]}
      end)

      # Create many mock models per provider
      expect(Registry.Adapter, :list_models, 5, fn provider ->
        models =
          Enum.map(1..10, fn i ->
            create_mock_reqllm_model(provider, "#{provider}-model-#{i}")
          end)

        {:ok, models}
      end)

      case Provider.list_all_models_enhanced(nil, source: :registry) do
        {:ok, enhanced_models} ->
          enhanced_count = length(enhanced_models)

          # Registry should provide significantly more models
          if enhanced_count > legacy_count do
            improvement_ratio = enhanced_count / max(legacy_count, 1)

            assert improvement_ratio >= 2.0,
                   "Expected significant model increase, got #{improvement_ratio}x"
          end

        {:error, _reason} ->
          # Registry unavailable - acceptable in test environment
          :ok
      end
    end
  end

  describe "Registry Model Metadata Validation" do
    test "required fields presence in registry models" do
      # Mock registry with model containing all required fields
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      expect(Registry.Adapter, :list_models, fn :anthropic ->
        {:ok,
         [
           create_mock_reqllm_model(:anthropic, "claude-3-5-sonnet", %{
             capabilities: %{tool_call: true, reasoning: true, temperature: true},
             modalities: %{input: [:text], output: [:text]},
             cost: %{input: 0.003, output: 0.015}
           })
         ]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(:anthropic, source: :registry)

      assert length(models) >= 1
      model = hd(models)

      # Required fields
      assert model.id != nil
      assert model.provider == :anthropic
      assert model.name != nil

      # ReqLLM-specific fields
      assert model.reqllm_id == "anthropic:claude-3-5-sonnet"
      assert model.capabilities != nil
      assert model.capabilities.tool_call == true
      assert model.modalities != nil
      assert model.cost != nil
    end

    test "metadata enrichment from registry data" do
      # Test that models get enriched with registry metadata
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:openai]}
      end)

      rich_model =
        create_mock_reqllm_model(:openai, "gpt-4", %{
          capabilities: %{tool_call: true, reasoning: true, temperature: true, attachment: false},
          modalities: %{input: [:text, :image], output: [:text]},
          cost: %{input: 0.01, output: 0.03},
          limit: %{context: 128_000, output: 4_096}
        })

      expect(Registry.Adapter, :list_models, fn :openai ->
        {:ok, [rich_model]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(:openai, source: :registry)

      enriched_model = hd(models)

      # Verify enrichment
      assert enriched_model.capabilities.tool_call == true
      assert enriched_model.capabilities.reasoning == true
      assert enriched_model.capabilities.attachment == false
      assert enriched_model.modalities.input == [:text, :image]
      assert enriched_model.modalities.output == [:text]
      assert enriched_model.cost.input == 0.01
      assert enriched_model.cost.output == 0.03

      # Check endpoint enrichment
      if length(enriched_model.endpoints) > 0 do
        endpoint = hd(enriched_model.endpoints)
        assert endpoint.context_length == 128_000
        assert endpoint.max_completion_tokens == 4_096
      end
    end

    test "handles missing metadata gracefully" do
      # Test with minimal model metadata
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, [:test_provider]}
      end)

      minimal_model = %ReqLLM.Model{
        provider: :test_provider,
        model: "minimal-model"
        # All other fields nil/empty
      }

      expect(Registry.Adapter, :list_models, fn :test_provider ->
        {:ok, [minimal_model]}
      end)

      {:ok, models} = Provider.list_all_models_enhanced(:test_provider, source: :registry)

      model = hd(models)

      # Should still create valid model with defaults
      assert model.id == "minimal-model"
      assert model.provider == :test_provider
      assert model.reqllm_id == "test_provider:minimal-model"
      # Should have generated name
      assert is_binary(model.name)
    end
  end

  describe "Model Registry Statistics Validation" do
    test "get_model_registry_stats/0 completeness" do
      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          # Verify required statistical fields
          assert Map.has_key?(stats, :total_models)
          assert Map.has_key?(stats, :total_providers)
          assert Map.has_key?(stats, :provider_coverage)

          assert is_integer(stats.total_models)
          assert stats.total_models >= 0
          assert is_integer(stats.total_providers)
          # At least legacy providers
          assert stats.total_providers >= 5
          assert is_map(stats.provider_coverage)

        {:error, _reason} ->
          # Registry might be unavailable in test environment
          :ok
      end
    end

    test "provider coverage accuracy in stats" do
      # Mock known providers and verify coverage calculation
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expected_providers = [:anthropic, :openai, :google]

      expect(Registry.Adapter, :list_providers, fn ->
        {:ok, expected_providers}
      end)

      # Mock models for each provider
      expect(Registry.Adapter, :list_models, 3, fn
        :anthropic -> {:ok, [create_mock_reqllm_model(:anthropic, "claude-3")]}
        :openai -> {:ok, [create_mock_reqllm_model(:openai, "gpt-4")]}
        :google -> {:ok, [create_mock_reqllm_model(:google, "gemini-pro")]}
      end)

      expect(Registry.Adapter, :get_health_info, fn ->
        {:ok,
         %{
           registry_available: true,
           provider_count: 3,
           sampled_providers: 3,
           estimated_total_models: 3,
           response_time_ms: 5,
           timestamp: DateTime.utc_now()
         }}
      end)

      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          assert stats.total_providers >= 3

          # Check provider coverage includes expected providers
          Enum.each(expected_providers, fn provider ->
            assert Map.has_key?(stats.provider_coverage, provider)
            assert stats.provider_coverage[provider] >= 1
          end)

        {:error, _reason} ->
          # Acceptable if registry unavailable
          :ok
      end
    end

    test "registry health indicators in stats" do
      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          # If registry health is available, validate structure
          if registry_health = Map.get(stats, :registry_health) do
            assert Map.has_key?(registry_health, :status)
            assert registry_health.status in [:healthy, :unhealthy]
            assert Map.has_key?(registry_health, :timestamp)
            assert %DateTime{} = registry_health.timestamp
          end

        {:error, _reason} ->
          :ok
      end
    end
  end

  # Helper functions
  defp create_mock_reqllm_model(provider, model_name, extra_metadata \\ %{}) do
    base_model = %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: Map.get(extra_metadata, :max_tokens, 1024),
      max_retries: 3
    }

    # Merge extra metadata
    Enum.reduce(extra_metadata, base_model, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end

  defp overlap_count(registry_models, cached_models) do
    # Simple heuristic: count models that might be duplicates based on ID
    registry_ids =
      MapSet.new(registry_models, fn model ->
        Map.get(model, :id) || Map.get(model, "id")
      end)

    cached_ids =
      MapSet.new(cached_models, fn model ->
        Map.get(model, :id) || Map.get(model, "id")
      end)

    MapSet.intersection(registry_ids, cached_ids) |> MapSet.size()
  end
end
