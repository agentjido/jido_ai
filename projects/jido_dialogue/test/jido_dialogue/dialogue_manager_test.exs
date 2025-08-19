defmodule Jido.Dialogue.DialogueManagerTest do
  use ExUnit.Case
  alias Jido.Dialogue.{DialogueManager, TestHelper}

  setup do
    TestHelper.start_supervised_app()
    on_exit(fn -> TestHelper.stop_supervised_app() end)
    :ok
  end

  test "conversation management start_conversation/1 starts a new conversation" do
    assert {:ok, _} = DialogueManager.start_conversation("test-1")
  end

  test "conversation management start_conversation/1 returns error when conversation id already exists" do
    {:ok, _} = DialogueManager.start_conversation("test-2")
    assert {:error, :already_exists} = DialogueManager.start_conversation("test-2")
  end

  test "message handling send_message/2 sends message to existing conversation" do
    {:ok, id} = DialogueManager.start_conversation("test-3")

    message = %{
      timestamp: ~U[2025-01-18 19:40:20.712738Z],
      speaker: "user",
      content: "Hello"
    }

    assert :ok = DialogueManager.send_message(id, message)
  end

  test "message handling send_message/2 returns error for non-existent conversation" do
    message = %{
      timestamp: ~U[2025-01-18 19:40:20.712738Z],
      speaker: "user",
      content: "Hello"
    }

    assert {:error, :not_found} = DialogueManager.send_message("non-existent", message)
  end

  test "state retrieval get_conversation_state/1 returns conversation state" do
    {:ok, id} = DialogueManager.start_conversation("test-4")

    message = %{
      timestamp: ~U[2025-01-18 19:40:20.712738Z],
      speaker: "user",
      content: "Hello"
    }

    :ok = DialogueManager.send_message(id, message)
    assert {:ok, state} = DialogueManager.get_conversation_state(id)
    assert is_map(state)
  end

  test "state retrieval get_conversation_state/1 returns error for non-existent conversation" do
    assert {:error, :not_found} = DialogueManager.get_conversation_state("non-existent")
  end
end
