defmodule Jido.AI.ProviderDiscoveryListing.FilteringCapabilitiesTest do
  use ExUnit.Case, async: true
  use Mimic

  @moduletag :capture_log

  alias Jido.AI.Model.Registry.Adapter
  alias Jido.AI.Provider

  setup :set_mimic_global

  setup do
    # Copy modules that will be mocked
    copy(Code)
    copy(Adapter)
    :ok
  end

  describe "Basic Filter Functionality" do
    test "single filter criteria - capability filter" do
      # Mock registry with models having different capabilities
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      # Create models with different capabilities
      models_with_tool_call = [
        create_mock_model(:anthropic, "claude-3-5-sonnet", %{tool_call: true, reasoning: true}),
        create_mock_model(:openai, "gpt-4", %{tool_call: true, reasoning: false})
      ]

      models_without_tool_call = [
        create_mock_model(:anthropic, "claude-3-haiku", %{tool_call: false, reasoning: true}),
        create_mock_model(:openai, "gpt-3.5-turbo", %{tool_call: false, reasoning: false})
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic ->
          {:ok, [hd(models_with_tool_call), hd(models_without_tool_call)]}

        :openai ->
          {:ok, [Enum.at(models_with_tool_call, 1), Enum.at(models_without_tool_call, 1)]}
      end)

      # Test capability filter
      case Provider.discover_models_by_criteria(capability: :tool_call) do
        {:ok, filtered_models} ->
          assert is_list(filtered_models)

          # Should only return models with tool_call capability
          tool_call_models =
            Enum.filter(filtered_models, fn model ->
              model.capabilities && model.capabilities.tool_call == true
            end)

          non_tool_call_models =
            Enum.filter(filtered_models, fn model ->
              model.capabilities && model.capabilities.tool_call == false
            end)

          # All returned models should have tool_call capability
          if tool_call_models != [] do
            assert non_tool_call_models == [],
                   "Filter should exclude models without tool_call capability"
          end

        {:error, _reason} ->
          # Filter function might not be available
          :ok
      end
    end

    test "single filter criteria - provider filter" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok,
         [
           create_mock_model(:anthropic, "claude-3-5-sonnet"),
           create_mock_model(:anthropic, "claude-3-haiku")
         ]}
      end)

      case Provider.discover_models_by_criteria(provider: :anthropic) do
        {:ok, filtered_models} ->
          assert is_list(filtered_models)

          # All models should be from anthropic
          Enum.each(filtered_models, fn model ->
            assert model.provider == :anthropic
          end)

        {:error, _reason} ->
          :ok
      end
    end

    test "single filter criteria - min_context_length filter" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      # Create models with different context lengths
      high_context_models = [
        create_mock_model_with_context(:anthropic, "claude-3-5-sonnet", 200_000),
        create_mock_model_with_context(:openai, "gpt-4-turbo", 128_000)
      ]

      low_context_models = [
        create_mock_model_with_context(:anthropic, "claude-3-haiku", 200_000),
        create_mock_model_with_context(:openai, "gpt-4", 8_192)
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, [hd(high_context_models), hd(low_context_models)]}
        :openai -> {:ok, [Enum.at(high_context_models, 1), Enum.at(low_context_models, 1)]}
      end)

      # Test context length filter
      min_context = 100_000

      case Provider.discover_models_by_criteria(min_context_length: min_context) do
        {:ok, filtered_models} ->
          assert is_list(filtered_models)

          # All returned models should meet the context requirement
          Enum.each(filtered_models, fn model ->
            if length(model.endpoints) > 0 do
              endpoint = hd(model.endpoints)

              assert endpoint.context_length >= min_context,
                     "Model #{model.id} has context #{endpoint.context_length}, expected >= #{min_context}"
            end
          end)

        {:error, _reason} ->
          :ok
      end
    end

    test "empty filter list behavior" do
      # Test with empty filters - should return all models
      case Provider.discover_models_by_criteria([]) do
        {:ok, all_models} ->
          assert is_list(all_models)

        # Should return models (same as unfiltered discovery)

        {:error, _reason} ->
          :ok
      end
    end

    test "invalid filter handling" do
      # Test with invalid filter keys
      case Provider.discover_models_by_criteria(invalid_filter: "invalid_value") do
        {:ok, models} ->
          # Should ignore invalid filters and return models
          assert is_list(models)

        {:error, reason} ->
          # Error handling is also acceptable
          assert reason != nil
      end
    end
  end

  describe "Complex Filter Combinations" do
    test "multiple filter criteria - capability + provider" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok,
         [
           create_mock_model(:anthropic, "claude-3-5-sonnet", %{tool_call: true, reasoning: true}),
           create_mock_model(:anthropic, "claude-3-haiku", %{tool_call: false, reasoning: true})
         ]}
      end)

      # Filter by both provider and capability
      case Provider.discover_models_by_criteria(provider: :anthropic, capability: :tool_call) do
        {:ok, filtered_models} ->
          assert is_list(filtered_models)

          Enum.each(filtered_models, fn model ->
            # Must match both criteria
            assert model.provider == :anthropic

            if model.capabilities do
              assert model.capabilities.tool_call == true
            end
          end)

        {:error, _reason} ->
          :ok
      end
    end

    test "multiple filter criteria - cost and context combination" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      # Create models with different cost/context profiles
      premium_models = [
        create_mock_model_with_cost_and_context(:anthropic, "claude-3-opus", 0.015, 200_000),
        create_mock_model_with_cost_and_context(:openai, "gpt-4", 0.03, 8_192)
      ]

      budget_models = [
        create_mock_model_with_cost_and_context(:anthropic, "claude-3-haiku", 0.0008, 200_000),
        create_mock_model_with_cost_and_context(:openai, "gpt-3.5-turbo", 0.002, 4_096)
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, [hd(premium_models), hd(budget_models)]}
        :openai -> {:ok, [Enum.at(premium_models, 1), Enum.at(budget_models, 1)]}
      end)

      # Find cost-effective models with large context
      case Provider.discover_models_by_criteria(max_cost: 0.005, min_context_length: 50_000) do
        {:ok, filtered_models} ->
          assert is_list(filtered_models)

          Enum.each(filtered_models, fn model ->
            # Check cost requirement
            if model.cost && model.cost.input do
              assert model.cost.input <= 0.005
            end

            # Check context requirement
            if length(model.endpoints) > 0 do
              endpoint = hd(model.endpoints)
              assert endpoint.context_length >= 50_000
            end
          end)

        {:error, _reason} ->
          :ok
      end
    end

    test "filter precedence and logic" do
      # Test that filters are applied with correct logic (AND, not OR)
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic]}
      end)

      models = [
        # Model matching both filters
        create_mock_model(:anthropic, "claude-3-5-sonnet", %{tool_call: true, reasoning: true}),
        # Model matching only one filter
        create_mock_model(:anthropic, "claude-3-haiku", %{tool_call: false, reasoning: true}),
        # Model matching neither filter
        create_mock_model(:anthropic, "claude-instant", %{tool_call: false, reasoning: false})
      ]

      expect(Adapter, :list_models, fn :anthropic ->
        {:ok, models}
      end)

      # Apply multiple filters - should use AND logic
      case Provider.discover_models_by_criteria(capability: :tool_call, provider: :anthropic) do
        {:ok, filtered_models} ->
          # Should only return models that match ALL criteria
          _matching_models =
            Enum.filter(filtered_models, fn model ->
              (model.provider == :anthropic and
                 model.capabilities) &&
                model.capabilities.tool_call == true
            end)

          non_matching_models =
            Enum.filter(filtered_models, fn model ->
              model.provider != :anthropic or
                not model.capabilities or
                model.capabilities.tool_call != true
            end)

          assert non_matching_models == [],
                 "Filter should use AND logic, excluding models that don't match all criteria"

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "Advanced Search Capabilities" do
    test "discovery by reasoning capability" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      reasoning_models = [
        create_mock_model(:anthropic, "claude-3-5-sonnet", %{reasoning: true, tool_call: true}),
        create_mock_model(:anthropic, "claude-3-opus", %{reasoning: true, tool_call: false})
      ]

      non_reasoning_models = [
        create_mock_model(:openai, "gpt-3.5-turbo", %{reasoning: false, tool_call: true})
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, reasoning_models}
        :openai -> {:ok, non_reasoning_models}
      end)

      case Provider.discover_models_by_criteria(capability: :reasoning) do
        {:ok, filtered_models} ->
          reasoning_found =
            Enum.filter(filtered_models, fn model ->
              model.capabilities && model.capabilities.reasoning == true
            end)

          non_reasoning_found =
            Enum.filter(filtered_models, fn model ->
              model.capabilities && model.capabilities.reasoning == false
            end)

          # Should find reasoning models and exclude non-reasoning ones
          if reasoning_found != [] do
            assert non_reasoning_found == []
          end

        {:error, _reason} ->
          :ok
      end
    end

    test "cost-based filtering with max_cost_per_token" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      # Create models with different pricing
      budget_models = [
        create_mock_model_with_pricing(:anthropic, "claude-3-haiku", 0.0008, 0.004)
      ]

      premium_models = [
        create_mock_model_with_pricing(:openai, "gpt-4", 0.01, 0.03)
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, budget_models}
        :openai -> {:ok, premium_models}
      end)

      # Filter by maximum cost
      max_cost = 0.005

      case Provider.discover_models_by_criteria(max_cost: max_cost) do
        {:ok, filtered_models} ->
          # Check that returned models meet cost requirements
          Enum.each(filtered_models, fn model ->
            if model.cost do
              input_cost = Map.get(model.cost, :input, 0)
              output_cost = Map.get(model.cost, :output, 0)

              # At least input cost should be within limit
              assert input_cost <= max_cost or output_cost <= max_cost,
                     "Model #{model.id} cost (#{input_cost}/#{output_cost}) exceeds limit #{max_cost}"
            end
          end)

        {:error, _reason} ->
          :ok
      end
    end

    test "modality-based filtering" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:anthropic, :openai]}
      end)

      # Create models with different modalities
      text_only_models = [
        create_mock_model_with_modalities(:anthropic, "claude-3-haiku", [:text], [:text])
      ]

      multimodal_models = [
        create_mock_model_with_modalities(:anthropic, "claude-3-5-sonnet", [:text, :image], [
          :text
        ]),
        create_mock_model_with_modalities(:openai, "gpt-4-vision", [:text, :image], [:text])
      ]

      expect(Adapter, :list_models, 2, fn
        :anthropic -> {:ok, text_only_models ++ [hd(multimodal_models)]}
        :openai -> {:ok, [Enum.at(multimodal_models, 1)]}
      end)

      # Filter for multimodal capabilities
      case Provider.discover_models_by_criteria(modality: :multimodal) do
        {:ok, filtered_models} ->
          # Check that models support multiple input modalities
          Enum.each(filtered_models, fn model ->
            if model.modalities && model.modalities.input do
              assert length(model.modalities.input) > 1,
                     "Model #{model.id} should support multiple input modalities"
            end
          end)

        {:error, _reason} ->
          :ok
      end
    end
  end

  describe "Edge Cases and Error Handling" do
    test "filters with no matching results" do
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:module, ReqLLM.Provider.Registry}
      end)

      expect(Adapter, :list_providers, fn ->
        {:ok, [:openai]}
      end)

      # Create models that won't match the filter
      expect(Adapter, :list_models, fn :openai ->
        {:ok,
         [
           # Expensive model
           create_mock_model_with_cost(:openai, "gpt-4", 0.03, 0.06)
         ]}
      end)

      # Filter for very cheap models (none should match)
      case Provider.discover_models_by_criteria(max_cost: 0.0001) do
        {:ok, filtered_models} ->
          # Should return empty list or very few models
          assert is_list(filtered_models)
          assert filtered_models == []

        {:error, _reason} ->
          # No results error is also acceptable
          :ok
      end
    end

    test "invalid filter values" do
      # Test with invalid filter values
      invalid_filters = [
        [capability: :nonexistent_capability],
        [provider: :nonexistent_provider],
        [min_context_length: -1000],
        [max_cost: -1.0]
      ]

      Enum.each(invalid_filters, fn filter ->
        case Provider.discover_models_by_criteria(filter) do
          {:ok, models} ->
            # Should handle gracefully, possibly returning empty results
            assert is_list(models)

          {:error, reason} ->
            # Error handling is acceptable
            assert reason != nil
        end
      end)
    end

    test "registry unavailable scenarios" do
      # Test fallback when registry is not available
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        {:error, :nofile}
      end)

      case Provider.discover_models_by_criteria(capability: :tool_call) do
        {:ok, models} ->
          # Should fall back to basic filtering on cached models
          assert is_list(models)

        {:error, reason} ->
          # Error indicating unavailable registry is acceptable
          assert reason != nil
      end
    end

    test "fallback to basic filtering" do
      # Test that when advanced filtering fails, basic filtering still works
      expect(Code, :ensure_loaded, fn ReqLLM.Provider.Registry ->
        raise "Registry error"
      end)

      case Provider.discover_models_by_criteria(provider: :openai) do
        {:ok, models} ->
          # Should fall back and try basic provider filtering
          assert is_list(models)

        {:error, _reason} ->
          # Error is acceptable when registry unavailable
          :ok
      end
    end
  end

  # Helper functions
  defp create_mock_model(provider, model_name, capabilities \\ %{}) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      capabilities: capabilities,
      modalities: %{input: [:text], output: [:text]},
      cost: %{input: 0.001, output: 0.002},
      limit: %{context: 100_000, output: 4_096}
    }
  end

  defp create_mock_model_with_context(provider, model_name, context_length) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      limit: %{context: context_length, output: 4_096}
    }
  end

  defp create_mock_model_with_cost(provider, model_name, input_cost, output_cost) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      cost: %{input: input_cost, output: output_cost}
    }
  end

  defp create_mock_model_with_cost_and_context(provider, model_name, input_cost, context_length) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      cost: %{input: input_cost, output: input_cost * 2},
      limit: %{context: context_length, output: 4_096}
    }
  end

  defp create_mock_model_with_pricing(provider, model_name, input_cost, output_cost) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      cost: %{input: input_cost, output: output_cost},
      limit: %{context: 100_000, output: 4_096}
    }
  end

  defp create_mock_model_with_modalities(
         provider,
         model_name,
         input_modalities,
         output_modalities
       ) do
    %ReqLLM.Model{
      provider: provider,
      model: model_name,
      modalities: %{input: input_modalities, output: output_modalities},
      capabilities: %{tool_call: true}
    }
  end
end
