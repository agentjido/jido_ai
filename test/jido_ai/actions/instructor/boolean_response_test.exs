defmodule Jido.AI.Actions.Instructor.BooleanResponseTest do
  use ExUnit.Case
  use Mimic

  alias Jido.AI.Actions.Instructor.{BooleanResponse, ChatCompletion}
  alias Jido.AI.Prompt
  alias Jido.Workflow

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Mimic.copy(BooleanResponse)
    Mimic.copy(Workflow)
    :ok
  end

  describe "run/2" do
    setup do
      prompt = %Prompt{
        id: "test-prompt-id",
        messages: [
          %{role: :system, content: "You are a precise reasoning engine that answers questions with true or false.\n- If you can determine a clear answer, set answer to true or false\n- Always provide a brief explanation of your reasoning\n- Set confidence between 0.00 and 1.00 based on certainty\n- If the question is ambiguous, set is_ambiguous to true and explain why\n"},
          %{role: :user, content: "Is this a test?"}
        ],
        version: 1
      }

      {:ok, %{prompt: prompt}}
    end

    defp mock_workflow_response(expected_response) do
      expect(Workflow, :run, fn ChatCompletion, params ->
        assert params[:model] != nil
        assert params[:temperature] != nil
        assert params[:max_tokens] != nil
        {:ok, %{result: expected_response}, %{}}
      end)
    end

    defp mock_workflow_error(error) do
      expect(Workflow, :run, fn ChatCompletion, params ->
        assert params[:model] != nil
        assert params[:temperature] != nil
        assert params[:max_tokens] != nil
        {:error, error, %{}}
      end)
    end

    test "returns true for clear affirmative response", %{prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "The sky is blue on a clear day due to Rayleigh scattering of sunlight.",
        confidence: 0.95,
        is_ambiguous: false
      }

      mock_workflow_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{prompt: prompt}, %{})
      assert response.result == true
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "returns false for clear negative response", %{prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: false,
        explanation: "The sky is not green on a clear day. It appears blue due to Rayleigh scattering.",
        confidence: 0.98,
        is_ambiguous: false
      }

      mock_workflow_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{prompt: prompt}, %{})
      assert response.result == false
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "handles ambiguous questions", %{prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: false,
        explanation: "The question is ambiguous as it lacks context about what 'this' refers to.",
        confidence: 0.0,
        is_ambiguous: true
      }

      mock_workflow_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{prompt: prompt}, %{})
      assert response.is_ambiguous == true
      assert response.confidence == 0.0
      assert response.explanation == expected_response.explanation
    end

    test "handles prompts with multiple messages", %{prompt: prompt} do
      prompt = %{prompt | messages: [
        %{role: :system, content: "You are a precise reasoning engine that answers questions with true or false.\n- If you can determine a clear answer, set answer to true or false\n- Always provide a brief explanation of your reasoning\n- Set confidence between 0.00 and 1.00 based on certainty\n- If the question is ambiguous, set is_ambiguous to true and explain why\n"},
        %{role: :system, content: "You are a helpful assistant."},
        %{role: :user, content: "Is this a test?"}
      ]}

      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "This is a test question.",
        confidence: 0.9,
        is_ambiguous: false
      }

      mock_workflow_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{prompt: prompt}, %{})
      assert response.result == true
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end

    test "handles workflow errors gracefully", %{prompt: prompt} do
      mock_workflow_error("API error")

      assert {:error, "API error"} = BooleanResponse.run(%{prompt: prompt}, %{})
    end

    test "handles unexpected response shapes", %{prompt: prompt} do
      expected_response = %BooleanResponse.Schema{
        answer: true,
        explanation: "This is a test question.",
        confidence: 0.9,
        is_ambiguous: false
      }

      mock_workflow_response(expected_response)

      assert {:ok, response} = BooleanResponse.run(%{prompt: prompt}, %{})
      assert response.result == true
      assert response.explanation == expected_response.explanation
      assert response.confidence == expected_response.confidence
      assert response.is_ambiguous == false
    end
  end
end
