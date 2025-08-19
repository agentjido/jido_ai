defmodule Jido.Chat.MessageTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Message
  @moduletag :capture_log
  describe "new/1" do
    test "creates a new message with required fields" do
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: "room123",
          sender: "user123",
          content: "Hello, world!",
          timestamp: timestamp
        })

      assert message.type == "chat.message"
      assert message.room_id == "room123"
      assert message.sender == "user123"
      assert message.content == "Hello, world!"
      assert message.timestamp == timestamp
      assert message.metadata == %{}
      assert is_binary(message.id)
      assert String.starts_with?(message.id, "msg_")
    end

    test "creates a new message with optional fields" do
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: "room123",
          sender: "user123",
          content: "Hello, @alice and @bob!",
          timestamp: timestamp,
          metadata: %{important: true}
        })

      assert message.type == "chat.message"
      assert message.room_id == "room123"
      assert message.sender == "user123"
      assert message.content == "Hello, @alice and @bob!"
      assert message.timestamp == timestamp
      assert Map.get(message.metadata, :important) == true
      # The metadata should not contain participant_refs yet
      refute Map.has_key?(message.metadata, :participant_refs)

      # Now parse the message for mentions
      parsed_message = Message.parse_message(message)
      # The implementation adds participant_refs to metadata
      assert is_list(Map.get(parsed_message.metadata, :participant_refs))
    end
  end

  describe "type/1" do
    test "returns predefined message types" do
      assert Message.type(:message) == "chat.message"
      assert Message.type(:join) == "chat.room.join"
      assert Message.type(:leave) == "chat.room.leave"
      assert Message.type(:room_created) == "chat.room.created"
      assert Message.type(:room_deleted) == "chat.room.deleted"
      assert Message.type(:system_notification) == "chat.system.notification"
      assert Message.type(:system_error) == "chat.system.error"
      assert Message.type(:turn_notification) == "chat.room.turn"
    end
  end

  describe "to_signal/1" do
    test "converts a message to a signal" do
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: "room123",
          sender: "user123",
          content: "Hello, world!",
          timestamp: timestamp,
          metadata: %{important: true}
        })

      signal = Message.to_signal(message)

      assert signal.type == "chat.message"
      assert signal.subject == "jido://chat/room/room123"
      assert signal.data.content == "Hello, world!"
      assert signal.data.sender == "user123"
      assert signal.data.metadata.important == true
    end

    test "handles turn notifications correctly" do
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.room.turn",
          room_id: "room123",
          sender: "system",
          content: "It's user123's turn to speak",
          timestamp: timestamp,
          metadata: %{participant_id: "user123"}
        })

      signal = Message.to_signal(message)

      assert signal.type == "chat.room.turn"
      assert signal.subject == "jido://chat/room/room123"
      assert signal.data.content == "It's user123's turn to speak"
      assert signal.data.sender == "system"
      assert signal.data.metadata.participant_id == "user123"
    end
  end

  describe "from_signal/1" do
    test "converts a signal to a message" do
      timestamp = DateTime.utc_now()

      # Create a signal that matches the actual implementation
      signal = %Jido.Signal{
        id: "msg_123",
        type: "chat.message",
        source: "jido_chat",
        subject: "jido://chat/room/room123",
        time: timestamp,
        data: %Message.ChatData{
          room_id: "room123",
          sender: "user123",
          content: "Hello, world!",
          metadata: %{important: true}
        }
      }

      {:ok, message} = Message.from_signal(signal)

      assert message.id == "msg_123"
      assert message.type == "chat.message"
      assert message.room_id == "room123"
      assert message.sender == "user123"
      assert message.content == "Hello, world!"
      assert message.timestamp == timestamp
      assert message.metadata.important == true
    end
  end

  describe "parse_message/1" do
    test "parses mentions in message content" do
      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: "room123",
          sender: "user123",
          content: "Hello @alice and @bob!",
          timestamp: DateTime.utc_now()
        })

      # Initially, there should be no participant_refs
      refute Map.has_key?(message.metadata, :participant_refs)

      # After parsing, participant_refs should be added
      parsed_message = Message.parse_message(message)
      assert is_list(parsed_message.metadata.participant_refs)
      assert length(parsed_message.metadata.participant_refs) == 2
    end
  end

  describe "chat_message/4" do
    test "creates a chat message signal" do
      signal = Message.chat_message("room123", "user123", "Hello, world!")

      assert signal.type == "chat.message"
      assert signal.subject == "jido://chat/room/room123"
      assert signal.data.content == "Hello, world!"
      assert signal.data.sender == "user123"
      assert signal.data.room_id == "room123"
    end
  end

  describe "join_room/3" do
    test "creates a join room signal" do
      signal = Message.join_room("room123", "user123")

      assert signal.type == "chat.room.join"
      assert signal.subject == "jido://chat/room/room123"
      assert signal.data.content == "user123 has joined the room"
      assert signal.data.sender == "user123"
      assert signal.data.room_id == "room123"
    end
  end

  describe "leave_room/3" do
    test "creates a leave room signal" do
      signal = Message.leave_room("room123", "user123")

      assert signal.type == "chat.room.leave"
      assert signal.subject == "jido://chat/room/room123"
      assert signal.data.content == "user123 has left the room"
      assert signal.data.sender == "user123"
      assert signal.data.room_id == "room123"
    end
  end

  describe "Jido.AI.Promptable implementation" do
    test "to_prompt/1 formats regular chat messages correctly" do
      {:ok, message} =
        Message.new(%{
          type: Message.type(:message),
          room_id: "room123",
          sender: "alice",
          content: "Hello, world!",
          timestamp: DateTime.utc_now()
        })

      assert Jido.AI.Promptable.to_prompt(message) == "alice: Hello, world!"
    end

    test "to_prompt/1 formats system messages correctly" do
      {:ok, message} =
        Message.new(%{
          type: Message.type(:system_notification),
          room_id: "room123",
          sender: "system",
          content: "Server maintenance in 5 minutes",
          timestamp: DateTime.utc_now()
        })

      assert Jido.AI.Promptable.to_prompt(message) ==
               "[SYSTEM] system: Server maintenance in 5 minutes"
    end

    test "to_prompt/1 formats room event messages correctly" do
      {:ok, message} =
        Message.new(%{
          type: Message.type(:join),
          room_id: "room123",
          sender: "bob",
          content: "bob has joined the room",
          timestamp: DateTime.utc_now()
        })

      assert Jido.AI.Promptable.to_prompt(message) == "[ROOM EVENT] bob: bob has joined the room"
    end

    test "to_prompt/1 formats turn notification messages correctly" do
      {:ok, message} =
        Message.new(%{
          type: Message.type(:turn_notification),
          room_id: "room123",
          sender: "system",
          content: "It's alice's turn to speak",
          timestamp: DateTime.utc_now(),
          metadata: %{participant_id: "alice"}
        })

      assert Jido.AI.Promptable.to_prompt(message) == "[TURN] system: It's alice's turn to speak"
    end

    test "to_prompt/1 preserves mentions in the content" do
      {:ok, message} =
        Message.new(%{
          type: Message.type(:message),
          room_id: "room123",
          sender: "alice",
          content: "Hello @bob, how are you?",
          timestamp: DateTime.utc_now()
        })

      # Parse the message for mentions
      message = Message.parse_message(message)

      assert Jido.AI.Promptable.to_prompt(message) == "alice: Hello @bob, how are you?"
    end
  end
end
