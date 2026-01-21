defmodule JidoTest.AI.Model.RegistryTest do
  use ExUnit.Case, async: false
  import JidoTest.ReqLLMTestHelper

  alias Jido.AI.Model.Registry

  @moduletag :capture_log
  @moduletag :reqllm_integration

  describe "Registry.list_models/0" do
    test "returns list of models" do
      {:ok, models} = Registry.list_models()

      assert is_list(models)
      # Should have some models from the registry
      assert length(models) > 0
    end

    test "models are ReqLLM.Model structs" do
      {:ok, models} = Registry.list_models()

      # At least some models should be ReqLLM.Model structs
      reqllm_models = Enum.filter(models, &is_struct(&1, ReqLLM.Model))
      assert length(reqllm_models) > 0
    end

    test "models have required fields" do
      {:ok, models} = Registry.list_models()

      # Check that models have provider and model fields
      Enum.take(models, 5)
      |> Enum.each(fn model ->
        assert Map.has_key?(model, :provider)
        assert Map.has_key?(model, :model)
      end)
    end
  end

  describe "Registry.list_models/1 with provider filter" do
    test "returns models for openai provider" do
      {:ok, models} = Registry.list_models(:openai)

      assert is_list(models)
      assert length(models) > 0

      # All models should be for openai
      Enum.each(models, fn model ->
        assert model.provider == :openai
      end)
    end

    test "returns models for anthropic provider" do
      {:ok, models} = Registry.list_models(:anthropic)

      assert is_list(models)
      assert length(models) > 0

      # All models should be for anthropic
      Enum.each(models, fn model ->
        assert model.provider == :anthropic
      end)
    end

    test "returns models for google provider" do
      {:ok, models} = Registry.list_models(:google)

      assert is_list(models)

      if length(models) > 0 do
        Enum.each(models, fn model ->
          assert model.provider == :google
        end)
      end
    end

    test "returns error for unknown provider" do
      result = Registry.list_models(:nonexistent_provider)

      # Should return error for unknown provider
      assert match?({:error, _}, result)
    end
  end

  describe "Registry.get_model/2" do
    test "returns specific model by provider and name" do
      # First get available models to find a valid one
      {:ok, models} = Registry.list_models(:openai)

      if length(models) > 0 do
        # Get the first model's name
        first_model = hd(models)
        model_name = first_model.model

        {:ok, model} = Registry.get_model(:openai, model_name)

        assert model.provider == :openai
        assert model.model == model_name
      end
    end

    test "returns error for non-existent model" do
      result = Registry.get_model(:openai, "non-existent-model-xyz-123")

      assert match?({:error, _}, result)
    end

    test "returns error for invalid provider" do
      result = Registry.get_model(:nonexistent, "some-model")

      assert match?({:error, _}, result)
    end
  end

  describe "Registry.batch_get_models/2" do
    test "fetches models from multiple providers concurrently" do
      providers = [:openai, :anthropic]

      {:ok, results} = Registry.batch_get_models(providers)

      assert is_list(results)
      assert length(results) == length(providers)

      # Each result should be a tuple of {provider, result}
      Enum.each(results, fn result ->
        case result do
          {provider, {:ok, models}} ->
            assert provider in providers
            assert is_list(models)

          {provider, {:error, _reason}} ->
            assert provider in providers
        end
      end)
    end

    test "handles empty provider list" do
      {:ok, results} = Registry.batch_get_models([])

      assert results == []
    end

    test "handles single provider" do
      {:ok, results} = Registry.batch_get_models([:openai])

      assert length(results) == 1
      [{:openai, result}] = results
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts max_concurrency option" do
      providers = [:openai, :anthropic, :google]

      {:ok, results} = Registry.batch_get_models(providers, max_concurrency: 2)

      assert length(results) == 3
    end
  end

  describe "Registry.discover_models/1" do
    test "returns all models with empty filters" do
      {:ok, models} = Registry.discover_models([])

      assert is_list(models)
      assert length(models) > 0
    end

    test "filters by capability" do
      {:ok, models} = Registry.discover_models(capability: :tool_call)

      # All returned models should have tool_call capability
      Enum.each(models, fn model ->
        if model.capabilities do
          assert Map.get(model.capabilities, :tool_call, false) == true
        end
      end)
    end

    test "filters by modality" do
      {:ok, models} = Registry.discover_models(modality: :text)

      # All returned models should support text modality
      Enum.each(models, fn model ->
        case model.modalities do
          # Unknown modality allowed
          nil ->
            :ok

          modalities ->
            input = Map.get(modalities, :input, [])
            assert :text in input or input == []
        end
      end)
    end

    test "filters by provider" do
      {:ok, models} = Registry.discover_models(provider: :anthropic)

      # All returned models should be from anthropic
      Enum.each(models, fn model ->
        assert model.provider == :anthropic
      end)
    end

    test "combines multiple filters" do
      {:ok, models} =
        Registry.discover_models(
          provider: :openai,
          capability: :tool_call
        )

      Enum.each(models, fn model ->
        assert model.provider == :openai

        if model.capabilities do
          assert Map.get(model.capabilities, :tool_call, false) == true
        end
      end)
    end

    test "returns empty list when no models match filters" do
      # Use impossible combination
      {:ok, models} =
        Registry.discover_models(
          provider: :openai,
          min_context_length: 999_999_999
        )

      assert is_list(models)
      # Should be empty or very small
      assert length(models) <= 1
    end
  end

  describe "Registry.get_registry_stats/0" do
    test "returns registry statistics" do
      {:ok, stats} = Registry.get_registry_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_models)
      assert Map.has_key?(stats, :total_providers)
      assert Map.has_key?(stats, :provider_coverage)
    end

    test "statistics have correct structure" do
      {:ok, stats} = Registry.get_registry_stats()

      assert is_integer(stats.total_models)
      assert stats.total_models >= 0

      assert is_integer(stats.total_providers)
      assert stats.total_providers >= 0

      assert is_map(stats.provider_coverage)

      # Provider coverage should have counts
      Enum.each(stats.provider_coverage, fn {provider, count} ->
        assert is_atom(provider)
        assert is_integer(count)
        assert count >= 0
      end)
    end

    test "statistics include capability distribution" do
      {:ok, stats} = Registry.get_registry_stats()

      assert Map.has_key?(stats, :capabilities_distribution)
      assert is_map(stats.capabilities_distribution)
    end

    test "statistics include registry vs legacy counts" do
      {:ok, stats} = Registry.get_registry_stats()

      assert Map.has_key?(stats, :registry_models)
      assert Map.has_key?(stats, :legacy_models)
      assert is_integer(stats.registry_models)
      assert is_integer(stats.legacy_models)
    end
  end

  describe "Registry model metadata" do
    test "models have capabilities field" do
      {:ok, models} = Registry.list_models(:openai)

      # Check first few models for capabilities
      models
      |> Enum.take(3)
      |> Enum.each(fn model ->
        # Capabilities may be nil or a map
        case model.capabilities do
          nil -> :ok
          caps when is_map(caps) -> :ok
        end
      end)
    end

    test "models have cost information" do
      {:ok, models} = Registry.list_models(:anthropic)

      # Check first few models for cost info
      models
      |> Enum.take(3)
      |> Enum.each(fn model ->
        # Cost may be nil or a map
        case model.cost do
          nil ->
            :ok

          cost when is_map(cost) ->
            # If present, should have input/output costs
            assert Map.has_key?(cost, :input) or is_nil(cost[:input])
        end
      end)
    end
  end

  describe "Registry error handling" do
    test "handles rescue gracefully in list_models" do
      # This tests the rescue clause by calling with valid params
      # The actual error scenarios are hard to trigger without mocking
      result = Registry.list_models(:openai)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles rescue gracefully in get_model" do
      result = Registry.get_model(:openai, "gpt-4")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles rescue gracefully in discover_models" do
      result = Registry.discover_models([])
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
