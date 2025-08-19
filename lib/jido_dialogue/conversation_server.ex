defmodule Jido.Dialogue.ConversationServer do
  use GenServer

  alias Jido.Dialogue.{CharacterRegistry, ScriptManager}

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def add_message(pid, speaker, content) do
    GenServer.call(pid, {:add_message, speaker, content})
  end

  def get_turns(pid) do
    GenServer.call(pid, :get_turns)
  end

  @impl true
  def init(opts) do
    state = %{
      id: Keyword.fetch!(opts, :id),
      turns: [],
      script_ended: false,
      context: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_message, speaker, content}, _from, state) do
    # Add the message
    turn = %{
      speaker: speaker,
      content: content,
      timestamp: DateTime.utc_now()
    }

    state = %{state | turns: state.turns ++ [turn]}

    # Update context based on the message
    state = update_context(state, turn)

    # Get character response if it's a user message or system start message
    state =
      if speaker in ["user", "system"] do
        case handle_character_response(state) do
          {:ok, new_state} -> new_state
          _ -> state
        end
      else
        state
      end

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_turns, _from, state) do
    {:reply, {:ok, state.turns}, state}
  end

  # Private Functions

  defp handle_character_response(state) do
    # First try to get a scripted response
    case get_scripted_response(state) do
      {:ok, new_state} ->
        {:ok, new_state}

      {:error, :end_of_script} ->
        # If we've reached the end of the script, switch to dynamic responses
        get_dynamic_response(state)

      error ->
        error
    end
  end

  defp get_scripted_response(%{script_ended: true} = _state) do
    {:error, :end_of_script}
  end

  defp get_scripted_response(state) do
    with {:ok, %{name: _scene_name, current_beat: _beat_name} = scene} <-
           ScriptManager.get_current_scene(state.id),
         {:ok, script} <- ScriptManager.get_script(state.id),
         character_name <- get_character_for_beat(script, scene),
         response <- get_character_response(script, scene) do
      # Add character response
      turn = %{
        speaker: character_name,
        content: response,
        timestamp: DateTime.utc_now()
      }

      new_state = %{
        state
        | turns: state.turns ++ [turn]
      }

      # Update context with the character's response
      new_state = update_context(new_state, turn)

      # Advance script after character response
      case ScriptManager.advance_script(state.id) do
        :ok -> {:ok, new_state}
        {:error, :end_of_script} -> {:ok, %{new_state | script_ended: true}}
        error -> error
      end
    else
      {:error, :end_of_script} -> {:error, :end_of_script}
      error -> error
    end
  end

  defp get_dynamic_response(state) do
    # Get the last character that spoke from the script
    with {:ok, script} <- ScriptManager.get_script(state.id),
         character_name <- get_last_character(script),
         {:ok, characters} <- CharacterRegistry.get_conversation_characters(state.id),
         {:ok, character_pid} <- Map.fetch(characters, character_name),
         message = prepare_message_with_context(List.last(state.turns), state.context),
         {:ok, response} <- Jido.Dialogue.CharacterServer.handle_message(character_pid, message) do
      turn = %{
        speaker: character_name,
        content: response,
        timestamp: DateTime.utc_now()
      }

      new_state = %{
        state
        | turns: state.turns ++ [turn]
      }

      # Update context with the character's response
      new_state = update_context(new_state, turn)

      {:ok, new_state}
    else
      error -> error
    end
  end

  defp get_character_for_beat(script, %{name: scene_name, current_beat: beat_name}) do
    scene = Enum.find(script.scenes, &(&1.name == scene_name))
    beat = Enum.find(scene.beats, &(&1.name == beat_name))
    beat.character
  end

  defp get_character_response(script, %{name: scene_name, current_beat: beat_name}) do
    scene = Enum.find(script.scenes, &(&1.name == scene_name))
    beat = Enum.find(scene.beats, &(&1.name == beat_name))
    beat.content
  end

  defp get_last_character(script) do
    last_scene = List.last(script.scenes)
    last_beat = List.last(last_scene.beats)
    last_beat.character
  end

  defp update_context(state, %{speaker: "user", content: content}) do
    # Extract name from content if present
    case Regex.run(~r/My name is (\w+)/i, content) do
      [_, name] ->
        %{state | context: Map.put(state.context, :user_name, name)}

      nil ->
        state
    end
  end

  defp update_context(state, _), do: state

  defp prepare_message_with_context(message, context) do
    Map.merge(message, %{context: context})
  end
end
