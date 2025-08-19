defmodule Jido.Dialogue.CharacterRegistry do
  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def register_character(conversation_id, character_name, config) do
    GenServer.call(__MODULE__, {:register_character, conversation_id, character_name, config})
  end

  def get_character(conversation_id, character_name) do
    GenServer.call(__MODULE__, {:get_character, conversation_id, character_name})
  end

  def get_conversation_characters(conversation_id) do
    GenServer.call(__MODULE__, {:get_conversation_characters, conversation_id})
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{conversations: %{}}}
  end

  @impl true
  def handle_call({:register_character, conv_id, char_name, config}, _from, state) do
    case get_in(state.conversations, [conv_id, char_name]) do
      nil ->
        {:ok, pid} =
          DynamicSupervisor.start_child(
            Jido.Dialogue.CharacterSupervisor,
            {Jido.Dialogue.CharacterServer,
             [
               conversation_id: conv_id,
               name: char_name,
               config: config
             ]}
          )

        new_state =
          update_in(state.conversations, fn convos ->
            Map.put_new(convos, conv_id, %{})
            |> put_in([conv_id, char_name], pid)
          end)

        {:reply, :ok, new_state}

      _pid ->
        {:reply, {:error, :already_exists}, state}
    end
  end

  @impl true
  def handle_call({:get_character, conv_id, char_name}, _from, state) do
    case get_in(state.conversations, [conv_id, char_name]) do
      nil -> {:reply, {:error, :not_found}, state}
      pid -> {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:get_conversation_characters, conv_id}, _from, state) do
    characters = get_in(state.conversations, [conv_id]) || %{}
    {:reply, {:ok, characters}, state}
  end
end
