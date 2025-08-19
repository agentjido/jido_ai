defmodule Jido.Dialogue.CharacterIntegrationTest do
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

  test "character interaction in conversation", %{
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

  test "character maintains context across messages", %{
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

    # Send user message
    :ok = NarratorInterface.send_user_message(conversation_id, "My name is Bob")

    # Get updated state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 4
    [system_message, initial_response, user_message, character_response] = state.turns
    assert system_message.speaker == "system"
    assert initial_response.speaker == "TechnicalGuide"
    assert user_message.speaker == "user"
    assert user_message.content == "My name is Bob"
    assert character_response.speaker == "TechnicalGuide"

    assert character_response.content ==
             "Nice to meet you! I'm here to help you with any technical questions."
  end

  test "character switches to dynamic responses after script ends", %{
    conversation_id: conversation_id,
    script: script,
    characters: characters
  } do
    # Start conversation
    {:ok, ^conversation_id} =
      NarratorInterface.start_conversation(script, characters, conversation_id)

    # Get through the scripted part
    :ok = NarratorInterface.send_user_message(conversation_id, "My name is Charlie")
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 4

    # Send another message after script ends
    :ok = NarratorInterface.send_user_message(conversation_id, "What can you help me with?")

    # Get updated state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 6
    [_, _, _, _, user_message, character_response] = state.turns
    assert user_message.speaker == "user"
    assert user_message.content == "What can you help me with?"
    assert character_response.speaker == "TechnicalGuide"
    # Dynamic response should mention help
    assert character_response.content =~ "help"
  end

  test "character uses context in dynamic responses", %{
    conversation_id: conversation_id,
    script: script,
    characters: characters
  } do
    # Start conversation
    {:ok, ^conversation_id} =
      NarratorInterface.start_conversation(script, characters, conversation_id)

    # Get through the scripted part
    :ok = NarratorInterface.send_user_message(conversation_id, "My name is David")
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 4

    # Send another message after script ends
    :ok = NarratorInterface.send_user_message(conversation_id, "Can you help me?")

    # Get updated state
    {:ok, state} = NarratorInterface.get_conversation_state(conversation_id)
    assert length(state.turns) == 6
    [_, _, _, _, user_message, character_response] = state.turns
    assert user_message.speaker == "user"
    assert user_message.content == "Can you help me?"
    assert character_response.speaker == "TechnicalGuide"
    # Response should include the user's name
    assert character_response.content =~ "David"
    # Response should mention help
    assert character_response.content =~ "help"
  end
end
