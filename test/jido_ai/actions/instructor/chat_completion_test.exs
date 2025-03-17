defmodule JidoTest.AI.Actions.Instructor.BaseCompletionTest do
  use ExUnit.Case
  use Mimic
  require Logger

  alias Jido.AI.Actions.Instructor.BaseCompletion
  alias Jido.AI.Model
  alias Jido.AI.Prompt

  # Define test response model at module level
  defmodule TestResponse do
    use Ecto.Schema

    embedded_schema do
      field :message, :string
    end
  end

  @moduletag :capture_log

  describe "run/2" do
    setup do
      # Copy Instructor module for Mimic
      Mimic.copy(Instructor)

      # Create a mock model for Anthropic
      anthropic_model = %Model{
        provider: :anthropic,
        model_id: "claude-3-sonnet-20240229",
        api_key: "test-api-key",
        temperature: 0.7,
        max_tokens: 1024,
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

      # Create a mock model for OpenAI
      openai_model = %{anthropic_model | provider: :openai}

      # Create a mock model for Ollama
      ollama_model = %{anthropic_model | provider: :ollama, base_url: "http://test-ollama:11434"}

      # Create a prompt
      prompt = Prompt.new(:user, "Hello, how are you?")

      # Create valid params
      params = %{
        model: anthropic_model,
        prompt: prompt,
        response_model: TestResponse
      }

      # Create context
      context = %{state: %{}}

      {:ok, %{
        anthropic_model: anthropic_model,
        openai_model: openai_model,
        ollama_model: ollama_model,
        prompt: prompt,
        params: params,
        context: context
      }}
    end

    test "successfully processes a valid request", %{params: params, context: context} do
      # Create expected response
      expected_response = %TestResponse{message: "I'm doing well, thank you!"}

      # Mock Instructor.chat_completion
      expect(Instructor, :chat_completion, fn opts, config ->
        # Verify the configuration
        assert config[:adapter] == Instructor.Adapters.Anthropic
        assert config[:api_key] == "test-api-key"

        # Verify the options
        assert opts[:model] == "claude-3-sonnet-20240229"
        assert opts[:temperature] == 0.7
        assert opts[:max_tokens] == 1000
        assert opts[:response_model] == TestResponse
        assert [%{role: "user", content: "Hello, how are you?"}] = opts[:messages]

        {:ok, expected_response}
      end)

      assert {:ok, %{result: ^expected_response}, %{}} = BaseCompletion.run(params, context)
    end

    test "handles error response from Instructor", %{params: params, context: context} do
      expect(Instructor, :chat_completion, fn _opts, _config ->
        {:error, "API Error"}
      end)

      assert {:error, "API Error", %{}} = BaseCompletion.run(params, context)
    end

    test "handles nil response from Instructor", %{params: params, context: context} do
      expect(Instructor, :chat_completion, fn _opts, _config ->
        nil
      end)

      assert {:error, "Instructor chat completion returned nil", %{}} =
        BaseCompletion.run(params, context)
    end

    test "handles streaming response", %{params: params, context: context} do
      params = Map.merge(params, %{stream: true})
      expected_response = [%TestResponse{message: "I'm doing well!"}, %TestResponse{message: "Thank you!"}]

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:stream] == true
        assert opts[:response_model] == {:array, TestResponse}
        {:ok, expected_response}
      end)

      assert {:ok, %{result: ^expected_response}, %{}} = BaseCompletion.run(params, context)
    end

    test "handles partial streaming response", %{params: params, context: context} do
      params = Map.merge(params, %{stream: true, partial: true})
      expected_response = %TestResponse{message: "I'm doing well!"}

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:stream] == true
        assert opts[:response_model] == {:partial, TestResponse}
        {:ok, expected_response}
      end)

      assert {:ok, %{result: ^expected_response}, %{}} = BaseCompletion.run(params, context)
    end

    test "handles optional parameters", %{params: params, context: context} do
      params = Map.merge(params, %{
        top_p: 0.9,
        stop: ["END"],
        max_retries: 2,
        mode: :json
      })

      expect(Instructor, :chat_completion, fn opts, _config ->
        assert opts[:top_p] == 0.9
        assert opts[:stop] == ["END"]
        assert opts[:max_retries] == 2
        assert opts[:mode] == :json
        {:ok, %TestResponse{message: "Response"}}
      end)

      assert {:ok, %{result: %TestResponse{message: "Response"}}, %{}} =
        BaseCompletion.run(params, context)
    end

    test "uses OpenAI adapter for OpenAI provider", %{openai_model: model, prompt: prompt, context: context} do
      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      expect(Instructor, :chat_completion, fn _opts, config ->
        assert config[:adapter] == Instructor.Adapters.OpenAI
        assert config[:openai][:api_key] == "test-api-key"
        {:ok, %TestResponse{message: "OpenAI response"}}
      end)

      assert {:ok, %{result: %TestResponse{message: "OpenAI response"}}, %{}} =
        BaseCompletion.run(params, context)
    end

    test "uses Ollama provider configuration", %{ollama_model: model, prompt: prompt, context: context} do
      params = %{
        model: model,
        prompt: prompt,
        response_model: TestResponse
      }

      expect(Instructor, :chat_completion, fn _opts, config ->
        assert config[:adapter] == Instructor.Adapters.OpenAI
        assert config[:openai][:api_key] == "test-api-key"
        assert config[:openai][:api_url] == "http://test-ollama:11434"
        {:ok, %TestResponse{message: "Ollama response"}}
      end)

      assert {:ok, %{result: %TestResponse{message: "Ollama response"}}, %{}} =
        BaseCompletion.run(params, context)
    end

    test "validates model specification", context do
      params = %{context.params | model: "invalid_model"}

      assert {:error, "Invalid model specification: \"invalid_model\""} =
        BaseCompletion.on_before_validate_params(params)
    end

    test "converts string to system prompt", context do
      params = %{context.params | prompt: "Hello, system!"}

      assert {:ok, validated_params} = BaseCompletion.on_before_validate_params(params)
      assert %Prompt{} = validated_params.prompt
      assert [%{role: :system, content: "Hello, system!"}] = Prompt.render(validated_params.prompt)
    end

    test "rejects invalid prompt type", context do
      params = %{context.params | prompt: ["not a string or prompt"]}

      assert {:error, "Expected a string or a Jido.AI.Prompt struct, got: [\"not a string or prompt\"]"} =
        BaseCompletion.on_before_validate_params(params)
    end
  end
end
