defmodule ReqLLM.ObjectGeneration do
  @moduledoc """
  Object generation functionality for structured AI responses.

  This module handles generating and streaming structured data objects using AI models.
  It provides schema validation, tool-based response parsing, and streaming support
  for creating validated structured data from AI responses.

  ## Core Functions

  - `generate_object/4` - Generate a structured object with schema validation
  - `stream_object/4` - Stream structured object chunks with validation

  ## Schema Support

  Both functions accept NimbleOptions schema definitions for strict validation:

      schema = [
        name: [type: :string, required: true, doc: "User's full name"],
        age: [type: :integer, doc: "User's age in years"],
        preferences: [type: {:list, :string}, doc: "List of preferences"]
      ]

  ## Examples

      # Generate structured user profile
      {:ok, profile} = ReqLLM.ObjectGeneration.generate_object(
        "openai:gpt-4",
        [%{role: "user", content: "Create a profile for John, age 25"}],
        [name: [type: :string], age: [type: :integer]]
      )

      # Stream structured data
      {:ok, stream} = ReqLLM.ObjectGeneration.stream_object(
        "openai:gpt-4",
        messages,
        schema,
        temperature: 0.3
      )
  """

  import ReqLLM.Schema

  # Object generation schema - extends text options with additional fields
  @object_opts_schema NimbleOptions.new!(
                        temperature: [
                          type: :float,
                          doc: "Controls randomness in the output (0.0 to 2.0)"
                        ],
                        max_tokens: [
                          type: :pos_integer,
                          doc: "Maximum number of tokens to generate"
                        ],
                        top_p: [type: :float, doc: "Nucleus sampling parameter"],
                        presence_penalty: [
                          type: :float,
                          doc: "Penalize new tokens based on presence"
                        ],
                        frequency_penalty: [
                          type: :float,
                          doc: "Penalize new tokens based on frequency"
                        ],
                        tools: [type: :any, doc: "List of tool definitions"],
                        tool_choice: [
                          type: {:or, [:string, :atom, :map]},
                          default: "auto",
                          doc: "Tool choice strategy"
                        ],
                        system_prompt: [type: :string, doc: "System prompt to prepend"],
                        provider_options: [type: :map, doc: "Provider-specific options"],
                        output_type: [
                          type: {:in, [:object, :array, :enum, :no_schema]},
                          default: :object,
                          doc: "Type of output structure"
                        ],
                        enum_values: [
                          type: {:list, :string},
                          doc: "Allowed values when output_type is :enum"
                        ],
                        reasoning: [
                          type: {:in, [nil, false, true, "low", "auto", "high"]},
                          doc: "Request reasoning tokens from the model"
                        ]
                      )

  @doc """
  Generates a structured object using an AI model with schema validation.

  Accepts flexible model specifications and generates validated structured data using the appropriate provider.
  The schema parameter defines the expected structure and validation rules for the response.

  ## Parameters

  - `model_spec` - Model specification (string like "openai:gpt-4" or tuple with options)
  - `messages` - List of message maps with `:role` and `:content` keys
  - `schema` - NimbleOptions schema definition as keyword list
  - `opts` - Additional options for generation (temperature, max_tokens, etc.)

  ## Returns

  - `{:ok, validated_object}` - Successfully generated and validated structured object
  - `{:error, error}` - Generation or validation error

  ## Examples

      # Generate user profile with validation
      schema = [
        name: [type: :string, required: true],
        age: [type: :integer],
        email: [type: :string]
      ]

      {:ok, profile} = ReqLLM.ObjectGeneration.generate_object(
        "openai:gpt-4",
        [%{role: "user", content: "Create profile for Alice, 30"}],
        schema,
        temperature: 0.3
      )
      #=> %{name: "Alice", age: 30, email: "alice@example.com"}

      # Generate with enum constraints
      color_schema = [
        primary: [type: {:in, ["red", "green", "blue"]}, required: true],
        intensity: [type: :float]
      ]

      {:ok, color} = ReqLLM.ObjectGeneration.generate_object(
        model,
        messages,
        color_schema
      )
  """
  @spec generate_object(
          ReqLLM.Model.model_spec(),
          list(map()),
          keyword(),
          keyword()
        ) :: {:ok, map() | list() | String.t()} | {:error, ReqLLM.Error.t()}
  def generate_object(model_spec, messages, schema, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @object_opts_schema),
         {:ok, compiled_schema} <- compile_schema(schema),
         {:ok, tool} <- create_response_tool(schema),
         enhanced_opts <- prepare_tool_opts(validated_opts, tool),
         {:ok, response} <- ReqLLM.generate_text(model_spec, messages, enhanced_opts),
         {:ok, model} <- ReqLLM.Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider),
         {:ok, tool_args} <- parse_tool_response(response, provider_module),
         {:ok, validated_result} <- validate_result(tool_args, compiled_schema) do
      {:ok, validated_result}
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         ReqLLM.Error.Validation.Error.exception(
           tag: :invalid_options,
           reason: Exception.message(error),
           context: []
         )}

      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  @doc """
  Streams structured data using an AI model with schema validation.

  Accepts flexible model specifications and streams validated structured data using the appropriate provider.
  Returns a Stream that emits validated structured data chunks as they arrive.

  ## Parameters

  Same as `generate_object/4`.

  ## Returns

  - `{:ok, response}` - Response with streaming body containing validated objects
  - `{:error, error}` - Stream setup or validation error

  ## Examples

      # Stream structured responses
      {:ok, response} = ReqLLM.ObjectGeneration.stream_object(
        "anthropic:claude-3-sonnet",
        messages,
        schema,
        temperature: 0.1
      )

      # Process stream chunks
      response.body
      |> Stream.each(fn validated_chunk ->
        IO.inspect(validated_chunk, label: "Validated Object")
      end)
      |> Stream.run()
  """
  @spec stream_object(
          ReqLLM.Model.model_spec(),
          list(map()),
          keyword(),
          keyword()
        ) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(model_spec, messages, schema, opts \\ []) do
    with {:ok, validated_opts} <- NimbleOptions.validate(opts, @object_opts_schema),
         {:ok, compiled_schema} <- compile_schema(schema),
         {:ok, tool} <- create_response_tool(schema),
         enhanced_opts <- prepare_tool_opts(validated_opts, tool),
         streaming_opts <- Keyword.merge(enhanced_opts, stream?: true, return_response: true),
         {:ok, response} <- ReqLLM.stream_text(model_spec, messages, streaming_opts),
         {:ok, model} <- ReqLLM.Model.from(model_spec),
         {:ok, provider_module} <- ReqLLM.provider(model.provider) do
      # Build the validating stream
      validating_stream =
        build_validating_stream(
          response.body,
          provider_module,
          compiled_schema,
          "response_object"
        )

      # Return the stream in the same response structure for consistency
      updated_response = %{response | body: validating_stream}
      {:ok, updated_response}
    else
      {:error, %NimbleOptions.ValidationError{} = error} ->
        {:error,
         ReqLLM.Error.Validation.Error.exception(
           tag: :invalid_options,
           reason: Exception.message(error),
           context: []
         )}

      {:error, :not_found} ->
        {:error, ReqLLM.Error.Invalid.Provider.exception(provider: "unknown")}

      error ->
        error
    end
  end

  # Private helper functions

  defp create_response_tool(schema) do
    ReqLLM.Tool.new(
      name: "response_object",
      description: "Return the response for the user request as arguments",
      parameters: schema,
      callback: fn args -> {:ok, args} end
    )
  end

  defp prepare_tool_opts(validated_opts, tool) do
    # Remove generate_object-specific options that don't apply to generate_text
    text_opts =
      validated_opts
      |> Keyword.delete(:output_type)
      |> Keyword.delete(:enum_values)

    # Convert Tool struct to format expected by providers
    provider_tool = convert_tool_for_provider(tool)

    text_opts
    |> Keyword.put(:tools, [provider_tool])
    |> Keyword.put(:tool_choice, "response_object")
  end

  defp convert_tool_for_provider(%ReqLLM.Tool{} = tool) do
    %{
      name: tool.name,
      description: tool.description,
      parameters_schema: parameters_to_json_schema(tool.parameters)
    }
  end

  defp parse_tool_response(%Req.Response{body: %{tool_calls: tool_calls}}, _provider_module)
       when is_list(tool_calls) and tool_calls != [] do
    case Enum.find(tool_calls, &(&1[:name] == "response_object")) do
      %{arguments: args} ->
        {:ok, args}

      nil ->
        {:error,
         ReqLLM.Error.API.Response.exception(
           reason: "No response_object tool call found in response"
         )}
    end
  end

  defp parse_tool_response(%Req.Response{body: body}, provider_module) do
    case provider_module.parse_tool_call(body, "response_object") do
      {:ok, args} ->
        {:ok, args}

      {:error, :tool_not_found} ->
        {:error,
         ReqLLM.Error.API.Response.exception(
           reason: "No response_object tool call found in response"
         )}

      {:error, :no_tool_calls} ->
        {:error, ReqLLM.Error.API.Response.exception(reason: "No tool calls found in response")}

      {:error, reason} ->
        {:error,
         ReqLLM.Error.API.Response.exception(
           reason: "Failed to parse tool call: #{inspect(reason)}"
         )}
    end
  end

  defp validate_result(tool_args, compiled_schema) do
    case NimbleOptions.validate(tool_args, compiled_schema) do
      {:ok, validated_result} ->
        {:ok, validated_result}

      {:error, error} ->
        {:error,
         ReqLLM.Error.Validation.Error.exception(
           tag: :result_validation,
           reason: Exception.message(error),
           context: [result: tool_args]
         )}
    end
  end

  # Helper functions for stream_object/4

  defp build_validating_stream(stream, provider_module, compiled_schema, _tool_name) do
    Stream.resource(
      fn -> stream_tool_init(provider_module) end,
      fn state ->
        case Enum.take(stream, 1) do
          [] ->
            {:halt, state}

          [chunk] ->
            case stream_tool_accumulate(provider_module, chunk, state) do
              {:ok, new_state} ->
                {[], new_state}

              {:ok, new_state, completed_args} ->
                case validate_all(completed_args, compiled_schema) do
                  {:ok, validated_results} ->
                    {validated_results, new_state}

                  {:error, error} ->
                    raise error
                end

              {:error, error} ->
                raise ReqLLM.Error.API.Response.exception(
                        reason: "Stream processing error: #{inspect(error)}"
                      )
            end
        end
      end,
      fn _state -> :ok end
    )
  end

  defp stream_tool_init(provider_module) do
    if function_exported?(provider_module, :stream_tool_init, 1) do
      provider_module.stream_tool_init("response_object")
    else
      %{}
    end
  end

  defp stream_tool_accumulate(provider_module, chunk, state) do
    if function_exported?(provider_module, :stream_tool_accumulate, 3) do
      provider_module.stream_tool_accumulate(chunk, "response_object", state)
    else
      {:error, :not_implemented}
    end
  end

  defp validate_all(args_list, compiled_schema) when is_list(args_list) do
    try do
      validated =
        Enum.map(args_list, fn args ->
          case NimbleOptions.validate(args, compiled_schema) do
            {:ok, validated_args} -> validated_args
            {:error, error} -> throw({:validation_error, error})
          end
        end)

      {:ok, validated}
    catch
      {:validation_error, error} ->
        {:error,
         ReqLLM.Error.Validation.Error.exception(
           tag: :result_validation,
           reason: Exception.message(error),
           context: [result: args_list]
         )}
    end
  end

  defp validate_all(args, compiled_schema) do
    validate_all([args], compiled_schema)
  end
end
