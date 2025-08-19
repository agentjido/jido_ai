defmodule Jido.Chat.Room.Supervisor do
  @moduledoc """
  Supervises chat room processes.
  """
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new room with the given options.

  Options:
  - name: The name of the room (required)
  - bus: The bus to use for this room (defaults to Jido.Chat.Bus)
  - id: The room ID (generated if not provided)

  Returns `{:ok, room_id}` or `{:error, reason}`.
  """
  def start_room(opts) when is_map(opts) do
    # Generate a room ID if one wasn't provided
    room_id = Map.get(opts, :id, generate_room_id())

    # Ensure the room has an ID
    opts = Map.put(opts, :id, room_id)

    case DynamicSupervisor.start_child(__MODULE__, {Jido.Chat.Room, opts}) do
      {:ok, _pid} -> {:ok, room_id}
      error -> error
    end
  end

  # For backward compatibility
  def start_room(name) when is_binary(name) do
    start_room(%{name: name})
  end

  @doc """
  Lists all active rooms.

  Returns a list of `{room_id, room_name}` tuples.
  """
  def list_rooms do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} ->
      GenServer.call(pid, :get_info)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp generate_room_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
