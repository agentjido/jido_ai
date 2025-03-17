defmodule Jido.AI.Actions.Instructor.ChoiceResponseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Instructor.{ChoiceResponse, BaseCompletion}
  alias Jido.AI.Prompt
  alias Jido.AI.Model

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Mimic.copy(BaseCompletion)
    :ok
  end

  defp create_prompt(content, engine \\ :none, params \\ %{}) do
    %Prompt{
      metadata: %{},
      params: params,
      messages: [
        %{role: :user, engine: engine, content: content}
      ],
      history: [],
      version: 1,
      id: "test-prompt-id"
    }
  end

  defp create_model do
    {:ok, model} = Model.from({:anthropic, [
      model_id: "claude-3-sonnet-20240229",
      api_key: "test-api-key"
    ]})

    model
  end

  defp mock_base_completion_response(expected_response) do
    expect(BaseCompletion, :run, fn params, _context ->
      assert params.model != nil
      assert params.prompt != nil
      assert params.response_model == ChoiceResponse.Schema
      assert params.temperature != nil
      assert params.max_tokens != nil
      assert params.mode == :json
      {:ok, %{result: expected_response}, %{}}
    end)
  end

  defp mock_base_completion_error(error) do
    expect(BaseCompletion, :run, fn _params, _context ->
      {:error, error, %{}}
    end)
  end

  describe "run/2" do
    test "selects a valid option and provides explanation" do
      prompt = create_prompt("How should I handle errors?")
      model = create_model()

      available_actions = [
        %{id: "try_rescue", name: "Try/Rescue", description: "Use try/rescue for error handling"},
        %{
          id: "with_statement",
          name: "With Statement",
          description: "Use with statement for error handling"
        }
      ]

      expected_response = %ChoiceResponse.Schema{
        selected_option: "with_statement",
        confidence: 0.8,
        explanation:
          "For error handling in Elixir, I would recommend using the 'with' statement. The 'with' statement allows you to chain multiple function calls together and handle errors at each step, rather than having to wrap everything in a try/rescue block. This makes your code more readable and maintainable, especially for complex error handling scenarios."
      }

      mock_base_completion_response(expected_response)

      assert {:ok, %{result: result}} = ChoiceResponse.run(
        %{
          prompt: prompt,
          model: model,
          temperature: 0.7,
          max_tokens: 1024,
          available_actions: available_actions
        },
        %{}
      )

      assert result.selected_option == "with_statement"
      assert result.confidence == 0.8
      assert result.explanation == expected_response.explanation
    end

    test "rejects invalid option selection" do
      prompt = create_prompt("How should I handle errors?")
      model = create_model()

      available_actions = [
        %{id: "try_rescue", name: "Try/Rescue", description: "Use try/rescue for error handling"},
        %{
          id: "with_statement",
          name: "With Statement",
          description: "Use with statement for error handling"
        }
      ]

      expected_response = %ChoiceResponse.Schema{
        selected_option: "invalid_option",
        confidence: 0.7,
        explanation: "The selected option is not valid."
      }

      mock_base_completion_response(expected_response)

      assert {:error, error_message} = ChoiceResponse.run(
        %{
          prompt: prompt,
          model: model,
          temperature: 0.7,
          max_tokens: 1024,
          available_actions: available_actions
        },
        %{}
      )

      assert error_message =~ "Selected option 'invalid_option' is not one of the available options"
    end

    test "handles base completion errors gracefully" do
      prompt = create_prompt("How should I handle errors?")
      model = create_model()

      available_actions = [
        %{id: "try_rescue", name: "Try/Rescue", description: "Use try/rescue for error handling"},
        %{
          id: "with_statement",
          name: "With Statement",
          description: "Use with statement for error handling"
        }
      ]

      mock_base_completion_error("API rate limit exceeded")

      assert {:error, "API rate limit exceeded"} = ChoiceResponse.run(
        %{
          prompt: prompt,
          model: model,
          temperature: 0.7,
          max_tokens: 1024,
          available_actions: available_actions
        },
        %{}
      )
    end

    test "supports different model providers" do
      prompt = create_prompt("How should I handle errors?")

      # Use OpenAI model
      {:ok, openai_model} = Model.from({:openai, [
        model_id: "gpt-4",
        api_key: "test-openai-key"
      ]})

      available_actions = [
        %{id: "try_rescue", name: "Try/Rescue", description: "Use try/rescue for error handling"},
        %{
          id: "with_statement",
          name: "With Statement",
          description: "Use with statement for error handling"
        }
      ]

      expected_response = %ChoiceResponse.Schema{
        selected_option: "try_rescue",
        confidence: 0.85,
        explanation: "Try/Rescue is a common pattern in Elixir for handling exceptions."
      }

      mock_base_completion_response(expected_response)

      assert {:ok, %{result: result}} = ChoiceResponse.run(
        %{
          prompt: prompt,
          model: openai_model,
          available_actions: available_actions
        },
        %{}
      )

      assert result.selected_option == "try_rescue"
      assert result.confidence == 0.85
    end
  end
end
