defmodule Jido.AI.Conversation.Manager do
  @moduledoc """
  Manages conversation state with ETS-backed storage.

  The ConversationManager provides stateful multi-turn conversation support,
  tracking message history and conversation metadata. Conversations are stored
  in ETS and do not persist across application restarts.

  ## Usage

      # Create a conversation with a model
      {:ok, model} = Jido.AI.Model.from({:openai, [model: "gpt-4"]})
      {:ok, conv_id} = Jido.AI.Conversation.Manager.create(model)

      # Add messages
      :ok = Jido.AI.Conversation.Manager.add_message(conv_id, :user, "Hello!")

      # Get history
      {:ok, messages} = Jido.AI.Conversation.Manager.get_messages(conv_id)

      # Clean up
      :ok = Jido.AI.Conversation.Manager.delete(conv_id)

  ## With System Prompt

      {:ok, conv_id} = Jido.AI.Conversation.Manager.create(model,
        system_prompt: "You are a helpful assistant."
      )
  """

  use GenServer
  require Logger

  alias Jido.AI.Conversation.Message

  @table_name :jido_ai_conversations
  @default_options %{
    temperature: 0.7,
    max_tokens: 1024
  }

  # Conversation struct stored in ETS
  defmodule Conversation do
    @moduledoc false
    defstruct [
      :id,
      :model,
      :messages,
      :options,
      :created_at,
      :updated_at,
      :message_count
    ]
  end

  # =============================================================================
  # Client API
  # =============================================================================

  @doc """
  Starts the ConversationManager GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates a new conversation with the given model.

  ## Options

    * `:system_prompt` - Initial system message for the conversation
    * `:options` - LLM options like temperature, max_tokens

  ## Examples

      {:ok, conv_id} = Manager.create(model)
      {:ok, conv_id} = Manager.create(model, system_prompt: "You are helpful.")
  """
  @spec create(ReqLLM.Model.t() | map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def create(model, opts \\ []) do
    GenServer.call(__MODULE__, {:create, model, opts})
  end

  @doc """
  Adds a message to the conversation.

  ## Examples

      :ok = Manager.add_message(conv_id, :user, "Hello!")
      :ok = Manager.add_message(conv_id, :assistant, "Hi!", tool_calls: [...])
  """
  @spec add_message(String.t(), atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def add_message(conversation_id, role, content, opts \\ []) do
    GenServer.call(__MODULE__, {:add_message, conversation_id, role, content, opts})
  end

  @doc """
  Gets all messages in the conversation.
  """
  @spec get_messages(String.t()) :: {:ok, [Message.t()]} | {:error, term()}
  def get_messages(conversation_id) do
    GenServer.call(__MODULE__, {:get_messages, conversation_id})
  end

  @doc """
  Gets messages formatted for LLM API calls.
  """
  @spec get_messages_for_llm(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_messages_for_llm(conversation_id) do
    GenServer.call(__MODULE__, {:get_messages_for_llm, conversation_id})
  end

  @doc """
  Gets the full conversation state.
  """
  @spec get(String.t()) :: {:ok, map()} | {:error, term()}
  def get(conversation_id) do
    GenServer.call(__MODULE__, {:get, conversation_id})
  end

  @doc """
  Gets conversation metadata.
  """
  @spec get_metadata(String.t()) :: {:ok, map()} | {:error, term()}
  def get_metadata(conversation_id) do
    GenServer.call(__MODULE__, {:get_metadata, conversation_id})
  end

  @doc """
  Updates conversation options.
  """
  @spec update_options(String.t(), map()) :: :ok | {:error, term()}
  def update_options(conversation_id, options) do
    GenServer.call(__MODULE__, {:update_options, conversation_id, options})
  end

  @doc """
  Deletes a conversation and frees resources.
  """
  @spec delete(String.t()) :: :ok
  def delete(conversation_id) do
    GenServer.call(__MODULE__, {:delete, conversation_id})
  end

  @doc """
  Lists all active conversation IDs.
  """
  @spec list() :: [String.t()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @doc """
  Checks if a conversation exists.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(conversation_id) do
    GenServer.call(__MODULE__, {:exists, conversation_id})
  end

  # =============================================================================
  # Server Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:set, :protected, :named_table])
    Logger.debug("[Conversation.Manager] Initialized with ETS table: #{@table_name}")
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:create, model, opts}, _from, state) do
    id = generate_conversation_id()
    system_prompt = Keyword.get(opts, :system_prompt)
    user_options = Keyword.get(opts, :options, %{})

    messages =
      if system_prompt do
        [Message.system(system_prompt)]
      else
        []
      end

    conversation = %Conversation{
      id: id,
      model: model,
      messages: messages,
      options: Map.merge(@default_options, user_options),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      message_count: length(messages)
    }

    :ets.insert(@table_name, {id, conversation})
    Logger.debug("[Conversation.Manager] Created conversation: #{id}")

    {:reply, {:ok, id}, state}
  end

  @impl true
  def handle_call({:add_message, conversation_id, role, content, opts}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        message = Message.new(role, content, opts)

        updated = %{
          conversation
          | messages: conversation.messages ++ [message],
            updated_at: DateTime.utc_now(),
            message_count: conversation.message_count + 1
        }

        :ets.insert(@table_name, {conversation_id, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_messages, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        {:reply, {:ok, conversation.messages}, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_messages_for_llm, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        formatted = Enum.map(conversation.messages, &Message.to_llm_format/1)
        {:reply, {:ok, formatted}, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        {:reply, {:ok, conversation}, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_metadata, conversation_id}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        metadata = %{
          id: conversation.id,
          message_count: conversation.message_count,
          created_at: conversation.created_at,
          updated_at: conversation.updated_at,
          options: conversation.options
        }

        {:reply, {:ok, metadata}, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:update_options, conversation_id, new_options}, _from, state) do
    case :ets.lookup(@table_name, conversation_id) do
      [{^conversation_id, conversation}] ->
        updated = %{
          conversation
          | options: Map.merge(conversation.options, new_options),
            updated_at: DateTime.utc_now()
        }

        :ets.insert(@table_name, {conversation_id, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :conversation_not_found}, state}
    end
  end

  @impl true
  def handle_call({:delete, conversation_id}, _from, state) do
    :ets.delete(@table_name, conversation_id)
    Logger.debug("[Conversation.Manager] Deleted conversation: #{conversation_id}")
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:list, _from, state) do
    ids =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {id, _conv} -> id end)

    {:reply, ids, state}
  end

  @impl true
  def handle_call({:exists, conversation_id}, _from, state) do
    exists = :ets.member(@table_name, conversation_id)
    {:reply, exists, state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp generate_conversation_id do
    :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
  end
end
