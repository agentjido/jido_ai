defmodule Jido.AI.Runner.ChainOfThought.Backtracking.StateManager do
  @moduledoc """
  Manages reasoning state snapshots and history for backtracking.

  Provides:
  - State snapshot system capturing decision points
  - State stack with push/pop operations for branching
  - State comparison utilities identifying differences
  - State persistence for long-running sessions
  """

  require Logger

  @type state_snapshot :: %{
          id: String.t(),
          timestamp: integer(),
          data: map(),
          metadata: map()
        }

  @type state_stack :: list(state_snapshot())

  @doc """
  Captures current state as a snapshot.

  ## Parameters

  - `state` - Current state to capture
  - `opts` - Options:
    - `:metadata` - Additional metadata to store

  ## Returns

  State snapshot map

  ## Examples

      snapshot = StateManager.capture_snapshot(current_state)
      # => %{id: "snap_123", timestamp: ..., data: state, metadata: %{}}
  """
  @spec capture_snapshot(map(), keyword()) :: state_snapshot()
  def capture_snapshot(state, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    %{
      id: generate_id(),
      timestamp: System.system_time(:millisecond),
      data: state,
      metadata: metadata
    }
  end

  @doc """
  Restores state from snapshot.

  ## Parameters

  - `snapshot` - Snapshot to restore

  ## Returns

  Restored state map
  """
  @spec restore_snapshot(state_snapshot()) :: map()
  def restore_snapshot(%{data: data}) do
    Logger.debug("Restoring state from snapshot")
    data
  end

  @doc """
  Creates new state stack.

  ## Returns

  Empty state stack
  """
  @spec init_stack() :: state_stack()
  def init_stack, do: []

  @doc """
  Pushes state snapshot onto stack.

  ## Parameters

  - `stack` - Current state stack
  - `snapshot` - Snapshot to push

  ## Returns

  Updated state stack
  """
  @spec push(state_stack(), state_snapshot()) :: state_stack()
  def push(stack, snapshot) do
    [snapshot | stack]
  end

  @doc """
  Pops state snapshot from stack.

  ## Parameters

  - `stack` - Current state stack

  ## Returns

  - `{:ok, snapshot, remaining_stack}` - Snapshot popped successfully
  - `{:error, :empty_stack}` - Stack is empty
  """
  @spec pop(state_stack()) :: {:ok, state_snapshot(), state_stack()} | {:error, :empty_stack}
  def pop([]), do: {:error, :empty_stack}
  def pop([snapshot | rest]), do: {:ok, snapshot, rest}

  @doc """
  Peeks at top of stack without removing.

  ## Parameters

  - `stack` - Current state stack

  ## Returns

  - `{:ok, snapshot}` - Top snapshot
  - `{:error, :empty_stack}` - Stack is empty
  """
  @spec peek(state_stack()) :: {:ok, state_snapshot()} | {:error, :empty_stack}
  def peek([]), do: {:error, :empty_stack}
  def peek([snapshot | _rest]), do: {:ok, snapshot}

  @doc """
  Gets stack size.

  ## Parameters

  - `stack` - State stack

  ## Returns

  Number of snapshots in stack
  """
  @spec stack_size(state_stack()) :: non_neg_integer()
  def stack_size(stack), do: length(stack)

  @doc """
  Compares two state snapshots and identifies differences.

  ## Parameters

  - `snapshot1` - First snapshot
  - `snapshot2` - Second snapshot

  ## Returns

  Map containing differences:
  - `:added` - Keys added in snapshot2
  - `:removed` - Keys removed in snapshot2
  - `:changed` - Keys with different values
  """
  @spec compare_snapshots(state_snapshot(), state_snapshot()) :: map()
  def compare_snapshots(%{data: data1}, %{data: data2}) do
    keys1 = Map.keys(data1) |> MapSet.new()
    keys2 = Map.keys(data2) |> MapSet.new()

    added = MapSet.difference(keys2, keys1) |> MapSet.to_list()
    removed = MapSet.difference(keys1, keys2) |> MapSet.to_list()

    common_keys = MapSet.intersection(keys1, keys2)

    changed =
      common_keys
      |> Enum.filter(fn key -> Map.get(data1, key) != Map.get(data2, key) end)
      |> Enum.map(fn key ->
        {key, %{old: Map.get(data1, key), new: Map.get(data2, key)}}
      end)
      |> Map.new()

    %{
      added: added,
      removed: removed,
      changed: changed
    }
  end

  @doc """
  Compares current state with snapshot.

  ## Parameters

  - `current_state` - Current state map
  - `snapshot` - Snapshot to compare against

  ## Returns

  Differences map
  """
  @spec compare_with_snapshot(map(), state_snapshot()) :: map()
  def compare_with_snapshot(current_state, snapshot) do
    current_snapshot = capture_snapshot(current_state)
    compare_snapshots(current_snapshot, snapshot)
  end

  @doc """
  Persists state stack to storage.

  ## Parameters

  - `stack` - State stack to persist
  - `key` - Storage key

  ## Returns

  - `:ok` - Successfully persisted
  - `{:error, reason}` - Persistence failed
  """
  @spec persist_stack(state_stack(), String.t()) :: :ok | {:error, term()}
  def persist_stack(stack, key) do
    :persistent_term.put({__MODULE__, :stack, key}, stack)
    Logger.debug("Persisted state stack with key: #{key}")
    :ok
  rescue
    error -> {:error, error}
  end

  @doc """
  Loads persisted state stack from storage.

  ## Parameters

  - `key` - Storage key

  ## Returns

  - `{:ok, stack}` - Stack loaded successfully
  - `{:error, :not_found}` - No stack found for key
  """
  @spec load_stack(String.t()) :: {:ok, state_stack()} | {:error, :not_found}
  def load_stack(key) do
    case :persistent_term.get({__MODULE__, :stack, key}, nil) do
      nil ->
        {:error, :not_found}

      stack ->
        Logger.debug("Loaded state stack with key: #{key}")
        {:ok, stack}
    end
  end

  @doc """
  Deletes persisted state stack.

  ## Parameters

  - `key` - Storage key

  ## Returns

  `:ok`
  """
  @spec delete_stack(String.t()) :: :ok
  def delete_stack(key) do
    :persistent_term.erase({__MODULE__, :stack, key})
    Logger.debug("Deleted state stack with key: #{key}")
    :ok
  end

  @doc """
  Creates state diff between current and previous state.

  ## Parameters

  - `current_state` - Current state
  - `previous_state` - Previous state

  ## Returns

  Diff map
  """
  @spec create_diff(map(), map()) :: map()
  def create_diff(current_state, previous_state) do
    current_snapshot = capture_snapshot(current_state)
    previous_snapshot = capture_snapshot(previous_state)
    compare_snapshots(previous_snapshot, current_snapshot)
  end

  @doc """
  Applies diff to state.

  ## Parameters

  - `state` - Base state
  - `diff` - Diff to apply

  ## Returns

  Updated state
  """
  @spec apply_diff(map(), map()) :: map()
  def apply_diff(state, %{added: added, removed: removed, changed: changed}) do
    # Add new keys
    state = Enum.reduce(added, state, fn key, acc -> Map.put(acc, key, nil) end)

    # Remove keys
    state = Enum.reduce(removed, state, fn key, acc -> Map.delete(acc, key) end)

    # Update changed keys
    Enum.reduce(changed, state, fn {key, %{new: new_value}}, acc ->
      Map.put(acc, key, new_value)
    end)
  end

  @doc """
  Merges two state snapshots, with second snapshot taking precedence.

  ## Parameters

  - `snapshot1` - First snapshot
  - `snapshot2` - Second snapshot

  ## Returns

  Merged snapshot
  """
  @spec merge_snapshots(state_snapshot(), state_snapshot()) :: state_snapshot()
  def merge_snapshots(%{data: data1} = snap1, %{data: data2}) do
    merged_data = Map.merge(data1, data2)

    %{
      snap1
      | data: merged_data,
        timestamp: System.system_time(:millisecond)
    }
  end

  # Private functions

  defp generate_id do
    "snap_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end
