defmodule Jido.Dialogue.NarratorInterfaceTest do
  use ExUnit.Case

  alias Jido.Dialogue.NarratorInterface

  setup do
    # Start each test with a clean slate
    Application.stop(:jido_dialogue)
    :ok = Application.start(:jido_dialogue)

    conversation_id = "test_conversation"

    script = %{
      scenes: [
        %{
          name: "introduction",
          beats: [
            %{
              name: "greeting",
              character: "TechnicalGuide",
              content: "Hello! I'm your technical guide. What's your name?"
            },
            %{
              name: "response",
              character: "TechnicalGuide",
              content: "Nice to meet you! I'm here to help you with any technical questions."
            }
          ]
        }
      ]
    }

    characters = [
      %{
        name: "TechnicalGuide",
        config: %{
          role: "A helpful technical guide who assists users with their questions",
          personality: "Friendly and knowledgeable"
        }
      }
    ]

    {:ok, conversation_id: conversation_id, script: script, characters: characters}
  end

  test "start_conversation/3 starts a new conversation with script and characters", %{
    conversation_id: conversation_id,
    script: script,
    characters: characters
  } do
    # Start conversation
    {:ok, ^conversation_id} =
      NarratorInterface.start_conversation(script, characters, conversation_id)

    # Get initial state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 2
    [system_message, character_response] = state.turns
    assert system_message.speaker == "system"
    assert character_response.speaker == "TechnicalGuide"
    assert character_response.content == "Hello! I'm your technical guide. What's your name?"
  end

  test "send_user_message/2 sends a user message and advances the script", %{
    conversation_id: conversation_id,
    script: script,
    characters: characters
  } do
    # Start conversation
    {:ok, ^conversation_id} =
      NarratorInterface.start_conversation(script, characters, conversation_id)

    # Send user message
    :ok = NarratorInterface.send_user_message(conversation_id, "My name is Alice")

    # Get updated state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 4
    [system_message, initial_response, user_message, character_response] = state.turns
    assert system_message.speaker == "system"
    assert initial_response.speaker == "TechnicalGuide"
    assert user_message.speaker == "user"
    assert user_message.content == "My name is Alice"
    assert character_response.speaker == "TechnicalGuide"

    assert character_response.content ==
             "Nice to meet you! I'm here to help you with any technical questions."
  end

  test "get_conversation_state/1 returns the full conversation state", %{
    conversation_id: conversation_id,
    script: script,
    characters: characters
  } do
    # Start conversation
    {:ok, ^conversation_id} =
      NarratorInterface.start_conversation(script, characters, conversation_id)

    # Get state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 2
    [system_message, character_response] = state.turns
    assert system_message.speaker == "system"
    assert character_response.speaker == "TechnicalGuide"
    assert character_response.content == "Hello! I'm your technical guide. What's your name?"
  end

  test "get_conversation_state/1 returns error for non-existent conversation" do
    assert {:error, :not_found} = NarratorInterface.get_conversation_state("non_existent")
  end
end
