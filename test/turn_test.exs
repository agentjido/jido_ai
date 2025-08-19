defmodule Jido.Dialogue.TurnTest do
  use ExUnit.Case
  alias Jido.Dialogue.Turn
  doctest Jido.Dialogue.Turn

  describe "new/3" do
    test "creates a new turn with required fields" do
      content = "Hello there"
      turn = Turn.new(:human, content)

      assert turn.speaker == :human
      assert turn.content == content
      assert %DateTime{} = turn.timestamp
      assert is_binary(turn.id)
      assert map_size(turn.metadata) == 0
    end

    test "accepts custom metadata" do
      metadata = %{intent: "greeting", confidence: 0.9}
      turn = Turn.new(:agent, "Hi!", metadata)

      assert turn.metadata.intent == "greeting"
      assert turn.metadata.confidence == 0.9
    end

    test "generates unique IDs for different turns" do
      turn1 = Turn.new(:human, "msg1")
      turn2 = Turn.new(:human, "msg2")

      refute turn1.id == turn2.id
    end
  end
end
