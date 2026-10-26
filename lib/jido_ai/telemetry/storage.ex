defmodule Jido.AI.Telemetry.Storage do
  @moduledoc false

  use GenServer

  @table :jido_ai_telemetry_storage

  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec put(term(), term()) :: :ok
  def put(key, value) do
    true = :ets.insert(@table, {key, value})
    :ok
  rescue
    ArgumentError -> :ok
  end

  @spec put_new(term(), term()) :: boolean()
  def put_new(key, value) do
    :ets.insert_new(@table, {key, value})
  rescue
    ArgumentError -> false
  end

  @spec get(term()) :: term() | nil
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @spec take(term()) :: term() | nil
  def take(key) do
    case :ets.take(@table, key) do
      [{^key, value}] -> value
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  @impl GenServer
  def init(:ok) do
    _table =
      :ets.new(@table, [
        :named_table,
        :public,
        :set,
        read_concurrency: true,
        write_concurrency: true
      ])

    {:ok, %{}}
  end
end
