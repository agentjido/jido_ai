defmodule Jido.Chat.ParticipantRefTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.ParticipantRef
  @moduletag :capture_log
  describe "new/4" do
    test "creates a new participant reference with required fields" do
      ref = ParticipantRef.new("user123", "User 123", 0, 10)

      assert ref.participant_id == "user123"
      assert ref.display_name == "User 123"
      assert ref.ref_type == :mention
      assert ref.offset == 0
      assert ref.length == 10
    end
  end

  describe "new/1" do
    test "creates a new participant reference from a map" do
      attrs = %{
        participant_id: "user123",
        display_name: "User 123",
        offset: 5,
        length: 8
      }

      {:ok, ref} = ParticipantRef.new(attrs)

      assert ref.participant_id == "user123"
      assert ref.display_name == "User 123"
      assert ref.ref_type == :mention
      assert ref.offset == 5
      assert ref.length == 8
    end
  end

  describe "new!/1" do
    test "returns the reference struct directly" do
      attrs = %{
        participant_id: "user123",
        display_name: "User 123",
        offset: 5,
        length: 8
      }

      ref = ParticipantRef.new!(attrs)

      assert ref.participant_id == "user123"
      assert ref.display_name == "User 123"
      assert ref.ref_type == :mention
      assert ref.offset == 5
      assert ref.length == 8
    end
  end
end
