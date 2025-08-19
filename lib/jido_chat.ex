defmodule Jido.Chat do
  @moduledoc """
  Jido.Chat is a simple chat system built on a signal bus architecture.

  This module provides a high-level API for interacting with the chat system.
  It uses the Jido.Signal.Bus for message delivery and routing.
  """

  alias Jido.Chat.{Room, Message}

  @doc """
  Creates a new chat room with the given name.

  Returns `{:ok, room_id}` or `{:error, reason}`.
  """
  def create_room(name, opts \\ %{}) do
    # Merge default options with provided options
    opts = Map.merge(%{name: name}, opts)
    Room.Supervisor.start_room(opts)
  end

  @doc """
  Sends a message to a specific room.

  Returns `:ok` or `{:error, reason}`.
  """
  def send_message(room_id, sender, content, opts \\ %{}) do
    # Get the bus to use (default to Jido.Chat.Bus)
    bus = Map.get(opts, :bus, Jido.Chat.Bus)

    # Create and publish the message signal
    signal = Message.chat_message(room_id, sender, content, opts)

    case Jido.Signal.Bus.publish(bus, [signal]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Joins a chat room.

  Returns `:ok` or `{:error, reason}`.
  """
  def join_room(room_id, username, opts \\ %{}) do
    # Get the bus to use (default to Jido.Chat.Bus)
    bus = Map.get(opts, :bus, Jido.Chat.Bus)

    # Create and publish the join signal
    signal = Message.join_room(room_id, username, opts)

    case Jido.Signal.Bus.publish(bus, [signal]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Leaves a chat room.

  Returns `:ok` or `{:error, reason}`.
  """
  def leave_room(room_id, username, opts \\ %{}) do
    # Get the bus to use (default to Jido.Chat.Bus)
    bus = Map.get(opts, :bus, Jido.Chat.Bus)

    # Create and publish the leave signal
    signal = Message.leave_room(room_id, username, opts)

    case Jido.Signal.Bus.publish(bus, [signal]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Gets all messages from a room.

  Returns `{:ok, messages}` or `{:error, reason}`.
  """
  def get_messages(room_id) do
    Room.get_messages(room_id)
  end

  @doc """
  Lists all active rooms.

  Returns a list of `{room_id, room_name}` tuples.
  """
  def list_rooms do
    Room.Supervisor.list_rooms()
  end
end
