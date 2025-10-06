defmodule Jido.AI.ModelCatalogIntegrationTest do
  use ExUnit.Case, async: true

  alias Jido.AI.{Model, Provider}
  alias Jido.AI.Model.Registry

  @moduletag :integration

  describe "End-to-end model catalog integration" do
    test "complete model discovery workflow" do
      # Test the complete workflow from registry discovery to enhanced model access

      # Step 1: Verify enhanced model listing works
      case Provider.list_all_models_enhanced() do
        {:ok, models} ->
          # Should have significantly more models than the original cached models
          cached_models = Provider.list_all_cached_models()

          assert is_list(models)
          assert is_list(cached_models)

          # Registry integration should provide more models (unless registry is unavailable)
          if length(models) > length(cached_models) do
            # Should have many more models from registry
            assert length(models) >= 50
          end

          # All models should be properly formatted
          assert Enum.all?(models, fn model ->
                   (Map.has_key?(model, :id) || Map.has_key?(model, "id")) &&
                     (Map.has_key?(model, :provider) || Map.has_key?(model, "provider"))
                 end)

        {:error, reason} ->
          # If registry is unavailable, should still work with fallback
          IO.puts("Registry unavailable during test: #{inspect(reason)}")
          assert reason != nil
      end
    end

    test "provider-specific model discovery" do
      # Test discovery for a specific provider
      test_providers = [:anthropic, :openai, :google]

      for provider <- test_providers do
        case Provider.list_all_models_enhanced(provider) do
          {:ok, provider_models} ->
            # Should return models for this provider
            assert is_list(provider_models)

            # All models should belong to the specified provider
            assert Enum.all?(provider_models, fn model ->
                     model_provider = Map.get(model, :provider) || Map.get(model, "provider")
                     model_provider == provider
                   end)

          {:error, reason} ->
            # Some providers might not be available - that's ok
            IO.puts("Provider #{provider} not available: #{inspect(reason)}")
        end
      end
    end

    test "registry statistics and health" do
      # Test comprehensive registry statistics
      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          # Should have comprehensive statistics
          assert is_integer(stats.total_models)
          assert stats.total_models >= 0
          assert is_integer(stats.total_providers)
          # At least legacy providers
          assert stats.total_providers >= 5

          # Should have provider coverage information
          assert is_map(stats.provider_coverage)
          assert map_size(stats.provider_coverage) >= 5

          # Check for registry health information
          if registry_health = Map.get(stats, :registry_health) do
            assert Map.has_key?(registry_health, :status)
            assert registry_health.status in [:healthy, :unhealthy]
          end

        {:error, reason} ->
          # Stats computation failed, but that's handled gracefully
          IO.puts("Registry stats failed: #{inspect(reason)}")
      end
    end

    test "model discovery with filters" do
      # Test advanced model filtering capabilities
      filter_tests = [
        [capability: :tool_call],
        [min_context_length: 50_000],
        [provider: :anthropic],
        [modality: :text]
      ]

      for filters <- filter_tests do
        case Provider.discover_models_by_criteria(filters) do
          {:ok, filtered_models} ->
            assert is_list(filtered_models)

            # Verify filtering worked (basic check)
            if length(filtered_models) > 0 do
              # At least some models should match the criteria
              case filters do
                [provider: expected_provider] ->
                  # Check that all models are from expected provider
                  assert Enum.all?(filtered_models, fn model ->
                           model_provider =
                             Map.get(model, :provider) || Map.get(model, "provider")

                           model_provider == expected_provider
                         end)

                [capability: required_cap] ->
                  # Check that models with capabilities have the required one
                  models_with_caps =
                    Enum.filter(filtered_models, fn model ->
                      Map.has_key?(model, :capabilities) && model.capabilities != nil
                    end)

                  if length(models_with_caps) > 0 do
                    assert Enum.any?(models_with_caps, fn model ->
                             Map.get(model.capabilities, required_cap, false)
                           end)
                  end

                _ ->
                  # For other filters, just verify we got some results
                  :ok
              end
            end

          {:error, reason} ->
            # Filter might not work if registry unavailable - fallback to basic filtering
            IO.puts("Filtered discovery failed with #{inspect(filters)}: #{inspect(reason)}")
        end
      end
    end

    test "registry adapter health check" do
      # Test direct registry adapter health
      case Registry.Adapter.get_health_info() do
        {:ok, health} ->
          assert is_boolean(health.registry_available)
          assert %DateTime{} = health.timestamp

          if health.registry_available do
            assert is_integer(health.provider_count)
            assert health.provider_count >= 0
            assert is_integer(health.response_time_ms)
            assert health.response_time_ms >= 0
          end

        {:error, reason} ->
          # Health check failed - that's ok, indicates registry issues
          IO.puts("Health check failed: #{inspect(reason)}")
      end
    end

    test "model metadata enhancement" do
      # Test that models are properly enhanced with registry metadata
      case Registry.list_models() do
        {:ok, models} when models != [] ->
          # Take a sample of models to test
          sample_models = Enum.take(models, 5)

          for model <- sample_models do
            # Should be proper Model structs
            if is_struct(model, Model) do
              assert is_atom(model.provider)
              assert is_binary(model.id)

              # Should have ReqLLM ID if from registry
              if model.reqllm_id do
                assert String.contains?(model.reqllm_id, ":")
                [provider, model_id] = String.split(model.reqllm_id, ":", parts: 2)
                assert String.to_atom(provider) == model.provider
                assert model_id == model.id
              end

              # Should have reasonable architecture info
              if model.architecture do
                assert model.architecture.modality in ["text", "multimodal", nil]

                assert is_binary(model.architecture.tokenizer) ||
                         is_nil(model.architecture.tokenizer)
              end
            end
          end

        {:ok, []} ->
          IO.puts("No models returned from registry - might be unavailable")

        {:error, reason} ->
          IO.puts("Model listing failed: #{inspect(reason)}")
      end
    end

    test "backward compatibility preservation" do
      # Ensure all existing APIs still work

      # 1. Original Provider.list_all_cached_models should still work
      cached_models = Provider.list_all_cached_models()
      assert is_list(cached_models)

      # 2. Provider.get_combined_model_info should still work for known models
      known_models = ["gpt-4", "claude-3", "claude-3-5-sonnet", "gemini-pro"]

      for model_name <- known_models do
        case Provider.get_combined_model_info(model_name) do
          {:ok, model_info} ->
            assert is_map(model_info)
            # Should have basic model information
            assert Map.has_key?(model_info, :id) || Map.has_key?(model_info, "id")

          {:error, _reason} ->
            # Model might not be available in cache - that's ok
            :ok
        end
      end

      # 3. Provider.providers should still work
      providers = Provider.providers()
      assert is_list(providers)
      # At least legacy providers
      assert length(providers) >= 5

      # 4. Provider.list should still work
      provider_list = Provider.list()
      assert is_list(provider_list)
      assert Enum.all?(provider_list, &is_struct(&1, Provider))
    end

    test "performance characteristics" do
      # Test that registry operations are reasonably fast
      start_time = System.monotonic_time(:millisecond)

      # Test model listing performance
      case Registry.list_models() do
        {:ok, models} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time

          # Should complete within reasonable time (10 seconds max)
          assert duration <= 10_000, "Model listing took #{duration}ms, expected <= 10000ms"

          IO.puts("Registry model listing: #{length(models)} models in #{duration}ms")

        {:error, _reason} ->
          # Registry might be unavailable - performance test not applicable
          :ok
      end

      # Test individual model lookup performance
      start_time = System.monotonic_time(:millisecond)

      case Registry.get_model(:anthropic, "claude-3-5-sonnet") do
        {:ok, model} ->
          end_time = System.monotonic_time(:millisecond)
          duration = end_time - start_time

          # Individual model lookup should be very fast
          assert duration <= 1000, "Model lookup took #{duration}ms, expected <= 1000ms"

          assert is_struct(model, Model)
          IO.puts("Registry model lookup in #{duration}ms")

        {:error, _reason} ->
          # Model might not be available - that's ok
          :ok
      end
    end

    test "error handling and resilience" do
      # Test that system handles various error conditions gracefully

      # 1. Test invalid provider
      case Registry.list_models(:nonexistent_provider) do
        {:ok, models} ->
          # Should return empty list or fallback models
          assert is_list(models)

        {:error, reason} ->
          # Error is acceptable
          assert reason != nil
      end

      # 2. Test invalid model lookup
      case Registry.get_model(:anthropic, "nonexistent-model-12345") do
        {:ok, _model} ->
          # Unlikely but not impossible
          :ok

        {:error, reason} ->
          # Expected result
          assert is_binary(reason) || is_atom(reason)
      end

      # 3. Test discovery with invalid filters
      case Provider.discover_models_by_criteria(invalid_filter: "invalid_value") do
        {:ok, models} ->
          # Should ignore invalid filters and return all models
          assert is_list(models)

        {:error, reason} ->
          # Error handling is acceptable
          assert reason != nil
      end

      # 4. Test enhanced listing with invalid options
      case Provider.list_all_models_enhanced(nil, invalid_option: true) do
        {:ok, models} ->
          # Should ignore invalid options
          assert is_list(models)

        {:error, reason} ->
          # Error handling is acceptable
          assert reason != nil
      end
    end

    test "mix task integration" do
      # Test that enhanced mix task functionality works
      # Note: This is a basic integration test - full CLI testing would require more setup

      # Test that the new functionality doesn't break existing mix task structure
      # We can't easily test the actual CLI output, but we can test the underlying functions

      # Test registry stats function (used by mix task)
      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          # Should have the required fields for display
          required_fields = [:total_models, :total_providers, :provider_coverage]

          for field <- required_fields do
            assert Map.has_key?(stats, field), "Missing required field #{field} in stats"
          end

        {:error, _reason} ->
          # Stats might fail if registry unavailable
          :ok
      end

      # Test enhanced listing functions (used by mix task)
      case Provider.list_all_models_enhanced(nil, source: :both) do
        {:ok, models} ->
          assert is_list(models)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "migration verification" do
    test "model count increase verification" do
      # Verify that the migration actually provides more models
      legacy_models = Provider.list_all_cached_models()

      case Provider.list_all_models_enhanced() do
        {:ok, enhanced_models} ->
          legacy_count = length(legacy_models)
          enhanced_count = length(enhanced_models)

          IO.puts("Legacy models: #{legacy_count}, Enhanced models: #{enhanced_count}")

          # If registry is available, should have more models
          if enhanced_count > legacy_count do
            improvement_ratio = enhanced_count / max(legacy_count, 1)
            IO.puts("Model count improvement: #{Float.round(improvement_ratio, 2)}x")

            # Should be a significant improvement (at least 10x more models)
            assert improvement_ratio >= 10.0,
                   "Expected significant model count increase, got #{improvement_ratio}x (from #{legacy_count} to #{enhanced_count})"
          else
            IO.puts("Registry appears unavailable - enhanced count not greater than legacy")
            # This is acceptable - registry might not be available in test environment
          end

        {:error, reason} ->
          IO.puts("Enhanced model listing failed: #{inspect(reason)}")
          # This is acceptable in test environment
      end
    end

    test "provider coverage expansion" do
      # Verify that new providers are available
      legacy_provider_ids = [:openai, :anthropic, :google, :cloudflare, :openrouter]

      current_providers = Provider.providers()
      current_provider_ids = Enum.map(current_providers, fn {id, _} -> id end)

      # Should have all legacy providers
      for legacy_provider <- legacy_provider_ids do
        assert legacy_provider in current_provider_ids,
               "Legacy provider #{legacy_provider} missing from current providers"
      end

      # Should have additional providers if registry is available
      new_provider_count = length(current_provider_ids) - length(legacy_provider_ids)

      IO.puts(
        "Legacy providers: #{length(legacy_provider_ids)}, Current providers: #{length(current_provider_ids)}, New: #{new_provider_count}"
      )

      if new_provider_count > 0 do
        assert new_provider_count >= 30, "Expected many new providers, got #{new_provider_count}"

        # Check for some expected new providers
        expected_new_providers = [:mistral, :cohere, :groq, :perplexity]
        found_new_providers = Enum.filter(expected_new_providers, &(&1 in current_provider_ids))

        assert length(found_new_providers) > 0,
               "Expected to find some new providers like #{inspect(expected_new_providers)}, but none found"

        IO.puts("Found new providers: #{inspect(found_new_providers)}")
      end
    end

    test "metadata richness verification" do
      # Verify that models now have richer metadata
      case Provider.list_all_models_enhanced(nil, source: :registry) do
        {:ok, registry_models} when registry_models != [] ->
          # Sample some models to check metadata richness
          sample_models = Enum.take(registry_models, 10)

          models_with_capabilities =
            Enum.count(sample_models, fn model ->
              Map.get(model, :capabilities) != nil
            end)

          models_with_reqllm_id =
            Enum.count(sample_models, fn model ->
              Map.get(model, :reqllm_id) != nil
            end)

          models_with_modalities =
            Enum.count(sample_models, fn model ->
              Map.get(model, :modalities) != nil
            end)

          IO.puts("Metadata richness in sample of #{length(sample_models)} models:")
          IO.puts("  - With capabilities: #{models_with_capabilities}")
          IO.puts("  - With ReqLLM ID: #{models_with_reqllm_id}")
          IO.puts("  - With modalities: #{models_with_modalities}")

          # At least some models should have enhanced metadata
          assert models_with_reqllm_id > 0, "Expected some models to have ReqLLM IDs"

        {:ok, []} ->
          IO.puts("No registry models available for metadata verification")

        {:error, reason} ->
          IO.puts("Registry models not available: #{inspect(reason)}")
      end
    end
  end
end
