defmodule Jido.Dialogue.NarratorInterface do
  alias Jido.Dialogue.{DialogueManager, ScriptManager, CharacterRegistry}

  @doc """
  Starts a new conversation with the given script and characters.
  Returns {:ok, conversation_id} on success, or {:error, reason} on failure.
  """
  def start_conversation(script, characters, conversation_id) do
    with {:ok, _script} <- ScriptManager.load_script(conversation_id, script),
         {:ok, _} <- register_characters(conversation_id, characters),
         {:ok, _} <- DialogueManager.start_conversation(conversation_id),
         :ok <- send_initial_message(conversation_id),
         {:ok, _} <- get_conversation_state(conversation_id) do
      {:ok, conversation_id}
    end
  end

  @doc """
  Sends a user message to the conversation.
  Returns :ok on success, or {:error, reason} on failure.
  """
  def send_user_message(conversation_id, content) do
    DialogueManager.send_message(conversation_id, %{
      speaker: "user",
      content: content,
      timestamp: DateTime.utc_now()
    })
  end

  @doc """
  Gets the full state of a conversation, including turns, current scene/beat, and characters.
  Returns {:ok, state} on success, or {:error, reason} on failure.
  """
  def get_conversation_state(conversation_id) do
    DialogueManager.get_conversation_state(conversation_id)
  end

  # Private functions

  defp register_characters(conversation_id, characters) do
    Enum.reduce_while(characters, {:ok, []}, fn character, {:ok, acc} ->
      case CharacterRegistry.register_character(conversation_id, character.name, character.config) do
        :ok -> {:cont, {:ok, [character | acc]}}
        error -> {:halt, error}
      end
    end)
  end

  defp send_initial_message(conversation_id) do
    DialogueManager.send_message(conversation_id, %{
      speaker: "system",
      content: "start",
      timestamp: DateTime.utc_now()
    })
  end
end
