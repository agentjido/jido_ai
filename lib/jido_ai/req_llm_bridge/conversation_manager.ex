defmodule Jido.AI.ReqLlmBridge.ConversationManager do
  @moduledoc """
  Manages conversation state for multi-turn tool-enabled interactions.

  This module handles the storage and retrieval of conversation context,
  including message history, tool configurations, and conversation-specific
  options. It provides a stateful interface for managing ongoing conversations
  with LLM and tool interactions.

  ## Features

  - Conversation lifecycle management (create, update, end)
  - Message history tracking with role-based organization
  - Tool configuration persistence per conversation
  - Thread-safe conversation state management
  - Automatic cleanup and garbage collection
  - Conversation metadata and analytics

  ## Architecture

  Uses ETS tables for fast in-memory storage with optional persistence.
  Each conversation is identified by a unique ID and maintains:

  - Message history (user, assistant, tool messages)
  - Available tools and their configurations
  - Conversation-specific options and settings
  - Metadata (creation time, last activity, etc.)

  ## Usage

      # Start a new conversation
      {:ok, conv_id} = ConversationManager.create_conversation()

      # Configure tools for the conversation
      :ok = ConversationManager.set_tools(conv_id, tool_descriptors)

      # Add messages to the conversation
      :ok = ConversationManager.add_user_message(conv_id, "Hello!")
      :ok = ConversationManager.add_assistant_response(conv_id, response)

      # Retrieve conversation state
      {:ok, history} = ConversationManager.get_history(conv_id)
  """

  use GenServer
  require Logger

  @table_name :req_llm_conversations
  @cleanup_interval :timer.minutes(30)
  @conversation_ttl :timer.hours(24)

  @type conversation_id :: String.t()
  @type message :: %{
          role: String.t(),
          content: String.t(),
          timestamp: DateTime.t(),
          metadata: map()
        }
  @type tool_descriptor :: map()
  @type conversation_options :: map()

  @doc """
  Starts the ConversationManager process.

  Initializes the ETS table for conversation storage and sets up
  periodic cleanup of expired conversations.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new conversation and returns its unique identifier.

  ## Returns

  - `{:ok, conversation_id}` - New conversation created successfully
  - `{:error, reason}` - Error creating conversation

  ## Examples

      {:ok, conv_id} = ConversationManager.create_conversation()
  """
  @spec create_conversation() :: {:ok, conversation_id()} | {:error, term()}
  def create_conversation do
    GenServer.call(__MODULE__, :create_conversation)
  end

  @doc """
  Sets the available tools for a conversation.

  Configures which tools are available for use in the specified conversation.
  This overwrites any previously set tools.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `tool_descriptors` - List of tool descriptors to make available

  ## Returns

  - `:ok` - Tools set successfully
  - `{:error, reason}` - Error setting tools

  ## Examples

      :ok = ConversationManager.set_tools(conv_id, [weather_tool, calculator_tool])
  """
  @spec set_tools(conversation_id(), [tool_descriptor()]) :: :ok | {:error, term()}
  def set_tools(conversation_id, tool_descriptors) do
    GenServer.call(__MODULE__, {:set_tools, conversation_id, tool_descriptors})
  end

  @doc """
  Gets the tools configured for a conversation.

  ## Parameters

  - `conversation_id` - Identifier of the conversation

  ## Returns

  - `{:ok, tool_descriptors}` - List of available tools
  - `{:error, reason}` - Error retrieving tools or conversation not found

  ## Examples

      {:ok, tools} = ConversationManager.get_tools(conv_id)
  """
  @spec get_tools(conversation_id()) :: {:ok, [tool_descriptor()]} | {:error, term()}
  def get_tools(conversation_id) do
    GenServer.call(__MODULE__, {:get_tools, conversation_id})
  end

  @doc """
  Finds a specific tool by name within a conversation.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `tool_name` - Name of the tool to find

  ## Returns

  - `{:ok, tool_descriptor}` - Tool found
  - `{:error, :not_found}` - Tool not found in conversation
  - `{:error, reason}` - Other error

  ## Examples

      {:ok, weather_tool} = ConversationManager.find_tool_by_name(conv_id, "get_weather")
  """
  @spec find_tool_by_name(conversation_id(), String.t()) ::
          {:ok, tool_descriptor()} | {:error, :not_found | term()}
  def find_tool_by_name(conversation_id, tool_name) do
    GenServer.call(__MODULE__, {:find_tool_by_name, conversation_id, tool_name})
  end

  @doc """
  Sets conversation-specific options.

  Stores options like model preferences, temperature, timeout values,
  and other conversation-specific configurations.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `options` - Map of options to store

  ## Returns

  - `:ok` - Options set successfully
  - `{:error, reason}` - Error setting options

  ## Examples

      options = %{model: "gpt-4", temperature: 0.7, max_tokens: 1000}
      :ok = ConversationManager.set_options(conv_id, options)
  """
  @spec set_options(conversation_id(), conversation_options()) :: :ok | {:error, term()}
  def set_options(conversation_id, options) do
    GenServer.call(__MODULE__, {:set_options, conversation_id, options})
  end

  @doc """
  Gets the options configured for a conversation.

  ## Parameters

  - `conversation_id` - Identifier of the conversation

  ## Returns

  - `{:ok, options}` - Conversation options
  - `{:error, reason}` - Error retrieving options

  ## Examples

      {:ok, options} = ConversationManager.get_options(conv_id)
      model = options.model
  """
  @spec get_options(conversation_id()) :: {:ok, conversation_options()} | {:error, term()}
  def get_options(conversation_id) do
    GenServer.call(__MODULE__, {:get_options, conversation_id})
  end

  @doc """
  Adds a user message to the conversation history.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `content` - Message content from the user
  - `metadata` - Optional metadata for the message

  ## Returns

  - `:ok` - Message added successfully
  - `{:error, reason}` - Error adding message

  ## Examples

      :ok = ConversationManager.add_user_message(conv_id, "What's the weather like?")
  """
  @spec add_user_message(conversation_id(), String.t(), map()) :: :ok | {:error, term()}
  def add_user_message(conversation_id, content, metadata \\ %{}) do
    message = create_message("user", content, metadata)
    GenServer.call(__MODULE__, {:add_message, conversation_id, message})
  end

  @doc """
  Adds an assistant response to the conversation history.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `response` - Response data from the assistant (may include tool calls)
  - `metadata` - Optional metadata for the response

  ## Returns

  - `:ok` - Response added successfully
  - `{:error, reason}` - Error adding response

  ## Examples

      :ok = ConversationManager.add_assistant_response(conv_id, llm_response)
  """
  @spec add_assistant_response(conversation_id(), map(), map()) :: :ok | {:error, term()}
  def add_assistant_response(conversation_id, response, metadata \\ %{}) do
    content = extract_response_content(response)

    enhanced_metadata =
      Map.merge(metadata, %{
        tool_calls: Map.get(response, :tool_calls, []),
        usage: Map.get(response, :usage, %{}),
        model: Map.get(response, :model)
      })

    message = create_message("assistant", content, enhanced_metadata)
    GenServer.call(__MODULE__, {:add_message, conversation_id, message})
  end

  @doc """
  Adds tool execution results to the conversation history.

  ## Parameters

  - `conversation_id` - Identifier of the conversation
  - `tool_results` - List of tool execution results
  - `metadata` - Optional metadata for the tool results

  ## Returns

  - `:ok` - Tool results added successfully
  - `{:error, reason}` - Error adding tool results

  ## Examples

      tool_results = [%{tool_call_id: "call_1", content: "Weather is sunny"}]
      :ok = ConversationManager.add_tool_results(conv_id, tool_results)
  """
  @spec add_tool_results(conversation_id(), [map()], map()) :: :ok | {:error, term()}
  def add_tool_results(conversation_id, tool_results, metadata \\ %{}) do
    messages =
      Enum.map(tool_results, fn result ->
        content = Map.get(result, :content, "")

        tool_metadata =
          Map.merge(metadata, %{
            tool_call_id: Map.get(result, :tool_call_id),
            tool_name: Map.get(result, :name),
            error: Map.get(result, :error, false)
          })

        create_message("tool", content, tool_metadata)
      end)

    GenServer.call(__MODULE__, {:add_messages, conversation_id, messages})
  end

  @doc """
  Gets the complete message history for a conversation.

  Returns all messages in chronological order with role information,
  timestamps, and metadata.

  ## Parameters

  - `conversation_id` - Identifier of the conversation

  ## Returns

  - `{:ok, messages}` - List of messages in chronological order
  - `{:error, reason}` - Error retrieving history

  ## Examples

      {:ok, history} = ConversationManager.get_history(conv_id)
      # Process history as needed
  """
  @spec get_history(conversation_id()) :: {:ok, [message()]} | {:error, term()}
  def get_history(conversation_id) do
    GenServer.call(__MODULE__, {:get_history, conversation_id})
  end

  @doc """
  Gets conversation metadata including creation time, message count, etc.

  ## Parameters

  - `conversation_id` - Identifier of the conversation

  ## Returns

  - `{:ok, metadata}` - Conversation metadata
  - `{:error, reason}` - Error retrieving metadata

  ## Examples

      {:ok, metadata} = ConversationManager.get_conversation_metadata(conv_id)
      # Use metadata as needed
  """
  @spec get_conversation_metadata(conversation_id()) :: {:ok, map()} | {:error, term()}
  def get_conversation_metadata(conversation_id) do
    GenServer.call(__MODULE__, {:get_metadata, conversation_id})
  end

  @doc """
  Ends a conversation and removes it from storage.

  Cleans up all conversation data including history, tools, and options.
  The conversation ID becomes invalid after this operation.

  ## Parameters

  - `conversation_id` - Identifier of the conversation to end

  ## Returns

  - `:ok` - Conversation ended successfully
  - `{:error, reason}` - Error ending conversation

  ## Examples

      :ok = ConversationManager.end_conversation(conv_id)
  """
  @spec end_conversation(conversation_id()) :: :ok | {:error, term()}
  def end_conversation(conversation_id) do
    GenServer.call(__MODULE__, {:end_conversation, conversation_id})
  end

  @doc """
  Lists all active conversation IDs.

  Returns a list of conversation IDs that are currently active.
  Useful for debugging and administrative purposes.

  ## Returns

  - `{:ok, conversation_ids}` - List of active conversation IDs
  - `{:error, reason}` - Error retrieving list

  ## Examples

      {:ok, conversation_ids} = ConversationManager.list_conversations()
      # Use conversation_ids as needed
  """
  @spec list_conversations() :: {:ok, [conversation_id()]} | {:error, term()}
  def list_conversations do
    GenServer.call(__MODULE__, :list_conversations)
  end

  @doc """
  Clears all conversations from storage.

  This is primarily intended for testing purposes to ensure a clean state.
  Use with caution in production environments.

  ## Returns

  - `:ok` - All conversations cleared successfully

  ## Examples

      :ok = ConversationManager.clear_all_conversations()
  """
  @spec clear_all_conversations() :: :ok
  def clear_all_conversations do
    GenServer.call(__MODULE__, :clear_all_conversations)
  end

  # GenServer Implementation

  @impl true
  def init(_opts) do
    :ets.new(@table_name, [:named_table, :set, :protected])
    schedule_cleanup()

    Logger.info("ConversationManager started with cleanup interval #{@cleanup_interval}ms")

    {:ok,
     %{
       table: @table_name,
       cleanup_interval: @cleanup_interval,
       conversation_ttl: @conversation_ttl
     }}
  end

  @impl true
  def handle_call(:create_conversation, _from, state) do
    conversation_id = generate_conversation_id()
    timestamp = DateTime.utc_now()

    conversation_data = %{
      id: conversation_id,
      created_at: timestamp,
      last_activity: timestamp,
      messages: [],
      tools: [],
      options: %{},
      metadata: %{
        message_count: 0,
        total_tokens: 0
      }
    }

    true = :ets.insert(@table_name, {conversation_id, conversation_data})

    {:reply, {:ok, conversation_id}, state}
  end

  @impl true
  def handle_call({:set_tools, conversation_id, tools}, _from, state) do
    case update_conversation(conversation_id, fn data ->
           %{data | tools: tools, last_activity: DateTime.utc_now()}
         end) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_tools, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] -> {:reply, {:ok, data.tools}, state}
      [] -> {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:find_tool_by_name, conversation_id, tool_name}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] ->
        case Enum.find(data.tools, &(&1.name == tool_name)) do
          nil -> {:reply, {:error, :not_found}, state}
          tool -> {:reply, {:ok, tool}, state}
        end

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:set_options, conversation_id, options}, _from, state) do
    case update_conversation(conversation_id, fn data ->
           %{data | options: options, last_activity: DateTime.utc_now()}
         end) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_options, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] -> {:reply, {:ok, data.options}, state}
      [] -> {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:add_message, conversation_id, message}, _from, state) do
    case update_conversation(conversation_id, fn data ->
           updated_messages = data.messages ++ [message]

           updated_metadata = %{
             data.metadata
             | message_count: data.metadata.message_count + 1
           }

           %{
             data
             | messages: updated_messages,
               metadata: updated_metadata,
               last_activity: DateTime.utc_now()
           }
         end) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:add_messages, conversation_id, messages}, _from, state) do
    case update_conversation(conversation_id, fn data ->
           updated_messages = data.messages ++ messages

           updated_metadata = %{
             data.metadata
             | message_count: data.metadata.message_count + length(messages)
           }

           %{
             data
             | messages: updated_messages,
               metadata: updated_metadata,
               last_activity: DateTime.utc_now()
           }
         end) do
      :ok -> {:reply, :ok, state}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:get_history, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] -> {:reply, {:ok, data.messages}, state}
      [] -> {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_metadata, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] ->
        metadata =
          Map.merge(data.metadata, %{
            id: data.id,
            created_at: data.created_at,
            last_activity: data.last_activity,
            tool_count: length(data.tools)
          })

        {:reply, {:ok, metadata}, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:end_conversation, conversation_id}, _from, state) do
    case :ets.delete(@table_name, conversation_id) do
      true -> {:reply, :ok, state}
      false -> {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call(:list_conversations, _from, state) do
    conversation_ids = :ets.foldl(fn {id, _data}, acc -> [id | acc] end, [], @table_name)
    {:reply, {:ok, conversation_ids}, state}
  end

  @impl true
  def handle_call(:clear_all_conversations, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:cleanup_expired_conversations, state) do
    cleanup_expired_conversations(state.conversation_ttl)
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    # Clean up the ETS table on shutdown to prevent memory leaks
    if :ets.whereis(@table_name) != :undefined do
      :ets.delete(@table_name)
    end

    :ok
  end

  # Private Functions

  defp generate_conversation_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
    |> String.slice(0, 32)
  end

  defp create_message(role, content, metadata) do
    %{
      role: role,
      content: content,
      timestamp: DateTime.utc_now(),
      metadata: metadata
    }
  end

  defp extract_response_content(response) when is_map(response) do
    content = Map.get(response, :content, Map.get(response, "content", ""))

    cond do
      is_list(content) ->
        Enum.map_join(content, "", &extract_content_part/1)

      is_binary(content) ->
        content

      is_map(content) ->
        inspect(content)

      true ->
        to_string(content)
    end
  end

  defp extract_response_content(response) when is_binary(response), do: response
  defp extract_response_content(response), do: inspect(response)

  defp extract_content_part(%{type: "text", text: text}), do: text
  defp extract_content_part(%{"type" => "text", "text" => text}), do: text
  defp extract_content_part(content) when is_binary(content), do: content
  defp extract_content_part(_), do: ""

  defp update_conversation(conversation_id, update_fn) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, data}] ->
        updated_data = update_fn.(data)
        :ets.insert(@table_name, {conversation_id, updated_data})
        :ok

      [] ->
        {:error, :conversation_not_found}
    end
  rescue
    error ->
      Logger.error("Failed to update conversation #{conversation_id}: #{inspect(error)}")
      {:error, {:update_failed, error}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_expired_conversations, @cleanup_interval)
  end

  defp cleanup_expired_conversations(ttl) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -ttl, :millisecond)

    expired_conversations =
      :ets.foldl(
        fn {id, data}, acc ->
          if DateTime.compare(data.last_activity, cutoff_time) == :lt do
            [id | acc]
          else
            acc
          end
        end,
        [],
        @table_name
      )

    Enum.each(expired_conversations, fn id ->
      :ets.delete(@table_name, id)
    end)

    unless Enum.empty?(expired_conversations) do
      Logger.info("Cleaned up #{length(expired_conversations)} expired conversations")
    end
  end
end
