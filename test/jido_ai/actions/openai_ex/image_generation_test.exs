defmodule JidoTest.AI.Actions.OpenaiEx.ImageGenerationTest do
  use ExUnit.Case, async: false
  use Mimic
  require Logger
  alias Jido.AI.Actions.OpenaiEx.ImageGeneration
  alias Jido.AI.Model
  alias OpenaiEx

  @moduletag :capture_log

  # Add global mock setup
  setup :set_mimic_global

  describe "run/2" do
    setup do
      # Copy the modules we need to mock
      Mimic.copy(OpenaiEx)
      Mimic.copy(OpenaiEx.Images)

      # Create a mock model
      {:ok, model} =
        Model.from({:openai, [model: "dall-e-3", api_key: "test-api-key"]})

      # Create valid params
      params = %{
        model: model,
        prompt: "A beautiful sunset over the ocean"
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, params: params, context: context}}
    end

    test "successfully generates an image with default parameters", %{
      params: params,
      context: context
    } do
      # Create expected request
      expected_req =
        OpenaiEx.Images.Generate.new(
          model: "dall-e-3",
          prompt: "A beautiful sunset over the ocean"
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Images, :generate, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               url: "https://example.com/image.png"
             }
           ]
         }}
      end)

      assert {:ok, %{images: ["https://example.com/image.png"]}} =
               ImageGeneration.run(params, context)
    end

    test "successfully generates multiple images", %{params: params, context: context} do
      # Update params to generate multiple images
      params = Map.put(params, :n, 2)

      # Create expected request
      expected_req =
        OpenaiEx.Images.Generate.new(
          model: "dall-e-3",
          prompt: "A beautiful sunset over the ocean",
          n: 2
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Images, :generate, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{url: "https://example.com/image1.png"},
             %{url: "https://example.com/image2.png"}
           ]
         }}
      end)

      assert {:ok,
              %{images: ["https://example.com/image1.png", "https://example.com/image2.png"]}} =
               ImageGeneration.run(params, context)
    end

    test "successfully generates images with additional parameters", %{
      params: params,
      context: context
    } do
      # Add additional parameters
      params =
        Map.merge(params, %{
          size: "1024x1792",
          quality: "hd",
          style: "natural",
          response_format: "b64_json"
        })

      # Create expected request
      expected_req =
        OpenaiEx.Images.Generate.new(
          model: "dall-e-3",
          prompt: "A beautiful sunset over the ocean",
          size: "1024x1792",
          quality: "hd",
          style: "natural",
          response_format: "b64_json"
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Images, :generate, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               b64_json: "base64_encoded_image_data"
             }
           ]
         }}
      end)

      assert {:ok, %{images: ["base64_encoded_image_data"]}} =
               ImageGeneration.run(params, context)
    end

    test "successfully generates images with OpenRouter model", %{
      params: params,
      context: context
    } do
      # Update params to use OpenRouter model
      {:ok, model} =
        Model.from({:openrouter, [model: "stability/sdxl", api_key: "test-api-key"]})

      # Update params with the OpenRouter model
      params = %{params | model: model}

      # Create expected request
      expected_req =
        OpenaiEx.Images.Generate.new(
          model: "stability/sdxl",
          prompt: "A beautiful sunset over the ocean"
        )

      # Mock the OpenRouter client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)
      expect(OpenaiEx, :with_base_url, fn client, _url -> client end)
      expect(OpenaiEx, :with_additional_headers, fn client, _headers -> client end)

      expect(OpenaiEx.Images, :generate, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               url: "https://example.com/image.png"
             }
           ]
         }}
      end)

      assert {:ok, %{images: ["https://example.com/image.png"]}} =
               ImageGeneration.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."} =
               ImageGeneration.run(params, context)
    end

    test "returns error for invalid provider", %{params: params, context: context} do
      params = %{
        params
        | model: %Model{
            provider: :invalid_provider,
            model: "test-model",
            api_key: "test-api-key",
            name: "Test Model",
            id: "test-model",
            description: "Test Model",
            created: System.system_time(:second),
            architecture: %Model.Architecture{
              modality: "text",
              tokenizer: "unknown",
              instruct_type: nil
            },
            endpoints: []
          }
      }

      assert {:error,
              "Invalid provider: :invalid_provider. Must be one of: [:openai, :openrouter, :google]"} =
               ImageGeneration.run(params, context)
    end

    test "returns error for missing prompt", %{params: params, context: context} do
      params = Map.delete(params, :prompt)

      assert {:error, "Prompt is required"} = ImageGeneration.run(params, context)
    end

    test "returns error for empty prompt", %{params: params, context: context} do
      params = %{params | prompt: ""}

      assert {:error, "Prompt must be a non-empty string"} = ImageGeneration.run(params, context)
    end

    test "returns error for invalid prompt type", %{params: params, context: context} do
      params = %{params | prompt: 123}

      assert {:error, "Prompt must be a non-empty string"} = ImageGeneration.run(params, context)
    end
  end
end
