defmodule Jido.AI.Actions.Instructor.BooleanResponseTest do
  use ExUnit.Case
  use Mimic

  alias Jido.AI.Actions.Instructor.BooleanResponse
  alias Jido.AI.Actions.Instructor
  alias Jido.AI.Prompt
  alias Jido.AI.Model

  @moduletag :capture_log

  setup :set_mimic_global

  describe "run/2" do
    setup do
      {:ok, model} =
        Model.from({:anthropic, [model: "claude-3-haiku-20240307", api_key: "test-api-key"]})

      prompt = %Prompt{
        id: "test-prompt-id",
        messages: [
          %{role: :user, content: "Is this a test?"}
        ],
        version: 1
      }

      {:ok, %{model: model, prompt: prompt}}
    end

    defp mock_base_completion_response(expected_response) do
      expect(Instructor, :run, fn params, _context ->
        assert params.model != nil
        assert params.prompt != nil
        assert params.response_model == BooleanResponse.Schema
        assert params.temperature != nil
        assert params.max_tokens != nil
        assert params.mode == :json
        {:ok, %{result: expected_response}, %{}}
      end)
    end

    defp mock_base_completion_error(error) do
      expect(Instructor, :run, fn _params, _context ->
        {:error, error, %{}}
      end)
    end

    test "returns true for clear affirmative response", %{model: model, prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "The sky is blue on a clear day due to Rayleigh scattering of sunlight.",
        confidence: 0.95,
        is_ambiguous: false
      }

      mock_base_completion_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{model: model, prompt: prompt}, %{})
      assert response.result == true
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "returns false for clear negative response", %{model: model, prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: false,
        explanation:
          "The sky is not green on a clear day. It appears blue due to Rayleigh scattering.",
        confidence: 0.98,
        is_ambiguous: false
      }

      mock_base_completion_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{model: model, prompt: prompt}, %{})
      assert response.result == false
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "handles ambiguous questions", %{model: model, prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: false,
        explanation: "The question is ambiguous as it lacks context about what 'this' refers to.",
        confidence: 0.0,
        is_ambiguous: true
      }

      mock_base_completion_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{model: model, prompt: prompt}, %{})
      assert response.is_ambiguous == true
      assert response.confidence == 0.0
      assert response.explanation == expected_response.explanation
    end

    test "handles prompts with multiple messages", %{model: model, prompt: prompt} do
      prompt = %{
        prompt
        | messages: [
            %{role: :system, content: "You are a helpful assistant."},
            %{role: :user, content: "Is this a test?"}
          ]
      }

      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "This is a test question.",
        confidence: 0.9,
        is_ambiguous: false
      }

      mock_base_completion_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{model: model, prompt: prompt}, %{})
      assert response.result == true
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "handles Instructor errors gracefully", %{model: model, prompt: prompt} do
      mock_base_completion_error("API error")

      assert {:error, "API error"} = BooleanResponse.run(%{model: model, prompt: prompt}, %{})
    end

    test "supports different model providers", %{prompt: prompt} do
      openai_model = %Model{
        provider: :openai,
        model: "gpt-4",
        api_key: "test-openai-key"
      }

      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "This is a test as indicated by the context.",
        confidence: 0.98,
        is_ambiguous: false
      }

      mock_base_completion_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{model: openai_model, prompt: prompt}, %{})
      assert response.result == true
    end
  end
end
