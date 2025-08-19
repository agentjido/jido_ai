defmodule Jido.Chat.Room.Strategy.RoundRobin do
  @moduledoc """
  A strategy that enforces a round-robin turn order for agent participants.

  In this strategy:
  - Human participants can send messages at any time
  - Agent participants must wait for their turn
  - When a human sends a message, the first agent gets a turn
  - After an agent sends a message, the turn passes to the next agent
  - If an agent doesn't respond within the timeout period, the turn passes to the next agent
  """

  @behaviour Jido.Chat.Room.Strategy

  alias Jido.Chat.Room.Strategy

  # 30 seconds
  @default_turn_timeout 30_000

  @impl true
  def init(opts) do
    # Extract options
    room_id = opts.room_id
    participants = opts.participants || %{}
    turn_timeout = Map.get(opts, :turn_timeout, @default_turn_timeout)

    # Initialize state
    state = %{
      room_id: room_id,
      participants: participants,
      turn_timeout: turn_timeout,
      current_turn: nil,
      agent_order: [],
      timer_ref: nil
    }

    # Set up the initial agent order
    state = update_agent_order(state)

    {:ok, state}
  end

  @impl true
  def handle_participant_added(state, participant) do
    # Add participant to the state
    updated_participants = Map.put(state.participants, participant.id, participant)
    state = %{state | participants: updated_participants}

    # Update the agent order if this is an agent
    state = update_agent_order(state)

    {:ok, state}
  end

  @impl true
  def handle_participant_removed(state, participant_id) do
    # Remove participant from the state
    updated_participants = Map.delete(state.participants, participant_id)
    state = %{state | participants: updated_participants}

    # Update the agent order
    state = update_agent_order(state)

    # If the current turn belongs to the removed participant, advance to the next turn
    state =
      if state.current_turn == participant_id do
        {state, _} = do_advance_turn(state, :participant_left)
        state
      else
        state
      end

    {:ok, state}
  end

  @impl true
  def is_message_allowed(state, message) do
    # Get the participant from the sender
    participant_id = get_participant_id_from_sender(state, message.sender)

    # Check if the participant exists
    case Map.get(state.participants, participant_id) do
      nil ->
        # Unknown participant, don't allow the message
        {:ok, false, state, []}

      participant ->
        case participant.type do
          :human ->
            # Humans can send messages at any time
            # Cancel any existing timer
            state = cancel_timer(state)

            # After a human message, it's the first agent's turn
            {state, notifications} = start_agent_round(state)

            # Allow the message
            {:ok, true, state, notifications}

          :agent ->
            # Agents can only send messages during their turn
            if state.current_turn == participant_id do
              # It's this agent's turn, allow the message
              # Cancel the turn timer
              state = cancel_timer(state)

              # Advance to the next agent's turn
              {state, notifications} = do_advance_turn(state, :message_processed)

              # Allow the message
              {:ok, true, state, notifications}
            else
              # It's not this agent's turn, don't allow the message
              {:ok, false, state, []}
            end

          _ ->
            # Unknown participant type, don't allow the message
            {:ok, false, state, []}
        end
    end
  end

  @impl true
  def advance_turn(state, reason) do
    {state, notifications} = do_advance_turn(state, reason)
    {:ok, state, notifications}
  end

  # Private helper functions

  # Update the agent order based on the current participants
  defp update_agent_order(state) do
    # Get all agent participants
    agents =
      state.participants
      |> Enum.filter(fn {_id, participant} -> participant.type == :agent end)
      |> Enum.map(fn {id, _participant} -> id end)
      |> Enum.sort_by(fn id ->
        # Sort by the numeric suffix if it exists
        case Regex.run(~r/user_agent(\d+)/, id) do
          [_, num] -> String.to_integer(num)
          # Default high value for non-matching IDs
          _ -> 999
        end
      end)

    %{state | agent_order: agents}
  end

  # Start a new round of agent turns
  defp start_agent_round(state) do
    case state.agent_order do
      [] ->
        # No agents, no turns to assign
        {%{state | current_turn: nil}, []}

      [first_agent | _] ->
        # Assign turn to the first agent
        do_set_turn(state, first_agent)
    end
  end

  # Advance to the next agent's turn
  defp do_advance_turn(state, _reason) do
    case state.agent_order do
      [] ->
        # No agents, no turns to assign
        {%{state | current_turn: nil}, []}

      agents ->
        current_index = Enum.find_index(agents, fn id -> id == state.current_turn end)

        next_index =
          case current_index do
            # Start with the first agent
            nil -> 0
            # Move to the next agent, wrapping around
            i -> rem(i + 1, length(agents))
          end

        next_agent = Enum.at(agents, next_index)
        do_set_turn(state, next_agent)
    end
  end

  # Set the turn to a specific agent and create notifications
  defp do_set_turn(state, agent_id) do
    # Cancel any existing timer
    state = cancel_timer(state)

    # Set the current turn
    state = %{state | current_turn: agent_id}

    # Create a turn notification
    {:ok, notification} = Strategy.create_turn_notification(state.room_id, agent_id)

    # Start a timer for this turn
    timer_ref = Process.send_after(self(), {:turn_timeout, agent_id}, state.turn_timeout)
    state = %{state | timer_ref: timer_ref}

    {state, [notification]}
  end

  # Cancel the current turn timer if it exists
  defp cancel_timer(state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
      %{state | timer_ref: nil}
    else
      state
    end
  end

  # Get the participant ID from a sender name
  defp get_participant_id_from_sender(state, sender) do
    # First try to find a participant with this exact ID
    case Map.get(state.participants, sender) do
      nil ->
        # If not found, look for a participant with this display name
        participant = Enum.find(state.participants, fn {_id, p} -> p.display_name == sender end)

        case participant do
          {id, _} -> id
          # Default to the sender if no match found
          _ -> sender
        end

      _ ->
        sender
    end
  end
end
