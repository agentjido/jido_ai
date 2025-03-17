defmodule Jido.AI.Actions.Instructor.ChatResponse do
  require Logger

  defmodule Schema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A chat response from an AI assistant.
    """
    @primary_key false
    embedded_schema do
      field(:response, :string)
    end
  end

  use Jido.Action,
    name: "get_chat_response",
    description: "Get a natural language response from the AI assistant",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        required: true,
        doc: "The AI model to use"
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt containing the conversation context and query"
      ],
      temperature: [
        type: :float,
        default: 0.7,
        doc: "Temperature for response randomness"
      ],
      max_tokens: [
        type: :integer,
        default: 1000,
        doc: "Maximum tokens in response"
      ],
      mode: [
        type: {:in, [:json, nil]},
        default: :json,
        doc: "Response mode (:json or nil for default)"
      ]
    ]

  alias Jido.AI.Actions.Instructor.BaseCompletion
  alias Jido.AI.Model

  def run(params, context) do
    Logger.debug("Starting chat response generation with params: #{inspect(params, pretty: true)}")

    # Create a map with all optional parameters set to defaults
    params_with_defaults =
      Map.merge(
        %{
          temperature: 0.7,
          max_tokens: 1000,
          mode: :json
        },
        params
      )

    # Create a model using the provider tuple format
    {:ok, model} = Model.from(params_with_defaults.model)

    # Add system message to guide response structure
    enhanced_prompt = add_chat_system_message(params_with_defaults.prompt)

    # Make the chat completion call directly
    case BaseCompletion.run(
           %{
             model: model,
             prompt: enhanced_prompt,
             response_model: Schema,
             temperature: params_with_defaults.temperature,
             max_tokens: params_with_defaults.max_tokens,
             mode: params_with_defaults.mode
           },
           context
         ) do
      {:ok, %{result: %Schema{} = response}, _} ->
        {:ok, %{response: response.response}}

      {:error, reason, _} ->
        Logger.error("Chat response generation failed: #{inspect(reason)}")
        {:error, reason}

      unknown ->
        Logger.error("Unexpected response shape: #{inspect(unknown)}")
        {:error, "Unexpected response shape"}
    end
  end

  # Helper to add system message for chat responses
  defp add_chat_system_message(prompt) do
    system_msg = %{
      role: :system,
      content: """
      You are a helpful AI assistant that provides clear and informative responses.
      - Provide a natural, conversational response
      """,
      engine: :none
    }

    %{prompt | messages: [system_msg | prompt.messages]}
  end
end
