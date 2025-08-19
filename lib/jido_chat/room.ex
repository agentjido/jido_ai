defmodule Jido.Chat.Room do
  @moduledoc """
  Represents a chat room in the Jido Chat system.

  A room is a GenServer process that:
  - Maintains a list of participants
  - Stores messages
  - Handles message delivery
  - Manages turn-based messaging strategies
  """

  use GenServer
  require Logger

  alias Jido.Chat.Message
  alias Jido.Chat.Room.Strategy

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          participants: map(),
          messages: list(),
          bus: pid(),
          subscription_id: String.t() | nil,
          strategy_module: module(),
          strategy_state: map()
        }

  defstruct [
    :id,
    :name,
    :bus,
    :subscription_id,
    :strategy_module,
    :strategy_state,
    participants: %{},
    messages: []
  ]

  # Client API

  @doc """
  Starts a new room process.

  ## Parameters

  - `opts` - A map of options:
    - `:id` - The ID of the room (required)
    - `:name` - The name of the room (required)
    - `:bus` - The Jido.Signal.Bus process (required)
    - `:strategy` - The strategy module to use (optional, defaults to Strategy.FreeForm)
    - `:turn_timeout` - The timeout for a participant's turn in milliseconds (optional)

  ## Returns

  - `{:ok, pid}` - The PID of the room process
  - `{:error, reason}` - If there was an error starting the room
  """
  def start_link(opts) when is_list(opts) do
    id = Keyword.get(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(id))
  end

  @doc """
  Adds a participant to the room.

  ## Parameters

  - `room_id` - The ID of the room
  - `participant` - The participant to add

  ## Returns

  - `:ok` - If the participant was added successfully
  - `{:error, reason}` - If there was an error adding the participant
  """
  def add_participant(room_id, participant) do
    GenServer.call(via_tuple(room_id), {:add_participant, participant})
  end

  @doc """
  Removes a participant from the room.

  ## Parameters

  - `room_id` - The ID of the room
  - `participant_id` - The ID of the participant to remove

  ## Returns

  - `:ok` - If the participant was removed successfully
  - `{:error, reason}` - If there was an error removing the participant
  """
  def remove_participant(room_id, participant_id) do
    GenServer.call(via_tuple(room_id), {:remove_participant, participant_id})
  end

  @doc """
  Gets the participants in the room.

  ## Parameters

  - `room_id` - The ID of the room

  ## Returns

  - `{:ok, participants}` - A map of participant IDs to participants
  - `{:error, reason}` - If there was an error getting the participants
  """
  def get_participants(room_id) do
    GenServer.call(via_tuple(room_id), :get_participants)
  end

  @doc """
  Gets the messages in the room.

  ## Parameters

  - `room_id` - The ID of the room

  ## Returns

  - `{:ok, messages}` - A list of messages in the room
  - `{:error, reason}` - If there was an error getting the messages
  """
  def get_messages(room_id) do
    GenServer.call(via_tuple(room_id), :get_messages)
  end

  # Server callbacks

  @impl true
  def init(opts) when is_list(opts) do
    # Extract options
    id = Keyword.get(opts, :id)
    name = Keyword.get(opts, :name, id)
    bus = Keyword.get(opts, :bus)
    strategy = Keyword.get(opts, :strategy, :free_form)

    # Get the strategy module
    strategy_module = Strategy.get_strategy(strategy)

    # Create the initial state
    state = %__MODULE__{
      id: id,
      name: name,
      bus: bus,
      strategy_module: strategy_module
    }

    # Subscribe to chat messages
    {:ok, sub_id} = Jido.Signal.Bus.subscribe(bus, "chat.*")
    state = %{state | subscription_id: sub_id}

    # Initialize the strategy
    strategy_opts = %{
      room_id: id,
      participants: %{},
      turn_timeout: Keyword.get(opts, :turn_timeout, 30_000)
    }

    {:ok, strategy_state} = strategy_module.init(strategy_opts)
    state = %{state | strategy_state: strategy_state}

    # Create a room created message
    {:ok, created_message} =
      Message.new(%{
        type: "chat.room.created",
        room_id: id,
        sender: "system",
        content: "Room created: #{name}",
        timestamp: DateTime.utc_now()
      })

    # Add the message to the room
    state = add_message_to_state(state, created_message)

    {:ok, state}
  end

  @impl true
  def handle_call({:add_participant, participant}, _from, state) do
    # Check if the participant is already in the room
    case Map.has_key?(state.participants, participant.id) do
      true ->
        # Participant already exists
        {:reply, :ok, state}

      false ->
        # Add the participant to the room
        participants = Map.put(state.participants, participant.id, participant)
        state = %{state | participants: participants}

        # Notify the strategy
        {:ok, strategy_state} =
          state.strategy_module.handle_participant_added(state.strategy_state, participant)

        state = %{state | strategy_state: strategy_state}

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:remove_participant, participant_id}, _from, state) do
    # Check if the participant is in the room
    case Map.has_key?(state.participants, participant_id) do
      false ->
        # Participant doesn't exist
        {:reply, {:error, :not_found}, state}

      true ->
        # Remove the participant from the room
        participants = Map.delete(state.participants, participant_id)
        state = %{state | participants: participants}

        # Notify the strategy
        {:ok, strategy_state} =
          state.strategy_module.handle_participant_removed(state.strategy_state, participant_id)

        state = %{state | strategy_state: strategy_state}

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call(:get_participants, _from, state) do
    {:reply, {:ok, state.participants}, state}
  end

  @impl true
  def handle_call(:get_messages, _from, state) do
    {:reply, {:ok, state.messages}, state}
  end

  @impl true
  def handle_info({:turn_timeout, participant_id}, state) do
    # Check if this is still the current turn
    if state.strategy_state.current_turn == participant_id do
      # Advance to the next turn due to timeout
      {:ok, new_strategy_state, notifications} =
        state.strategy_module.advance_turn(state.strategy_state, :timeout)

      state = %{state | strategy_state: new_strategy_state}

      # Process any turn notifications
      updated_state = process_turn_notifications(state, notifications)

      {:noreply, updated_state}
    else
      # This is an old timeout, ignore it
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:signal, signal}, state) do
    # Log incoming signal
    Logger.debug("Room #{state.id} received signal: #{inspect(signal.type)}")

    # Convert the signal to a message
    {:ok, message} = Message.from_signal(signal)

    # Parse mentions if this is a chat message
    message =
      if message.type == Message.type(:message) do
        Message.parse_message(message)
      else
        message
      end

    # Only process messages intended for this room
    if message.room_id == state.id do
      Logger.debug(
        "Processing message for room #{state.id}: #{inspect(message.type)} from #{message.sender}"
      )

      # Check if this message is allowed by the strategy
      {:ok, allowed, new_strategy_state, notifications} = check_message_allowed(state, message)
      state = %{state | strategy_state: new_strategy_state}

      # Process any turn notifications
      updated_state = process_turn_notifications(state, notifications)

      if allowed do
        # Add the message to the room's messages
        Logger.debug(
          "Adding allowed message to room #{state.id}: #{inspect(message.type)} from #{message.sender}"
        )

        updated_state = add_message_to_state(updated_state, message)
        {:noreply, updated_state}
      else
        # Message not allowed, ignore it
        Logger.debug(
          "Ignoring disallowed message in room #{state.id}: #{inspect(message.type)} from #{message.sender}"
        )

        {:noreply, updated_state}
      end
    else
      # Message is for a different room, ignore it
      Logger.debug(
        "Ignoring message for different room: #{message.room_id} (current room: #{state.id})"
      )

      {:noreply, state}
    end
  end

  @impl true
  def terminate(_reason, state) do
    # Unsubscribe from the bus
    if state.subscription_id do
      Jido.Signal.Bus.unsubscribe(state.bus, state.subscription_id)
    end

    :ok
  end

  # Private helper functions

  defp via_tuple(room_id) do
    {:via, Registry, {Jido.Chat.Registry, "room:#{room_id}"}}
  end

  defp add_message_to_state(state, message) do
    # Add the message to the list of messages
    messages = [message | state.messages]
    %{state | messages: messages}
  end

  defp process_turn_notifications(state, notifications) do
    # Log notifications being processed
    if length(notifications) > 0 do
      Logger.debug("Processing #{length(notifications)} turn notifications in room #{state.id}")
    end

    # Publish each notification as a signal
    updated_state =
      Enum.reduce(notifications, state, fn notification, acc_state ->
        signal = Message.to_signal(notification)

        Logger.debug(
          "Publishing notification signal: #{inspect(notification.type)} from #{notification.sender}"
        )

        {:ok, _} = Jido.Signal.Bus.publish(state.bus, [signal])

        # Also add the notification to the room's messages
        add_message_to_state(acc_state, notification)
      end)

    updated_state
  end

  defp check_message_allowed(state, message) do
    # Log message being checked
    Logger.debug(
      "Checking if message is allowed: #{inspect(message.type)} from #{message.sender} in room #{state.id}"
    )

    # Check if the message is allowed by the strategy
    case state.strategy_module.is_message_allowed(state.strategy_state, message) do
      {:ok, allowed, new_strategy_state, notifications} ->
        # Strategy already provided notifications
        Logger.debug(
          "Strategy returned allowed=#{allowed} with #{length(notifications)} notifications"
        )

        {:ok, allowed, new_strategy_state, notifications}

      {:ok, allowed, new_strategy_state} ->
        Logger.debug("Strategy returned allowed=#{allowed} without notifications")
        # If the message is allowed and it's a regular message, we might need to advance the turn
        {notifications, updated_strategy_state} =
          if allowed && message.type == Jido.Chat.Message.type(:message) do
            # Advance the turn if needed
            {:ok, updated_strategy_state, turn_notifications} =
              state.strategy_module.advance_turn(new_strategy_state, :message_processed)

            Logger.debug(
              "Advanced turn after message, got #{length(turn_notifications)} notifications"
            )

            {turn_notifications, updated_strategy_state}
          else
            {[], new_strategy_state}
          end

        {:ok, allowed, updated_strategy_state, notifications}
    end
  end
end

defimpl Jido.AI.Promptable, for: Jido.Chat.Room do
  @doc """
  Converts a chat room to a prompt string suitable for an LLM.

  The format is:
  ```
  Room: [room_name] (ID: [room_id])
  Participants:
  - [participant_display_name] ([human/agent])
  - [participant_display_name] ([human/agent])
  ...
  ```
  """
  def to_prompt(room) do
    participants_str =
      room.participants
      |> Map.values()
      |> Enum.map_join("\n", fn participant ->
        type_str = if participant.type == :human, do: "human", else: "agent"
        "- #{Jido.Chat.Participant.display_name(participant)} (#{type_str})"
      end)

    """
    Room: #{room.name} (ID: #{room.id})
    Participants:
    #{participants_str}
    """
  end
end
