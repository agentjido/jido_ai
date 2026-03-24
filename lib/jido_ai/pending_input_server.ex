defmodule Jido.AI.PendingInputServer do
  @moduledoc """
  Per-run FIFO queue for ReAct steering input.

  The server is owned by the parent ReAct strategy process for the active run.
  Inputs are accepted synchronously, drained by the runtime before LLM turns,
  and the queue can be sealed at terminal boundaries to reject late arrivals.
  """

  use GenServer

  @type input_item :: %{
          optional(:id) => String.t(),
          required(:content) => String.t(),
          optional(:source) => term(),
          optional(:refs) => map() | nil,
          optional(:at_ms) => integer()
        }

  @type state :: %{
          owner: pid(),
          owner_ref: reference(),
          request_id: String.t() | nil,
          queue: :queue.queue(map()),
          sealed?: boolean()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  @doc """
  Starts a pending-input queue for a single active run.
  """
  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec enqueue(GenServer.server(), input_item(), timeout()) :: :ok | {:error, term()}
  @doc """
  Enqueues a user-style input item for later consumption by the runtime.
  """
  def enqueue(server, input_item, timeout \\ 5_000) when is_map(input_item) do
    GenServer.call(server, {:enqueue, input_item}, timeout)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @spec drain(GenServer.server(), timeout()) :: [map()]
  @doc """
  Returns all queued input items in FIFO order and clears the queue.
  """
  def drain(server, timeout \\ 5_000) do
    GenServer.call(server, :drain, timeout)
  catch
    :exit, _ -> []
  end

  @spec has_pending?(GenServer.server(), timeout()) :: boolean()
  @doc """
  Returns true when the queue currently contains at least one item.
  """
  def has_pending?(server, timeout \\ 5_000) do
    GenServer.call(server, :has_pending?, timeout)
  catch
    :exit, _ -> false
  end

  @spec seal(GenServer.server(), timeout()) :: :ok | {:error, term()}
  @doc """
  Seals the queue so future enqueue attempts are rejected.
  """
  def seal(server, timeout \\ 5_000) do
    GenServer.call(server, :seal, timeout)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @spec seal_if_empty(GenServer.server(), timeout()) :: :sealed | :pending | {:error, term()}
  @doc """
  Seals the queue only when it is empty.

  Returns `:sealed` when the queue is empty and has been sealed, or `:pending`
  when items remain and the queue must be drained before completion.
  """
  def seal_if_empty(server, timeout \\ 5_000) do
    GenServer.call(server, :seal_if_empty, timeout)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @spec stop(GenServer.server()) :: :ok
  @doc """
  Stops the queue process, ignoring shutdown races.
  """
  def stop(server) do
    GenServer.stop(server, :normal)
  catch
    :exit, _ -> :ok
  end

  @impl true
  def init(opts) do
    owner = Keyword.fetch!(opts, :owner)
    owner_ref = Process.monitor(owner)

    {:ok,
     %{
       owner: owner,
       owner_ref: owner_ref,
       request_id: Keyword.get(opts, :request_id),
       queue: :queue.new(),
       sealed?: false
     }}
  end

  @impl true
  def handle_call({:enqueue, _input_item}, _from, %{sealed?: true} = state) do
    {:reply, {:error, :closed}, state}
  end

  def handle_call({:enqueue, input_item}, _from, state) do
    case normalize_input_item(input_item) do
      {:ok, item} ->
        {:reply, :ok, %{state | queue: :queue.in(item, state.queue)}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:drain, _from, state) do
    {:reply, :queue.to_list(state.queue), %{state | queue: :queue.new()}}
  end

  def handle_call(:has_pending?, _from, state) do
    {:reply, not :queue.is_empty(state.queue), state}
  end

  def handle_call(:seal, _from, state) do
    {:reply, :ok, %{state | sealed?: true}}
  end

  def handle_call(:seal_if_empty, _from, state) do
    if :queue.is_empty(state.queue) do
      {:reply, :sealed, %{state | sealed?: true}}
    else
      {:reply, :pending, state}
    end
  end

  @impl true
  def handle_info({:DOWN, owner_ref, :process, owner, _reason}, %{owner_ref: owner_ref, owner: owner} = state) do
    {:stop, :normal, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  defp normalize_input_item(%{content: content} = item) when is_binary(content) do
    {:ok,
     %{
       id: Map.get(item, :id, "inp_#{Jido.Util.generate_id()}"),
       content: content,
       source: Map.get(item, :source),
       refs: normalize_refs(Map.get(item, :refs)),
       at_ms: Map.get(item, :at_ms, System.system_time(:millisecond))
     }}
  end

  defp normalize_input_item(_item), do: {:error, :invalid_input}

  defp normalize_refs(%{} = refs), do: refs
  defp normalize_refs(_), do: nil
end
