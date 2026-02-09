defmodule Jido.AI.RLM.Workspace.ETSAdapter do
  @moduledoc """
  ETS-backed workspace storage adapter.

  Uses a GenServer to serialize writes while allowing concurrent reads
  directly from the ETS table via `read_concurrency: true`.
  """

  use GenServer

  @behaviour Jido.AI.RLM.Workspace

  @type ref :: %{adapter: module(), pid: pid(), table: :ets.tid()}

  @impl Jido.AI.RLM.Workspace
  @spec init(String.t(), keyword()) :: {:ok, ref()} | {:error, term()}
  def init(_request_id, _opts) do
    case GenServer.start_link(__MODULE__, []) do
      {:ok, pid} ->
        table = GenServer.call(pid, :get_table)
        {:ok, %{adapter: __MODULE__, pid: pid, table: table}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl Jido.AI.RLM.Workspace
  @spec destroy(ref()) :: :ok
  def destroy(%{pid: pid}) do
    GenServer.stop(pid, :normal)
    :ok
  end

  @impl Jido.AI.RLM.Workspace
  @spec fetch(ref(), term()) :: {:ok, term()} | :error
  def fetch(%{table: table}, key) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :error
    end
  end

  @impl Jido.AI.RLM.Workspace
  @spec put(ref(), term(), term()) :: :ok
  def put(%{pid: pid}, key, value) do
    GenServer.call(pid, {:put, key, value})
  end

  @impl Jido.AI.RLM.Workspace
  @spec delete_key(ref(), term()) :: :ok
  def delete_key(%{pid: pid}, key) do
    GenServer.call(pid, {:delete_key, key})
  end

  @impl Jido.AI.RLM.Workspace
  @spec update(ref(), term(), term(), (term() -> term())) :: :ok
  def update(%{pid: pid}, key, default, fun) do
    GenServer.call(pid, {:update, key, default, fun})
  end

  @impl GenServer
  def init([]) do
    table = :ets.new(:workspace, [:set, :protected, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl GenServer
  def handle_call(:get_table, _from, %{table: table} = state) do
    {:reply, table, state}
  end

  def handle_call({:put, key, value}, _from, %{table: table} = state) do
    :ets.insert(table, {key, value})
    {:reply, :ok, state}
  end

  def handle_call({:delete_key, key}, _from, %{table: table} = state) do
    :ets.delete(table, key)
    {:reply, :ok, state}
  end

  def handle_call({:update, key, default, fun}, _from, %{table: table} = state) do
    current =
      case :ets.lookup(table, key) do
        [{^key, value}] -> value
        [] -> default
      end

    :ets.insert(table, {key, fun.(current)})
    {:reply, :ok, state}
  end

  @impl GenServer
  def terminate(_reason, %{table: table}) do
    :ets.delete(table)
    :ok
  end
end
