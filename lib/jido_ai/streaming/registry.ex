defmodule Jido.AI.Streaming.Registry do
  @moduledoc """
  In-memory stream lifecycle registry used by streaming actions.

  ## Lifecycle

  `Jido.AI.Streaming.Registry` supports two startup modes:

  1. **Explicit startup** via `start_link/1` under your supervisor tree.
  2. **Lazy startup** via `ensure_started/0`, which is called automatically by
     public API functions.

  This mirrors the lifecycle behavior of `Jido.AI.Skill.Registry` so both
  registries can be used without strict startup ordering.
  """

  @poll_interval_ms 25

  @type stream_id :: String.t()
  @type entry :: map()

  @doc """
  Starts the registry process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    opts = Keyword.put_new(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, opts)
  end

  @doc """
  Child spec for supervised startup.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Starts the registry unless it is already running.
  """
  @spec ensure_started() :: :ok | {:error, term()}
  def ensure_started do
    case Process.whereis(__MODULE__) do
      nil ->
        case start_link() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end

  @doc """
  Registers a new stream entry with defaults merged with `attrs`.
  """
  @spec register(stream_id(), map()) :: {:ok, entry()}
  def register(stream_id, attrs \\ %{}) when is_binary(stream_id) and is_map(attrs) do
    ensure_started!()
    now = now_ms()

    entry =
      %{
        stream_id: stream_id,
        status: :pending,
        model: nil,
        auto_process: true,
        buffered: false,
        token_count: 0,
        text: "",
        usage: %{input_tokens: 0, output_tokens: 0, total_tokens: 0},
        error: nil,
        started_at: now,
        updated_at: now
      }
      |> Map.merge(attrs)

    Agent.update(__MODULE__, &Map.put(&1, stream_id, entry))
    {:ok, entry}
  end

  @doc """
  Replaces an existing stream entry by `stream_id`.
  """
  @spec put(entry()) :: {:ok, entry()}
  def put(%{stream_id: stream_id} = entry) when is_binary(stream_id) do
    ensure_started!()
    Agent.update(__MODULE__, &Map.put(&1, stream_id, entry))
    {:ok, entry}
  end

  @doc """
  Fetches a stream entry by ID.
  """
  @spec get(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def get(stream_id) when is_binary(stream_id) do
    ensure_started!()

    case Agent.get(__MODULE__, &Map.get(&1, stream_id)) do
      nil -> {:error, :stream_not_found}
      entry -> {:ok, entry}
    end
  end

  @doc """
  Updates a stream entry atomically with the provided function.
  """
  @spec update(stream_id(), (entry() -> entry())) :: {:ok, entry()} | {:error, :stream_not_found}
  def update(stream_id, fun) when is_binary(stream_id) and is_function(fun, 1) do
    ensure_started!()

    Agent.get_and_update(__MODULE__, fn state ->
      case Map.fetch(state, stream_id) do
        {:ok, entry} ->
          updated = entry |> fun.() |> Map.put(:updated_at, now_ms())
          {{:ok, updated}, Map.put(state, stream_id, updated)}

        :error ->
          {{:error, :stream_not_found}, state}
      end
    end)
  end

  @doc """
  Appends a token to a stream, updating token count and optional buffer text.
  """
  @spec append_token(stream_id(), String.t()) :: {:ok, entry()} | {:error, :stream_not_found}
  def append_token(stream_id, token) when is_binary(stream_id) and is_binary(token) do
    update(stream_id, fn entry ->
      text =
        if Map.get(entry, :buffered, false) do
          Map.get(entry, :text, "") <> token
        else
          Map.get(entry, :text, "")
        end

      entry
      |> Map.put(:text, text)
      |> Map.put(:token_count, Map.get(entry, :token_count, 0) + 1)
    end)
  end

  @doc """
  Marks a stream as `:processing`.
  """
  @spec mark_processing(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_processing(stream_id) when is_binary(stream_id) do
    update(stream_id, &Map.put(&1, :status, :processing))
  end

  @doc """
  Marks a stream as `:streaming`.
  """
  @spec mark_streaming(stream_id()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_streaming(stream_id) when is_binary(stream_id) do
    update(stream_id, &Map.put(&1, :status, :streaming))
  end

  @doc """
  Marks a stream as `:completed`, merging in final attributes.
  """
  @spec mark_completed(stream_id(), map()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_completed(stream_id, attrs \\ %{}) when is_binary(stream_id) and is_map(attrs) do
    update(stream_id, fn entry ->
      attrs
      |> Map.put(:status, :completed)
      |> then(&Map.merge(entry, &1))
      |> Map.put(:error, nil)
    end)
  end

  @doc """
  Marks a stream as `:error` and stores the failure reason.
  """
  @spec mark_error(stream_id(), term()) :: {:ok, entry()} | {:error, :stream_not_found}
  def mark_error(stream_id, reason) when is_binary(stream_id) do
    update(stream_id, fn entry ->
      entry
      |> Map.put(:status, :error)
      |> Map.put(:error, reason)
    end)
  end

  @doc """
  Deletes a stream entry from the registry.
  """
  @spec delete(stream_id()) :: :ok
  def delete(stream_id) when is_binary(stream_id) do
    ensure_started!()
    Agent.update(__MODULE__, &Map.delete(&1, stream_id))
    :ok
  end

  @doc """
  Waits until a stream reaches a terminal state (`:completed` or `:error`).
  """
  @spec wait_for_terminal(stream_id(), non_neg_integer()) ::
          {:ok, entry()} | {:error, :stream_not_found | :timeout}
  def wait_for_terminal(stream_id, timeout_ms) when is_binary(stream_id) and is_integer(timeout_ms) do
    deadline = now_ms() + max(timeout_ms, 0)
    do_wait(stream_id, deadline)
  end

  defp do_wait(stream_id, deadline) do
    case get(stream_id) do
      {:ok, %{status: status} = entry} when status in [:completed, :error] ->
        {:ok, entry}

      {:ok, _entry} ->
        if now_ms() >= deadline do
          {:error, :timeout}
        else
          Process.sleep(@poll_interval_ms)
          do_wait(stream_id, deadline)
        end

      {:error, :stream_not_found} ->
        {:error, :stream_not_found}
    end
  end

  defp ensure_started! do
    case ensure_started() do
      :ok ->
        :ok

      {:error, reason} ->
        raise "Failed to start #{inspect(__MODULE__)}: #{inspect(reason)}"
    end
  end

  defp now_ms, do: System.system_time(:millisecond)
end
