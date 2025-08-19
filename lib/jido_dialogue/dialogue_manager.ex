defmodule Jido.Dialogue.DialogueManager do
  use GenServer

  alias Jido.Dialogue.ConversationServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def start_conversation(conversation_id) do
    GenServer.call(__MODULE__, {:start_conversation, conversation_id})
  end

  def send_message(conversation_id, message) do
    GenServer.call(__MODULE__, {:send_message, conversation_id, message})
  end

  def get_conversation_state(conversation_id) do
    GenServer.call(__MODULE__, {:get_state, conversation_id})
  end

  # Server Callbacks

  @impl true
  def init(_) do
    {:ok, %{conversations: %{}}}
  end

  @impl true
  def handle_call({:start_conversation, conversation_id}, _from, state) do
    case Map.has_key?(state.conversations, conversation_id) do
      true ->
        {:reply, {:error, :already_exists}, state}

      false ->
        {:ok, pid} = ConversationServer.start_link(id: conversation_id)
        new_state = put_in(state.conversations[conversation_id], pid)
        {:reply, {:ok, conversation_id}, new_state}
    end
  end

  @impl true
  def handle_call({:send_message, conversation_id, message}, _from, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        result = ConversationServer.add_message(pid, message.speaker, message.content)
        {:reply, result, state}
    end
  end

  @impl true
  def handle_call({:get_state, conversation_id}, _from, state) do
    case Map.get(state.conversations, conversation_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pid ->
        {:ok, turns} = ConversationServer.get_turns(pid)
        {:reply, {:ok, %{turns: turns}}, state}
    end
  end
end
