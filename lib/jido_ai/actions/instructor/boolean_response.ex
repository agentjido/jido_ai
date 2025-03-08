defmodule Jido.AI.Actions.Instructor.BooleanResponse do
  require Logger

  defmodule Schema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A boolean response from an AI assistant.
    """
    @primary_key false
    embedded_schema do
      field(:answer, :boolean)
      field(:explanation, :string)
      field(:confidence, :float)
      field(:is_ambiguous, :boolean)
    end
  end

  use Jido.Action,
    name: "get_boolean_response",
    description: "Get a true/false answer to a question with explanation",
    schema: [
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt containing the yes/no question"
      ]
    ]

  alias Jido.AI.Actions.Instructor.ChatCompletion
  alias Jido.AI.Model

  def run(params, _context) do
    Logger.debug("Starting boolean response generation with params: #{inspect(params)}")

    # Create a model using the provider tuple format
    {:ok, model} = Model.from({:anthropic, [model_id: "claude-3-haiku-20240307"]})

    # Add system message to force structured boolean response
    enhanced_prompt = add_boolean_system_message(params.prompt)

    # Make the chat completion call
    case Jido.Workflow.run(ChatCompletion, %{
           model: model,
           prompt: enhanced_prompt,
           response_model: Schema,
           temperature: 0.1,
           max_tokens: 500
         }) do
      {:ok, %{result: %Schema{} = response}, _} ->
        {:ok,
         %{
           result: response.answer,
           explanation: response.explanation,
           confidence: response.confidence,
           is_ambiguous: response.is_ambiguous
         }}

      {:error, reason, _} ->
        Logger.error("Boolean response generation failed: #{inspect(reason)}")
        {:error, reason}

      unknown ->
        Logger.error("Unexpected response shape: #{inspect(unknown)}")
        {:error, "Unexpected response shape"}
    end
  end

  # Helper to add system message for boolean responses
  defp add_boolean_system_message(prompt) do
    system_msg = %{
      role: :system,
      content: """
      You are a precise reasoning engine that answers questions with true or false.
      - If you can determine a clear answer, set answer to true or false
      - Always provide a brief explanation of your reasoning
      - Set confidence between 0.00 and 1.00 based on certainty
      - If the question is ambiguous, set is_ambiguous to true and explain why
      """,
      engine: :none
    }

    %{prompt | messages: [system_msg | prompt.messages]}
  end
end
