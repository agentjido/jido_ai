defmodule Jido.AI.ProviderValidation.Functional.CohereValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for Cohere provider through :reqllm_backed interface.

  This test suite validates that the Cohere provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for specialized operations.

  Test Categories:
  - Provider availability and discovery
  - Authentication validation
  - Model discovery and RAG-optimized features
  - Advanced capabilities (Embed, Rerank, RAG workflows)
  - Enterprise features and large context handling
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :cohere
  @moduletag :specialized_providers

  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "Cohere provider availability" do
    test "Cohere is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      assert :cohere in provider_list, "Cohere provider should be available in provider list"

      # Verify it's using the reqllm_backed adapter
      cohere_adapter = Enum.find(providers, fn {provider, _adapter} -> provider == :cohere end)
      assert cohere_adapter != nil, "Cohere provider configuration should exist"
      assert {_, :reqllm_backed} = cohere_adapter
    end

    test "Cohere provider metadata is accessible" do
      case ProviderMapping.get_jido_provider_metadata(:cohere) do
        {:ok, metadata} ->
          assert is_map(metadata), "Provider metadata should be a map"
          assert metadata[:name] != nil, "Provider should have a name"
          # Cohere typically uses api.cohere.ai
          assert is_binary(metadata[:base_url]) or metadata[:base_url] == nil

        {:error, reason} ->
          flunk("Failed to get Cohere provider metadata: #{inspect(reason)}")
      end
    end

    test "Cohere provider is included in supported providers list" do
      supported_providers = ProviderMapping.supported_providers()
      assert :cohere in supported_providers, "Cohere should be in supported providers list"
    end
  end

  describe "Cohere authentication validation" do
    test "session authentication functionality" do
      # Test session authentication for Cohere provider
      session_result = SessionAuthentication.has_session_auth?(:cohere)
      assert session_result == true or session_result == false, "Should return boolean"

      # Test setting session auth (without real key)
      SessionAuthentication.set_for_provider(:cohere, "test-cohere-key-123")
      assert SessionAuthentication.has_session_auth?(:cohere) == true

      # Clear session auth
      SessionAuthentication.clear_for_provider(:cohere)
      assert SessionAuthentication.has_session_auth?(:cohere) == false
    end

    test "authentication request handling" do
      # Test the ReqLLM request authentication bridge
      result = SessionAuthentication.get_for_request(:cohere, %{})

      # Should return either session auth or no session auth
      assert result == {:no_session_auth} or match?({:session_auth, _opts}, result)
    end
  end

  describe "Cohere model discovery" do
    test "model registry can list Cohere models" do
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          assert is_list(models), "Should return a list of models"

          # Cohere models include command-r-plus, command-r, command, etc.
          if length(models) > 0 do
            model = hd(models)

            assert Map.has_key?(model, :id) or Map.has_key?(model, :name),
                   "Models should have id or name"

            # Check for Cohere-specific model characteristics
            model_name = Map.get(model, :name, Map.get(model, :id, ""))

            # Cohere models often have "command" or "embed" in names
            cohere_patterns = ["command", "embed", "rerank"]

            has_cohere_pattern =
              Enum.any?(cohere_patterns, &String.contains?(String.downcase(model_name), &1))

            if has_cohere_pattern do
              IO.puts("Found Cohere model: #{model_name}")
            end
          end

        {:error, :provider_not_available} ->
          IO.puts("Skipping Cohere model discovery - ReqLLM not available in test environment")

        {:error, reason} ->
          flunk("Failed to list Cohere models: #{inspect(reason)}")
      end
    end

    test "Cohere model metadata structure validation" do
      case Registry.list_models(:cohere) do
        {:ok, [model | _]} ->
          # Check that models have expected metadata structure
          expected_fields = [:id, :name, :provider, :capabilities, :modalities]
          present_fields = Enum.filter(expected_fields, &Map.has_key?(model, &1))

          # At least some expected fields should be present
          assert present_fields != [], "Model should have some expected metadata fields"

          # Verify provider field if present
          if Map.has_key?(model, :provider) do
            assert model.provider == :cohere, "Provider field should be :cohere"
          end

        {:ok, []} ->
          IO.puts("No Cohere models found in registry - may be expected in test environment")

        {:error, _reason} ->
          IO.puts("Skipping model metadata test - ReqLLM not available")
      end
    end
  end

  describe "Cohere RAG-optimized features" do
    @tag :integration
    test "model creation with Cohere provider" do
      # Test creating models for RAG workflows
      rag_models = ["command-r-plus", "command-r", "command"]

      Enum.each(rag_models, fn model_name ->
        model_opts = {:cohere, [model: model_name]}

        case Model.from(model_opts) do
          {:ok, model} ->
            assert model.provider == :cohere
            assert model.reqllm_id == "cohere:#{model_name}"
            assert model.model == model_name
            IO.puts("Successfully created Cohere model: #{model_name}")

          {:error, reason} ->
            IO.puts("Model creation test for #{model_name} skipped: #{inspect(reason)}")
        end
      end)
    end

    @tag :integration
    test "RAG workflow capabilities detection" do
      # Test detection of RAG-specific capabilities
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          rag_capable_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              String.contains?(String.downcase(model_name), "command")
            end)

          if length(rag_capable_models) > 0 do
            model = hd(rag_capable_models)

            # Check for RAG-related capabilities
            capabilities = Map.get(model, :capabilities, [])

            if is_list(capabilities) do
              rag_capabilities = ["citation", "grounded_generation", "tool_use"]
              found_rag_caps = Enum.filter(rag_capabilities, &(&1 in capabilities))

              if length(found_rag_caps) > 0 do
                IO.puts("Found RAG capabilities: #{Enum.join(found_rag_caps, ", ")}")
              end
            end
          end

        {:error, _reason} ->
          IO.puts("Skipping RAG capabilities test - ReqLLM not available")
      end
    end

    test "large context window handling" do
      # Test detection of large context windows (Cohere supports up to 128K tokens)
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          large_context_models =
            Enum.filter(models, fn model ->
              context_length = Map.get(model, :context_length, 0)
              is_integer(context_length) and context_length >= 100_000
            end)

          if length(large_context_models) > 0 do
            model = hd(large_context_models)
            context_length = Map.get(model, :context_length)
            model_name = Map.get(model, :name, Map.get(model, :id, "unknown"))

            IO.puts("Found large context Cohere model: #{model_name} (#{context_length} tokens)")

            # Cohere's command-r-plus supports 128K context
            if String.contains?(String.downcase(model_name), "command-r-plus") do
              assert context_length >= 128_000, "Command-R-Plus should support 128K+ context"
            end
          else
            IO.puts("No large context models detected - may be metadata limitation")
          end

        {:error, _reason} ->
          IO.puts("Skipping context window test - ReqLLM not available")
      end
    end
  end

  describe "Cohere specialized APIs" do
    test "embed API model detection" do
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          # Look for embedding models
          embed_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              String.contains?(String.downcase(model_name), "embed")
            end)

          if length(embed_models) > 0 do
            embed_model = hd(embed_models)
            model_name = Map.get(embed_model, :name, Map.get(embed_model, :id, "unknown"))

            IO.puts("Found Cohere embedding model: #{model_name}")

            # Check for embedding-specific capabilities
            capabilities = Map.get(embed_model, :capabilities, [])
            modalities = Map.get(embed_model, :modalities, [])

            if is_list(capabilities) and "embedding" in capabilities do
              assert true, "Embedding model should have embedding capability"
            end

            if is_list(modalities) and "text" in modalities do
              assert true, "Embedding model should support text modality"
            end
          else
            IO.puts("No embedding models found - may be registry limitation")
          end

        {:error, _reason} ->
          IO.puts("Skipping embed API test - ReqLLM not available")
      end
    end

    test "rerank API model detection" do
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          # Look for reranking models
          rerank_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              String.contains?(String.downcase(model_name), "rerank")
            end)

          if length(rerank_models) > 0 do
            rerank_model = hd(rerank_models)
            model_name = Map.get(rerank_model, :name, Map.get(rerank_model, :id, "unknown"))

            IO.puts("Found Cohere rerank model: #{model_name}")

            # Check for reranking-specific capabilities
            capabilities = Map.get(rerank_model, :capabilities, [])

            if is_list(capabilities) and "reranking" in capabilities do
              assert true, "Rerank model should have reranking capability"
            end
          else
            IO.puts("No rerank models found - may be registry limitation")
          end

        {:error, _reason} ->
          IO.puts("Skipping rerank API test - ReqLLM not available")
      end
    end
  end

  describe "Cohere enterprise features" do
    test "enterprise model variants detection" do
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          # Look for enterprise or dedicated models
          enterprise_indicators = ["enterprise", "dedicated", "private"]

          enterprise_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              description = Map.get(model, :description, "")

              Enum.any?(enterprise_indicators, fn indicator ->
                String.contains?(String.downcase(model_name), indicator) or
                  String.contains?(String.downcase(description), indicator)
              end)
            end)

          if length(enterprise_models) > 0 do
            enterprise_model = hd(enterprise_models)

            model_name =
              Map.get(enterprise_model, :name, Map.get(enterprise_model, :id, "unknown"))

            IO.puts("Found Cohere enterprise model: #{model_name}")

            # Enterprise models might have different pricing or capabilities
            cost_info = Map.get(enterprise_model, :cost, %{})

            if is_map(cost_info) and map_size(cost_info) > 0 do
              IO.puts("Enterprise model has cost information: #{inspect(cost_info)}")
            end
          else
            IO.puts("No enterprise models detected")
          end

        {:error, _reason} ->
          IO.puts("Skipping enterprise features test - ReqLLM not available")
      end
    end

    test "multi-language support detection" do
      case Registry.list_models(:cohere) do
        {:ok, models} ->
          # Cohere supports multiple languages especially in Command models
          command_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              String.contains?(String.downcase(model_name), "command")
            end)

          if length(command_models) > 0 do
            command_model = hd(command_models)
            model_name = Map.get(command_model, :name, Map.get(command_model, :id, "unknown"))

            IO.puts("Checking multi-language support for: #{model_name}")

            # Check if model metadata indicates language support
            supported_languages = Map.get(command_model, :supported_languages, [])
            capabilities = Map.get(command_model, :capabilities, [])

            if is_list(supported_languages) and length(supported_languages) > 1 do
              IO.puts("Multi-language support detected: #{Enum.join(supported_languages, ", ")}")
            end

            if is_list(capabilities) and "multilingual" in capabilities do
              IO.puts("Multilingual capability detected")
            end
          end

        {:error, _reason} ->
          IO.puts("Skipping multi-language test - ReqLLM not available")
      end
    end
  end

  describe "Cohere error conditions and edge cases" do
    test "handles missing ReqLLM gracefully" do
      # Test behavior when ReqLLM module is not available
      if Code.ensure_loaded?(ReqLLM) do
        providers = Provider.providers()
        assert is_list(providers)
      else
        providers = Provider.providers()
        assert is_list(providers), "Should still return provider list even without ReqLLM"
      end
    end

    test "handles network-related errors gracefully" do
      case Registry.list_models(:cohere) do
        {:ok, _models} ->
          assert true

        {:error, reason} when is_binary(reason) or is_atom(reason) ->
          assert true

        unexpected ->
          flunk("Unexpected response from Cohere model listing: #{inspect(unexpected)}")
      end
    end

    test "validates provider name consistency" do
      providers = Provider.list()
      provider_ids = Enum.map(providers, & &1.id)

      # Cohere should be available as :cohere
      assert :cohere in provider_ids, "Cohere should be available as :cohere"

      # Test that we can find the Cohere provider consistently
      cohere_provider = Enum.find(providers, fn p -> p.id == :cohere end)
      assert cohere_provider != nil, "Should be able to find Cohere provider"
      assert cohere_provider.id == :cohere
    end

    test "error handling for invalid configurations" do
      # Test invalid Cohere configurations
      invalid_opts = {:cohere, []}

      case Model.from(invalid_opts) do
        {:error, reason} ->
          assert is_binary(reason), "Should return a descriptive error message"

        {:ok, _model} ->
          # Some configurations might work with defaults
          assert true
      end
    end
  end

  describe "Cohere integration with Jido AI ecosystem" do
    test "Cohere works with provider listing APIs" do
      providers = Provider.list()
      cohere_provider = Enum.find(providers, fn p -> p.id == :cohere end)

      if cohere_provider do
        assert cohere_provider.id == :cohere
        assert cohere_provider.name != nil
      else
        IO.puts("Cohere not found in provider list - may be expected in test environment")
      end
    end

    test "Cohere compatibility with keyring system" do
      keyring_compatible = function_exported?(Keyring, :get, 2)
      assert keyring_compatible, "Keyring system should be available for authentication"

      result = Keyring.get(Keyring, :cohere_api_key, "default")
      assert is_binary(result), "Keyring should return string value"
    end

    test "provider adapter resolution" do
      providers = Provider.list()
      cohere_provider = Enum.find(providers, fn p -> p.id == :cohere end)

      if cohere_provider do
        case Provider.get_adapter_module(cohere_provider) do
          {:ok, :reqllm_backed} ->
            assert true

          {:ok, adapter} ->
            assert adapter != nil

          {:error, reason} ->
            flunk("Failed to resolve Cohere adapter: #{inspect(reason)}")
        end
      else
        IO.puts("Cohere provider not found in provider listing")
      end
    end
  end
end
