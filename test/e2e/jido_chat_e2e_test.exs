defmodule Jido.ChatE2ETest do
  use ExUnit.Case, async: false
  @moduletag :capture_log

  @moduledoc """
  End-to-end tests for the Jido.Chat module.

  This test demonstrates the full chat room lifecycle, including:
  - Creating rooms
  - Adding participants
  - Joining rooms
  - Sending messages with @mentions
  - Processing mentions
  - Multiple room interactions
  - Leaving rooms
  - Turn-based messaging strategies
  """

  alias Jido.Chat.Message
  alias Jido.Chat.Participant
  alias Jido.Chat.Room.Strategy

  # Setup test environment
  setup do
    # Start the registry for test subscribers
    Registry.start_link(keys: :unique, name: Jido.Chat.Registry)

    # Start the Jido.Signal.Bus for testing if it's not already started
    bus_pid =
      case Process.whereis(Jido.Signal.Bus) do
        nil ->
          {:ok, pid} = Jido.Signal.Bus.start_link(name: Jido.Signal.Bus)
          pid

        pid ->
          pid
      end

    # Create test users
    alice = "Alice"
    bob = "Bob"
    charlie = "Charlie"
    dave = "Dave"
    eve = "Eve"

    # Create a test process to receive messages
    test_pid = self()

    # Subscribe to chat messages directly using the bus
    subscription_id = "chat_test_#{:erlang.unique_integer([:positive])}"

    {:ok, _sub_pid} =
      Jido.Signal.Bus.PersistentSubscription.start_link(
        id: subscription_id,
        bus_pid: bus_pid,
        path: "chat.*",
        client_pid: test_pid,
        start_from: :current
      )

    on_exit(fn ->
      # Unsubscribe when the test is done
      case Process.whereis(:"subscription_#{subscription_id}") do
        nil -> :ok
        pid -> Jido.Signal.Bus.PersistentSubscription.unsubscribe(pid)
      end
    end)

    %{users: [alice, bob, charlie, dave, eve], bus_pid: bus_pid}
  end

  @tag :e2e
  test "comprehensive chat system demonstration", %{
    users: [alice, bob, charlie, dave, eve],
    bus_pid: bus_pid
  } do
    IO.puts("\n=== Comprehensive Chat System Demonstration ===")

    # Define rooms
    rooms = [
      %{id: "room_general", name: "General Chat"},
      %{id: "room_tech", name: "Tech Talk"}
    ]

    # Start room processes
    Enum.each(rooms, fn room ->
      {:ok, _room_pid} = Jido.Chat.Room.start_link(id: room.id, name: room.name, bus: bus_pid)
      IO.puts("Created room: #{room.name} (#{room.id})")
    end)

    # Create participants
    {:ok, alice_participant} = Participant.new("user_alice", display_name: alice)
    {:ok, bob_participant} = Participant.new("user_bob", display_name: bob)
    {:ok, charlie_participant} = Participant.new("user_charlie", display_name: charlie)
    {:ok, dave_participant} = Participant.new("user_dave", display_name: dave)
    {:ok, eve_participant} = Participant.new("user_eve", display_name: eve)

    # Define room memberships
    memberships = [
      {alice_participant, ["room_general", "room_tech"]},
      {bob_participant, ["room_general", "room_tech"]},
      {charlie_participant, ["room_general"]},
      {dave_participant, ["room_tech"]},
      {eve_participant, ["room_general", "room_tech"]}
    ]

    # Add participants to rooms
    Enum.each(memberships, fn {participant, room_ids} ->
      Enum.each(room_ids, fn room_id ->
        :ok = Jido.Chat.Room.add_participant(room_id, participant)
        room_name = Enum.find(rooms, fn r -> r.id == room_id end).name
        IO.puts("Added #{participant.display_name} to #{room_name}")
      end)
    end)

    # Verify participants were added correctly
    Enum.each(rooms, fn room ->
      {:ok, participants} = Jido.Chat.Room.get_participants(room.id)

      expected_count =
        Enum.count(memberships, fn {_, room_ids} -> Enum.member?(room_ids, room.id) end)

      assert map_size(participants) == expected_count,
             "Expected #{expected_count} participants in #{room.name}, got #{map_size(participants)}"

      IO.puts("✓ Verified #{room.name} has #{map_size(participants)} participants")
    end)

    # Helper function to create and publish a signal
    publish_message = fn message ->
      signal = Message.to_signal(message)
      {:ok, _} = Jido.Signal.Bus.publish(bus_pid, [signal])
    end

    # Helper function to create a message
    create_message = fn type, room_id, sender, content ->
      {:ok, message} =
        Message.new(%{
          type: type,
          room_id: room_id,
          sender: sender,
          content: content,
          timestamp: DateTime.utc_now()
        })

      message
    end

    # PART 1: Basic room joining and messaging
    IO.puts("\n--- Part 1: Basic Room Joining and Messaging ---")

    # Users join rooms
    Enum.each(memberships, fn {participant, room_ids} ->
      Enum.each(room_ids, fn room_id ->
        join_message =
          create_message.(
            Message.type(:join),
            room_id,
            participant.display_name,
            "#{participant.display_name} has joined the room"
          )

        publish_message.(join_message)

        room_name = Enum.find(rooms, fn r -> r.id == room_id end).name
        IO.puts("#{participant.display_name} joined #{room_name}")
      end)
    end)

    # Basic messaging in General room
    general_id = "room_general"

    # Alice sends a message
    alice_msg =
      create_message.(Message.type(:message), general_id, alice, "Hello everyone in General!")

    publish_message.(alice_msg)
    IO.puts("[General] #{alice}: #{alice_msg.content}")

    # Bob responds
    bob_msg =
      create_message.(Message.type(:message), general_id, bob, "Hi Alice, nice to see you!")

    publish_message.(bob_msg)
    IO.puts("[General] #{bob}: #{bob_msg.content}")

    # Charlie joins the conversation
    charlie_msg =
      create_message.(Message.type(:message), general_id, charlie, "Hello Alice and Bob!")

    publish_message.(charlie_msg)
    IO.puts("[General] #{charlie}: #{charlie_msg.content}")

    # PART 2: Mentions functionality
    IO.puts("\n--- Part 2: Mentions Functionality ---")

    # Alice mentions Bob in General
    alice_mention_bob =
      create_message.(
        Message.type(:message),
        general_id,
        alice,
        "Hey @#{bob}, what do you think about the new features?"
      )

    publish_message.(alice_mention_bob)
    IO.puts("[General] #{alice}: #{alice_mention_bob.content}")

    # Bob mentions Alice and Charlie in General
    bob_mention_multiple =
      create_message.(
        Message.type(:message),
        general_id,
        bob,
        "I think they're great @#{alice}! @#{charlie}, have you tried them yet?"
      )

    publish_message.(bob_mention_multiple)
    IO.puts("[General] #{bob}: #{bob_mention_multiple.content}")

    # Eve mentions everyone in General
    eve_mention_all =
      create_message.(
        Message.type(:message),
        general_id,
        eve,
        "Hello @#{alice}, @#{bob}, and @#{charlie}! I'm new here."
      )

    publish_message.(eve_mention_all)
    IO.puts("[General] #{eve}: #{eve_mention_all.content}")

    # PART 3: Multi-room interactions
    IO.puts("\n--- Part 3: Multi-Room Interactions ---")

    tech_id = "room_tech"

    # Alice sends a message in Tech Talk
    alice_tech_msg =
      create_message.(Message.type(:message), tech_id, alice, "Welcome to the Tech Talk room!")

    publish_message.(alice_tech_msg)
    IO.puts("[Tech Talk] #{alice}: #{alice_tech_msg.content}")

    # Dave responds and mentions Alice
    dave_tech_msg =
      create_message.(
        Message.type(:message),
        tech_id,
        dave,
        "Thanks @#{alice} for creating this room!"
      )

    publish_message.(dave_tech_msg)
    IO.puts("[Tech Talk] #{dave}: #{dave_tech_msg.content}")

    # Bob mentions both Alice and Dave
    bob_tech_msg =
      create_message.(
        Message.type(:message),
        tech_id,
        bob,
        "Hey @#{alice} and @#{dave}, what tech topics should we discuss?"
      )

    publish_message.(bob_tech_msg)
    IO.puts("[Tech Talk] #{bob}: #{bob_tech_msg.content}")

    # PART 4: Room leaving
    IO.puts("\n--- Part 4: Room Leaving ---")

    # Charlie leaves General
    charlie_leave =
      create_message.(Message.type(:leave), general_id, charlie, "#{charlie} has left the room")

    publish_message.(charlie_leave)
    IO.puts("#{charlie} left General Chat")

    # Dave leaves Tech Talk
    dave_leave = create_message.(Message.type(:leave), tech_id, dave, "#{dave} has left the room")
    publish_message.(dave_leave)
    IO.puts("#{dave} left Tech Talk")

    # PART 5: Turn-based strategies demonstration
    IO.puts("\n--- Part 5: Turn-Based Strategies Demonstration ---")

    # Create a room with FreeForm strategy
    free_form_room_id = "room_free_form"
    free_form_room_name = "Free Form Chat"

    {:ok, _free_form_room_pid} =
      Jido.Chat.Room.start_link(
        id: free_form_room_id,
        name: free_form_room_name,
        bus: bus_pid,
        strategy: Strategy.FreeForm
      )

    IO.puts("Created room: #{free_form_room_name} (#{free_form_room_id}) with FreeForm strategy")

    # Create a room with RoundRobin strategy
    round_robin_room_id = "room_round_robin"
    round_robin_room_name = "Round Robin Chat"

    {:ok, _round_robin_room_pid} =
      Jido.Chat.Room.start_link(
        id: round_robin_room_id,
        name: round_robin_room_name,
        bus: bus_pid,
        strategy: Strategy.RoundRobin,
        # Short timeout for testing
        turn_timeout: 1000
      )

    IO.puts(
      "Created room: #{round_robin_room_name} (#{round_robin_room_id}) with RoundRobin strategy"
    )

    # Create human and agent participants
    {:ok, human_participant} = Participant.new("user_human", display_name: "Human", type: :human)

    {:ok, agent1_participant} =
      Participant.new("user_agent1", display_name: "Agent1", type: :agent)

    {:ok, agent2_participant} =
      Participant.new("user_agent2", display_name: "Agent2", type: :agent)

    {:ok, agent3_participant} =
      Participant.new("user_agent3", display_name: "Agent3", type: :agent)

    # Add participants to both rooms
    participants = [human_participant, agent1_participant, agent2_participant, agent3_participant]

    Enum.each(participants, fn participant ->
      # Add to FreeForm room
      :ok = Jido.Chat.Room.add_participant(free_form_room_id, participant)
      IO.puts("Added #{participant.display_name} to #{free_form_room_name}")

      # Add to RoundRobin room
      :ok = Jido.Chat.Room.add_participant(round_robin_room_id, participant)
      IO.puts("Added #{participant.display_name} to #{round_robin_room_name}")

      # Join messages
      join_message =
        create_message.(
          Message.type(:join),
          free_form_room_id,
          participant.display_name,
          "#{participant.display_name} has joined the room"
        )

      publish_message.(join_message)

      join_message =
        create_message.(
          Message.type(:join),
          round_robin_room_id,
          participant.display_name,
          "#{participant.display_name} has joined the room"
        )

      publish_message.(join_message)
    end)

    # Demonstrate FreeForm strategy (all participants can send messages anytime)
    IO.puts("\n--- FreeForm Strategy Demonstration ---")
    IO.puts("In FreeForm strategy, all participants can send messages at any time.")

    # Human sends a message
    human_msg =
      create_message.(
        Message.type(:message),
        free_form_room_id,
        "Human",
        "Hello everyone! This is a free-form chat room."
      )

    publish_message.(human_msg)
    IO.puts("[FreeForm] Human: #{human_msg.content}")

    # All agents can respond immediately in any order
    agent1_msg =
      create_message.(
        Message.type(:message),
        free_form_room_id,
        "Agent1",
        "Hello Human! I can respond immediately."
      )

    publish_message.(agent1_msg)
    IO.puts("[FreeForm] Agent1: #{agent1_msg.content}")

    agent3_msg =
      create_message.(
        Message.type(:message),
        free_form_room_id,
        "Agent3",
        "I can respond out of order too!"
      )

    publish_message.(agent3_msg)
    IO.puts("[FreeForm] Agent3: #{agent3_msg.content}")

    agent2_msg =
      create_message.(
        Message.type(:message),
        free_form_room_id,
        "Agent2",
        "And I can respond whenever I want."
      )

    publish_message.(agent2_msg)
    IO.puts("[FreeForm] Agent2: #{agent2_msg.content}")

    # Demonstrate RoundRobin strategy
    IO.puts("\n--- RoundRobin Strategy Demonstration ---")

    IO.puts(
      "In RoundRobin strategy, humans can send messages anytime, but agents must wait their turn."
    )

    # Clear any previous signals
    Process.sleep(100)
    flush_messages()

    # Human sends a message, which should trigger Agent1's turn
    human_msg =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Human",
        "Hello agents! This is a round-robin chat room."
      )

    publish_message.(human_msg)
    IO.puts("[RoundRobin] Human: #{human_msg.content}")

    # Wait for turn notification
    assert_receive {:signal,
                    %{type: "chat.room.turn", data: %{metadata: %{participant_id: "user_agent1"}}}},
                   1000

    IO.puts("[RoundRobin] System: It's Agent1's turn to speak")

    # Agent1 responds (allowed)
    agent1_msg =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Agent1",
        "Hello Human! I'm responding in my turn."
      )

    publish_message.(agent1_msg)
    IO.puts("[RoundRobin] Agent1: #{agent1_msg.content}")

    # Wait for turn notification for Agent2
    assert_receive {:signal,
                    %{type: "chat.room.turn", data: %{metadata: %{participant_id: "user_agent2"}}}},
                   1000

    IO.puts("[RoundRobin] System: It's Agent2's turn to speak")

    # Agent3 tries to respond out of turn (should be ignored)
    agent3_msg =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Agent3",
        "I'm trying to speak out of turn!"
      )

    publish_message.(agent3_msg)
    IO.puts("[RoundRobin] Agent3 tries to speak out of turn (should be ignored)")

    # Agent2 responds (allowed)
    agent2_msg =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Agent2",
        "Now it's my turn to respond."
      )

    publish_message.(agent2_msg)
    IO.puts("[RoundRobin] Agent2: #{agent2_msg.content}")

    # Wait for turn notification for Agent3
    assert_receive {:signal,
                    %{type: "chat.room.turn", data: %{metadata: %{participant_id: "user_agent3"}}}},
                   1000

    IO.puts("[RoundRobin] System: It's Agent3's turn to speak")

    # Agent3 responds (allowed)
    agent3_msg =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Agent3",
        "Finally, it's my turn!"
      )

    publish_message.(agent3_msg)
    IO.puts("[RoundRobin] Agent3: #{agent3_msg.content}")

    # Human can send a message at any time, which starts a new round
    human_msg2 =
      create_message.(
        Message.type(:message),
        round_robin_room_id,
        "Human",
        "Let me start another round of responses."
      )

    publish_message.(human_msg2)
    IO.puts("[RoundRobin] Human: #{human_msg2.content}")

    # Wait for turn notification for Agent1 again
    assert_receive {:signal,
                    %{type: "chat.room.turn", data: %{metadata: %{participant_id: "user_agent1"}}}},
                   1000

    IO.puts("[RoundRobin] System: It's Agent1's turn to speak again")

    # Demonstrate timeout behavior
    IO.puts("\n--- Turn Timeout Demonstration ---")
    IO.puts("If an agent doesn't respond in time, the turn moves to the next agent.")

    # Wait for timeout and turn notification for Agent2
    assert_receive {:signal,
                    %{type: "chat.room.turn", data: %{metadata: %{participant_id: "user_agent2"}}}},
                   2000

    IO.puts("[RoundRobin] System: Agent1 timed out, now it's Agent2's turn")

    # Give some time for messages to be processed
    Process.sleep(100)

    # PART 6: Verification
    IO.puts("\n--- Part 6: Verification ---")

    # Verify messages in FreeForm room
    {:ok, free_form_messages} = Jido.Chat.Room.get_messages(free_form_room_id)

    free_form_chat_messages =
      Enum.filter(free_form_messages, fn msg -> msg.type == Message.type(:message) end)

    # Verify message count
    assert length(free_form_chat_messages) == 4,
           "Expected 4 chat messages in FreeForm room, got #{length(free_form_chat_messages)}"

    IO.puts("✓ Verified FreeForm room has correct number of messages")

    # Verify messages in RoundRobin room
    {:ok, round_robin_messages} = Jido.Chat.Room.get_messages(round_robin_room_id)

    round_robin_chat_messages =
      Enum.filter(round_robin_messages, fn msg -> msg.type == Message.type(:message) end)

    # Verify message count (should only include allowed messages)
    # Human (2) + Agent1 (1) + Agent2 (1) + Agent3 (1) = 5
    assert length(round_robin_chat_messages) == 5,
           "Expected 5 chat messages in RoundRobin room, got #{length(round_robin_chat_messages)}"

    IO.puts("✓ Verified RoundRobin room has correct number of messages")

    # Verify turn notifications
    turn_notifications =
      Enum.filter(round_robin_messages, fn msg ->
        msg.type == Message.type(:turn_notification)
      end)

    assert length(turn_notifications) > 0,
           "Expected turn notifications in RoundRobin room"

    IO.puts("✓ Verified RoundRobin room has turn notifications")

    IO.puts("\n=== End of Comprehensive Demonstration ===")
  end

  # Helper function to flush all messages from the process mailbox
  defp flush_messages do
    receive do
      _ -> flush_messages()
    after
      0 -> :ok
    end
  end
end
