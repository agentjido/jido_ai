defmodule Jido.AI.Skill.Registry do
  @moduledoc """
  ETS-backed registry for runtime-loaded skills.

  Stores skill specs in an ETS table for fast lookup by name.
  Supports loading skills from directories at startup.

  ## Lifecycle

  `Jido.AI.Skill.Registry` supports two startup modes:

  1. **Explicit startup** via `start_link/1` under your supervisor tree.
  2. **Lazy startup** via `ensure_started/0`, which is called automatically by
     public API functions.

  This matches `Jido.AI.Streaming.Registry` lifecycle semantics so both
  registries work consistently regardless of startup ordering.
  """

  use GenServer

  alias Jido.AI.Skill.{Spec, Loader, Error}

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
  @spec register(Spec.t()) :: :ok | {:error, term()}
  def register(%Spec{} = spec) do
    with_started_registry(fn -> GenServer.call(__MODULE__, {:register, spec}) end)
  end

  @doc """
  Looks up a skill by name.
  """
  @spec lookup(String.t()) :: {:ok, Spec.t()} | {:error, term()}
  def lookup(name) when is_binary(name) do
    with_started_registry(fn ->
      case :ets.lookup(@table_name, name) do
        [{^name, spec}] -> {:ok, spec}
        [] -> {:error, %Error.NotFound{name: name}}
      end
    end)
    |> unwrap_or_error()
  end

  @doc """
  Lists all registered skill names.

  The registry is lazily started on first access.
  """
  @spec list() :: [String.t()]
  def list do
    with_started_registry(fn ->
      :ets.select(@table_name, [{{:"$1", :_}, [], [:"$1"]}])
    end)
    |> unwrap_or_empty_list()
  end

  @doc """
  Lists all registered skill specs.

  The registry is lazily started on first access.
  """
  @spec all() :: [Spec.t()]
  def all do
    with_started_registry(fn ->
      :ets.select(@table_name, [{{:_, :"$1"}, [], [:"$1"]}])
    end)
    |> unwrap_or_empty_list()
  end

  @doc """
  Loads all SKILL.md files from the given paths.

  The registry is lazily started on first access.
  """
  @spec load_from_paths([String.t()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def load_from_paths(paths) do
    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:load_paths, paths})
    end)
    |> unwrap_or_error()
  end

  @doc """
  Unregisters a skill by name.

  The registry is lazily started on first access.
  """
  @spec unregister(String.t()) :: :ok | {:error, term()}
  def unregister(name) when is_binary(name) do
    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:unregister, name})
    end)
    |> unwrap_or_error()
  end

  @doc """
  Clears all registered skills.

  The registry is lazily started on first access.
  """
  @spec clear() :: :ok | {:error, term()}
  def clear do
    with_started_registry(fn ->
      GenServer.call(__MODULE__, :clear)
    end)
    |> unwrap_or_error()
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

  def handle_call({:load_paths, paths}, _from, state) do
    result = do_load_paths(paths)
    {:reply, result, state}
  end

  # Private functions

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

  defp with_started_registry(fun) when is_function(fun, 0) do
    case ensure_started() do
      :ok -> fun.()
      {:error, _reason} = error -> error
    end
  end

  defp unwrap_or_error({:error, _reason} = error), do: error
  defp unwrap_or_error(value), do: value

  defp unwrap_or_empty_list({:error, _reason}), do: []
  defp unwrap_or_empty_list(value) when is_list(value), do: value
end
