defmodule JidoTest.AI.Actions.OpenaiEx.EmbeddingsTest do
  use ExUnit.Case, async: false
  use Mimic
  require Logger
  alias Jido.AI.Actions.OpenaiEx.Embeddings
  alias Jido.AI.Model
  alias OpenaiEx

  @moduletag :capture_log

  # Add global mock setup
  setup :set_mimic_global

  describe "run/2" do
    setup do
      {:ok, model} =
        Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-api-key"]})

      # Create valid params
      params = %{
        model: model,
        input: "Hello, world!"
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{model: model, params: params, context: context}}
    end

    test "successfully generates embeddings for a single string", %{
      params: params,
      context: context
    } do
      # Create expected request
      expected_req =
        OpenaiEx.Embeddings.new(
          model: "text-embedding-ada-002",
          input: "Hello, world!"
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Embeddings, :create, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               embedding: [0.1, 0.2, 0.3]
             }
           ]
         }}
      end)

      assert {:ok, %{embeddings: [[0.1, 0.2, 0.3]]}} = Embeddings.run(params, context)
    end

    test "successfully generates embeddings for multiple strings", %{
      params: params,
      context: context
    } do
      # Update params with multiple inputs
      params = %{params | input: ["Hello", "World"]}

      # Create expected request
      expected_req =
        OpenaiEx.Embeddings.new(
          model: "text-embedding-ada-002",
          input: ["Hello", "World"]
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Embeddings, :create, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{embedding: [0.1, 0.2, 0.3]},
             %{embedding: [0.4, 0.5, 0.6]}
           ]
         }}
      end)

      assert {:ok, %{embeddings: [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]}} =
               Embeddings.run(params, context)
    end

    test "successfully generates embeddings with additional parameters", %{
      params: params,
      context: context
    } do
      # Add additional parameters
      params =
        Map.merge(params, %{
          dimensions: 1024,
          encoding_format: :base64
        })

      # Create expected request
      expected_req =
        OpenaiEx.Embeddings.new(
          model: "text-embedding-ada-002",
          input: "Hello, world!",
          dimensions: 1024,
          encoding_format: :base64
        )

      # Mock the OpenAI client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)

      expect(OpenaiEx.Embeddings, :create, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               embedding: [0.1, 0.2, 0.3]
             }
           ]
         }}
      end)

      assert {:ok, %{embeddings: [[0.1, 0.2, 0.3]]}} = Embeddings.run(params, context)
    end

    test "successfully generates embeddings with OpenRouter model", %{
      params: params,
      context: context
    } do
      {:ok, model} =
        Model.from(
          {:openrouter, [model: "openai/text-embedding-3-large", api_key: "test-api-key"]}
        )

      # Update params to use OpenRouter model
      params = %{
        params
        | model: model
      }

      # Create expected request
      expected_req =
        OpenaiEx.Embeddings.new(
          model: "openai/text-embedding-3-large",
          input: "Hello, world!"
        )

      # Mock the OpenRouter client
      expect(OpenaiEx, :new, fn "test-api-key" -> %OpenaiEx{} end)
      expect(OpenaiEx, :with_base_url, fn client, _url -> client end)
      expect(OpenaiEx, :with_additional_headers, fn client, _headers -> client end)

      expect(OpenaiEx.Embeddings, :create, fn _client, ^expected_req ->
        {:ok,
         %{
           data: [
             %{
               embedding: [0.1, 0.2, 0.3]
             }
           ]
         }}
      end)

      assert {:ok, %{embeddings: [[0.1, 0.2, 0.3]]}} = Embeddings.run(params, context)
    end

    test "returns error for invalid model specification", %{params: params, context: context} do
      params = %{params | model: "invalid_model"}

      assert {:error, "Invalid model specification. Must be a map or {provider, opts} tuple."} =
               Embeddings.run(params, context)
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
              "Invalid provider: :invalid_provider. Must be one of: [:openai, :openrouter]"} =
               Embeddings.run(params, context)
    end

    test "returns error for invalid input type", %{params: params, context: context} do
      params = %{params | input: 123}

      assert {:error, "Input must be a string or list of strings"} =
               Embeddings.run(params, context)
    end

    test "returns error for invalid input list", %{params: params, context: context} do
      params = %{params | input: ["valid", 123, "also valid"]}

      assert {:error, "All inputs must be strings"} = Embeddings.run(params, context)
    end
  end
end
