defmodule Jido.AI.ReqLlmBridge.ToolIntegrationManager do
  @moduledoc """
  Manages the integration of tool-enabled LLM requests with ReqLlmBridge.

  This module provides the primary interface for making LLM requests that can
  use tools (function calling). It coordinates between the LLM client, tool
  execution, and response handling to provide a complete tool-enabled conversation flow.

  ## Features

  - Tool-enabled text generation with automatic tool execution
  - Multi-turn conversation support with tool results
  - Streaming and non-streaming response handling
  - Tool choice parameter mapping and validation
  - Error handling and recovery for tool execution failures
  - Conversation context management

  ## Usage

      # Basic tool-enabled request
      {:ok, response} = ToolIntegrationManager.generate_with_tools(
        "What's the weather in Paris?",
        [WeatherAction],
        %{model: "gpt-4", temperature: 0.7}
      )

      # Multi-turn conversation with tools
      {:ok, manager} = ToolIntegrationManager.start_conversation([WeatherAction])
      {:ok, response} = ToolIntegrationManager.continue_conversation(
        manager,
        "What's the weather in Paris and London?"
      )
  """

  alias Jido.AI.ReqLlmBridge.{ConversationManager, ToolBuilder, ToolResponseHandler}

  @default_options %{
    model: "gpt-4",
    temperature: 0.7,
    max_tokens: 1000,
    tool_choice: :auto,
    max_tool_calls: 5,
    stream: false,
    timeout: 30_000
  }

  @type tool_action :: module()
  @type conversation_id :: String.t()
  @type tool_choice :: :auto | :none | :required | {:function, String.t() | atom()}

  @type options :: %{
          optional(:model) => String.t(),
          optional(:temperature) => float(),
          optional(:max_tokens) => pos_integer(),
          optional(:tool_choice) => tool_choice(),
          optional(:max_tool_calls) => pos_integer(),
          optional(:stream) => boolean(),
          optional(:timeout) => pos_integer(),
          optional(:context) => map(),
          optional(:conversation_id) => conversation_id()
        }

  @type response :: %{
          content: String.t(),
          tool_calls: list(map()),
          usage: map(),
          conversation_id: conversation_id(),
          finished: boolean()
        }

  @doc """
  Generates a response using tools for a single message.

  This is a convenience function for one-off tool-enabled requests without
  maintaining conversation state.

  ## Parameters

  - `message` - The user message/prompt
  - `tools` - List of Jido Action modules to make available as tools
  - `options` - Request options (model, temperature, etc.)

  ## Returns

  - `{:ok, response}` - Successful response with content and tool call results
  - `{:error, reason}` - Error during request or tool execution

  ## Examples

      {:ok, response} = ToolIntegrationManager.generate_with_tools(
        "Calculate 15 * 8 and tell me the result",
        [CalculatorAction],
        %{model: "gpt-4", temperature: 0.0}
      )

      IO.puts(response.content)
      # "The result of 15 * 8 is 120."
  """
  @spec generate_with_tools(String.t(), [tool_action()], options()) ::
          {:ok, response()} | {:error, term()}
  def generate_with_tools(message, tools, options \\ %{}) do
    with {:ok, merged_options} <- validate_and_merge_options(options),
         {:ok, tool_descriptors} <- convert_tools_to_descriptors(tools, merged_options),
         {:ok, conversation_id} <- ConversationManager.create_conversation() do
      execute_tool_enabled_request(
        message,
        tool_descriptors,
        conversation_id,
        merged_options
      )
    end
  end

  @doc """
  Starts a new tool-enabled conversation.

  Creates a managed conversation context that can handle multiple turns
  with tool usage and maintains conversation history.

  ## Parameters

  - `tools` - List of Jido Action modules to make available as tools
  - `options` - Conversation options and LLM parameters

  ## Returns

  - `{:ok, conversation_id}` - New conversation identifier
  - `{:error, reason}` - Error during conversation setup

  ## Examples

      {:ok, conv_id} = ToolIntegrationManager.start_conversation([WeatherAction])
      {:ok, response} = ToolIntegrationManager.continue_conversation(
        conv_id,
        "What's the weather like?"
      )
  """
  @spec start_conversation([tool_action()], options()) ::
          {:ok, conversation_id()} | {:error, term()}
  def start_conversation(tools, options \\ %{}) do
    with {:ok, merged_options} <- validate_and_merge_options(options),
         {:ok, tool_descriptors} <- convert_tools_to_descriptors(tools, merged_options),
         {:ok, conversation_id} <- ConversationManager.create_conversation() do
      :ok = ConversationManager.set_tools(conversation_id, tool_descriptors)
      :ok = ConversationManager.set_options(conversation_id, merged_options)
      {:ok, conversation_id}
    end
  end

  @doc """
  Continues an existing conversation with a new message.

  Adds the message to the conversation history and generates a response
  using the tools and options configured for the conversation.

  ## Parameters

  - `conversation_id` - Identifier of the conversation to continue
  - `message` - The user message to add and respond to
  - `options` - Optional overrides for this specific request

  ## Returns

  - `{:ok, response}` - Response with tool execution results
  - `{:error, reason}` - Error during conversation or tool execution

  ## Examples

      {:ok, response} = ToolIntegrationManager.continue_conversation(
        conversation_id,
        "Now check the weather in Tokyo too"
      )
  """
  @spec continue_conversation(conversation_id(), String.t(), options()) ::
          {:ok, response()} | {:error, term()}
  def continue_conversation(conversation_id, message, options \\ %{}) do
    with {:ok, conversation_options} <- ConversationManager.get_options(conversation_id),
         {:ok, merged_options} <- merge_conversation_options(conversation_options, options),
         {:ok, tool_descriptors} <- ConversationManager.get_tools(conversation_id),
         :ok <- ConversationManager.add_user_message(conversation_id, message),
         {:ok, response} <-
           execute_tool_enabled_request(
             message,
             tool_descriptors,
             conversation_id,
             merged_options
           ) do
      :ok = ConversationManager.add_assistant_response(conversation_id, response)
      {:ok, response}
    end
  end

  @doc """
  Gets the current conversation history.

  Returns all messages in the conversation, including user messages,
  assistant responses, and tool call results.

  ## Parameters

  - `conversation_id` - Identifier of the conversation

  ## Returns

  - `{:ok, messages}` - List of conversation messages
  - `{:error, reason}` - Error retrieving conversation

  ## Examples

      {:ok, history} = ToolIntegrationManager.get_conversation_history(conversation_id)
      # Process history as needed
  """
  @spec get_conversation_history(conversation_id()) :: {:ok, [map()]} | {:error, term()}
  def get_conversation_history(conversation_id) do
    ConversationManager.get_history(conversation_id)
  end

  @doc """
  Ends a conversation and cleans up resources.

  Removes the conversation from memory and cleans up any associated resources.
  The conversation ID becomes invalid after this call.

  ## Parameters

  - `conversation_id` - Identifier of the conversation to end

  ## Returns

  - `:ok` - Conversation ended successfully
  - `{:error, reason}` - Error ending conversation

  ## Examples

      :ok = ToolIntegrationManager.end_conversation(conversation_id)
  """
  @spec end_conversation(conversation_id()) :: :ok | {:error, term()}
  def end_conversation(conversation_id) do
    ConversationManager.end_conversation(conversation_id)
  end

  # Private Functions

  defp validate_and_merge_options(options) do
    merged = Map.merge(@default_options, options)

    with :ok <- validate_model(merged.model),
         :ok <- validate_temperature(merged.temperature),
         :ok <- validate_max_tokens(merged.max_tokens),
         :ok <- validate_tool_choice(merged.tool_choice),
         :ok <- validate_max_tool_calls(merged.max_tool_calls) do
      {:ok, merged}
    end
  end

  defp validate_model(model) when is_binary(model) and byte_size(model) > 0, do: :ok
  defp validate_model(_), do: {:error, "Invalid model: must be a non-empty string"}

  defp validate_temperature(temp) when is_number(temp) and temp >= 0.0 and temp <= 2.0, do: :ok
  defp validate_temperature(_), do: {:error, "Invalid temperature: must be between 0.0 and 2.0"}

  defp validate_max_tokens(tokens) when is_integer(tokens) and tokens > 0, do: :ok
  defp validate_max_tokens(_), do: {:error, "Invalid max_tokens: must be a positive integer"}

  defp validate_tool_choice(choice) when choice in [:auto, :none, :required], do: :ok
  defp validate_tool_choice({:function, name}) when is_binary(name) or is_atom(name), do: :ok
  defp validate_tool_choice(_), do: {:error, "Invalid tool_choice format"}

  defp validate_max_tool_calls(calls) when is_integer(calls) and calls > 0, do: :ok

  defp validate_max_tool_calls(_),
    do: {:error, "Invalid max_tool_calls: must be a positive integer"}

  defp convert_tools_to_descriptors(tools, options) do
    context = Map.get(options, :context, %{})
    conversion_options = %{context: context, timeout: options.timeout}

    case ToolBuilder.batch_convert(tools, conversion_options) do
      {:ok, descriptors} -> {:ok, descriptors}
      {:error, reason} -> {:error, {:tool_conversion_failed, reason}}
    end
  end

  defp merge_conversation_options(conversation_options, request_options) do
    merged = Map.merge(conversation_options, request_options)
    validate_and_merge_options(merged)
  end

  defp execute_tool_enabled_request(message, tool_descriptors, conversation_id, options) do
    req_options = build_req_llm_options(tool_descriptors, options)

    case options.stream do
      true -> execute_streaming_request(message, req_options, conversation_id, options)
      false -> execute_non_streaming_request(message, req_options, conversation_id, options)
    end
  end

  defp build_req_llm_options(tool_descriptors, options) do
    base_options = %{
      model: options.model,
      temperature: options.temperature,
      max_tokens: options.max_tokens,
      tools: tool_descriptors
    }

    # ReqLLM doesn't have map_tool_choice_parameters, use tool_choice directly
    Map.put(base_options, :tool_choice, options.tool_choice)
  end

  defp execute_non_streaming_request(message, req_options, conversation_id, options) do
    case ReqLLM.generate_text(options.model, message, req_options) do
      {:ok, llm_response} ->
        ToolResponseHandler.process_llm_response(
          llm_response,
          conversation_id,
          options
        )

      {:error, reason} ->
        {:error, {:llm_request_failed, reason}}
    end
  end

  defp execute_streaming_request(message, req_options, conversation_id, options) do
    stream_options = Map.put(req_options, :stream, true)

    case ReqLLM.stream_text(options.model, message, stream_options) do
      {:ok, stream} ->
        ToolResponseHandler.process_streaming_response(
          stream,
          conversation_id,
          options
        )

      {:error, reason} ->
        {:error, {:streaming_request_failed, reason}}
    end
  end
end
