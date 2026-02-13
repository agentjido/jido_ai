defmodule Jido.AI.Skill.Registry do
  @moduledoc """
  ETS-backed registry for runtime-loaded skills.

  Stores skill specs in an ETS table for fast lookup by name.
  Supports loading skills from directories at startup.
  """

  use GenServer

  alias Jido.AI.Skill.{Error, Loader, Spec}

  @table_name :jido_skill_registry

  # Client API

  @doc """
  Starts the registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a skill spec in the registry.
  """
  @spec register(Spec.t()) :: :ok
  def register(%Spec{} = spec) do
    GenServer.call(__MODULE__, {:register, spec})
  end

  @doc """
  Looks up a skill by name.
  """
  @spec lookup(String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def lookup(name) when is_binary(name) do
    case :ets.lookup(@table_name, name) do
      [{^name, spec}] -> {:ok, spec}
      [] -> {:error, %Error.NotFound{name: name}}
    end
  end

  @doc """
  Lists all registered skill names.
  """
  @spec list() :: [String.t()]
  def list do
    :ets.select(@table_name, [{{:"$1", :_}, [], [:"$1"]}])
  end

  @doc """
  Lists all registered skill specs.
  """
  @spec all() :: [Spec.t()]
  def all do
    :ets.select(@table_name, [{{:_, :"$1"}, [], [:"$1"]}])
  end

  @doc """
  Loads all SKILL.md files from the given paths.
  """
  @spec load_from_paths([String.t()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_from_paths(paths) do
    with :ok <- ensure_registry_started() do
      do_load_paths(paths)
    end
  end

  @doc """
  Unregisters a skill by name.
  """
  @spec unregister(String.t()) :: :ok
  def unregister(name) when is_binary(name) do
    GenServer.call(__MODULE__, {:unregister, name})
  end

  @doc """
  Clears all registered skills.
  """
  @spec clear() :: :ok
  def clear do
    GenServer.call(__MODULE__, :clear)
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, %Spec{name: name} = spec}, _from, state) do
    :ets.insert(@table_name, {name, spec})
    {:reply, :ok, state}
  end

  def handle_call({:unregister, name}, _from, state) do
    :ets.delete(@table_name, name)
    {:reply, :ok, state}
  end

  def handle_call(:clear, _from, state) do
    :ets.delete_all_objects(@table_name)
    {:reply, :ok, state}
  end

  # Private functions

  defp ensure_registry_started do
    case :ets.whereis(@table_name) do
      :undefined -> {:error, :registry_not_started}
      _tid -> :ok
    end
  end

  defp do_load_paths(paths) do
    paths
    |> Enum.flat_map(&find_skill_files/1)
    |> Enum.reduce_while({:ok, 0}, fn path, {:ok, count} ->
      case load_and_register(path) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp load_and_register(path) do
    case Loader.load(path) do
      {:ok, spec} ->
        :ets.insert(@table_name, {spec.name, spec})
        :ok

      {:error, _reason} = error ->
        error
    end
  end

  defp find_skill_files(path) do
    cond do
      File.regular?(path) and String.ends_with?(path, "SKILL.md") ->
        [path]

      File.dir?(path) ->
        Path.wildcard(Path.join([path, "**", "SKILL.md"]))

      true ->
        []
    end
  end
end
