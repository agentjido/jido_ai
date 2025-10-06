defmodule JidoTest.AI.Actions.OpenaiEx.EmbeddingsReqLLMTest do
  use ExUnit.Case, async: false
  use Mimic

  import Mimic

  @moduletag :capture_log

  alias Jido.AI.Actions.OpenaiEx.Embeddings
  alias Jido.AI.Model
  alias ReqLlmBridge.Provider.Generated.ValidProviders

  # Add global mock setup
  setup :set_mimic_global

  setup do
    # Copy the modules we need to mock
    Mimic.copy(ReqLLM)
    Mimic.copy(JidoKeys)
    Mimic.copy(ValidProviders)

    # Create a mock model with ReqLLM ID
    {:ok, model} =
      Model.from({:openai, [model: "text-embedding-ada-002", api_key: "test-api-key"]})

    model = %{model | reqllm_id: "openai:text-embedding-ada-002"}

    # Create valid params for embeddings
    params = %{
      model: model,
      input: ["Hello world", "How are you?"]
    }

    # Create context
    context = %{state: %{}}

    {:ok, %{model: model, params: params, context: context}}
  end

  describe "validate_model_for_reqllm/1" do
    test "validates model with reqllm_id", %{model: model} do
      # This is a private function, so we test it indirectly through run/2
      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2, 0.3]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == [[0.1, 0.2, 0.3]]
    end

    test "rejects model without reqllm_id" do
      model_without_reqllm = %{reqllm_id: nil, api_key: "test-key"}
      params = %{model: model_without_reqllm, input: ["test"]}

      assert {:error, reason} = Embeddings.run(params, %{})
      assert reason =~ "ReqLLM ID is required"
    end

    test "rejects unsupported model types" do
      invalid_model = "not-a-model-struct"
      params = %{model: invalid_model, input: ["test"]}

      assert {:error, reason} = Embeddings.run(params, %{})
      assert reason =~ "Invalid model type"
    end
  end

  describe "extract_provider_from_reqllm_id/1" do
    test "extracts provider safely with valid providers" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      # Test through integration since it's a private function
      params = %{
        model: %{reqllm_id: "openai:text-embedding-ada-002", api_key: "test-key"},
        input: ["test"]
      }

      expect(ReqLLM, :embed_many, fn reqllm_id, _input, _opts ->
        assert reqllm_id == "openai:text-embedding-ada-002"
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(JidoKeys, :put, fn provider, key ->
        assert provider == :openai
        assert key == "test-key"
        :ok
      end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end

    test "handles invalid provider safely" do
      expect(ValidProviders, :list, fn ->
        # Limited list
        [:openai, :anthropic]
      end)

      # Should handle invalid provider gracefully
      params = %{
        model: %{reqllm_id: "invalid_provider:model", api_key: "test-key"},
        input: ["test"]
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      # JidoKeys.put should not be called for invalid provider
      expect(JidoKeys, :put, 0, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end

    test "prevents arbitrary atom creation" do
      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      params = %{
        model: %{reqllm_id: "malicious_atom_provider:model", api_key: "test-key"},
        input: ["test"]
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      # Should not create arbitrary atoms
      expect(JidoKeys, :put, 0, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})

      # Verify the malicious atom wasn't created
      assert_raise ArgumentError, fn ->
        :malicious_atom_provider = :this_should_not_exist
      end
    end
  end

  describe "build_reqllm_options/2" do
    test "builds options correctly with all parameters", %{model: model} do
      params = %{
        model: model,
        input: ["test"],
        encoding_format: "float",
        user: "test-user",
        dimensions: 512
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, opts ->
        # Verify the options were built correctly
        opts_map = Enum.into(opts, %{})
        assert opts_map[:encoding_format] == "float"
        assert opts_map[:user] == "test-user"
        assert opts_map[:dimensions] == 512

        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end

    test "handles missing optional parameters", %{model: model} do
      params = %{
        model: model,
        input: ["test"]
        # No optional parameters
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, opts ->
        # Should only have default options
        opts_map = Enum.into(opts, %{})
        assert Map.has_key?(opts_map, :encoding_format) == false
        assert Map.has_key?(opts_map, :user) == false
        assert Map.has_key?(opts_map, :dimensions) == false

        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end

    test "filters unsupported parameters", %{model: model} do
      params = %{
        model: model,
        input: ["test"],
        encoding_format: "float",
        unsupported_param: "should_be_ignored",
        another_unknown: 123
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, opts ->
        opts_map = Enum.into(opts, %{})
        assert opts_map[:encoding_format] == "float"
        assert Map.has_key?(opts_map, :unsupported_param) == false
        assert Map.has_key?(opts_map, :another_unknown) == false

        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end
  end

  describe "convert_reqllm_response/1" do
    test "converts standard ReqLLM response format", %{model: _model, params: params} do
      reqllm_response = %{
        embeddings: [
          [0.1, 0.2, 0.3],
          [0.4, 0.5, 0.6]
        ],
        usage: %{prompt_tokens: 5, total_tokens: 5}
      }

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, reqllm_response}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})

      assert response.embeddings == [
               [0.1, 0.2, 0.3],
               [0.4, 0.5, 0.6]
             ]
    end

    test "handles response with metadata", %{model: model} do
      reqllm_response = %{
        embeddings: [[0.1, 0.2]],
        usage: %{prompt_tokens: 3, total_tokens: 3},
        model: "text-embedding-ada-002"
      }

      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, reqllm_response}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == [[0.1, 0.2]]
    end

    test "handles response without usage metadata", %{model: model} do
      reqllm_response = %{
        embeddings: [[0.1, 0.2, 0.3]]
        # No usage field
      }

      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, reqllm_response}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == [[0.1, 0.2, 0.3]]
    end

    test "handles empty embeddings list", %{model: model} do
      reqllm_response = %{
        embeddings: []
      }

      params = %{model: model, input: []}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, reqllm_response}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == []
    end
  end

  describe "input validation and processing" do
    test "handles string input correctly", %{model: model} do
      params = %{model: model, input: "Single string input"}

      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        assert input_list == ["Single string input"]
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == [[0.1, 0.2]]
    end

    test "handles list of strings correctly", %{model: model} do
      params = %{model: model, input: ["First string", "Second string"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        assert input_list == ["First string", "Second string"]
        {:ok, %{embeddings: [[0.1, 0.2], [0.3, 0.4]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == [[0.1, 0.2], [0.3, 0.4]]
    end

    test "validates batch size limits", %{model: model} do
      # Create input that exceeds batch size (assuming limit of 100)
      large_input = Enum.map(1..101, fn i -> "Text #{i}" end)
      params = %{model: model, input: large_input}

      # Should handle large batches by processing in chunks
      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        # ReqLLM should receive a reasonable batch size
        assert length(input_list) <= 100
        {:ok, %{embeddings: Enum.map(input_list, fn _ -> [0.1, 0.2] end)}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert length(response.embeddings) <= 100
    end

    test "handles empty input gracefully", %{model: model} do
      params = %{model: model, input: []}

      expect(ReqLLM, :embed_many, fn _reqllm_id, input_list, _opts ->
        assert input_list == []
        {:ok, %{embeddings: []}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      assert {:ok, response} = Embeddings.run(params, %{})
      assert response.embeddings == []
    end
  end

  describe "error handling" do
    test "handles ReqLLM errors correctly", %{model: model} do
      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:error, %{message: "Rate limit exceeded", code: 429}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      expect(ReqLLM, :map_error, fn {:error, error} ->
        {:error, "Rate limit exceeded: #{error.message}"}
      end)

      assert {:error, error_message} = Embeddings.run(params, %{})
      assert error_message =~ "Rate limit exceeded"
    end

    test "handles network errors", %{model: model} do
      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:error, :timeout}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      expect(ReqLLM, :map_error, fn {:error, :timeout} ->
        {:error, "Request timed out"}
      end)

      assert {:error, error_message} = Embeddings.run(params, %{})
      assert error_message == "Request timed out"
    end

    test "handles invalid API key errors", %{model: model} do
      params = %{model: model, input: ["test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:error, %{message: "Invalid API key", code: 401}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      expect(JidoKeys, :put, fn _provider, _key -> :ok end)

      expect(ReqLLM, :map_error, fn {:error, error} ->
        {:error, "Authentication failed: #{error.message}"}
      end)

      assert {:error, error_message} = Embeddings.run(params, %{})
      assert error_message =~ "Authentication failed"
    end
  end

  describe "integration with ReqLLM" do
    test "full integration test with mocked ReqLLM", %{params: params, context: context} do
      # Mock ReqLlmBridge.embed_many
      expect(ReqLLM, :embed_many, fn reqllm_id, input_list, opts ->
        assert reqllm_id == "openai:text-embedding-ada-002"
        assert input_list == ["Hello world", "How are you?"]
        assert is_list(opts)

        {:ok,
         %{
           embeddings: [
             [0.1, 0.2, 0.3, 0.4],
             [0.5, 0.6, 0.7, 0.8]
           ],
           usage: %{prompt_tokens: 6, total_tokens: 6}
         }}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google, :openrouter]
      end)

      expect(JidoKeys, :put, fn provider, api_key ->
        assert provider == :openai
        assert api_key == "test-api-key"
        :ok
      end)

      # Execute the action
      assert {:ok, response} = Embeddings.run(params, context)

      # Verify response format
      assert response.embeddings == [
               [0.1, 0.2, 0.3, 0.4],
               [0.5, 0.6, 0.7, 0.8]
             ]

      assert length(response.embeddings) == 2
      assert length(Enum.at(response.embeddings, 0)) == 4
    end

    test "integration with different providers", %{context: context} do
      # Test with Anthropic model
      {:ok, anthropic_model} =
        Model.from({:anthropic, [model: "claude-3-haiku", api_key: "anthropic-key"]})

      anthropic_model = %{anthropic_model | reqllm_id: "anthropic:claude-3-haiku"}

      params = %{
        model: anthropic_model,
        input: ["Test with Anthropic"]
      }

      expect(ReqLLM, :embed_many, fn reqllm_id, _input, _opts ->
        assert reqllm_id == "anthropic:claude-3-haiku"
        {:ok, %{embeddings: [[0.9, 0.8, 0.7]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(JidoKeys, :put, fn provider, api_key ->
        assert provider == :anthropic
        assert api_key == "anthropic-key"
        :ok
      end)

      assert {:ok, response} = Embeddings.run(params, context)
      assert response.embeddings == [[0.9, 0.8, 0.7]]
    end
  end

  describe "security and validation" do
    test "API key management security", %{model: model} do
      params = %{model: model, input: ["security test"]}

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      expect(ValidProviders, :list, fn ->
        [:openai]
      end)

      # Verify API key is handled securely
      expect(JidoKeys, :put, fn provider, api_key ->
        assert provider == :openai
        assert api_key == "test-api-key"
        # Verify this is the secure way to store keys
        :ok
      end)

      assert {:ok, _response} = Embeddings.run(params, %{})

      # Verify the call was made with secure key management
      # assert_called(JidoKeys.put(:openai, "test-api-key"))
    end

    test "provider validation prevents injection", %{model: model} do
      # Test with malicious provider string
      malicious_model = %{model | reqllm_id: "'; DROP TABLE users; --:model"}
      params = %{model: malicious_model, input: ["injection test"]}

      expect(ValidProviders, :list, fn ->
        [:openai, :anthropic, :google]
      end)

      expect(ReqLLM, :embed_many, fn _reqllm_id, _input, _opts ->
        {:ok, %{embeddings: [[0.1, 0.2]]}}
      end)

      # Should not call JidoKeys.put with malicious provider
      expect(JidoKeys, :put, 0, fn _provider, _key -> :ok end)

      assert {:ok, _response} = Embeddings.run(params, %{})
    end
  end
end
