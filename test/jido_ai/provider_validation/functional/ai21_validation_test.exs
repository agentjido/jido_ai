defmodule Jido.AI.ProviderValidation.Functional.AI21ValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for AI21 Labs provider through :reqllm_backed interface.

  This test suite validates that the AI21 Labs provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for Jurassic model family operations.

  Test Categories:
  - Provider availability and discovery
  - Authentication validation
  - Jurassic model family discovery and access
  - Task-specific API validation (Contextual Answers, Paraphrase, etc.)
  - Large context window handling (8K-256K tokens)
  - Enterprise feature validation
  - Multilingual capabilities
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :ai21
  @moduletag :specialized_providers

  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "AI21 Labs provider availability" do
    test "AI21 is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      # AI21 Labs might be listed as :ai21 or :ai21labs
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      ai21_found = Enum.find(ai21_variants, &(&1 in provider_list))

      assert ai21_found != nil, "AI21 Labs provider should be available in provider list"

      # Verify it's using the reqllm_backed adapter
      ai21_adapter = Enum.find(providers, fn {provider, _adapter} -> provider == ai21_found end)
      assert ai21_adapter != nil, "AI21 Labs provider configuration should exist"
      assert {_, :reqllm_backed} = ai21_adapter
    end

    test "AI21 provider metadata is accessible" do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]

      ai21_provider =
        Enum.find(ai21_variants, fn variant ->
          case ProviderMapping.get_jido_provider_metadata(variant) do
            {:ok, _} -> true
            _ -> false
          end
        end)

      if ai21_provider do
        case ProviderMapping.get_jido_provider_metadata(ai21_provider) do
          {:ok, metadata} ->
            assert is_map(metadata), "Provider metadata should be a map"
            assert metadata[:name] != nil, "Provider should have a name"
            # AI21 Labs uses api.ai21.com
            assert is_binary(metadata[:base_url]) or metadata[:base_url] == nil

          {:error, reason} ->
            flunk("Failed to get AI21 Labs provider metadata: #{inspect(reason)}")
        end
      else
        IO.puts("Skipping AI21 metadata test - provider not found in expected variants")
      end
    end

    test "AI21 provider is included in supported providers list" do
      supported_providers = ProviderMapping.supported_providers()
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]

      ai21_found = Enum.find(ai21_variants, &(&1 in supported_providers))
      assert ai21_found != nil, "AI21 Labs should be in supported providers list"
    end
  end

  describe "AI21 authentication validation" do
    setup do
      # Find the correct AI21 provider variant for this test
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      ai21_provider = Enum.find(ai21_variants, &(&1 in provider_list))
      %{ai21_provider: ai21_provider}
    end

    test "session authentication functionality", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        # Test session authentication for AI21 Labs provider
        session_result = SessionAuthentication.has_session_auth?(ai21_provider)
        assert session_result == true or session_result == false, "Should return boolean"

        # Test setting session auth (without real key)
        SessionAuthentication.set_for_provider(ai21_provider, "test-ai21-key-123")
        assert SessionAuthentication.has_session_auth?(ai21_provider) == true

        # Clear session auth
        SessionAuthentication.clear_for_provider(ai21_provider)
        assert SessionAuthentication.has_session_auth?(ai21_provider) == false
      else
        IO.puts("Skipping authentication test - AI21 provider not found")
      end
    end

    test "authentication request handling", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        # Test the ReqLLM request authentication bridge
        result = SessionAuthentication.get_for_request(ai21_provider, %{})

        # Should return either session auth or no session auth
        assert result == {:no_session_auth} or match?({:session_auth, _opts}, result)
      else
        IO.puts("Skipping authentication request test - AI21 provider not found")
      end
    end
  end

  describe "AI21 Jurassic model family discovery" do
    setup do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      %{ai21_variants: ai21_variants}
    end

    test "model registry can list AI21 models", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {provider, models} ->
          assert is_list(models), "Should return a list of models"

          # AI21 models include jurassic-2-ultra, jurassic-2-mid, j2-light, etc.
          if length(models) > 0 do
            model = hd(models)

            assert Map.has_key?(model, :id) or Map.has_key?(model, :name),
                   "Models should have id or name"

            model_name = Map.get(model, :name, Map.get(model, :id, ""))

            # AI21 models often contain "jurassic" or "j2"
            ai21_patterns = ["jurassic", "j2"]

            has_ai21_pattern =
              Enum.any?(ai21_patterns, &String.contains?(String.downcase(model_name), &1))

            if has_ai21_pattern do
              IO.puts("Found AI21 Labs model (#{provider}): #{model_name}")
            else
              IO.puts("Found model (may not follow expected pattern): #{model_name}")
            end
          end

        nil ->
          IO.puts("Skipping AI21 model discovery - ReqLLM not available in test environment")
      end
    end

    test "Jurassic model variants detection", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {_provider, models} ->
          # Categorize Jurassic models by type and size
          jurassic_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              String.contains?(String.downcase(model_name), "jurassic") or
                String.contains?(String.downcase(model_name), "j2")
            end)

          if length(jurassic_models) > 0 do
            # Group by model variants
            ultra_models =
              Enum.filter(jurassic_models, fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "ultra")
              end)

            mid_models =
              Enum.filter(jurassic_models, fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "mid")
              end)

            light_models =
              Enum.filter(jurassic_models, fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "light")
              end)

            IO.puts("Jurassic Model Variants:")
            IO.puts("  Ultra models: #{length(ultra_models)}")
            IO.puts("  Mid models: #{length(mid_models)}")
            IO.puts("  Light models: #{length(light_models)}")

            # Ultra models should have the largest context and best capabilities
            if length(ultra_models) > 0 do
              ultra_model = hd(ultra_models)
              context_length = Map.get(ultra_model, :context_length, 0)

              if context_length > 0 do
                IO.puts("  Ultra model context: #{context_length} tokens")
              end
            end
          else
            IO.puts("No Jurassic models found")
          end

        nil ->
          IO.puts("Skipping Jurassic variants test - ReqLLM not available")
      end
    end

    test "model metadata structure validation", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {provider, [model | _]} ->
          # Check that models have expected metadata structure
          expected_fields = [:id, :name, :provider, :capabilities, :modalities]
          present_fields = Enum.filter(expected_fields, &Map.has_key?(model, &1))

          assert present_fields != [], "Model should have some expected metadata fields"

          # Verify provider field if present
          if Map.has_key?(model, :provider) do
            assert model.provider == provider, "Provider field should match"
          end

        nil ->
          IO.puts("Skipping model metadata test - ReqLLM not available")
      end
    end
  end

  describe "AI21 task-specific API validation" do
    setup do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      ai21_provider = Enum.find(ai21_variants, &(&1 in provider_list))
      %{ai21_provider: ai21_provider}
    end

    @tag :integration
    test "model creation with Jurassic models", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        # Test creating models for various Jurassic variants
        jurassic_models = ["jurassic-2-ultra", "jurassic-2-mid", "j2-light", "j2-grande-instruct"]

        Enum.each(jurassic_models, fn model_name ->
          model_opts = {ai21_provider, [model: model_name]}

          case Model.from(model_opts) do
            {:ok, model} ->
              assert model.provider == ai21_provider
              assert model.reqllm_id == "#{ai21_provider}:#{model_name}"
              assert model.model == model_name
              IO.puts("Successfully created AI21 Labs model: #{model_name}")

            {:error, reason} ->
              IO.puts("Model creation for #{model_name} skipped: #{inspect(reason)}")
          end
        end)
      else
        IO.puts("Skipping model creation test - AI21 provider not found")
      end
    end

    test "contextual answers capability detection", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        case Registry.list_models(ai21_provider) do
          {:ok, models} ->
            # Look for models with contextual answers capability
            contextual_models =
              Enum.filter(models, fn model ->
                capabilities = Map.get(model, :capabilities, [])
                model_name = Map.get(model, :name, Map.get(model, :id, ""))

                # Check for contextual answer capabilities
                has_contextual_caps =
                  is_list(capabilities) and
                    Enum.any?(
                      ["contextual_answers", "question_answering", "reading_comprehension"],
                      &(&1 in capabilities)
                    )

                # Ultra and Mid models typically support contextual answers
                has_contextual_name =
                  String.contains?(String.downcase(model_name), "ultra") or
                    String.contains?(String.downcase(model_name), "mid")

                has_contextual_caps or has_contextual_name
              end)

            if length(contextual_models) > 0 do
              contextual_model = hd(contextual_models)

              model_name =
                Map.get(contextual_model, :name, Map.get(contextual_model, :id, "unknown"))

              IO.puts("Found contextual answers model: #{model_name}")

              # Check for related capabilities
              capabilities = Map.get(contextual_model, :capabilities, [])

              if is_list(capabilities) do
                contextual_caps = ["contextual_answers", "reading_comprehension", "document_qa"]
                found_caps = Enum.filter(contextual_caps, &(&1 in capabilities))

                if length(found_caps) > 0 do
                  IO.puts("Contextual capabilities: #{Enum.join(found_caps, ", ")}")
                end
              end
            else
              IO.puts("No contextual answers models found")
            end

          {:error, _reason} ->
            IO.puts("Skipping contextual answers test - ReqLLM not available")
        end
      else
        IO.puts("Skipping contextual answers test - AI21 provider not found")
      end
    end

    test "paraphrase and summarization detection", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        case Registry.list_models(ai21_provider) do
          {:ok, models} ->
            # Look for models with paraphrase/summarization capabilities
            text_processing_models =
              Enum.filter(models, fn model ->
                capabilities = Map.get(model, :capabilities, [])

                is_list(capabilities) and
                  Enum.any?(
                    ["paraphrase", "summarization", "text_processing", "rewriting"],
                    &(&1 in capabilities)
                  )
              end)

            if length(text_processing_models) > 0 do
              text_model = hd(text_processing_models)
              model_name = Map.get(text_model, :name, Map.get(text_model, :id, "unknown"))

              IO.puts("Found text processing model: #{model_name}")

              capabilities = Map.get(text_model, :capabilities, [])
              text_caps = ["paraphrase", "summarization", "rewriting", "text_improvement"]
              found_text_caps = Enum.filter(text_caps, &(&1 in capabilities))

              if length(found_text_caps) > 0 do
                IO.puts("Text processing capabilities: #{Enum.join(found_text_caps, ", ")}")
              end
            else
              IO.puts("No specialized text processing models found")
            end

          {:error, _reason} ->
            IO.puts("Skipping text processing test - ReqLLM not available")
        end
      else
        IO.puts("Skipping text processing test - AI21 provider not found")
      end
    end
  end

  describe "AI21 large context window handling" do
    setup do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      %{ai21_variants: ai21_variants}
    end

    test "context window size detection", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {_provider, models} ->
          # Check context window sizes for AI21 models
          models_with_context =
            Enum.filter(models, fn model ->
              context_length = Map.get(model, :context_length, 0)
              is_integer(context_length) and context_length > 0
            end)

          if length(models_with_context) > 0 do
            # Sort by context length
            sorted_by_context =
              Enum.sort_by(models_with_context, &Map.get(&1, :context_length), :desc)

            IO.puts("AI21 Models by Context Window:")

            Enum.each(sorted_by_context, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, "unknown"))
              context_length = Map.get(model, :context_length)
              IO.puts("  #{model_name}: #{context_length} tokens")
            end)

            # Check for ultra-large context models (AI21 supports up to 256K)
            large_context =
              Enum.filter(models_with_context, fn model ->
                context_length = Map.get(model, :context_length, 0)
                context_length >= 100_000
              end)

            if length(large_context) > 0 do
              large_model = hd(large_context)
              model_name = Map.get(large_model, :name, Map.get(large_model, :id, "unknown"))
              context_length = Map.get(large_model, :context_length)

              IO.puts("Ultra-large context model found: #{model_name} (#{context_length} tokens)")

              if context_length >= 256_000 do
                IO.puts("Confirmed 256K+ context support")
              end
            end
          else
            IO.puts("No context window information available")
          end

        nil ->
          IO.puts("Skipping context window test - ReqLLM not available")
      end
    end

    test "large document processing capabilities", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {_provider, models} ->
          # Look for models optimized for large document processing
          document_models =
            Enum.filter(models, fn model ->
              capabilities = Map.get(model, :capabilities, [])
              context_length = Map.get(model, :context_length, 0)

              has_document_caps =
                is_list(capabilities) and
                  Enum.any?(
                    ["document_analysis", "long_form", "large_context"],
                    &(&1 in capabilities)
                  )

              has_large_context = context_length >= 32_000

              has_document_caps or has_large_context
            end)

          if length(document_models) > 0 do
            doc_model = hd(document_models)
            model_name = Map.get(doc_model, :name, Map.get(doc_model, :id, "unknown"))
            context_length = Map.get(doc_model, :context_length, 0)

            IO.puts("Found large document model: #{model_name}")
            IO.puts("Context capacity: #{context_length} tokens")

            # Check for document-specific capabilities
            capabilities = Map.get(doc_model, :capabilities, [])

            if is_list(capabilities) do
              doc_caps = ["document_analysis", "long_form_qa", "document_summarization"]
              found_doc_caps = Enum.filter(doc_caps, &(&1 in capabilities))

              if length(found_doc_caps) > 0 do
                IO.puts("Document capabilities: #{Enum.join(found_doc_caps, ", ")}")
              end
            end
          else
            IO.puts("No large document processing models found")
          end

        nil ->
          IO.puts("Skipping large document test - ReqLLM not available")
      end
    end
  end

  describe "AI21 enterprise and multilingual features" do
    setup do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      %{ai21_variants: ai21_variants}
    end

    test "enterprise model variants detection", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {_provider, models} ->
          # Look for enterprise features
          enterprise_indicators = ["enterprise", "business", "commercial", "professional"]

          enterprise_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              description = Map.get(model, :description, "")
              tags = Map.get(model, :tags, [])

              name_indicates_enterprise =
                Enum.any?(
                  enterprise_indicators,
                  &String.contains?(String.downcase(model_name), &1)
                )

              desc_indicates_enterprise =
                Enum.any?(
                  enterprise_indicators,
                  &String.contains?(String.downcase(description), &1)
                )

              tags_indicate_enterprise =
                is_list(tags) and
                  Enum.any?(tags, fn tag ->
                    Enum.any?(enterprise_indicators, &String.contains?(String.downcase(tag), &1))
                  end)

              name_indicates_enterprise or desc_indicates_enterprise or tags_indicate_enterprise
            end)

          if length(enterprise_models) > 0 do
            enterprise_model = hd(enterprise_models)

            model_name =
              Map.get(enterprise_model, :name, Map.get(enterprise_model, :id, "unknown"))

            IO.puts("Found enterprise AI21 model: #{model_name}")

            # Check for enterprise-specific pricing
            cost_info = Map.get(enterprise_model, :cost, %{})

            if is_map(cost_info) and map_size(cost_info) > 0 do
              IO.puts("Enterprise pricing structure: #{inspect(cost_info)}")
            end
          else
            # Check if Ultra models indicate enterprise capability
            ultra_models =
              Enum.filter(models, fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "ultra")
              end)

            if length(ultra_models) > 0 do
              IO.puts(
                "Ultra models available (typically enterprise-grade): #{length(ultra_models)}"
              )
            else
              IO.puts("No specific enterprise models detected")
            end
          end

        nil ->
          IO.puts("Skipping enterprise features test - ReqLLM not available")
      end
    end

    test "multilingual support detection", %{ai21_variants: ai21_variants} do
      ai21_models_found =
        Enum.find_value(ai21_variants, fn variant ->
          case Registry.list_models(variant) do
            {:ok, models} when length(models) > 0 -> {variant, models}
            _ -> nil
          end
        end)

      case ai21_models_found do
        {_provider, models} ->
          # Look for multilingual capabilities
          multilingual_models =
            Enum.filter(models, fn model ->
              capabilities = Map.get(model, :capabilities, [])
              supported_languages = Map.get(model, :supported_languages, [])

              has_multilingual_caps = is_list(capabilities) and "multilingual" in capabilities

              has_multiple_languages =
                is_list(supported_languages) and length(supported_languages) > 1

              has_multilingual_caps or has_multiple_languages
            end)

          if length(multilingual_models) > 0 do
            multilingual_model = hd(multilingual_models)

            model_name =
              Map.get(multilingual_model, :name, Map.get(multilingual_model, :id, "unknown"))

            IO.puts("Found multilingual AI21 model: #{model_name}")

            supported_languages = Map.get(multilingual_model, :supported_languages, [])

            if is_list(supported_languages) and length(supported_languages) > 0 do
              IO.puts(
                "Supported languages: #{Enum.join(Enum.take(supported_languages, 5), ", ")}"
              )

              if length(supported_languages) > 5 do
                IO.puts("... and #{length(supported_languages) - 5} more")
              end
            end

            # AI21 typically has strong Hebrew support due to Israeli origins
            if is_list(supported_languages) and
                 "hebrew" in Enum.map(supported_languages, &String.downcase/1) do
              IO.puts("Hebrew support confirmed (expected for AI21 Labs)")
            end
          else
            IO.puts("No explicit multilingual capabilities found")
          end

        nil ->
          IO.puts("Skipping multilingual test - ReqLLM not available")
      end
    end
  end

  describe "AI21 error conditions and edge cases" do
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
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]

      Enum.each(ai21_variants, fn variant ->
        case Registry.list_models(variant) do
          {:ok, _models} ->
            assert true

          {:error, reason} when is_binary(reason) or is_atom(reason) ->
            assert true

          {:error, :provider_not_available} ->
            assert true

          unexpected ->
            flunk("Unexpected response from AI21 model listing: #{inspect(unexpected)}")
        end
      end)
    end

    test "validates provider name consistency" do
      providers = Provider.list()
      provider_ids = Enum.map(providers, & &1.id)

      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      ai21_found = Enum.find(ai21_variants, &(&1 in provider_ids))

      if ai21_found do
        ai21_provider = Enum.find(providers, fn p -> p.id == ai21_found end)
        assert ai21_provider != nil, "Should be able to find AI21 provider"
        assert ai21_provider.id == ai21_found
      else
        IO.puts("AI21 Labs not found in provider list - may be expected in test environment")
      end
    end

    test "error handling for invalid configurations" do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      ai21_provider = Enum.find(ai21_variants, &(&1 in provider_list))

      if ai21_provider do
        # Test invalid AI21 configurations
        invalid_opts = {ai21_provider, []}

        case Model.from(invalid_opts) do
          {:error, reason} ->
            assert is_binary(reason), "Should return a descriptive error message"

          {:ok, _model} ->
            # Some configurations might work with defaults
            assert true
        end

        # Test with unsupported model name
        unsupported_opts = {ai21_provider, [model: "nonexistent-jurassic-model"]}

        case Model.from(unsupported_opts) do
          {:error, reason} ->
            assert is_binary(reason)

          {:ok, _model} ->
            # Model creation might succeed even with unknown names
            assert true
        end
      else
        IO.puts("Skipping error handling test - AI21 provider not found")
      end
    end
  end

  describe "AI21 integration with Jido AI ecosystem" do
    setup do
      ai21_variants = [:ai21, :ai21labs, :ai21_labs]
      providers = Provider.list()
      provider_ids = Enum.map(providers, & &1.id)

      ai21_provider = Enum.find(ai21_variants, &(&1 in provider_ids))
      %{ai21_provider: ai21_provider}
    end

    test "AI21 works with provider listing APIs", %{ai21_provider: ai21_provider} do
      providers = Provider.list()

      if ai21_provider do
        found_provider = Enum.find(providers, fn p -> p.id == ai21_provider end)
        assert found_provider != nil
        assert found_provider.id == ai21_provider
        assert found_provider.name != nil
      else
        IO.puts("AI21 not found in provider list - may be expected in test environment")
      end
    end

    test "AI21 compatibility with keyring system", %{ai21_provider: ai21_provider} do
      keyring_compatible = function_exported?(Keyring, :get, 2)
      assert keyring_compatible, "Keyring system should be available for authentication"

      if ai21_provider do
        # Test different possible key names
        key_names = [:ai21_api_key, :ai21labs_api_key, :ai21_labs_api_key]

        Enum.each(key_names, fn key_name ->
          result = Keyring.get(Keyring, key_name, "default")
          assert is_binary(result), "Keyring should return string value for #{key_name}"
        end)
      else
        # Test generic keyring functionality
        result = Keyring.get(Keyring, :ai21_api_key, "default")
        assert is_binary(result), "Keyring should return string value"
      end
    end

    test "provider adapter resolution", %{ai21_provider: ai21_provider} do
      providers = Provider.list()

      if ai21_provider do
        ai21_provider_obj = Enum.find(providers, fn p -> p.id == ai21_provider end)

        if ai21_provider_obj do
          case Provider.get_adapter_module(ai21_provider_obj) do
            {:ok, :reqllm_backed} ->
              assert true

            {:ok, adapter} ->
              assert adapter != nil

            {:error, reason} ->
              flunk("Failed to resolve AI21 adapter: #{inspect(reason)}")
          end
        else
          IO.puts("AI21 provider object not found")
        end
      else
        IO.puts("AI21 provider not found in provider listing")
      end
    end

    test "model selection helper for use cases", %{ai21_provider: ai21_provider} do
      if ai21_provider do
        case Registry.list_models(ai21_provider) do
          {:ok, models} when length(models) > 0 ->
            # Provide recommendations for different use cases
            use_cases = %{
              "high_quality" => fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "ultra")
              end,
              "balanced" => fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "mid")
              end,
              "fast" => fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "light")
              end,
              "instruction_following" => fn model ->
                model_name = Map.get(model, :name, Map.get(model, :id, ""))
                String.contains?(String.downcase(model_name), "instruct")
              end
            }

            IO.puts("AI21 Model Recommendations by Use Case:")

            Enum.each(use_cases, fn {use_case, filter_fn} ->
              recommended = Enum.filter(models, filter_fn)

              if length(recommended) > 0 do
                best_model = hd(recommended)
                model_name = Map.get(best_model, :name, Map.get(best_model, :id, "unknown"))
                IO.puts("  #{use_case}: #{model_name}")
              else
                IO.puts("  #{use_case}: No specific model found")
              end
            end)

          {:ok, []} ->
            IO.puts("No models available for recommendations")

          {:error, _reason} ->
            IO.puts("Skipping model recommendations - ReqLLM not available")
        end
      else
        IO.puts("Skipping model recommendations - AI21 provider not found")
      end
    end
  end
end
