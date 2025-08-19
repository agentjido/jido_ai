defmodule Jido.Dialogue.CharacterServerTest do
  use ExUnit.Case

  alias Jido.Dialogue.CharacterServer

  setup do
    config = %{
      role: "a helpful technical guide",
      personality: "friendly and knowledgeable"
    }

    {:ok, pid} =
      CharacterServer.start_link(
        conversation_id: "test-conversation",
        name: "TechnicalGuide",
        config: config
      )

    %{pid: pid}
  end

  test "handle_message/2 processes user message and generates response", %{pid: pid} do
    message = %{speaker: "user", content: "Hello there!"}
    {:ok, response} = CharacterServer.handle_message(pid, message)
    assert response =~ "Hello"
    assert response =~ "TechnicalGuide"
  end

  test "handle_message/2 maintains memory of conversation", %{pid: pid} do
    # First message with name
    message1 = %{
      speaker: "user",
      content: "My name is Alice",
      context: %{user_name: "Alice"}
    }

    {:ok, response1} = CharacterServer.handle_message(pid, message1)
    assert response1 =~ "Alice"

    # Ask about name
    message2 = %{
      speaker: "user",
      content: "What's my name?",
      context: %{user_name: "Alice"}
    }

    {:ok, response2} = CharacterServer.handle_message(pid, message2)
    assert response2 =~ "Alice"
  end

  test "handle_message/2 uses character config in responses", %{pid: pid} do
    message = %{speaker: "user", content: "What is your role?"}
    {:ok, response} = CharacterServer.handle_message(pid, message)
    assert response =~ "helpful technical guide"
  end

  test "get_state/1 returns current character state", %{pid: pid} do
    {:ok, state} = CharacterServer.get_state(pid)
    assert state.name == "TechnicalGuide"
    assert state.config.role == "a helpful technical guide"
  end

  test "character remembers name from memory even without context", %{pid: pid} do
    # First message introduces name
    message1 = %{
      speaker: "user",
      content: "My name is Bob"
    }

    {:ok, _} = CharacterServer.handle_message(pid, message1)

    # Second message asks about name without context
    message2 = %{
      speaker: "user",
      content: "What's my name?"
    }

    {:ok, response} = CharacterServer.handle_message(pid, message2)
    assert response =~ "Bob"
  end

  test "character tracks conversation topics", %{pid: pid} do
    # First message about technical help
    message1 = %{
      speaker: "user",
      content: "I need help with a technical problem"
    }

    {:ok, _} = CharacterServer.handle_message(pid, message1)

    # Second message should reference previous topic
    message2 = %{
      speaker: "user",
      content: "Can you assist me?"
    }

    {:ok, response} = CharacterServer.handle_message(pid, message2)
    assert response =~ "discussing"
    assert response =~ "technical"
    assert response =~ "help"
    assert response =~ "problem"
  end

  test "memory is limited to last 10 messages", %{pid: pid} do
    # Send 11 messages
    Enum.each(1..11, fn i ->
      message = %{
        speaker: "user",
        content: "Message #{i}"
      }

      CharacterServer.handle_message(pid, message)
    end)

    # Check state
    {:ok, state} = CharacterServer.get_state(pid)
    assert length(state.memory) == 10
    # First message should be dropped
    refute Enum.any?(state.memory, fn msg -> msg.content == "Message 1" end)
    # Last message should be present
    assert Enum.any?(state.memory, fn msg -> msg.content == "Message 11" end)
  end
end
