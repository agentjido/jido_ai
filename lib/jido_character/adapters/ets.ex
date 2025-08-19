defmodule Jido.Character.Persistence.ETS do
  @moduledoc """
  ETS-based persistence adapter for Jido.Character storage using binary term serialization.
  """

  @behaviour Jido.Character.Persistence.Adapter

  require Logger

  @table_name :jido_characters

  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts \\ []) do
    :ets.new(@table_name, [:set, :public, :named_table])
    {:ok, self()}
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @impl true
  def save(%Jido.Character{} = character) do
    try do
      true = :ets.insert(@table_name, {character.id, character})
      {:ok, character}
    rescue
      e ->
        Logger.warning("Failed to save character: #{inspect(e)}")
        {:error, :storage_error}
    end
  end

  @impl true
  def get(id) when is_binary(id) do
    case :ets.lookup(@table_name, id) do
      [{^id, character}] -> {:ok, character}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def delete(id) when is_binary(id) do
    :ets.delete(@table_name, id)
    :ok
  rescue
    e ->
      Logger.warning("Failed to delete character: #{inspect(e)}")
      {:error, :delete_failed}
  end
end
