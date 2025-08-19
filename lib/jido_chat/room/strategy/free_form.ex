defmodule Jido.Chat.Room.Strategy.FreeForm do
  @moduledoc """
  A strategy that allows all participants to send messages at any time.

  This is the default strategy for chat rooms, where there are no turn-based
  restrictions on who can send messages.
  """

  @behaviour Jido.Chat.Room.Strategy

  @impl true
  def init(opts) do
    state = %{
      room_id: opts.room_id,
      participants: opts.participants || %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_participant_added(state, participant) do
    updated_participants = Map.put(state.participants, participant.id, participant)

    {:ok, %{state | participants: updated_participants}}
  end

  @impl true
  def handle_participant_removed(state, participant_id) do
    updated_participants = Map.delete(state.participants, participant_id)

    {:ok, %{state | participants: updated_participants}}
  end

  @impl true
  def is_message_allowed(state, message) do
    # In free form strategy, all messages are allowed
    require Logger

    Logger.debug(
      "FreeForm strategy allowing message: #{inspect(message.type)} from #{message.sender} in room #{state.room_id}"
    )

    {:ok, true, state}
  end

  @impl true
  def advance_turn(state, _reason) do
    # In free form strategy, there's no concept of turns
    {:ok, state, []}
  end
end
