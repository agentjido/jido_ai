defmodule Jido.Chat.ParticipantTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Participant
  @moduletag :capture_log
  describe "new/2" do
    test "creates a new participant with default values" do
      {:ok, participant} = Participant.new("user123")

      assert participant.id == "user123"
      assert participant.display_name == "user123"
      assert participant.type == :human
      assert participant.metadata == %{}
    end

    test "creates a new participant with custom values" do
      {:ok, participant} =
        Participant.new("agent456",
          display_name: "Agent Smith",
          type: :agent,
          metadata: %{capabilities: ["text", "image"]}
        )

      assert participant.id == "agent456"
      assert participant.display_name == "Agent Smith"
      assert participant.type == :agent
      assert participant.metadata == %{capabilities: ["text", "image"]}
    end
  end

  describe "new!/2" do
    test "returns the participant struct directly" do
      participant = Participant.new!("user123", display_name: "User 123")

      assert participant.id == "user123"
      assert participant.display_name == "User 123"
      assert participant.type == :human
      assert participant.metadata == %{}
    end
  end

  describe "display_name/1" do
    test "returns the display name when set" do
      participant = Participant.new!("user123", display_name: "User 123")
      assert Participant.display_name(participant) == "User 123"
    end

    test "returns the id when display name is nil" do
      participant = %{Participant.new!("user123") | display_name: nil}
      assert Participant.display_name(participant) == "user123"
    end
  end
end
