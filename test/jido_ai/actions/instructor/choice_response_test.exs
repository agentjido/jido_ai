defmodule Jido.AI.Actions.Instructor.ChoiceResponseTest do
  use ExUnit.Case, async: true
  use Mimic

  alias Jido.AI.Actions.Instructor.ChoiceResponse
  alias Jido.AI.Prompt
  alias Jido.AI.Model

  @moduletag :capture_log

  setup :set_mimic_global

  setup do
    Mimic.copy(ChoiceResponse)
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
    Model.from(%{
      max_retries: 0,
      max_tokens: 1024,
      temperature: 0.7,
      model_id: "claude-3-sonnet-20240229",
      api_key: "test-api-key",
      base_url: "https://api.anthropic.com/v1",
      endpoints: [],
      description: "Anthropic Claude model",
      created: 1_741_285_515,
      architecture: %{
        tokenizer: "unknown",
        modality: "text",
        instruct_type: nil
      },
      provider: :anthropic,
      name: "Anthropic claude-3-sonnet-20240229",
      id: "anthropic_claude-3-sonnet-20240229"
    })
  end

  defp mock_workflow_response(expected_response) do
    expect(ChoiceResponse, :run, fn params, _opts ->
      assert params[:model] != nil
      assert params[:temperature] != nil
      assert params[:max_tokens] != nil
      {:ok, %{result: expected_response}, %{}}
    end)
  end

  defp mock_workflow_error(error) do
    expect(ChoiceResponse, :run, fn params, _opts ->
      assert params[:model] != nil
      assert params[:temperature] != nil
      assert params[:max_tokens] != nil
      {:error, error, %{}}
    end)
  end

  defp assert_response(actual, expected) do
    assert {:ok, %{result: result}, %{}} = actual
    assert result[:selected_option] == expected[:selected_option]
    assert result[:confidence] == expected[:confidence]
    assert result[:explanation] == expected[:explanation]
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

      expected_response = %{
        selected_option: "with_statement",
        confidence: 0.8,
        explanation:
          "For error handling in Elixir, I would recommend using the 'with' statement. The 'with' statement allows you to chain multiple function calls together and handle errors at each step, rather than having to wrap everything in a try/rescue block. This makes your code more readable and maintainable, especially for complex error handling scenarios."
      }

      mock_workflow_response(expected_response)

      assert_response(
        ChoiceResponse.run(
          %{
            prompt: prompt,
            model: model,
            temperature: 0.7,
            max_tokens: 1024,
            available_actions: available_actions
          },
          %{}
        ),
        expected_response
      )
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

      expected_response = %{
        selected_option: "invalid_option",
        confidence: +0.0,
        explanation: "The selected option is not valid."
      }

      mock_workflow_response(expected_response)

      assert {:ok,
              %{
                result: %{
                  selected_option: "invalid_option",
                  confidence: +0.0,
                  explanation: "The selected option is not valid."
                }
              },
              %{}} =
               ChoiceResponse.run(
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

    test "handles workflow errors gracefully" do
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

      mock_workflow_error("API rate limit exceeded")

      assert {:error, "API rate limit exceeded", %{}} =
               ChoiceResponse.run(
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
  end
end
