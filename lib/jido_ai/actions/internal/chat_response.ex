defmodule Jido.AI.Actions.Internal.ChatResponse do
  @moduledoc """
  Internal implementation for getting natural language chat responses from LLMs.

  This action uses the internal schema validation system (replacing Instructor)
  to get structured chat responses from any LLM provider supported by ReqLLM.

  ## Features

  - 57+ LLM providers via ReqLLM
  - Internal JSON schema validation (no Instructor dependency)
  - Automatic retry on validation failures
  - Support for all standard chat parameters (temperature, max_tokens, etc.)

  ## Usage

      {:ok, model} = Model.from({:anthropic, [model: "claude-3-5-haiku-latest"]})
      prompt = Prompt.new(:user, "Explain quantum computing in simple terms")

      {:ok, response} = ChatResponse.run(%{
        model: model,
        prompt: prompt,
        temperature: 0.7
      }, %{})

      # response = %{response: "Quantum computing is..."}

  ## Parameters

  - `:model` (required) - The AI model to use (Model struct or provider tuple)
  - `:prompt` (required) - The prompt (Prompt struct or string)
  - `:temperature` (optional) - Temperature for randomness (default: 0.7)
  - `:max_tokens` (optional) - Maximum tokens in response (default: 1000)

  ## Response Format

  Returns `{:ok, %{response: string}}` on success, where:
  - `response` - The natural language response from the AI

  ## Migration from Instructor

  This action is a drop-in replacement for `Jido.AI.Actions.Instructor.ChatResponse`:

      # Old (Instructor)
      Jido.AI.Actions.Instructor.ChatResponse.run(params, context)

      # New (Internal)
      Jido.AI.Actions.Internal.ChatResponse.run(params, context)

  The response format and parameters are identical.
  """

  require Logger

  use Jido.Action,
    name: "get_chat_response_internal",
    description:
      "Get a natural language response from the AI assistant (internal implementation)",
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
  alias Jido.AI.Schemas.ChatResponseSchema

  def run(params, context) do
    # Apply defaults
    params_with_defaults =
      Map.merge(
        %{
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

    # Enhance prompt with schema guidance
    {enhanced_prompt, opts} =
      JsonRequestBuilder.build_request(
        params_with_defaults.prompt,
        ChatResponseSchema,
        temperature: params_with_defaults.temperature,
        max_tokens: params_with_defaults.max_tokens
      )

    # Execute with retry logic
    execute_with_retry(
      model,
      enhanced_prompt,
      opts,
      context,
      params_with_defaults.max_retries
    )
  end

  defp execute_with_retry(model, prompt, opts, context, retries_left) do
    # Build ChatCompletion parameters
    completion_params = %{
      model: model,
      prompt: prompt,
      temperature: opts[:temperature] || 0.7,
      max_tokens: opts[:max_tokens] || 1000,
      response_format: opts[:response_format]
    }

    case ChatCompletion.run(completion_params, context) do
      {:ok, %{content: content}} ->
        # Parse and validate the JSON response
        case ResponseParser.parse_and_validate(content, ChatResponseSchema) do
          {:ok, validated_data} ->
            # Return in same format as Instructor version
            {:ok, %{response: validated_data.response}}

          {:error, validation_errors} when retries_left > 0 ->
            Logger.warning(
              "Chat response validation failed (#{retries_left} retries left): #{validation_errors}"
            )

            # Add validation error feedback to prompt and retry
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
              "Chat response validation failed after all retries: #{validation_errors}"
            )

            {:error, "Response validation failed: #{validation_errors}"}
        end

      {:error, reason} ->
        Logger.error("Chat completion failed: #{inspect(reason)}")
        {:error, reason}
    end
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
      Remember to include all required fields with correct types.
      """,
      engine: :none
    }

    %{prompt | messages: prompt.messages ++ [error_msg]}
  end
end
