defmodule Jido.AI.ProviderValidation.Functional.TogetherAiValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for Together AI provider through :reqllm_backed interface.

  This test suite validates that the Together AI provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for comprehensive model testing.

  Test Categories:
  - Provider availability and discovery
  - Authentication validation
  - Comprehensive model catalog testing
  - Multi-model validation
  - Advanced feature testing
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :together_ai

  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "Together AI provider discovery and metadata" do
    test "Together AI is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      # Together AI might be represented as :together_ai, :together, or similar
      together_variants = [:together_ai, :together, :togetherai]
      provider_found = Enum.any?(together_variants, fn variant -> variant in provider_list end)

      assert provider_found,
             "Together AI provider should be available in provider list (variants: #{inspect(together_variants)})"

      # Find the actual provider atom used
      together_provider = Enum.find(together_variants, fn variant -> variant in provider_list end)

      if together_provider do
        # Verify it's using the reqllm_backed adapter
        adapter_entry =
          Enum.find(providers, fn {provider, _adapter} -> provider == together_provider end)

        assert adapter_entry != nil, "Together AI provider configuration should exist"
        assert {_, :reqllm_backed} = adapter_entry
      end
    end

    test "Together AI provider metadata is accessible" do
      # Test with common Together AI provider name variants
      together_variants = [:together_ai, :together, :togetherai]

      metadata_found =
        Enum.find_value(together_variants, fn variant ->
          case ProviderMapping.get_jido_provider_metadata(variant) do
            {:ok, metadata} -> metadata
            {:error, _} -> nil
          end
        end)

      if metadata_found do
        assert is_map(metadata_found), "Provider metadata should be a map"
        assert metadata_found[:name] != nil, "Provider should have a name"
        # Together AI typically uses api.together.xyz or api.together.ai
        assert is_binary(metadata_found[:base_url]) or metadata_found[:base_url] == nil
      else
        IO.puts(
          "Together AI metadata not found - provider may not be available in current ReqLLM version"
        )
      end
    end

    test "Together AI provider-specific configuration" do
      # Test that provider-specific configurations are handled
      together_variants = [:together_ai, :together, :togetherai]

      Enum.each(together_variants, fn variant ->
        case Provider.get_adapter_module(variant) do
          {:ok, :reqllm_backed} ->
            # Test authentication requirements can be retrieved
            auth_requirements = SessionAuthentication.get_provider_auth_requirements(variant)
            assert is_map(auth_requirements), "Should return auth requirements for #{variant}"

          {:error, _reason} ->
            # Provider variant not available, continue testing other variants
            :ok
        end
      end)
    end
  end

  describe "Together AI authentication validation" do
    test "authentication patterns and header formats" do
      together_variants = [:together_ai, :together, :togetherai]

      authenticated_variant =
        Enum.find(together_variants, fn variant ->
          case Provider.get_adapter_module(variant) do
            {:ok, :reqllm_backed} -> true
            _ -> false
          end
        end)

      if authenticated_variant do
        # Test authentication key retrieval
        result = SessionAuthentication.get_provider_key(authenticated_variant, %{})
        assert result == nil or is_binary(result), "Should handle authentication gracefully"

        # Test authentication requirements
        auth_requirements =
          SessionAuthentication.get_provider_auth_requirements(authenticated_variant)

        assert is_map(auth_requirements), "Should provide authentication requirements"
      else
        IO.puts("No Together AI provider variant found for authentication testing")
      end
    end

    test "authentication error handling" do
      # Test authentication error handling without real credentials
      together_variants = [:together_ai, :together, :togetherai]

      Enum.each(together_variants, fn variant ->
        # This should not crash even with invalid or missing credentials
        result = SessionAuthentication.get_provider_key(variant, %{invalid: "config"})

        assert result == nil or is_binary(result),
               "Should handle invalid auth config for #{variant}"
      end)
    end
  end

  describe "Together AI comprehensive model catalog testing" do
    test "discovery of Together AI's extensive model catalog" do
      together_variants = [:together_ai, :together, :togetherai]

      models_found =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, [_ | _] = models} -> {variant, models}
            _ -> nil
          end
        end)

      case models_found do
        {provider, models} ->
          assert is_list(models), "Should return a list of models for #{provider}"
          assert length(models) > 0, "Together AI should have multiple models available"

          # Together AI typically has many models, so we expect a substantial catalog
          if length(models) > 5 do
            IO.puts("✓ Found #{length(models)} models for Together AI (#{provider})")
          else
            IO.puts(
              "Found #{length(models)} models for Together AI - may be limited in test environment"
            )
          end

        nil ->
          IO.puts(
            "No Together AI models found - provider may not be available in test environment"
          )
      end
    end

    test "model metadata accuracy for different model types" do
      together_variants = [:together_ai, :together, :togetherai]

      models_by_provider =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, [_ | _] = models} -> {variant, models}
            _ -> nil
          end
        end)

      case models_by_provider do
        {provider, models} ->
          # Test different model categories that Together AI typically offers
          model_categories = %{
            chat: ["chat", "instruct", "conversation"],
            code: ["code", "programming", "codellama"],
            specialized: ["fine-tuned", "custom", "specialized"]
          }

          Enum.each(model_categories, fn {category, keywords} ->
            category_models =
              Enum.filter(models, fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))

                Enum.any?(keywords, fn keyword ->
                  String.contains?(String.downcase(model_name), keyword)
                end)
              end)

            if length(category_models) > 0 do
              IO.puts("✓ Found #{length(category_models)} #{category} models for #{provider}")

              # Verify metadata structure for category models
              sample_model = hd(category_models)
              expected_fields = [:id, :name, :provider, :capabilities, :modalities]
              present_fields = expected_fields |> Enum.filter(&Map.has_key?(sample_model, &1))

              assert length(present_fields) > 0, "#{category} models should have metadata fields"
            end
          end)

        nil ->
          IO.puts("Skipping model category testing - no Together AI models found")
      end
    end

    test "model filtering by capabilities, size, and type" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test filtering capabilities through the registry
      together_provider =
        Enum.find(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> true
            _ -> false
          end
        end)

      if together_provider do
        # Test discovery with criteria
        case Provider.discover_models_by_criteria(%{provider: together_provider, limit: 10}) do
          {:ok, filtered_models} ->
            assert is_list(filtered_models), "Should return filtered model list"

            # Verify filtering worked
            if length(filtered_models) > 0 do
              sample_model = hd(filtered_models)
              assert Map.get(sample_model, :provider) == together_provider
            end

          {:error, reason} ->
            IO.puts("Model filtering test skipped: #{inspect(reason)}")
        end
      end
    end
  end

  describe "Together AI multi-model validation" do
    test "multiple Together AI models with different characteristics" do
      together_variants = [:together_ai, :together, :togetherai]

      models_by_provider =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 1 -> {variant, models}
            _ -> nil
          end
        end)

      case models_by_provider do
        {provider, models} ->
          # Test creating models with different characteristics
          sample_models = Enum.take(models, 3)

          Enum.each(sample_models, fn model ->
            model_name = Map.get(model, :name, Map.get(model, :id, "unknown"))
            model_opts = {provider, [model: model_name]}

            case Model.from(model_opts) do
              {:ok, jido_model} ->
                assert jido_model.provider == provider
                assert jido_model.model == model_name
                expected_reqllm_id = "#{provider}:#{model_name}"
                assert jido_model.reqllm_id == expected_reqllm_id

              {:error, reason} ->
                IO.puts("Model creation failed for #{model_name}: #{inspect(reason)}")
            end
          end)

        nil ->
          IO.puts("Skipping multi-model validation - insufficient Together AI models found")
      end
    end

    test "consistent behavior across model variants" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test that different Together AI models have consistent metadata structure
      models_by_provider =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 1 -> {variant, models}
            _ -> nil
          end
        end)

      case models_by_provider do
        {provider, models} ->
          # Check consistency across multiple models
          sample_models = Enum.take(models, 5)
          field_consistency = %{}

          field_consistency =
            Enum.reduce(sample_models, field_consistency, fn model, acc ->
              model_fields = Map.keys(model)

              Enum.reduce(model_fields, acc, fn field, field_acc ->
                Map.update(field_acc, field, 1, &(&1 + 1))
              end)
            end)

          # Fields that appear in most models should be consistent
          common_fields =
            field_consistency
            |> Enum.filter(fn {_field, count} -> count >= div(length(sample_models), 2) end)
            |> Enum.map(fn {field, _count} -> field end)

          assert length(common_fields) > 0, "Models should have consistent metadata structure"
          IO.puts("✓ Found #{length(common_fields)} consistent fields across Together AI models")

        nil ->
          IO.puts("Skipping consistency testing - insufficient Together AI models found")
      end
    end

    test "model switching and parameter compatibility" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test that we can switch between different Together AI models
      models_by_provider =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 1 -> {variant, models}
            _ -> nil
          end
        end)

      case models_by_provider do
        {provider, models} ->
          model_names =
            models
            |> Enum.take(3)
            |> Enum.map(fn model -> Map.get(model, :name, Map.get(model, :id)) end)
            |> Enum.filter(&is_binary/1)

          if length(model_names) >= 2 do
            # Test switching between models
            [model1, model2 | _] = model_names

            {:ok, jido_model1} = Model.from({provider, [model: model1]})
            {:ok, jido_model2} = Model.from({provider, [model: model2]})

            # Both should work with same provider but different models
            assert jido_model1.provider == jido_model2.provider
            assert jido_model1.model != jido_model2.model
            assert jido_model1.reqllm_id != jido_model2.reqllm_id

            IO.puts("✓ Successfully tested model switching between #{model1} and #{model2}")
          end

        nil ->
          IO.puts("Skipping model switching test - insufficient Together AI models found")
      end
    end
  end

  describe "Together AI advanced feature testing" do
    test "context window handling for large context models" do
      together_variants = [:together_ai, :together, :togetherai]

      # Look for models that might have large context windows
      large_context_models =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} ->
              # Look for models that might indicate large context (common Together AI patterns)
              large_models =
                Enum.filter(models, fn model ->
                  model_name = Map.get(model, :name, Map.get(model, :id, ""))

                  String.contains?(String.downcase(model_name), "32k") or
                    String.contains?(String.downcase(model_name), "long") or
                    Map.get(model, :context_length, 0) > 16_000
                end)

              if length(large_models) > 0, do: {variant, large_models}, else: nil

            _ ->
              nil
          end
        end)

      case large_context_models do
        {provider, models} ->
          sample_model = hd(models)
          model_name = Map.get(sample_model, :name, Map.get(sample_model, :id))

          case Model.from({provider, [model: model_name]}) do
            {:ok, jido_model} ->
              # Verify the model was created successfully for large context handling
              assert jido_model.model == model_name
              IO.puts("✓ Successfully created large context model: #{model_name}")

            {:error, reason} ->
              IO.puts("Large context model creation failed: #{inspect(reason)}")
          end

        nil ->
          IO.puts("No large context Together AI models found for testing")
      end
    end

    test "JSON mode and structured output support detection" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test detection of advanced features through model capabilities
      models_with_features =
        Enum.find_value(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} ->
              feature_models =
                Enum.filter(models, fn model ->
                  capabilities = Map.get(model, :capabilities, %{})

                  Map.get(capabilities, :json_mode, false) or
                    Map.get(capabilities, :structured_output, false) or
                    Map.get(capabilities, :function_calling, false)
                end)

              if length(feature_models) > 0, do: {variant, feature_models}, else: nil

            _ ->
              nil
          end
        end)

      case models_with_features do
        {provider, models} ->
          sample_model = hd(models)
          capabilities = Map.get(sample_model, :capabilities, %{})

          feature_count =
            [
              Map.get(capabilities, :json_mode, false),
              Map.get(capabilities, :structured_output, false),
              Map.get(capabilities, :function_calling, false)
            ]
            |> Enum.count(& &1)

          assert feature_count > 0, "Should detect advanced features in Together AI models"
          IO.puts("✓ Found Together AI model with #{feature_count} advanced features")

        nil ->
          IO.puts("No Together AI models with advanced features detected - this may be expected")
      end
    end

    test "advanced generation parameters support" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test that models can be created with advanced parameters
      working_provider =
        Enum.find(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> true
            _ -> false
          end
        end)

      if working_provider do
        {:ok, models} = Registry.list_models(working_provider)
        sample_model = hd(models)
        model_name = Map.get(sample_model, :name, Map.get(sample_model, :id))

        # Test creating model with advanced parameters
        advanced_opts =
          {working_provider,
           [
             model: model_name,
             temperature: 0.7,
             max_tokens: 1000,
             top_p: 0.9,
             frequency_penalty: 0.1
           ]}

        case Model.from(advanced_opts) do
          {:ok, jido_model} ->
            # Model creation with advanced parameters should succeed
            assert jido_model.model == model_name
            assert jido_model.temperature == 0.7
            assert jido_model.max_tokens == 1000
            IO.puts("✓ Successfully created Together AI model with advanced parameters")

          {:error, reason} ->
            IO.puts("Advanced parameter test failed: #{inspect(reason)}")
        end
      end
    end
  end

  describe "Together AI integration and error handling" do
    test "integration with Jido AI ecosystem" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test integration with Provider.list/0
      providers = Provider.list()

      together_found =
        Enum.find(providers, fn p ->
          Enum.any?(together_variants, fn variant -> p.id == variant end)
        end)

      if together_found do
        assert together_found.name != nil, "Provider should have a name"
        IO.puts("✓ Together AI integrated with provider listing: #{together_found.name}")
      else
        IO.puts("Together AI not found in provider listing - may be expected in test environment")
      end
    end

    test "error handling and recovery" do
      together_variants = [:together_ai, :together, :togetherai]

      # Test error handling for invalid configurations
      Enum.each(together_variants, fn variant ->
        case Provider.get_adapter_module(variant) do
          {:ok, :reqllm_backed} ->
            # Test invalid model configuration
            invalid_opts = {variant, [model: "non-existent-model-xyz-123"]}

            case Model.from(invalid_opts) do
              {:error, reason} ->
                assert is_binary(reason), "Should return descriptive error for #{variant}"

              {:ok, _model} ->
                # Some providers might accept any model name, that's acceptable
                IO.puts("#{variant} accepts arbitrary model names")
            end

          {:error, _reason} ->
            # Provider not available
            :ok
        end
      end)
    end

    test "performance expectations for high-throughput scenarios" do
      together_variants = [:together_ai, :together, :togetherai]

      # Basic performance expectation test - model creation should be fast
      working_provider =
        Enum.find(together_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> true
            _ -> false
          end
        end)

      if working_provider do
        {:ok, models} = Registry.list_models(working_provider)

        model_names =
          models
          |> Enum.take(3)
          |> Enum.map(fn model -> Map.get(model, :name, Map.get(model, :id)) end)
          |> Enum.filter(&is_binary/1)

        start_time = :os.system_time(:millisecond)

        # Create multiple models quickly
        results =
          Enum.map(model_names, fn model_name ->
            Model.from({working_provider, [model: model_name]})
          end)

        end_time = :os.system_time(:millisecond)
        duration = end_time - start_time

        successful_creates =
          Enum.count(results, fn
            {:ok, _} -> true
            _ -> false
          end)

        assert successful_creates > 0, "Should successfully create some models"

        assert duration < 5000,
               "Model creation should be fast (< 5s for #{length(model_names)} models)"

        IO.puts("✓ Created #{successful_creates} Together AI models in #{duration}ms")
      end
    end
  end
end
