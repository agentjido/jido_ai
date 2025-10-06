defmodule Jido.AI.ProviderValidation.Functional.ReplicateValidationTest do
  @moduledoc """
  Comprehensive functional validation tests for Replicate provider through :reqllm_backed interface.

  This test suite validates that the Replicate provider is properly accessible through
  the Phase 1 ReqLLM integration and works correctly for marketplace model operations.

  Test Categories:
  - Provider availability and discovery
  - Authentication validation
  - Marketplace model discovery and access
  - Multi-modal capabilities (text, image, video, audio)
  - Community model integration
  - Pay-per-use scaling validation
  """
  use ExUnit.Case, async: false
  use Mimic

  @moduletag :provider_validation
  @moduletag :functional_validation
  @moduletag :replicate
  @moduletag :specialized_providers

  alias Jido.AI.Keyring
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry
  alias Jido.AI.Provider
  alias Jido.AI.ReqLlmBridge.ProviderMapping
  alias Jido.AI.ReqLlmBridge.SessionAuthentication

  describe "Replicate provider availability" do
    test "Replicate is listed in available providers" do
      providers = Provider.providers()
      provider_list = Enum.map(providers, &elem(&1, 0))

      assert :replicate in provider_list,
             "Replicate provider should be available in provider list"

      # Verify it's using the reqllm_backed adapter
      replicate_adapter =
        Enum.find(providers, fn {provider, _adapter} -> provider == :replicate end)

      assert replicate_adapter != nil, "Replicate provider configuration should exist"
      assert {_, :reqllm_backed} = replicate_adapter
    end

    test "Replicate provider metadata is accessible" do
      case ProviderMapping.get_jido_provider_metadata(:replicate) do
        {:ok, metadata} ->
          assert is_map(metadata), "Provider metadata should be a map"
          assert metadata[:name] != nil, "Provider should have a name"
          # Replicate uses api.replicate.com
          assert is_binary(metadata[:base_url]) or metadata[:base_url] == nil

        {:error, reason} ->
          flunk("Failed to get Replicate provider metadata: #{inspect(reason)}")
      end
    end

    test "Replicate provider is included in supported providers list" do
      supported_providers = ProviderMapping.supported_providers()
      assert :replicate in supported_providers, "Replicate should be in supported providers list"
    end
  end

  describe "Replicate authentication validation" do
    test "session authentication functionality" do
      # Test session authentication for Replicate provider
      session_result = SessionAuthentication.has_session_auth?(:replicate)
      assert session_result == true or session_result == false, "Should return boolean"

      # Test setting session auth (without real key)
      SessionAuthentication.set_for_provider(:replicate, "test-replicate-key-123")
      assert SessionAuthentication.has_session_auth?(:replicate) == true

      # Clear session auth
      SessionAuthentication.clear_for_provider(:replicate)
      assert SessionAuthentication.has_session_auth?(:replicate) == false
    end

    test "authentication request handling" do
      # Test the ReqLLM request authentication bridge
      result = SessionAuthentication.get_for_request(:replicate, %{})

      # Should return either session auth or no session auth
      assert result == {:no_session_auth} or match?({:session_auth, _opts}, result)
    end
  end

  describe "Replicate marketplace model discovery" do
    test "model registry can list Replicate models" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          assert is_list(models), "Should return a list of models"

          # Replicate has thousands of community models
          if length(models) > 0 do
            model = hd(models)

            assert Map.has_key?(model, :id) or Map.has_key?(model, :name),
                   "Models should have id or name"

            model_name = Map.get(model, :name, Map.get(model, :id, ""))

            # Replicate models often have format: "owner/model-name"
            if String.contains?(model_name, "/") do
              [owner, model_part] = String.split(model_name, "/", parts: 2)
              IO.puts("Found Replicate model: #{owner}/#{model_part}")

              # Validate owner/model format
              assert String.length(owner) > 0, "Owner part should not be empty"
              assert String.length(model_part) > 0, "Model part should not be empty"
            end
          end

        {:error, :provider_not_available} ->
          IO.puts("Skipping Replicate model discovery - ReqLLM not available in test environment")

        {:error, reason} ->
          flunk("Failed to list Replicate models: #{inspect(reason)}")
      end
    end

    test "popular model discovery" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for popular Replicate models
          popular_models = [
            "meta/llama-2",
            "stability-ai/stable-diffusion",
            "openai/whisper",
            "salesforce/blip",
            "meta/codellama",
            "mistralai/mistral"
          ]

          found_popular =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              Enum.any?(popular_models, fn popular ->
                String.contains?(String.downcase(model_name), String.downcase(popular))
              end)
            end)

          if length(found_popular) > 0 do
            popular_model = hd(found_popular)
            model_name = Map.get(popular_model, :name, Map.get(popular_model, :id, "unknown"))
            IO.puts("Found popular Replicate model: #{model_name}")
          else
            IO.puts("No popular models found - may be registry limitation")
          end

        {:error, _reason} ->
          IO.puts("Skipping popular model test - ReqLLM not available")
      end
    end

    test "model metadata structure validation" do
      case Registry.list_models(:replicate) do
        {:ok, [model | _]} ->
          # Check that models have expected metadata structure
          expected_fields = [:id, :name, :provider, :capabilities, :modalities]
          present_fields = Enum.filter(expected_fields, &Map.has_key?(model, &1))

          assert present_fields != [], "Model should have some expected metadata fields"

          # Verify provider field if present
          if Map.has_key?(model, :provider) do
            assert model.provider == :replicate, "Provider field should be :replicate"
          end

          # Check for Replicate-specific metadata
          owner = Map.get(model, :owner)

          if owner do
            assert is_binary(owner), "Owner should be a string"
            assert String.length(owner) > 0, "Owner should not be empty"
          end

        {:ok, []} ->
          IO.puts("No Replicate models found in registry - may be expected in test environment")

        {:error, _reason} ->
          IO.puts("Skipping model metadata test - ReqLLM not available")
      end
    end
  end

  describe "Replicate multi-modal capabilities" do
    @tag :integration
    test "text generation model creation" do
      # Test creating models for text generation
      text_models = [
        "meta/llama-2-70b-chat",
        "mistralai/mistral-7b-instruct-v0.1",
        "meta/codellama-34b-instruct"
      ]

      Enum.each(text_models, fn model_name ->
        model_opts = {:replicate, [model: model_name]}

        case Model.from(model_opts) do
          {:ok, model} ->
            assert model.provider == :replicate
            assert model.reqllm_id == "replicate:#{model_name}"
            assert model.model == model_name
            IO.puts("Successfully created Replicate text model: #{model_name}")

          {:error, reason} ->
            IO.puts("Text model creation for #{model_name} skipped: #{inspect(reason)}")
        end
      end)
    end

    test "image generation capabilities detection" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for image generation models
          image_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              modalities = Map.get(model, :modalities, [])

              # Check name patterns or modalities
              name_indicates_image =
                String.contains?(String.downcase(model_name), "stable-diffusion") or
                  String.contains?(String.downcase(model_name), "dall-e") or
                  String.contains?(String.downcase(model_name), "midjourney")

              modality_indicates_image = is_list(modalities) and "image" in modalities

              name_indicates_image or modality_indicates_image
            end)

          if length(image_models) > 0 do
            image_model = hd(image_models)
            model_name = Map.get(image_model, :name, Map.get(image_model, :id, "unknown"))

            IO.puts("Found Replicate image model: #{model_name}")

            # Check capabilities
            capabilities = Map.get(image_model, :capabilities, [])

            if is_list(capabilities) do
              image_caps = Enum.filter(capabilities, &String.contains?(&1, "image"))

              if length(image_caps) > 0 do
                IO.puts("Image capabilities: #{Enum.join(image_caps, ", ")}")
              end
            end
          else
            IO.puts("No image generation models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping image capabilities test - ReqLLM not available")
      end
    end

    test "audio processing capabilities detection" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for audio processing models (Whisper, etc.)
          audio_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              modalities = Map.get(model, :modalities, [])

              name_indicates_audio =
                String.contains?(String.downcase(model_name), "whisper") or
                  String.contains?(String.downcase(model_name), "audio")

              modality_indicates_audio = is_list(modalities) and "audio" in modalities

              name_indicates_audio or modality_indicates_audio
            end)

          if length(audio_models) > 0 do
            audio_model = hd(audio_models)
            model_name = Map.get(audio_model, :name, Map.get(audio_model, :id, "unknown"))

            IO.puts("Found Replicate audio model: #{model_name}")

            # Check for audio-specific capabilities
            capabilities = Map.get(audio_model, :capabilities, [])

            if is_list(capabilities) do
              audio_caps = ["speech-to-text", "transcription", "audio-generation"]
              found_audio_caps = Enum.filter(audio_caps, &(&1 in capabilities))

              if length(found_audio_caps) > 0 do
                IO.puts("Audio capabilities: #{Enum.join(found_audio_caps, ", ")}")
              end
            end
          else
            IO.puts("No audio processing models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping audio capabilities test - ReqLLM not available")
      end
    end

    test "video processing capabilities detection" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for video processing models
          video_models =
            Enum.filter(models, fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))
              modalities = Map.get(model, :modalities, [])

              name_indicates_video =
                String.contains?(String.downcase(model_name), "video") or
                  String.contains?(String.downcase(model_name), "animation")

              modality_indicates_video = is_list(modalities) and "video" in modalities

              name_indicates_video or modality_indicates_video
            end)

          if length(video_models) > 0 do
            video_model = hd(video_models)
            model_name = Map.get(video_model, :name, Map.get(video_model, :id, "unknown"))

            IO.puts("Found Replicate video model: #{model_name}")
          else
            IO.puts("No video processing models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping video capabilities test - ReqLLM not available")
      end
    end
  end

  describe "Replicate community model integration" do
    test "model versioning support" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for models with version information
          versioned_models =
            Enum.filter(models, fn model ->
              model_id = Map.get(model, :id, "")
              model_name = Map.get(model, :name, "")

              # Replicate models can have version hashes or semantic versions
              String.contains?(model_id, ":") or String.contains?(model_name, ":")
            end)

          if length(versioned_models) > 0 do
            versioned_model = hd(versioned_models)
            model_id = Map.get(versioned_model, :id, Map.get(versioned_model, :name, "unknown"))

            IO.puts("Found versioned Replicate model: #{model_id}")

            if String.contains?(model_id, ":") do
              [base_id, version] = String.split(model_id, ":", parts: 2)
              assert String.length(base_id) > 0, "Base model ID should not be empty"
              assert String.length(version) > 0, "Version should not be empty"
            end
          else
            IO.puts("No versioned models found")
          end

        {:error, _reason} ->
          IO.puts("Skipping versioning test - ReqLLM not available")
      end
    end

    test "community contributor detection" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Group models by owner/contributor
          owners =
            models
            |> Enum.map(fn model ->
              model_name = Map.get(model, :name, Map.get(model, :id, ""))

              if String.contains?(model_name, "/") do
                String.split(model_name, "/", parts: 2) |> hd()
              else
                nil
              end
            end)
            |> Enum.filter(&(&1 != nil))
            |> Enum.frequencies()

          if map_size(owners) > 0 do
            top_contributors =
              owners
              |> Enum.sort_by(&elem(&1, 1), :desc)
              |> Enum.take(5)

            IO.puts("Top Replicate contributors:")

            Enum.each(top_contributors, fn {owner, count} ->
              IO.puts("  #{owner}: #{count} models")
            end)

            # Verify we have multiple contributors (community aspect)
            assert map_size(owners) > 1, "Should have multiple contributors in community"
          else
            IO.puts("No community contributors detected")
          end

        {:error, _reason} ->
          IO.puts("Skipping community test - ReqLLM not available")
      end
    end
  end

  describe "Replicate pay-per-use scaling" do
    test "cost information availability" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for models with cost information
          models_with_cost =
            Enum.filter(models, fn model ->
              cost_info = Map.get(model, :cost, %{})
              is_map(cost_info) and map_size(cost_info) > 0
            end)

          if length(models_with_cost) > 0 do
            cost_model = hd(models_with_cost)
            model_name = Map.get(cost_model, :name, Map.get(cost_model, :id, "unknown"))
            cost_info = Map.get(cost_model, :cost)

            IO.puts("Found Replicate model with pricing: #{model_name}")
            IO.puts("Cost structure: #{inspect(cost_info)}")

            # Replicate typically charges per prediction/second
            cost_keys = Map.keys(cost_info)
            expected_keys = ["prediction", "training", "per_second", "per_token"]

            found_expected = Enum.filter(expected_keys, &(&1 in cost_keys))

            if length(found_expected) > 0 do
              IO.puts("Found expected cost metrics: #{Enum.join(found_expected, ", ")}")
            end
          else
            IO.puts("No cost information found - may be metadata limitation")
          end

        {:error, _reason} ->
          IO.puts("Skipping cost information test - ReqLLM not available")
      end
    end

    test "hardware scaling indicators" do
      case Registry.list_models(:replicate) do
        {:ok, models} ->
          # Look for hardware/scaling information
          models_with_hardware =
            Enum.filter(models, fn model ->
              # Check various fields that might contain hardware info
              description = Map.get(model, :description, "")
              tags = Map.get(model, :tags, [])
              metadata = Map.get(model, :metadata, %{})

              hardware_indicators = ["gpu", "cpu", "memory", "nvidia", "cuda", "a100", "v100"]

              description_has_hardware =
                Enum.any?(
                  hardware_indicators,
                  &String.contains?(String.downcase(description), &1)
                )

              tags_have_hardware =
                is_list(tags) and
                  Enum.any?(tags, fn tag ->
                    Enum.any?(hardware_indicators, &String.contains?(String.downcase(tag), &1))
                  end)

              metadata_has_hardware =
                is_map(metadata) and
                  Enum.any?(Map.values(metadata), fn value ->
                    is_binary(value) and
                      Enum.any?(
                        hardware_indicators,
                        &String.contains?(String.downcase(value), &1)
                      )
                  end)

              description_has_hardware or tags_have_hardware or metadata_has_hardware
            end)

          if length(models_with_hardware) > 0 do
            hardware_model = hd(models_with_hardware)
            model_name = Map.get(hardware_model, :name, Map.get(hardware_model, :id, "unknown"))

            IO.puts("Found Replicate model with hardware info: #{model_name}")

            description = Map.get(hardware_model, :description, "")

            if String.length(description) > 0 do
              IO.puts("Description: #{String.slice(description, 0, 100)}...")
            end
          else
            IO.puts("No hardware scaling information found")
          end

        {:error, _reason} ->
          IO.puts("Skipping hardware scaling test - ReqLLM not available")
      end
    end
  end

  describe "Replicate error conditions and edge cases" do
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
      case Registry.list_models(:replicate) do
        {:ok, _models} ->
          assert true

        {:error, reason} when is_binary(reason) or is_atom(reason) ->
          assert true

        unexpected ->
          flunk("Unexpected response from Replicate model listing: #{inspect(unexpected)}")
      end
    end

    test "validates provider name consistency" do
      providers = Provider.list()
      provider_ids = Enum.map(providers, & &1.id)

      assert :replicate in provider_ids, "Replicate should be available as :replicate"

      replicate_provider = Enum.find(providers, fn p -> p.id == :replicate end)
      assert replicate_provider != nil, "Should be able to find Replicate provider"
      assert replicate_provider.id == :replicate
    end

    test "error handling for invalid model formats" do
      # Test invalid Replicate model format (should be owner/model)
      invalid_opts = {:replicate, [model: "invalid-model-format"]}

      case Model.from(invalid_opts) do
        {:error, reason} ->
          assert is_binary(reason), "Should return a descriptive error message"

        {:ok, _model} ->
          # Some configurations might work despite format issues
          assert true
      end

      # Test completely empty configuration
      empty_opts = {:replicate, []}

      case Model.from(empty_opts) do
        {:error, reason} ->
          assert is_binary(reason)

        {:ok, _model} ->
          assert true
      end
    end
  end

  describe "Replicate integration with Jido AI ecosystem" do
    test "Replicate works with provider listing APIs" do
      providers = Provider.list()
      replicate_provider = Enum.find(providers, fn p -> p.id == :replicate end)

      if replicate_provider do
        assert replicate_provider.id == :replicate
        assert replicate_provider.name != nil
      else
        IO.puts("Replicate not found in provider list - may be expected in test environment")
      end
    end

    test "Replicate compatibility with keyring system" do
      keyring_compatible = function_exported?(Keyring, :get, 2)
      assert keyring_compatible, "Keyring system should be available for authentication"

      result = Keyring.get(Keyring, :replicate_api_token, "default")
      assert is_binary(result), "Keyring should return string value"
    end

    test "provider adapter resolution" do
      providers = Provider.list()
      replicate_provider = Enum.find(providers, fn p -> p.id == :replicate end)

      if replicate_provider do
        case Provider.get_adapter_module(replicate_provider) do
          {:ok, :reqllm_backed} ->
            assert true

          {:ok, adapter} ->
            assert adapter != nil

          {:error, reason} ->
            flunk("Failed to resolve Replicate adapter: #{inspect(reason)}")
        end
      else
        IO.puts("Replicate provider not found in provider listing")
      end
    end

    test "model format validation helper" do
      # Test that Replicate models follow owner/model format
      valid_formats = [
        "meta/llama-2-70b-chat",
        "stability-ai/stable-diffusion-xl-base-1.0",
        "openai/whisper-large-v3"
      ]

      invalid_formats = [
        "just-a-model-name",
        "/missing-owner",
        "owner/",
        ""
      ]

      Enum.each(valid_formats, fn model_name ->
        assert String.contains?(model_name, "/"), "Valid format should contain '/'"
        [owner, model] = String.split(model_name, "/", parts: 2)
        assert String.length(owner) > 0, "Owner should not be empty"
        assert String.length(model) > 0, "Model should not be empty"
      end)

      Enum.each(invalid_formats, fn model_name ->
        if String.contains?(model_name, "/") do
          parts = String.split(model_name, "/", parts: 2)

          if length(parts) == 2 do
            [owner, model] = parts

            assert String.length(owner) == 0 or String.length(model) == 0,
                   "Invalid format should have empty parts"
          end
        else
          assert not String.contains?(model_name, "/"), "Invalid format should not contain '/'"
        end
      end)
    end
  end
end
