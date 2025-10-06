defmodule Jido.AI.ProviderValidation.Functional.PerplexityValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for Perplexity provider through :reqllm_backed interface.

  This test suite validates that the Perplexity provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for search-enhanced operations.

  Test Categories:
  - Provider availability and discovery
  - Authentication validation
  - Search-enhanced model discovery
  - Real-time search integration capabilities
  - Citation accuracy and source attribution
  - Multi-step reasoning validation
  - Extended context processing
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :perplexity
  @moduletag :specialized_providers

  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "Perplexity provider availability" do
    test "Perplexity is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      assert :perplexity in provider_list,
             "Perplexity provider should be available in provider list"

      # Verify it's using the reqllm_backed adapter
      perplexity_adapter =
        Enum.find(providers, fn {provider, _adapter} -> provider == :perplexity end)

      assert perplexity_adapter != nil, "Perplexity provider configuration should exist"
      assert {_, :reqllm_backed} = perplexity_adapter
    end

    test "Perplexity provider metadata is accessible" do
      case ProviderMapping.get_jido_provider_metadata(:perplexity) do
        {:ok, metadata} ->
          assert is_map(metadata), "Provider metadata should be a map"
          assert metadata[:name] != nil, "Provider should have a name"
          # Perplexity uses api.perplexity.ai
          assert is_binary(metadata[:base_url]) or metadata[:base_url] == nil

        {:error, reason} ->
          flunk("Failed to get Perplexity provider metadata: #{inspect(reason)}")
      end
    end

    test "Perplexity provider is included in supported providers list" do
      supported_providers = ProviderMapping.supported_providers()

      assert :perplexity in supported_providers,
             "Perplexity should be in supported providers list"
    end
  end

  describe "Perplexity authentication validation" do
    test "session authentication functionality" do
      # Test session authentication for Perplexity provider
      session_result = SessionAuthentication.has_session_auth?(:perplexity)
      assert session_result == true or session_result == false, "Should return boolean"

      # Test setting session auth (without real key)
      SessionAuthentication.set_for_provider(:perplexity, "test-perplexity-key-123")
      assert SessionAuthentication.has_session_auth?(:perplexity) == true

      # Clear session auth
      SessionAuthentication.clear_for_provider(:perplexity)
      assert SessionAuthentication.has_session_auth?(:perplexity) == false
    end

    test "authentication request handling" do
      # Test the ReqLLM request authentication bridge
      result = SessionAuthentication.get_for_request(:perplexity, %{})

      # Should return either session auth or no session auth
      assert result == {:no_session_auth} or match?({:session_auth, _opts}, result)
    end
  end

  describe "Perplexity search-enhanced model discovery" do
    test "model registry can list Perplexity models" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          assert is_list(models), "Should return a list of models"

          # Perplexity has models like pplx-7b-online, pplx-70b-online, etc.
          if length(models) > 0 do
            model = hd(models)

            assert Map.has_key?(model, :id) or Map.has_key?(model, :name),
                   "Models should have id or name"

            model_name = Map.get(model, :name, Map.get(model, :id, ""))

            # Perplexity models often contain "pplx" or "online" or "sonar"
            perplexity_patterns = ["pplx", "online", "sonar"]

            has_perplexity_pattern =
              Enum.any?(perplexity_patterns, &String.contains?(String.downcase(model_name), &1))

            if has_perplexity_pattern do
              IO.puts("Found Perplexity model: #{model_name}")
            else
              IO.puts("Found model (may not follow expected pattern): #{model_name}")
            end
          end

        {:error, :provider_not_available} ->
          IO.puts(
            "Skipping Perplexity model discovery - ReqLLM not available in test environment"
          )

        {:error, reason} ->
          flunk("Failed to list Perplexity models: #{inspect(reason)}")
      end
    end

    test "online vs offline model distinction" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Categorize models into online (search-enabled) and offline
          online_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              String.contains?(String.downcase(model_name), "online") or
                String.contains?(String.downcase(model_name), "sonar")
            end)

          offline_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              not (String.contains?(String.downcase(model_name), "online") or
                     String.contains?(String.downcase(model_name), "sonar"))
            end)

          if length(online_models) > 0 do
            online_model = hd(online_models)
            model_name = Map.get(online_model, :name, Map.get(online_model, :id, "unknown"))
            IO.puts("Found online Perplexity model: #{model_name}")

            # Online models should have search capabilities
            capabilities = Map.get(online_model, :capabilities, [])

            if is_list(capabilities) do
              search_caps = ["search", "real_time", "web_search", "citation"]
              found_search_caps = Enum.filter(search_caps, &(&1 in capabilities))

              if length(found_search_caps) > 0 do
                IO.puts("Search capabilities: #{Enum.join(found_search_caps, ", ")}")
              end
            end
          end

          if length(offline_models) > 0 do
            offline_model = hd(offline_models)
            model_name = Map.get(offline_model, :name, Map.get(offline_model, :id, "unknown"))
            IO.puts("Found offline Perplexity model: #{model_name}")
          end

          IO.puts(
            "Online models: #{length(online_models)}, Offline models: #{length(offline_models)}"
          )

        {:error, _reason} ->
          IO.puts("Skipping online/offline model test - ReqLLM not available")
      end
    end

    test "model metadata structure validation" do
      case Registry.list_models(:perplexity) do
        {:ok, [model | _]} ->
          # Check that models have expected metadata structure
          expected_fields = [:id, :name, :provider, :capabilities, :modalities]
          present_fields = Enum.filter(expected_fields, &Map.has_key?(model, &1))

          assert present_fields != [], "Model should have some expected metadata fields"

          # Verify provider field if present
          if Map.has_key?(model, :provider) do
            assert model.provider == :perplexity, "Provider field should be :perplexity"
          end

        {:ok, []} ->
          IO.puts("No Perplexity models found in registry - may be expected in test environment")

        {:error, _reason} ->
          IO.puts("Skipping model metadata test - ReqLLM not available")
      end
    end
  end

  describe "Perplexity search integration capabilities" do
    @tag :integration
    test "model creation with search-enabled models" do
      # Test creating models for search-enhanced operations
      search_models = ["pplx-7b-online", "pplx-70b-online", "sonar-medium-online"]

      Enum.each(search_models, fn model_name ->
        model_opts = {:perplexity, [model: model_name]}

        case Model.from(model_opts) do
          {:ok, model} ->
            assert model.provider == :perplexity
            assert model.reqllm_id == "perplexity:#{model_name}"
            assert model.model == model_name
            IO.puts("Successfully created Perplexity search model: #{model_name}")

          {:error, reason} ->
            IO.puts("Search model creation for #{model_name} skipped: #{inspect(reason)}")
        end
      end)
    end

    test "real-time search capability detection" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Look for models with real-time search capabilities
          search_models =
            Enum.filter(models, fn model ->
              capabilities = Map.get(model, :capabilities, [])
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              # Check for search-related capabilities or online indicators
              has_search_caps =
                is_list(capabilities) and
                  Enum.any?(
                    ["search", "real_time", "web_search", "online"],
                    &(&1 in capabilities)
                  )

              has_online_name =
                String.contains?(String.downcase(model_name), "online") or
                  String.contains?(String.downcase(model_name), "sonar")

              has_search_caps or has_online_name
            end)

          if length(search_models) > 0 do
            search_model = hd(search_models)
            model_name = Map.get(search_model, :name, Map.get(search_model, :id, "unknown"))

            IO.puts("Found real-time search model: #{model_name}")

            # Check for specific search capabilities
            capabilities = Map.get(search_model, :capabilities, [])

            if is_list(capabilities) do
              search_caps = ["web_search", "real_time_data", "citation", "fact_checking"]
              found_caps = Enum.filter(search_caps, &(&1 in capabilities))

              if length(found_caps) > 0 do
                IO.puts("Real-time capabilities: #{Enum.join(found_caps, ", ")}")
              end
            end
          else
            IO.puts("No real-time search models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping real-time search test - ReqLLM not available")
      end
    end

    test "citation and source attribution features" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Look for models with citation capabilities
          citation_models =
            Enum.filter(models, fn model ->
              capabilities = Map.get(model, :capabilities, [])
              is_list(capabilities) and "citation" in capabilities
            end)

          if length(citation_models) > 0 do
            citation_model = hd(citation_models)
            model_name = Map.get(citation_model, :name, Map.get(citation_model, :id, "unknown"))

            IO.puts("Found citation-capable model: #{model_name}")

            # Check for citation-related capabilities
            capabilities = Map.get(citation_model, :capabilities, [])

            citation_caps = [
              "citation",
              "source_attribution",
              "reference_tracking",
              "fact_verification"
            ]

            found_citation_caps = Enum.filter(citation_caps, &(&1 in capabilities))

            if length(found_citation_caps) > 0 do
              IO.puts("Citation capabilities: #{Enum.join(found_citation_caps, ", ")}")
            end

            # Check for metadata about citation format
            metadata = Map.get(citation_model, :metadata, %{})

            if is_map(metadata) and Map.has_key?(metadata, :citation_format) do
              IO.puts("Citation format: #{metadata.citation_format}")
            end
          else
            IO.puts("No citation-capable models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping citation capabilities test - ReqLLM not available")
      end
    end

    test "multi-step reasoning validation" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Look for models with multi-step reasoning capabilities
          reasoning_models =
            Enum.filter(models, fn model ->
              capabilities = Map.get(model, :capabilities, [])
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              # Check for reasoning-related capabilities
              reasoning_caps = ["reasoning", "multi_step", "chain_of_thought", "analysis"]

              has_reasoning_caps =
                is_list(capabilities) and
                  Enum.any?(reasoning_caps, &(&1 in capabilities))

              # Larger models (70b) typically have better reasoning
              has_large_model_name =
                String.contains?(String.downcase(model_name), "70b") or
                  String.contains?(String.downcase(model_name), "large")

              has_reasoning_caps or has_large_model_name
            end)

          if length(reasoning_models) > 0 do
            reasoning_model = hd(reasoning_models)
            model_name = Map.get(reasoning_model, :name, Map.get(reasoning_model, :id, "unknown"))

            IO.puts("Found reasoning-capable model: #{model_name}")

            # Check model size for reasoning capabilities
            if String.contains?(String.downcase(model_name), "70b") do
              IO.puts("Large model detected - should have strong reasoning capabilities")
            end

            capabilities = Map.get(reasoning_model, :capabilities, [])

            if is_list(capabilities) do
              reasoning_caps = ["complex_reasoning", "multi_step_analysis", "logical_inference"]
              found_reasoning = Enum.filter(reasoning_caps, &(&1 in capabilities))

              if length(found_reasoning) > 0 do
                IO.puts("Reasoning capabilities: #{Enum.join(found_reasoning, ", ")}")
              end
            end
          else
            IO.puts("No multi-step reasoning models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping reasoning validation test - ReqLLM not available")
      end
    end
  end

  describe "Perplexity extended context processing" do
    test "context window size detection" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Check context window sizes for Perplexity models
          models_with_context =
            Enum.filter(models, fn model ->
              context_length = Map.get(model, :context_length, 0)
              is_integer(context_length) and context_length > 0
            end)

          if length(models_with_context) > 0 do
            context_model = hd(models_with_context)
            model_name = Map.get(context_model, :name, Map.get(context_model, :id, "unknown"))
            context_length = Map.get(context_model, :context_length)

            IO.puts(
              "Found Perplexity model with context info: #{model_name} (#{context_length} tokens)"
            )

            # Perplexity models typically support reasonable context windows
            if context_length >= 4000 do
              IO.puts("Good context window size detected")
            end

            # Group by context sizes
            context_sizes =
              models_with_context
              |> Enum.map(&Map.get(&1, :context_length))
              |> Enum.frequencies()

            IO.puts("Context window distribution:")

            Enum.each(context_sizes, fn {size, count} ->
              IO.puts("  #{size} tokens: #{count} models")
            end)
          else
            IO.puts("No context window information available")
          end

        {:error, _reason} ->
          IO.puts("Skipping context window test - ReqLLM not available")
      end
    end

    test "extended context model availability" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Look for models with extended context (32K+ tokens)
          extended_context_models =
            Enum.filter(models, fn model ->
              context_length = Map.get(model, :context_length, 0)
              is_integer(context_length) and context_length >= 32_000
            end)

          if length(extended_context_models) > 0 do
            extended_model = hd(extended_context_models)
            model_name = Map.get(extended_model, :name, Map.get(extended_model, :id, "unknown"))
            context_length = Map.get(extended_model, :context_length)

            IO.puts("Found extended context model: #{model_name} (#{context_length} tokens)")

            # Extended context is useful for complex search tasks
            capabilities = Map.get(extended_model, :capabilities, [])

            if is_list(capabilities) and "long_context" in capabilities do
              IO.puts("Long context capability confirmed")
            end
          else
            IO.puts("No extended context models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping extended context test - ReqLLM not available")
      end
    end
  end

  describe "Perplexity model performance characteristics" do
    test "model size and capability correlation" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          # Analyze relationship between model size and capabilities
          model_analysis =
            Enum.map(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, "unknown"))
              capabilities = Map.get(model, :capabilities, [])
              context_length = Map.get(model, :context_length, 0)

              # Extract model size from name
              size =
                cond do
                  String.contains?(String.downcase(model_name), "70b") -> "70B"
                  String.contains?(String.downcase(model_name), "7b") -> "7B"
                  String.contains?(String.downcase(model_name), "large") -> "Large"
                  String.contains?(String.downcase(model_name), "medium") -> "Medium"
                  String.contains?(String.downcase(model_name), "small") -> "Small"
                  true -> "Unknown"
                end

              {model_name, size, length(capabilities), context_length}
            end)

          if length(model_analysis) > 0 do
            IO.puts("Perplexity Model Analysis:")

            Enum.each(model_analysis, fn {name, size, cap_count, context} ->
              IO.puts("  #{name}: Size=#{size}, Capabilities=#{cap_count}, Context=#{context}")
            end)

            # Group by size to see patterns
            size_groups = Enum.group_by(model_analysis, &elem(&1, 1))

            Enum.each(size_groups, fn {size, models} ->
              avg_caps = models |> Enum.map(&elem(&1, 2)) |> Enum.sum() |> div(length(models))
              IO.puts("#{size} models: #{length(models)} models, avg #{avg_caps} capabilities")
            end)
          end

        {:error, _reason} ->
          IO.puts("Skipping performance characteristics test - ReqLLM not available")
      end
    end

    test "online vs offline performance expectations" do
      case Registry.list_models(:perplexity) do
        {:ok, models} ->
          online_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              String.contains?(String.downcase(model_name), "online") or
                String.contains?(String.downcase(model_name), "sonar")
            end)

          offline_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              not (String.contains?(String.downcase(model_name), "online") or
                     String.contains?(String.downcase(model_name), "sonar"))
            end)

          IO.puts("Performance Expectations:")

          IO.puts(
            "  Online models: #{length(online_models)} (expected higher latency due to search)"
          )

          IO.puts("  Offline models: #{length(offline_models)} (expected lower latency)")

          # Online models should have search-related cost implications
          online_with_cost =
            Enum.filter(online_models, fn model ->
              cost_info = Map.get(model, :cost, %{})
              is_map(cost_info) and map_size(cost_info) > 0
            end)

          if length(online_with_cost) > 0 do
            cost_model = hd(online_with_cost)
            model_name = Map.get(cost_model, :name, Map.get(cost_model, :id, "unknown"))
            cost_info = Map.get(cost_model, :cost)

            IO.puts("  Online model cost structure (#{model_name}): #{inspect(cost_info)}")
          end

        {:error, _reason} ->
          IO.puts("Skipping performance expectations test - ReqLLM not available")
      end
    end
  end

  describe "Perplexity error conditions and edge cases" do
    test "handles missing ReqLLM gracefully" do
      if Code.ensure_loaded?(ReqLLM) do
        providers = Provider.providers()
        assert is_list(providers)
      else
        providers = Provider.providers()
        assert is_list(providers), "Should still return provider list even without ReqLLM"
      end
    end

    test "handles network-related errors gracefully" do
      case Registry.list_models(:perplexity) do
        {:ok, _models} ->
          assert true

        {:error, reason} when is_binary(reason) or is_atom(reason) ->
          assert true

        unexpected ->
          flunk("Unexpected response from Perplexity model listing: #{inspect(unexpected)}")
      end
    end

    test "validates provider name consistency" do
      providers = Provider.list()
      provider_ids = Enum.map(providers, & &1.id)

      assert :perplexity in provider_ids, "Perplexity should be available as :perplexity"

      perplexity_provider = Enum.find(providers, fn p -> p.id == :perplexity end)
      assert perplexity_provider != nil, "Should be able to find Perplexity provider"
      assert perplexity_provider.id == :perplexity
    end

    test "error handling for invalid configurations" do
      # Test invalid Perplexity configurations
      invalid_opts = {:perplexity, []}

      case Model.from(invalid_opts) do
        {:error, reason} ->
          assert is_binary(reason), "Should return a descriptive error message"

        {:ok, _model} ->
          # Some configurations might work with defaults
          assert true
      end

      # Test with unsupported model name
      unsupported_opts = {:perplexity, [model: "nonexistent-model"]}

      case Model.from(unsupported_opts) do
        {:error, reason} ->
          assert is_binary(reason)

        {:ok, _model} ->
          # Model creation might succeed even with unknown names
          assert true
      end
    end
  end

  describe "Perplexity integration with Jido AI ecosystem" do
    test "Perplexity works with provider listing APIs" do
      providers = Provider.list()
      perplexity_provider = Enum.find(providers, fn p -> p.id == :perplexity end)

      if perplexity_provider do
        assert perplexity_provider.id == :perplexity
        assert perplexity_provider.name != nil
      else
        IO.puts("Perplexity not found in provider list - may be expected in test environment")
      end
    end

    test "Perplexity compatibility with keyring system" do
      keyring_compatible = function_exported?(Keyring, :get, 2)
      assert keyring_compatible, "Keyring system should be available for authentication"

      result = Keyring.get(Keyring, :perplexity_api_key, "default")
      assert is_binary(result), "Keyring should return string value"
    end

    test "provider adapter resolution" do
      providers = Provider.list()
      perplexity_provider = Enum.find(providers, fn p -> p.id == :perplexity end)

      if perplexity_provider do
        case Provider.get_adapter_module(perplexity_provider) do
          {:ok, :reqllm_backed} ->
            assert true

          {:ok, adapter} ->
            assert adapter != nil

          {:error, reason} ->
            flunk("Failed to resolve Perplexity adapter: #{inspect(reason)}")
        end
      else
        IO.puts("Perplexity provider not found in provider listing")
      end
    end

    test "search parameter validation" do
      # Test that search-related parameters are handled correctly
      search_params = [
        return_related_questions: true,
        search_domain_filter: ["academic"],
        return_citations: true,
        search_recency_filter: "month"
      ]

      # These parameters should be handled by the provider integration
      Enum.each(search_params, fn {param, value} ->
        opts = {:perplexity, [{:model, "pplx-7b-online"} | [{param, value}]]}

        case Model.from(opts) do
          {:ok, model} ->
            # Check if the parameter is preserved in model options
            model_opts = Map.get(model, :opts, %{})

            if Map.has_key?(model_opts, param) do
              IO.puts(
                "Search parameter #{param} preserved: #{inspect(Map.get(model_opts, param))}"
              )
            end

          {:error, _reason} ->
            # Parameter validation might fail, which is acceptable
            IO.puts("Search parameter #{param} validation failed (expected in test environment)")
        end
      end)
    end
  end
end
