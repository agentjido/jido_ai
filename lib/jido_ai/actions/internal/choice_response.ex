defmodule Jido.AI.Actions.Internal.ChoiceResponse do
  @moduledoc """
  Internal implementation for getting multiple choice responses with explanation.

  This action uses the internal schema validation system (replacing Instructor)
  to get structured choice responses where the AI selects one option from a
  list of available choices and explains its reasoning.

  ## Features

  - 57+ LLM providers via ReqLLM
  - Internal JSON schema validation (no Instructor dependency)
  - Automatic retry on validation failures
  - Validates selected option is from available choices
  - Returns choice with explanation and confidence

  ## Usage

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-haiku-20240307"]})
      prompt = Prompt.new(:user, "Which error handling approach is best for web APIs?")

      available_actions = [
        %{id: "exception", name: "Exceptions", description: "Raise exceptions for errors"},
        %{id: "tuple", name: "Result Tuples", description: "Return {:ok, _} or {:error, _}"},
        %{id: "monad", name: "Monads", description: "Use Maybe/Either monads"}
      ]

      {:ok, response} = ChoiceResponse.run(%{
        model: model,
        prompt: prompt,
        available_actions: available_actions
      }, %{})

      # response = %{
      #   result: %{
      #     selected_option: "tuple",
      #     explanation: "Result tuples are idiomatic in Elixir...",
      #     confidence: 0.9
      #   }
      # }

  ## Parameters

  - `:model` (optional) - The AI model to use (defaults to Anthropic Claude Haiku)
  - `:prompt` (required) - The question about which option to choose
  - `:available_actions` (required) - List of choice options, each with `:id`, `:name`, `:description`
  - `:temperature` (optional) - Temperature for randomness (default: 0.7)
  - `:max_tokens` (optional) - Maximum tokens in response (default: 1000)

  ## Response Format

  Returns `{:ok, %{result: choice}}` on success, where:
  - `selected_option` - The ID of the chosen option
  - `explanation` - Reasoning behind the choice
  - `confidence` - Float between 0.0 and 1.0 indicating certainty

  ## Migration from Instructor

  Drop-in replacement for `Jido.AI.Actions.Instructor.ChoiceResponse`.
  """

  require Logger

  use Jido.Action,
    name: "generate_chat_response_internal",
    description: "Choose an option and explain why (internal implementation)",
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
      ],
      max_retries: [
        type: :integer,
        default: 3,
        doc: "Maximum number of retry attempts on validation failure"
      ]
    ]

  alias Jido.AI.Actions.ReqLlm.ChatCompletion
  alias Jido.AI.JsonRequestBuilder
  alias Jido.AI.Model
  alias Jido.AI.ResponseParser
  alias Jido.AI.Schemas.ChoiceResponseSchema

  def run(params, context) do
    Logger.debug("Starting choice response generation with params: #{inspect(params)}")

    # Apply defaults
    params_with_defaults =
      Map.merge(
        %{
          model: {:anthropic, [model: "claude-3-haiku-20240307"]},
          temperature: 0.7,
          max_tokens: 1000,
          max_retries: 3
        },
        params
      )

    # Convert model if needed
    model =
      case params_with_defaults.model do
        %Model{} = m ->
          m

        provider_tuple ->
          case Model.from(provider_tuple) do
            {:ok, m} -> m
            {:error, reason} -> raise "Failed to create model: #{inspect(reason)}"
          end
      end

    # Get list of valid option IDs
    valid_options = Enum.map(params_with_defaults.available_actions, & &1.id)

    # Enhance prompt with choice-specific system message
    enhanced_prompt =
      add_choice_system_message(
        params_with_defaults.prompt,
        params_with_defaults.available_actions
      )

    {final_prompt, opts} =
      JsonRequestBuilder.build_request(
        enhanced_prompt,
        ChoiceResponseSchema,
        temperature: params_with_defaults.temperature,
        max_tokens: params_with_defaults.max_tokens
      )

    # Execute with retry logic
    execute_with_retry(
      model,
      final_prompt,
      opts,
      context,
      params_with_defaults.max_retries,
      valid_options
    )
  end

  defp execute_with_retry(model, prompt, opts, context, retries_left, valid_options) do
    completion_params = %{
      model: model,
      prompt: prompt,
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 1000,
      response_format: opts[:response_format]
    }

    case ChatCompletion.run(completion_params, context) do
      {:ok, %{content: content}} ->
        case ResponseParser.parse_and_validate(content, ChoiceResponseSchema) do
          {:ok, validated_data} ->
            # Validate that selected_option is one of the valid options
            if validated_data.selected_option in valid_options do
              {:ok,
               %{
                 result: %{
                   selected_option: validated_data.selected_option,
                   explanation: validated_data.explanation,
                   confidence: validated_data.confidence
                 }
               }}
            else
              error_msg =
                "Selected option '#{validated_data.selected_option}' is not one of the available options. Please choose from: #{Enum.join(valid_options, ", ")}"

              if retries_left > 0 do
                Logger.warning("Invalid option selected (#{retries_left} retries left)")
                retry_prompt = add_invalid_option_error(prompt, error_msg, content)

                execute_with_retry(
                  model,
                  retry_prompt,
                  opts,
                  context,
                  retries_left - 1,
                  valid_options
                )
              else
                {:error, error_msg}
              end
            end

          {:error, validation_errors} when retries_left > 0 ->
            Logger.warning(
              "Choice response validation failed (#{retries_left} retries left): #{validation_errors}"
            )

            retry_prompt = add_validation_error_to_prompt(prompt, validation_errors, content)

            execute_with_retry(
              model,
              retry_prompt,
              opts,
              context,
              retries_left - 1,
              valid_options
            )

          {:error, validation_errors} ->
            Logger.error(
              "Choice response validation failed after all retries: #{validation_errors}"
            )

            {:error, "Response validation failed: #{validation_errors}"}
        end

      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

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

  defp add_validation_error_to_prompt(prompt, error_message, previous_response) do
    error_msg = %{
      role: :user,
      content: """
      Your previous response had validation errors:
      #{error_message}

      Previous response was:
      #{previous_response}

      Please provide a new response that matches the required JSON schema exactly.
      Required fields:
      - selected_option: string (must be one of the available option IDs)
      - explanation: string
      - confidence: number between 0.0 and 1.0
      """,
      engine: :none
    }

    %{prompt | messages: prompt.messages ++ [error_msg]}
  end

  defp add_invalid_option_error(prompt, error_message, previous_response) do
    error_msg = %{
      role: :user,
      content: """
      Your previous response selected an invalid option:
      #{error_message}

      Previous response was:
      #{previous_response}

      Please choose one of the valid option IDs listed in the system message.
      """,
      engine: :none
    }

    %{prompt | messages: prompt.messages ++ [error_msg]}
  end
end
