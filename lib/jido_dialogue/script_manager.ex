defmodule Jido.Dialogue.ScriptManager do
  use GenServer

  def start_link(init_arg) do
    GenServer.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  def load_script(conversation_id, script) do
    GenServer.call(__MODULE__, {:load_script, conversation_id, script})
  end

  def get_script(conversation_id) do
    GenServer.call(__MODULE__, {:get_script, conversation_id})
  end

  def get_current_scene(conversation_id) do
    GenServer.call(__MODULE__, {:get_current_scene, conversation_id})
  end

  def advance_script(conversation_id) do
    GenServer.call(__MODULE__, {:advance_script, conversation_id})
  end

  @impl true
  def init(_init_arg) do
    {:ok, %{scripts: %{}, states: %{}}}
  end

  @impl true
  def handle_call({:load_script, conv_id, script}, _from, state) do
    with :ok <- validate_script(script),
         initial_state <- initialize_script_state(script) do
      new_state =
        state
        |> put_in([:scripts, conv_id], script)
        |> put_in([:states, conv_id], initial_state)

      {:reply, {:ok, script}, new_state}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_script, conv_id}, _from, state) do
    case Map.fetch(state.scripts, conv_id) do
      {:ok, script} -> {:reply, {:ok, script}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_current_scene, conv_id}, _from, state) do
    with {:ok, script_state} <- Map.fetch(state.states, conv_id) do
      {:reply, {:ok, script_state}, state}
    else
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:advance_script, conv_id}, _from, state) do
    with {:ok, script} <- Map.fetch(state.scripts, conv_id),
         {:ok, script_state} <- Map.fetch(state.states, conv_id),
         {:ok, new_script_state} <- advance_state(script, script_state) do
      new_state = put_in(state.states[conv_id], new_script_state)
      {:reply, :ok, new_state}
    else
      :error -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  # Private functions

  defp validate_script(%{scenes: scenes}) when is_list(scenes) do
    if Enum.all?(scenes, &valid_scene?/1), do: :ok, else: {:error, :invalid_script}
  end

  defp validate_script(_), do: {:error, :invalid_script}

  defp valid_scene?(%{name: name, beats: beats})
       when is_binary(name) and is_list(beats) do
    Enum.all?(beats, &valid_beat?/1)
  end

  defp valid_scene?(_), do: false

  defp valid_beat?(%{
         name: name,
         character: character,
         content: content
       })
       when is_binary(name) and is_binary(character) and
              is_binary(content),
       do: true

  defp valid_beat?(_), do: false

  defp initialize_script_state(%{scenes: [first_scene | _]}) do
    %{
      name: first_scene.name,
      current_beat: first_scene.beats |> List.first() |> Map.get(:name),
      scene_index: 0,
      beat_index: 0
    }
  end

  defp advance_state(script, state) do
    current_scene = Enum.at(script.scenes, state.scene_index)
    next_beat_index = state.beat_index + 1

    cond do
      next_beat_index < length(current_scene.beats) ->
        # Move to next beat in current scene
        new_state = %{
          state
          | beat_index: next_beat_index,
            current_beat: Enum.at(current_scene.beats, next_beat_index).name
        }

        {:ok, new_state}

      state.scene_index + 1 < length(script.scenes) ->
        # Move to first beat of next scene
        next_scene = Enum.at(script.scenes, state.scene_index + 1)

        new_state = %{
          state
          | scene_index: state.scene_index + 1,
            beat_index: 0,
            name: next_scene.name,
            current_beat: List.first(next_scene.beats).name
        }

        {:ok, new_state}

      true ->
        {:error, :end_of_script}
    end
  end
end
