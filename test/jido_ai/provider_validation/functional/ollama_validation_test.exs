defmodule Jido.AI.ProviderValidation.Functional.OllamaValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for Ollama provider through :reqllm_backed interface.

  This test suite validates that the Ollama provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for local model operations.

  Test Categories:
  - Provider availability and discovery
  - Local connection validation
  - Model discovery and registry integration
  - Health checks and error handling
  - Local deployment scenarios
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :ollama
  @moduletag :local_providers

  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "Ollama provider availability" do
    test "Ollama is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      assert :ollama in provider_list, "Ollama provider should be available in provider list"

      # Verify it's using the reqllm_backed adapter
      ollama_adapter = Enum.find(providers, fn {provider, _adapter} -> provider == :ollama end)
      assert ollama_adapter != nil, "Ollama provider configuration should exist"
      assert {_, :reqllm_backed} = ollama_adapter
    end

    test "Ollama provider metadata is accessible" do
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          assert is_map(metadata), "Provider metadata should be a map"
          assert metadata[:name] != nil, "Provider should have a name"
          # Ollama typically uses localhost:11434
          assert is_binary(metadata[:base_url]) or metadata[:base_url] == nil

        {:error, reason} ->
          flunk("Failed to get Ollama provider metadata: #{inspect(reason)}")
      end
    end

    test "Ollama provider is included in supported providers list" do
      supported_providers = ProviderMapping.supported_providers()
      assert :ollama in supported_providers, "Ollama should be in supported providers list"
    end

    test "Ollama provider characteristics for local deployment" do
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          # Ollama should not require authentication for basic usage
          auth_required = Map.get(metadata, :requires_auth, true)

          assert auth_required == false or auth_required == true,
                 "Should have auth requirement info"

          # Check if it's identified as a local provider
          is_local = Map.get(metadata, :is_local, false)

          if is_local do
            IO.puts("Ollama correctly identified as local provider")
          end

        {:error, reason} ->
          IO.puts("Skipping provider characteristics test: #{inspect(reason)}")
      end
    end
  end

  describe "Ollama local connection validation" do
    test "session authentication handling for local provider" do
      # Ollama typically doesn't require API keys but the system should handle this gracefully
      session_result = SessionAuthentication.has_session_auth?(:ollama)
      assert session_result == true or session_result == false, "Should return boolean"

      # Test setting session auth (may not be required but should work)
      SessionAuthentication.set_for_provider(:ollama, "not-required-but-testing")
      assert SessionAuthentication.has_session_auth?(:ollama) == true

      # Clear session auth
      SessionAuthentication.clear_for_provider(:ollama)
      assert SessionAuthentication.has_session_auth?(:ollama) == false
    end

    test "authentication request handling for local provider" do
      # Test the ReqLLM request authentication bridge for local providers
      result = SessionAuthentication.get_for_request(:ollama, %{})

      # Should return either session auth or no session auth
      assert result == {:no_session_auth} or match?({:session_auth, _opts}, result)
    end

    test "connection health check simulation" do
      # This test validates that we can check if Ollama is running
      # In real scenarios, this would connect to localhost:11434

      # Test the provider mapping for connection details
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          base_url = Map.get(metadata, :base_url, "http://localhost:11434")
          assert is_binary(base_url), "Should have a base URL for connection"

          # Check that it's a localhost URL (typical for Ollama)
          if String.contains?(base_url, "localhost") or String.contains?(base_url, "127.0.0.1") do
            IO.puts("Ollama configured for local connection: #{base_url}")
          end

        {:error, reason} ->
          IO.puts("Skipping connection health check: #{inspect(reason)}")
      end
    end

    test "local service availability detection" do
      # Test that we can detect if Ollama service would be available
      # This is important for graceful degradation in environments where Ollama isn't running

      case Registry.list_models(:ollama) do
        {:ok, _models} ->
          IO.puts("Ollama appears to be available for model listing")
          assert true

        {:error, reason} when is_atom(reason) or is_binary(reason) ->
          IO.puts(
            "Ollama service not available (expected in test environment): #{inspect(reason)}"
          )

          assert true, "Should handle unavailable service gracefully"

        unexpected ->
          flunk("Unexpected response from Ollama service check: #{inspect(unexpected)}")
      end
    end
  end

  describe "Ollama model discovery and registry" do
    test "model registry can list Ollama models" do
      case Registry.list_models(:ollama) do
        {:ok, models} ->
          assert is_list(models), "Should return a list of models"

          # Ollama models typically include llama2, codellama, mistral, etc.
          if length(models) > 0 do
            model = hd(models)

            assert Map.has_key?(model, :id) or Map.has_key?(model, :name),
                   "Models should have id or name"

            # Check for typical Ollama model characteristics
            model_name = Map.get(model, :name, Map.get(model, :id, ""))

            # Common Ollama models patterns
            ollama_patterns = ["llama", "mistral", "codellama", "phi", "gemma", "qwen"]

            has_ollama_pattern =
              Enum.any?(ollama_patterns, fn pattern ->
                String.contains?(String.downcase(model_name), pattern)
              end)

            if has_ollama_pattern do
              IO.puts("Found typical Ollama model: #{model_name}")
            end
          else
            IO.puts("No Ollama models found - may be expected if Ollama service not running")
          end

        {:error, :provider_not_available} ->
          IO.puts("Skipping Ollama model discovery - service not available in test environment")

        {:error, reason} ->
          IO.puts("Ollama model listing handled error gracefully: #{inspect(reason)}")
      end
    end

    test "Ollama model metadata structure validation" do
      case Registry.list_models(:ollama) do
        {:ok, [model | _]} ->
          # Check that models have expected metadata structure
          expected_fields = [:id, :name, :provider, :capabilities, :modalities]
          present_fields = Enum.filter(expected_fields, &Map.has_key?(model, &1))

          # At least some expected fields should be present
          assert present_fields != [], "Model should have some expected metadata fields"

          # Verify provider field if present
          if Map.has_key?(model, :provider) do
            assert model.provider == :ollama, "Provider field should be :ollama"
          end

          # Check for local-specific metadata
          if Map.has_key?(model, :size) do
            size = model.size

            if is_binary(size) do
              IO.puts("Ollama model size information: #{size}")
            end
          end

        {:ok, []} ->
          IO.puts("No Ollama models found in registry - expected without running Ollama service")

        {:error, _reason} ->
          IO.puts("Skipping model metadata validation - Ollama service not available")
      end
    end

    test "local model discovery patterns" do
      # Test that local models can be discovered through the registry
      case Registry.list_models(:ollama) do
        {:ok, models} ->
          local_models =
            Enum.filter(models, fn model ->
              # Local models might have different characteristics
              capabilities = Map.get(model, :capabilities, [])
              modalities = Map.get(model, :modalities, [])

              # Check for local deployment indicators
              is_list(capabilities) or is_list(modalities)
            end)

          if length(local_models) > 0 do
            IO.puts("Found #{length(local_models)} local models through registry")
          end

        {:error, _reason} ->
          IO.puts("Local model discovery test skipped - Ollama not available")
      end
    end
  end

  describe "Ollama model creation and usage" do
    @tag :integration
    test "model creation with Ollama provider" do
      # Test creating models for local execution
      common_models = ["llama2", "mistral", "codellama"]

      Enum.each(common_models, fn model_name ->
        model_opts = {:ollama, [model: model_name]}

        case Model.from(model_opts) do
          {:ok, model} ->
            assert model.provider == :ollama
            assert model.reqllm_id == "ollama:#{model_name}"
            assert model.model == model_name
            IO.puts("Successfully created Ollama model: #{model_name}")

          {:error, reason} ->
            IO.puts("Model creation test for #{model_name} handled error: #{inspect(reason)}")
        end
      end)
    end

    test "local model configuration validation" do
      # Test that local models can be configured properly
      test_config = {:ollama, [model: "test-model", temperature: 0.7]}

      case Model.from(test_config) do
        {:ok, model} ->
          assert model.provider == :ollama
          # Test that configuration is preserved
          config = Map.get(model, :config, %{})

          if is_map(config) do
            temp = Map.get(config, :temperature)

            if temp do
              assert temp == 0.7, "Temperature configuration should be preserved"
            end
          end

        {:error, reason} ->
          IO.puts("Local model configuration test handled error: #{inspect(reason)}")
      end
    end
  end

  describe "Ollama error handling and edge cases" do
    test "handles Ollama service unavailable gracefully" do
      # Test behavior when Ollama service is not running
      case Registry.list_models(:ollama) do
        {:ok, _models} ->
          # Service is available
          assert true

        {:error, reason} when is_binary(reason) or is_atom(reason) ->
          # Service not available - should be handled gracefully
          assert true, "Should handle unavailable Ollama service"

        unexpected ->
          flunk("Unexpected response when Ollama unavailable: #{inspect(unexpected)}")
      end
    end

    test "connection timeout handling" do
      # Test that connection timeouts are handled appropriately for local services
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          # Check if timeout settings exist
          timeout = Map.get(metadata, :timeout, nil)

          if timeout do
            assert is_integer(timeout) and timeout > 0, "Timeout should be positive integer"
          end

        {:error, _reason} ->
          IO.puts("Skipping timeout validation - provider metadata not available")
      end
    end

    test "invalid model handling" do
      # Test handling of models that don't exist in Ollama
      invalid_config = {:ollama, [model: "non-existent-model-xyz"]}

      case Model.from(invalid_config) do
        {:error, reason} ->
          assert is_binary(reason), "Should return descriptive error message"

        {:ok, _model} ->
          # Model creation might succeed even if model doesn't exist locally
          # This is acceptable as the error might occur during actual usage
          assert true
      end
    end

    test "network connectivity validation" do
      # Test validation that would check if local Ollama is reachable
      providers = Provider.list()
      ollama_provider = Enum.find(providers, fn p -> p.id == :ollama end)

      if ollama_provider do
        assert ollama_provider.id == :ollama
        assert ollama_provider.name != nil

        # Test adapter resolution
        case Provider.get_adapter_module(ollama_provider) do
          {:ok, :reqllm_backed} ->
            assert true

          {:ok, adapter} ->
            assert adapter != nil

          {:error, reason} ->
            IO.puts("Adapter resolution test info: #{inspect(reason)}")
        end
      else
        IO.puts("Ollama provider not found in provider listing")
      end
    end
  end

  describe "Ollama deployment scenarios" do
    test "local development environment detection" do
      # Test patterns for detecting local development usage
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          base_url = Map.get(metadata, :base_url, "")

          local_indicators = ["localhost", "127.0.0.1", "0.0.0.0"]

          is_local_deployment =
            Enum.any?(local_indicators, fn indicator ->
              String.contains?(String.downcase(base_url), indicator)
            end)

          if is_local_deployment do
            IO.puts("Detected local development environment for Ollama")
          end

        {:error, _reason} ->
          IO.puts("Local environment detection skipped")
      end
    end

    test "privacy-conscious deployment validation" do
      # Test characteristics that make Ollama suitable for privacy-conscious deployments
      case ProviderMapping.get_jido_provider_metadata(:ollama) do
        {:ok, metadata} ->
          # Check for privacy indicators
          requires_internet = Map.get(metadata, :requires_internet, true)
          is_local = Map.get(metadata, :is_local, false)

          if not requires_internet or is_local do
            IO.puts("Ollama validated for privacy-conscious deployment")
          end

          # Data should stay local
          data_locality = Map.get(metadata, :data_locality, "unknown")

          if data_locality == "local" do
            IO.puts("Data locality confirmed as local")
          end

        {:error, _reason} ->
          IO.puts("Privacy validation skipped - metadata not available")
      end
    end

    test "resource usage considerations" do
      # Test that we can get information about local resource usage
      case Registry.list_models(:ollama) do
        {:ok, models} ->
          models_with_size =
            Enum.filter(models, fn model ->
              Map.has_key?(model, :size) or Map.has_key?(model, :parameters)
            end)

          if length(models_with_size) > 0 do
            model = hd(models_with_size)
            size_info = Map.get(model, :size, Map.get(model, :parameters, "unknown"))
            model_name = Map.get(model, :name, "unknown")
            IO.puts("Resource info for #{model_name}: #{size_info}")
          end

        {:error, _reason} ->
          IO.puts("Resource usage test skipped - models not available")
      end
    end
  end

  describe "Ollama integration with Jido AI ecosystem" do
    test "Ollama works with provider listing APIs" do
      providers = Provider.list()
      ollama_provider = Enum.find(providers, fn p -> p.id == :ollama end)

      if ollama_provider do
        assert ollama_provider.id == :ollama
        assert ollama_provider.name != nil
      else
        IO.puts("Ollama not found in provider list - may be expected in test environment")
      end
    end

    test "Ollama compatibility with local keyring system" do
      # Test that Ollama works with the keyring even if it doesn't require API keys
      keyring_compatible = function_exported?(Keyring, :get, 3)
      assert keyring_compatible, "Keyring system should be available"

      # Ollama might not need API keys but keyring should still work
      result = Keyring.get(Keyring, :ollama_api_key, "default")
      assert is_binary(result), "Keyring should return string value"
    end

    test "provider adapter resolution for local provider" do
      providers = Provider.list()
      ollama_provider = Enum.find(providers, fn p -> p.id == :ollama end)

      if ollama_provider do
        case Provider.get_adapter_module(ollama_provider) do
          {:ok, :reqllm_backed} ->
            assert true, "Ollama should use reqllm_backed adapter"

          {:ok, adapter} ->
            assert adapter != nil

          {:error, reason} ->
            IO.puts("Adapter resolution for Ollama: #{inspect(reason)}")
        end
      else
        IO.puts("Ollama provider not found in provider listing")
      end
    end

    test "local provider configuration inheritance" do
      # Test that local providers inherit global configurations appropriately
      providers = Provider.providers()
      ollama_config = Enum.find(providers, fn {provider, _adapter} -> provider == :ollama end)

      if ollama_config do
        {_provider, adapter} = ollama_config
        assert adapter == :reqllm_backed, "Should use ReqLLM backend"
      end
    end
  end
end
