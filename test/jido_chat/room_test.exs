defmodule Jido.Chat.RoomTest do
  use ExUnit.Case, async: true
  alias Jido.Chat.Room
  alias Jido.Chat.Participant
  alias Jido.Chat.Message
  @moduletag :capture_log

  setup do
    # Create a test bus with a unique name
    bus_name = :"Jido.Signal.Bus.Test#{:rand.uniform(1000)}"
    {:ok, bus_pid} = Jido.Signal.Bus.start_link(name: bus_name)

    # Create a test room with a unique ID
    room_id = "test_room_#{:rand.uniform(1000)}"

    {:ok, room_pid} =
      Room.start_link(id: room_id, name: "Test Room", strategy: :free_form, bus: bus_pid)

    # Create test participants
    {:ok, human} = Participant.new("human1", display_name: "Human User", type: :human)
    {:ok, agent} = Participant.new("agent1", display_name: "Agent User", type: :agent)

    %{
      room_id: room_id,
      room_pid: room_pid,
      human: human,
      agent: agent,
      bus_pid: bus_pid,
      bus_name: bus_name
    }
  end

  describe "start_link/1" do
    test "starts a room process with default values" do
      room_id = "default_room_#{:rand.uniform(1000)}"
      bus_name = :"Jido.Signal.Bus.Test#{:rand.uniform(1000)}"
      {:ok, bus_pid} = Jido.Signal.Bus.start_link(name: bus_name)
      {:ok, pid} = Room.start_link(id: room_id, bus: bus_pid)

      assert Process.alive?(pid)

      # Verify default values
      state = :sys.get_state(pid)
      assert state.id == room_id
      assert state.name == room_id
      assert state.strategy_module == Jido.Chat.Room.Strategy.FreeForm
    end

    test "starts a room process with custom values" do
      room_id = "custom_room_#{:rand.uniform(1000)}"
      bus_name = :"Jido.Signal.Bus.Test#{:rand.uniform(1000)}"
      {:ok, bus_pid} = Jido.Signal.Bus.start_link(name: bus_name)

      {:ok, pid} =
        Room.start_link(
          id: room_id,
          name: "Custom Room",
          strategy: :round_robin,
          bus: bus_pid
        )

      assert Process.alive?(pid)

      # Verify custom values
      state = :sys.get_state(pid)
      assert state.id == room_id
      assert state.name == "Custom Room"
      assert state.strategy_module == Jido.Chat.Room.Strategy.RoundRobin
    end
  end

  describe "add_participant/2" do
    test "adds a participant to the room", %{room_id: room_id, room_pid: room_pid, human: human} do
      :ok = Room.add_participant(room_id, human)

      state = :sys.get_state(room_pid)
      assert Map.has_key?(state.participants, human.id)
      # Room created message should be added
      assert length(state.messages) == 1
    end

    test "returns error when adding the same participant twice", %{room_id: room_id, human: human} do
      :ok = Room.add_participant(room_id, human)
      # Should be idempotent
      :ok = Room.add_participant(room_id, human)
    end
  end

  describe "remove_participant/2" do
    test "removes a participant from the room", %{
      room_id: room_id,
      room_pid: room_pid,
      human: human
    } do
      :ok = Room.add_participant(room_id, human)
      :ok = Room.remove_participant(room_id, human.id)

      state = :sys.get_state(room_pid)
      refute Map.has_key?(state.participants, human.id)
    end

    test "returns error when removing a participant not in the room", %{room_id: room_id} do
      {:error, :not_found} = Room.remove_participant(room_id, "nonexistent_id")
    end
  end

  describe "get_participants/1" do
    test "returns all participants in the room", %{room_id: room_id, human: human, agent: agent} do
      :ok = Room.add_participant(room_id, human)
      :ok = Room.add_participant(room_id, agent)

      {:ok, participants} = Room.get_participants(room_id)

      assert map_size(participants) == 2
      assert Map.has_key?(participants, human.id)
      assert Map.has_key?(participants, agent.id)
    end

    test "returns empty map for a room with no participants", %{room_id: room_id} do
      {:ok, participants} = Room.get_participants(room_id)
      assert participants == %{}
    end
  end

  describe "get_messages/1" do
    test "returns all messages in the room", %{room_id: room_id, human: human} do
      :ok = Room.add_participant(room_id, human)

      # Add a test message via signal
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: room_id,
          sender: human.id,
          content: "Hello, world!",
          timestamp: timestamp
        })

      # Send the signal to the room process
      signal = Message.to_signal(message)
      # Get the actual PID from the registry
      [{pid, _}] = Registry.lookup(Jido.Chat.Registry, "room:#{room_id}")
      send(pid, {:signal, signal})

      # Allow some time for the message to be processed
      :timer.sleep(100)

      {:ok, messages} = Room.get_messages(room_id)

      # Room created message and our test message
      assert length(messages) == 2
      assert Enum.any?(messages, fn msg -> msg.content == "Hello, world!" end)
    end
  end

  describe "handle_info/2 for chat signals" do
    test "processes chat message signals for the room", %{room_id: room_id, human: human} do
      :ok = Room.add_participant(room_id, human)

      # Create a message signal
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: room_id,
          sender: human.id,
          content: "Hello via signal!",
          timestamp: timestamp
        })

      signal = Message.to_signal(message)

      # Send the signal to the room process
      # Get the actual PID from the registry
      [{pid, _}] = Registry.lookup(Jido.Chat.Registry, "room:#{room_id}")
      send(pid, {:signal, signal})

      # Allow some time for the message to be processed
      :timer.sleep(100)

      # Check that the message was added
      {:ok, messages} = Room.get_messages(room_id)
      assert Enum.any?(messages, fn msg -> msg.content == "Hello via signal!" end)
    end

    test "ignores signals for other rooms", %{room_id: room_id, human: human} do
      :ok = Room.add_participant(room_id, human)

      # Create a message signal for a different room
      timestamp = DateTime.utc_now()

      {:ok, message} =
        Message.new(%{
          type: "chat.message",
          room_id: "different_room_id",
          sender: human.id,
          content: "Hello to another room!",
          timestamp: timestamp
        })

      signal = Message.to_signal(message)

      # Send the signal to the room process
      # Get the actual PID from the registry
      [{pid, _}] = Registry.lookup(Jido.Chat.Registry, "room:#{room_id}")
      send(pid, {:signal, signal})

      # Allow some time for the message to be processed
      :timer.sleep(100)

      # Check that the message was not added
      {:ok, messages} = Room.get_messages(room_id)
      refute Enum.any?(messages, fn msg -> msg.content == "Hello to another room!" end)
    end
  end

  describe "Jido.AI.Promptable implementation" do
    test "to_prompt/1 formats room information correctly", %{
      room_id: room_id,
      room_pid: room_pid,
      human: human,
      agent: agent
    } do
      # Add participants to the room
      :ok = Room.add_participant(room_id, human)
      :ok = Room.add_participant(room_id, agent)

      # Get the room state directly from the PID we already have from setup
      state = :sys.get_state(room_pid)

      # Test the to_prompt implementation
      prompt = Jido.AI.Promptable.to_prompt(state)

      # Verify the prompt format
      assert prompt =~ "Room: Test Room (ID: #{room_id})"
      assert prompt =~ "Participants:"
      assert prompt =~ "- Human User (human)"
      assert prompt =~ "- Agent User (agent)"
    end
  end
end
