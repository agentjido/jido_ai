defmodule Jido.AI.RLM.Reaper do
  @moduledoc """
  Tracks workspace, context, and budget refs with TTLs and cleans them up on expiry.

  Prevents lifecycle leaks when callers forget to explicitly delete resources.
  Each tracked resource gets a timer; when the timer fires the reaper calls the
  appropriate store's delete/destroy function. Callers that do their own cleanup
  should call `untrack/2` to cancel the pending timer.

  ## Usage

      {:ok, _} = Reaper.start_link()
      {:ok, ws_ref} = WorkspaceStore.init("req-1")
      :ok = Reaper.track({:workspace, ws_ref}, :timer.minutes(5))
      # ... later, if manually deleting:
      :ok = Reaper.untrack({:workspace, ws_ref})
      :ok = WorkspaceStore.delete(ws_ref)
  """

  use GenServer

  require Logger

  alias Jido.AI.RLM.ContextStore
  alias Jido.AI.RLM.WorkspaceStore

  @type resource_type :: :workspace | :context | :budget
  @type resource :: {resource_type(), map()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec track(GenServer.server(), resource(), non_neg_integer()) :: :ok
  def track(server \\ __MODULE__, resource, ttl_ms) do
    GenServer.call(server, {:track, resource, ttl_ms})
  end

  @spec untrack(GenServer.server(), resource()) :: :ok
  def untrack(server \\ __MODULE__, resource) do
    GenServer.call(server, {:untrack, resource})
  end

  # --- Server callbacks ---

  @impl GenServer
  def init(_opts) do
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:track, resource, ttl_ms}, _from, state) do
    key = resource_key(resource)

    state =
      case Map.get(state, key) do
        %{timer_ref: old_timer} ->
          Process.cancel_timer(old_timer)
          Map.delete(state, key)

        nil ->
          state
      end

    timer_ref = Process.send_after(self(), {:reap, key}, ttl_ms)

    entry = %{
      resource: resource,
      timer_ref: timer_ref,
      expires_at: System.monotonic_time(:millisecond) + ttl_ms
    }

    {:reply, :ok, Map.put(state, key, entry)}
  end

  def handle_call({:untrack, resource}, _from, state) do
    key = resource_key(resource)

    state =
      case Map.pop(state, key) do
        {%{timer_ref: timer_ref}, rest} ->
          Process.cancel_timer(timer_ref)
          rest

        {nil, rest} ->
          rest
      end

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_info({:reap, key}, state) do
    case Map.pop(state, key) do
      {%{resource: resource}, rest} ->
        reap_resource(resource)
        {:noreply, rest}

      {nil, state} ->
        {:noreply, state}
    end
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # --- Internals ---

  defp resource_key({type, %{pid: pid}}), do: {type, pid}
  defp resource_key({type, %{table: table}}), do: {type, table}
  defp resource_key({type, %{backend: :inline}}), do: {type, :inline}
  defp resource_key({type, ref}) when is_map(ref), do: {type, :erlang.phash2(ref)}

  defp reap_resource({:workspace, ref}) do
    try do
      WorkspaceStore.delete(ref)
    catch
      kind, reason ->
        Logger.debug("Reaper: workspace delete failed (#{kind}: #{inspect(reason)})")
    end
  end

  defp reap_resource({:context, ref}) do
    try do
      ContextStore.delete(ref)
    catch
      kind, reason ->
        Logger.debug("Reaper: context delete failed (#{kind}: #{inspect(reason)})")
    end
  end

  defp reap_resource({:budget, ref}) do
    try do
      Jido.AI.RLM.BudgetStore.destroy(ref)
    catch
      kind, reason ->
        Logger.debug("Reaper: budget delete failed (#{kind}: #{inspect(reason)})")
    end
  end
end
