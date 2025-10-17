defmodule Jido.AI.Actions.Instructor.ChoiceResponse do
  require Logger

  defmodule Schema do
    use Ecto.Schema
    use Instructor

    @llm_doc """
    A response that chooses one of the available options and explains why.
    """
    @primary_key false
    embedded_schema do
      field(:selected_option, :string)
      field(:explanation, :string)
      field(:confidence, :float)
    end
  end

  use Jido.Action,
    name: "generate_chat_response",
    description: "Choose an option and explain why",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        doc: "The AI model to use (defaults to Anthropic Claude)",
        default: {:anthropic, [model: "claude-3-haiku-20240307"]}
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt to use for the response"
      ],
      available_actions: [
        type: {:list, :map},
        required: true,
        doc: "List of available options to choose from, each with an id, name, and description"
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
      ]
    ]

  alias Jido.AI.Actions.Instructor
  alias Jido.AI.Model

  def run(params, context) do
    Logger.debug("Starting choice response generation with params: #{inspect(params)}")

    # Create a map with all optional parameters set to defaults
    params_with_defaults =
      Map.merge(
        %{
          temperature: 0.7,
          max_tokens: 1000
        },
        params
      )

    # Create a model using the provider tuple format
    {:ok, model} = Model.from(params_with_defaults.model)

    # Get list of valid option IDs
    valid_options = Enum.map(params_with_defaults.available_actions, & &1.id)

    # Enhance the prompt with available options
    enhanced_prompt =
      add_choice_system_message(
        params_with_defaults.prompt,
        params_with_defaults.available_actions
      )

    # Make the chat completion call directly
    case Instructor.run(
           %{
             model: model,
             prompt: enhanced_prompt,
             response_model: Schema,
             temperature: params_with_defaults.temperature,
             max_tokens: params_with_defaults.max_tokens,
             mode: :json
           },
           context
         ) do
      {:ok, %{result: %Schema{} = response}, _} ->
        if response.selected_option in valid_options do
          {:ok,
           %{
             result: %{
               selected_option: response.selected_option,
               explanation: response.explanation,
               confidence: response.confidence
             }
           }}
        else
          {:error,
           "Selected option '#{response.selected_option}' is not one of the available options. Please choose from: #{Enum.join(valid_options, ", ")}"}
        end

      {:error, reason, _} ->
        Logger.error("Choice response generation failed: #{inspect(reason)}")
        {:error, reason}

      unknown ->
        Logger.error("Unexpected response shape: #{inspect(unknown)}")
        {:error, "Unexpected response shape"}
    end
  end

  # Helper to add system message for choice responses
  defp add_choice_system_message(prompt, available_actions) do
    system_msg = %{
      role: :system,
      content: """
      You are a helpful AI assistant that helps users learn about Elixir programming.
      When asked about error handling, you must choose one of the available options by its ID.
      The available options are:
      #{Enum.map_join(available_actions, "\n", fn opt -> "- #{opt.id}: #{opt.name} (#{opt.description})" end)}

      You must:
      - Respond with the exact ID of one of these options
      - Provide a clear explanation of your choice
      - Set confidence between 0.00 and 1.00 based on how certain you are of your choice
      """,
      engine: :none
    }

    %{prompt | messages: [system_msg | prompt.messages]}
  end
end
