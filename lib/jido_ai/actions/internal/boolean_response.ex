defmodule Jido.AI.Actions.Internal.BooleanResponse do
  @moduledoc """
  Internal implementation for getting boolean (yes/no) answers with explanation.

  This action uses the internal schema validation system (replacing Instructor)
  to get structured boolean responses with reasoning and confidence scoring.

  ## Features

  - 57+ LLM providers via ReqLLM
  - Internal JSON schema validation (no Instructor dependency)
  - Automatic retry on validation failures
  - Returns boolean answer with explanation and confidence
  - Detects ambiguous questions

  ## Usage

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-haiku-20240307"]})
      prompt = Prompt.new(:user, "Is Earth the third planet from the Sun?")

      {:ok, response} = BooleanResponse.run(%{
        model: model,
        prompt: prompt
      }, %{})

      # response = %{
      #   result: true,
      #   explanation: "Yes, Earth is the third planet...",
      #   confidence: 1.0,
      #   is_ambiguous: false
      # }

  ## Parameters

  - `:model` (optional) - The AI model to use (defaults to Anthropic Claude Haiku)
  - `:prompt` (required) - The yes/no question (Prompt struct or string)
  - `:temperature` (optional) - Temperature for randomness (default: 0.1 for deterministic answers)
  - `:max_tokens` (optional) - Maximum tokens in response (default: 500)

  ## Response Format

  Returns `{:ok, response}` on success, where:
  - `result` - Boolean true/false answer
  - `explanation` - Reasoning behind the answer
  - `confidence` - Float between 0.0 and 1.0 indicating certainty
  - `is_ambiguous` - Boolean indicating if the question was ambiguous

  ## Migration from Instructor

  Drop-in replacement for `Jido.AI.Actions.Instructor.BooleanResponse`.
  """

  require Logger

  use Jido.Action,
    name: "get_boolean_response_internal",
    description: "Get a true/false answer with explanation (internal implementation)",
    schema: [
      model: [
        type: {:custom, Jido.AI.Model, :validate_model_opts, []},
        doc: "The AI model to use (defaults to Anthropic Claude)",
        default: {:anthropic, [model: "claude-3-haiku-20240307"]}
      ],
      prompt: [
        type: {:custom, Jido.AI.Prompt, :validate_prompt_opts, []},
        required: true,
        doc: "The prompt containing the yes/no question"
      ],
      temperature: [
        type: :float,
        default: 0.1,
        doc: "Temperature for response randomness (lower is more deterministic)"
      ],
      max_tokens: [
        type: :integer,
        default: 500,
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
  alias Jido.AI.Schemas.BooleanResponseSchema

  def run(params, context) do
    # Apply defaults
    params_with_defaults =
      Map.merge(
        %{
          model: {:anthropic, [model: "claude-3-haiku-20240307"]},
          temperature: 0.1,
          max_tokens: 500,
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

    # Enhance prompt with boolean-specific system message and schema
    enhanced_prompt = add_boolean_system_message(params_with_defaults.prompt)

    {final_prompt, opts} =
      JsonRequestBuilder.build_request(
        enhanced_prompt,
        BooleanResponseSchema,
        temperature: params_with_defaults.temperature,
        max_tokens: params_with_defaults.max_tokens
      )

    # Execute with retry logic
    execute_with_retry(
      model,
      final_prompt,
      opts,
      context,
      params_with_defaults.max_retries
    )
  end

  defp execute_with_retry(model, prompt, opts, context, retries_left) do
    completion_params = %{
      model: model,
      prompt: prompt,
      temperature: opts[:temperature] || 0.1,
      max_tokens: opts[:max_tokens] || 500,
      response_format: opts[:response_format]
    }

    case ChatCompletion.run(completion_params, context) do
      {:ok, %{content: content}} ->
        case ResponseParser.parse_and_validate(content, BooleanResponseSchema) do
          {:ok, validated_data} ->
            # Return in same format as Instructor version
            {:ok,
             %{
               result: validated_data.answer,
               explanation: validated_data.explanation,
               confidence: validated_data.confidence,
               is_ambiguous: validated_data.is_ambiguous
             }}

          {:error, validation_errors} when retries_left > 0 ->
            Logger.warning(
              "Boolean response validation failed (#{retries_left} retries left): #{validation_errors}"
            )

            retry_prompt = add_validation_error_to_prompt(prompt, validation_errors, content)

            execute_with_retry(
              model,
              retry_prompt,
              opts,
              context,
              retries_left - 1
            )

          {:error, validation_errors} ->
            Logger.error(
              "Boolean response validation failed after all retries: #{validation_errors}"
            )

            {:error, "Response validation failed: #{validation_errors}"}
        end

      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

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
      - answer: boolean (true or false)
      - explanation: string
      - confidence: number between 0.0 and 1.0
      - is_ambiguous: boolean
      """,
      engine: :none
    }

    %{prompt | messages: prompt.messages ++ [error_msg]}
  end
end
