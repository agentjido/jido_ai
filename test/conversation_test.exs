defmodule Jido.Dialogue.ConversationTest do
  use ExUnit.Case
  alias Jido.Dialogue.{Conversation, Turn}
  doctest Jido.Dialogue.Conversation

  setup do
    conv = Conversation.new("test-conv-1")
    {:ok, conversation: conv}
  end

  describe "new/2" do
    test "creates a new conversation with default values", %{conversation: conv} do
      assert conv.id == "test-conv-1"
      assert conv.state == :initial
      assert conv.turns == []
      assert conv.context == %{}
      assert conv.metadata == %{}
      assert %DateTime{} = conv.start_time
      assert is_nil(conv.end_time)
    end

    test "accepts custom metadata" do
      metadata = %{user_id: "123", channel: "web"}
      conv = Conversation.new("test-conv-2", metadata)

      assert conv.metadata.user_id == "123"
      assert conv.metadata.channel == "web"
    end
  end

  describe "add_turn/2" do
    test "adds a turn to the conversation", %{conversation: conv} do
      turn = Turn.new(:human, "Hello")
      updated_conv = Conversation.add_turn(conv, turn)

      assert length(updated_conv.turns) == 1
      assert List.first(updated_conv.turns) == turn
      assert updated_conv.state == :active
    end

    test "preserves turn order", %{conversation: conv} do
      turn1 = Turn.new(:human, "First")
      turn2 = Turn.new(:agent, "Second")

      conv =
        conv
        |> Conversation.add_turn(turn1)
        |> Conversation.add_turn(turn2)

      assert [^turn1, ^turn2] = conv.turns
    end
  end

  describe "update_context/2" do
    test "merges new context with existing context", %{conversation: conv} do
      conv = Conversation.update_context(conv, %{topic: "greeting"})
      assert conv.context.topic == "greeting"

      conv = Conversation.update_context(conv, %{intent: "farewell"})
      assert conv.context.topic == "greeting"
      assert conv.context.intent == "farewell"
    end
  end

  describe "complete/1" do
    test "marks conversation as completed", %{conversation: conv} do
      completed = Conversation.complete(conv)

      assert completed.state == :completed
      assert %DateTime{} = completed.end_time
    end
  end

  describe "latest_turn/1" do
    test "returns nil for empty conversation", %{conversation: conv} do
      assert is_nil(Conversation.latest_turn(conv))
    end

    test "returns the most recent turn", %{conversation: conv} do
      turn1 = Turn.new(:human, "First")
      turn2 = Turn.new(:agent, "Second")

      conv =
        conv
        |> Conversation.add_turn(turn1)
        |> Conversation.add_turn(turn2)

      assert Conversation.latest_turn(conv) == turn2
    end
  end

  describe "turn_count/1" do
    test "returns 0 for empty conversation", %{conversation: conv} do
      assert Conversation.turn_count(conv) == 0
    end

    test "returns correct count after adding turns", %{conversation: conv} do
      conv =
        conv
        |> Conversation.add_turn(Turn.new(:human, "One"))
        |> Conversation.add_turn(Turn.new(:agent, "Two"))
        |> Conversation.add_turn(Turn.new(:human, "Three"))

      assert Conversation.turn_count(conv) == 3
    end
  end

  describe "duration/1" do
    test "returns nil for incomplete conversation", %{conversation: conv} do
      assert is_nil(Conversation.duration(conv))
    end

    test "returns duration in seconds for completed conversation", %{conversation: conv} do
      # Wait 1 second
      Process.sleep(1000)
      completed = Conversation.complete(conv)

      assert Conversation.duration(completed) >= 1
    end
  end
end
