defmodule Jido.Dialogue.ManagerTest do
  use ExUnit.Case
  alias Jido.Dialogue.{Manager, Conversation}
  doctest Jido.Dialogue.Manager

  describe "start_conversation/2" do
    test "creates a new conversation" do
      conv = Manager.start_conversation("test-1")

      assert %Conversation{} = conv
      assert conv.id == "test-1"
      assert conv.state == :initial
    end

    test "accepts metadata" do
      metadata = %{channel: "web"}
      conv = Manager.start_conversation("test-2", metadata)

      assert conv.metadata.channel == "web"
    end
  end

  describe "add_message/4" do
    test "adds a message to the conversation" do
      conv = Manager.start_conversation("test-3")
      updated = Manager.add_message(conv, :human, "Hello")

      assert length(updated.turns) == 1
      assert List.first(updated.turns).content == "Hello"
      assert List.first(updated.turns).speaker == :human
    end

    test "accepts message metadata" do
      conv = Manager.start_conversation("test-4")
      metadata = %{intent: "greeting"}
      updated = Manager.add_message(conv, :human, "Hi", metadata)

      turn = List.first(updated.turns)
      assert turn.metadata.intent == "greeting"
    end
  end

  describe "get_history/1" do
    test "returns empty list for new conversation" do
      conv = Manager.start_conversation("test-5")
      assert Manager.get_history(conv) == []
    end

    test "returns all turns in order" do
      conv =
        "test-6"
        |> Manager.start_conversation()
        |> Manager.add_message(:human, "Hello")
        |> Manager.add_message(:agent, "Hi")
        |> Manager.add_message(:human, "How are you?")

      history = Manager.get_history(conv)
      assert length(history) == 3
      assert Enum.map(history, & &1.content) == ["Hello", "Hi", "How are you?"]
    end
  end

  describe "get_context/1" do
    test "returns empty map for new conversation" do
      conv = Manager.start_conversation("test-7")
      assert Manager.get_context(conv) == %{}
    end

    test "returns current context" do
      conv =
        "test-8"
        |> Manager.start_conversation()
        |> Conversation.update_context(%{topic: "greeting"})

      assert Manager.get_context(conv).topic == "greeting"
    end
  end
end
