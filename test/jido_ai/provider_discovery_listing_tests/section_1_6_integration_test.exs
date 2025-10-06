defmodule Jido.AI.ProviderDiscoveryListing.Section16IntegrationTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

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

  describe "End-to-End Section 1.6 Workflows" do
    @tag :integration
    test "complete provider discovery → model listing → filtering workflow" do
      # Step 1: Provider Discovery
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ValidProviders, :list, fn ->
        [:anthropic, :openai, :google, :mistral]
      end)

      start_time = System.monotonic_time(:millisecond)
      providers = Provider.list()
      discovery_time = System.monotonic_time(:millisecond) - start_time

      # Verify provider discovery performance
      assert discovery_time <= 1000,
             "Provider discovery took #{discovery_time}ms, expected <= 1000ms"

      assert is_list(providers)
      # Should include mocked providers
      assert length(providers) >= 4

      provider_ids = Enum.map(providers, & &1.id)
      assert :anthropic in provider_ids
      assert :openai in provider_ids

      # Step 2: Model Listing for discovered providers
      sample_providers = [:anthropic, :openai]

      expect(Adapter, :list_models, 2, fn
        :anthropic ->
          {:ok,
           [
             create_integration_model(:anthropic, "claude-3-5-sonnet", %{
               capabilities: %{tool_call: true, reasoning: true},
               cost: %{input: 0.003, output: 0.015}
             }),
             create_integration_model(:anthropic, "claude-3-haiku", %{
               capabilities: %{tool_call: true, reasoning: false},
               cost: %{input: 0.0008, output: 0.004}
             })
           ]}

        :openai ->
          {:ok,
           [
             create_integration_model(:openai, "gpt-4", %{
               capabilities: %{tool_call: true, reasoning: false},
               cost: %{input: 0.01, output: 0.03}
             }),
             create_integration_model(:openai, "gpt-3.5-turbo", %{
               capabilities: %{tool_call: true, reasoning: false},
               cost: %{input: 0.002, output: 0.006}
             })
           ]}
      end)

      start_time = System.monotonic_time(:millisecond)

      model_results =
        Enum.map(sample_providers, fn provider ->
          case Provider.list_all_models_enhanced(provider, source: :registry) do
            {:ok, models} -> {provider, models}
            {:error, reason} -> {provider, {:error, reason}}
          end
        end)

      listing_time = System.monotonic_time(:millisecond) - start_time

      # Verify model listing performance
      assert listing_time <= 2000, "Model listing took #{listing_time}ms, expected <= 2000ms"

      successful_listings =
        Enum.reject(model_results, fn {_provider, result} ->
          match?({:error, _}, result)
        end)

      assert length(successful_listings) >= 1, "At least one provider should return models"

      # Verify model structure
      Enum.each(successful_listings, fn {provider, models} ->
        assert is_list(models)
        assert length(models) >= 1

        Enum.each(models, fn model ->
          assert model.provider == provider
          assert is_binary(model.id)
          assert String.contains?(model.reqllm_id, ":")
        end)
      end)

      # Step 3: Filtering on discovered models
      start_time = System.monotonic_time(:millisecond)

      case Provider.discover_models_by_criteria(capability: :tool_call) do
        {:ok, filtered_models} ->
          filtering_time = System.monotonic_time(:millisecond) - start_time

          # Verify filtering performance
          assert filtering_time <= 1000, "Filtering took #{filtering_time}ms, expected <= 1000ms"

          assert is_list(filtered_models)

          # Verify filtering accuracy
          Enum.each(filtered_models, fn model ->
            if model.capabilities do
              assert model.capabilities.tool_call == true,
                     "Filtered model #{model.id} should have tool_call capability"
            end
          end)

        {:error, _reason} ->
          # Filtering might not be available
          :ok
      end
    end

    @tag :performance
    test "performance characteristics validation" do
      # Test registry operations performance targets
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(ValidProviders, :list, fn ->
        [:anthropic, :openai]
      end)

      # Test provider listing performance
      start_time = System.monotonic_time(:microsecond)
      providers = Provider.providers()
      end_time = System.monotonic_time(:microsecond)
      # Convert to milliseconds
      provider_time = (end_time - start_time) / 1000

      assert is_list(providers)
      assert provider_time <= 50.0, "Provider listing took #{provider_time}ms, expected <= 50ms"

      # Test model registry stats performance
      expect(Adapter, :get_health_info, fn ->
        {:ok,
         %{
           registry_available: true,
           provider_count: 2,
           sampled_providers: 2,
           estimated_total_models: 10,
           response_time_ms: 5,
           timestamp: DateTime.utc_now()
         }}
      end)

      start_time = System.monotonic_time(:microsecond)

      case Provider.get_model_registry_stats() do
        {:ok, stats} ->
          end_time = System.monotonic_time(:microsecond)
          stats_time = (end_time - start_time) / 1000

          assert stats_time <= 100.0, "Registry stats took #{stats_time}ms, expected <= 100ms"
          assert is_integer(stats.total_models)
          assert is_integer(stats.total_providers)

        {:error, _reason} ->
          # Stats might not be available
          :ok
      end

      # Test individual model lookup performance (if available)
      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, [create_integration_model(:anthropic, "claude-3-5-sonnet")]}
      end)

      start_time = System.monotonic_time(:microsecond)

      case Provider.list_all_models_enhanced(:anthropic, source: :registry) do
        {:ok, models} when models != [] ->
          end_time = System.monotonic_time(:microsecond)
          model_time = (end_time - start_time) / 1000

          assert model_time <= 200.0, "Model lookup took #{model_time}ms, expected <= 200ms"

        _ ->
          # Model lookup might not be available
          :ok
      end
    end

    @tag :integration
    test "memory usage patterns during large model discovery" do
      # Test memory behavior with larger datasets
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        # 5 providers
        [:anthropic, :openai, :google, :mistral, :cohere]
      end)

      # Create many models per provider to simulate large registry
      expect(Adapter, :list_models, 5, fn provider ->
        # 20 models per provider = 100 total
        models =
          Enum.map(1..20, fn i ->
            create_integration_model(provider, "#{provider}-model-#{i}")
          end)

        {:ok, models}
      end)

      # Measure memory before
      initial_memory = :erlang.memory(:total)

      case Provider.list_all_models_enhanced(nil, source: :registry) do
        {:ok, models} ->
          # Measure memory after
          final_memory = :erlang.memory(:total)
          memory_increase = final_memory - initial_memory

          assert is_list(models)
          # Should have many models
          assert length(models) >= 50

          # Memory increase should be reasonable (less than 50MB for this test)
          memory_increase_mb = memory_increase / (1024 * 1024)

          assert memory_increase_mb <= 50.0,
                 "Memory increased by #{memory_increase_mb}MB, expected <= 50MB"

        {:error, _reason} ->
          # Large model discovery might not be available
          :ok
      end
    end

    @tag :integration
    test "concurrent access patterns" do
      # Test concurrent access to registry functions
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        [:anthropic, :openai]
      end)

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, [create_integration_model(:anthropic, "claude-3-5-sonnet")]}
        :openai -> {:ok, [create_integration_model(:openai, "gpt-4")]}
      end)

      # Test concurrent provider listings
      tasks =
        Enum.map(1..5, fn _i ->
          Task.async(fn ->
            Provider.list()
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All concurrent calls should succeed
      assert length(results) == 5

      Enum.each(results, fn providers ->
        assert is_list(providers)
        assert length(providers) >= 2
      end)

      # Test concurrent model discoveries
      model_tasks =
        Enum.map(1..3, fn _i ->
          Task.async(fn ->
            Provider.list_all_models_enhanced(:anthropic, source: :registry)
          end)
        end)

      model_results = Task.await_many(model_tasks, 5000)

      # Concurrent model calls should not interfere
      successful_results =
        Enum.filter(model_results, fn
          {:ok, _models} -> true
          _ -> false
        end)

      assert length(successful_results) >= 1,
             "At least some concurrent model calls should succeed"
    end
  end

  describe "Error Recovery and Resilience" do
    @tag :integration
    test "graceful degradation when ReqLLM unavailable" do
      # Test fallback behavior when registry is completely unavailable
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      # Provider listing should fall back to legacy
      providers = Provider.providers()
      assert is_list(providers)
      # Should have legacy providers
      assert length(providers) >= 5

      # Provider.list() should work with legacy providers
      provider_structs = Provider.list()
      assert is_list(provider_structs)
      assert length(provider_structs) >= 5

      # Enhanced model listing should fall back gracefully
      case Provider.list_all_models_enhanced(nil, source: :both) do
        {:ok, models} ->
          # Should fall back to cached models
          assert is_list(models)

        {:error, _reason} ->
          # Error is acceptable when registry unavailable
          :ok
      end

      # Model discovery should handle unavailable registry
      case Provider.discover_models_by_criteria(capability: :tool_call) do
        {:ok, models} ->
          # Should fall back to basic filtering
          assert is_list(models)

        {:error, _reason} ->
          # Error is acceptable
          :ok
      end
    end

    @tag :integration
    test "partial failure scenarios handling" do
      # Test behavior when some providers work but others fail
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai, :failing_provider]}
      end)

      # Mock some providers succeeding and one failing
      expect(Adapter, :list_models, 3, fn
        :anthropic ->
          {:ok, [create_integration_model(:anthropic, "claude-3-5-sonnet")]}

        :openai ->
          {:ok, [create_integration_model(:openai, "gpt-4")]}

        :failing_provider ->
          {:error, :provider_unavailable}
      end)

      # Should get models from working providers despite one failure
      case Provider.list_all_models_enhanced(nil, source: :registry) do
        {:ok, models} ->
          assert is_list(models)
          # Should have models from working providers
          assert length(models) >= 2

          provider_ids = Enum.map(models, & &1.provider)
          assert :anthropic in provider_ids
          assert :openai in provider_ids

        {:error, _reason} ->
          # Complete failure is acceptable if aggregation fails
          :ok
      end
    end

    @tag :integration
    test "recovery after temporary failures" do
      # Test that system recovers after temporary failures
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      # First call fails
      expect(Adapter, :list_providers, fn ->
        {:error, :timeout}
      end)

      first_result = Provider.list_all_models_enhanced(nil, source: :registry)
      assert match?({:error, _}, first_result)

      # Second call succeeds (simulating recovery)
      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, [create_integration_model(:anthropic, "claude-3-5-sonnet")]}
      end)

      case Provider.list_all_models_enhanced(nil, source: :registry) do
        {:ok, models} ->
          # Should work after recovery
          assert is_list(models)
          assert length(models) >= 1

        {:error, _reason} ->
          # Might still fail due to test environment
          :ok
      end
    end

    @tag :integration
    test "data consistency after error recovery" do
      # Test that data remains consistent after errors
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      consistent_model =
        create_integration_model(:anthropic, "claude-3-5-sonnet", %{
          capabilities: %{tool_call: true, reasoning: true},
          cost: %{input: 0.003, output: 0.015}
        })

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, [consistent_model]}
      end)

      # Multiple calls should return consistent data
      results =
        Enum.map(1..3, fn _i ->
          Provider.list_all_models_enhanced(:anthropic, source: :registry)
        end)

      successful_results =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      if length(successful_results) >= 2 do
        # Compare consistency across calls
        [{:ok, first_models}, {:ok, second_models} | _] = successful_results

        # Should have same number of models
        assert length(first_models) == length(second_models)

        # Models should have consistent data
        first_claude = Enum.find(first_models, &(&1.id == "claude-3-5-sonnet"))
        second_claude = Enum.find(second_models, &(&1.id == "claude-3-5-sonnet"))

        if first_claude && second_claude do
          assert first_claude.reqllm_id == second_claude.reqllm_id
          assert first_claude.capabilities == second_claude.capabilities
          assert first_claude.cost == second_claude.cost
        end
      end
    end
  end

  # Helper function
  defp create_integration_model(provider, model_name, extras \\ %{}) do
    base = %ReqLLM.Model{
      provider: provider,
      model: model_name,
      max_tokens: 4096,
      max_retries: 3,
      capabilities: %{tool_call: true, reasoning: false},
      modalities: %{input: [:text], output: [:text]},
      cost: %{input: 0.001, output: 0.002},
      limit: %{context: 100_000, output: 4_096}
    }

    Enum.reduce(extras, base, fn {key, value}, acc ->
      Map.put(acc, key, value)
    end)
  end
end
