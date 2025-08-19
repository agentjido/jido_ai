defmodule Jido.Character.Persistence.Memory do
  @moduledoc """
  In-memory persistence adapter for Jido.Character storage.
  """

  @behaviour Jido.Character.Persistence.Adapter

  require Logger

  # Agent to store the characters in memory
  @agent_name __MODULE__

  @doc """
  Starts the MemoryAdapter process.
  """
  @spec start_link(keyword()) :: {:ok, pid()}
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: @agent_name)
  end

  @doc """
  Defines the child specification for the MemoryAdapter.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker
    }
  end

  @doc """
  Clears all data from the in-memory storage.
  """
  @spec clear() :: :ok
  def clear do
    Agent.update(@agent_name, fn _state -> %{} end)
  end

  @impl true
  @doc """
  Saves a character to the in-memory storage.
  """
  @spec save(Jido.Character.t()) :: {:ok, Jido.Character.t()} | {:error, term()}
  def save(%Jido.Character{} = character) do
    try do
      Agent.update(@agent_name, fn state ->
        Map.put(state, character.id, :erlang.term_to_binary(character))
      end)

      {:ok, character}
    rescue
      e ->
        Logger.warning("Failed to save character: #{inspect(e)}")
        {:error, :storage_error}
    end
  end

  @impl true
  @doc """
  Retrieves a character from the in-memory storage by its ID.
  """
  @spec get(String.t()) :: {:ok, Jido.Character.t()} | {:error, :not_found}
  def get(id) when is_binary(id) do
    case Agent.get(@agent_name, fn state -> Map.get(state, id) end) do
      nil ->
        {:error, :not_found}

      binary_character ->
        try do
          {:ok, :erlang.binary_to_term(binary_character)}
        rescue
          _ -> {:error, :invalid_data}
        end
    end
  end

  @impl true
  @doc """
  Deletes a character from the in-memory storage by its ID.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(id) when is_binary(id) do
    Agent.update(@agent_name, fn state ->
      Map.delete(state, id)
    end)

    :ok
  rescue
    e ->
      Logger.warning("Failed to delete character: #{inspect(e)}")
      {:error, :delete_failed}
  end
end
