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

  This ensures consistent startup behavior regardless of supervision order.
  """

  use GenServer

  alias Jido.AI.Skill.{Spec, Loader, Error}

  @table_name :jido_skill_registry
  @activation_table :jido_skill_activations

  @type session_id :: term()

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

  # Session/Activation API

  @doc """
  Marks a skill as activated with its activation context.

  Used by `Jido.AI.Skill.Activation` to track activated skills. The optional
  `:session_id` defaults to the caller process.
  """
  @spec mark_activated(String.t(), map(), keyword()) :: :ok | {:error, term()}
  def mark_activated(name, context, opts \\ []) when is_binary(name) and is_map(context) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:mark_activated, session_id, name, context})
    end)
    |> unwrap_or_error()
  end

  @doc """
  Checks if a skill has been activated in the selected session.

  The optional `:session_id` defaults to the caller process.
  """
  @spec activated?(String.t(), keyword()) :: boolean()
  def activated?(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      :ets.lookup(@activation_table, {session_id, name}) != []
    end)
    |> unwrap_or_false()
  end

  @doc """
  Lists all activated skill names in the selected session.

  The optional `:session_id` defaults to the caller process.
  """
  @spec list_activated(keyword()) :: [String.t()]
  def list_activated(opts \\ []) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      :ets.select(@activation_table, [{{{session_id, :"$1"}, :_}, [], [:"$1"]}])
    end)
    |> unwrap_or_empty_list()
  end

  @doc """
  Gets the activation context for an activated skill.

  The optional `:session_id` defaults to the caller process.

  ## Returns

  - `{:ok, context}` - Skill is activated, context returned
  - `{:error, :not_activated}` - Skill not found in activation table
  """
  @spec get_activation_context(String.t(), keyword()) :: {:ok, map()} | {:error, :not_activated}
  def get_activation_context(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      case :ets.lookup(@activation_table, {session_id, name}) do
        [{{^session_id, ^name}, %{context: context}}] -> {:ok, context}
        [] -> {:error, :not_activated}
      end
    end)
    |> unwrap_or_error()
  end

  @doc """
  Marks an activated skill as durable for lifecycle bookkeeping.

  Durable skills remain in the activation table until the registry is cleared.
  `Jido.AI.Actions.Skill.LoadSkill` also tags its conversation tool result so
  ReAct can preserve the actual instructions during compaction. Calling this
  registry function alone does not mutate conversation context.
  """
  @spec mark_durable(String.t(), keyword()) :: :ok | {:error, term()}
  def mark_durable(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:mark_durable, session_id, name})
    end)
    |> unwrap_or_error()
  end

  @doc """
  Clears durable lifecycle bookkeeping for a skill activation.
  """
  @spec unmark_durable(String.t(), keyword()) :: :ok | {:error, term()}
  def unmark_durable(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:unmark_durable, session_id, name})
    end)
    |> unwrap_or_error()
  end

  @doc """
  Checks if a skill is marked as durable.

  The optional `:session_id` defaults to the caller process.
  """
  @spec durable?(String.t(), keyword()) :: boolean()
  def durable?(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      case :ets.lookup(@activation_table, {session_id, name}) do
        [{{^session_id, ^name}, %{durable: true}}] -> true
        _ -> false
      end
    end)
    |> unwrap_or_false()
  end

  @doc """
  Deactivates a skill, removing it from the activation table.

  Fails if the skill is marked as durable.
  """
  @spec deactivate(String.t(), keyword()) :: :ok | {:error, term()}
  def deactivate(name, opts \\ []) when is_binary(name) do
    session_id = session_id(opts)

    with_started_registry(fn ->
      GenServer.call(__MODULE__, {:deactivate, session_id, name})
    end)
    |> unwrap_or_error()
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Main registry table
    table = :ets.new(@table_name, [:named_table, :set, :public, read_concurrency: true])

    # Activation tracking table (separate for session management)
    activation_table =
      :ets.new(@activation_table, [:named_table, :set, :public, read_concurrency: true])

    {:ok, %{table: table, activation_table: activation_table}}
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
    :ets.delete_all_objects(@activation_table)
    {:reply, :ok, state}
  end

  def handle_call({:load_paths, paths}, _from, state) do
    result = do_load_paths(paths)
    {:reply, result, state}
  end

  def handle_call({:mark_activated, session_id, name, context}, _from, state) do
    :ets.insert(@activation_table, {{session_id, name}, %{context: context, durable: false}})
    {:reply, :ok, state}
  end

  def handle_call({:mark_durable, session_id, name}, _from, state) do
    case :ets.lookup(@activation_table, {session_id, name}) do
      [{{^session_id, ^name}, activation}] ->
        :ets.insert(@activation_table, {{session_id, name}, %{activation | durable: true}})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_activated}, state}
    end
  end

  def handle_call({:unmark_durable, session_id, name}, _from, state) do
    case :ets.lookup(@activation_table, {session_id, name}) do
      [{{^session_id, ^name}, activation}] ->
        :ets.insert(@activation_table, {{session_id, name}, %{activation | durable: false}})
        {:reply, :ok, state}

      [] ->
        {:reply, :ok, state}
    end
  end

  def handle_call({:deactivate, session_id, name}, _from, state) do
    case :ets.lookup(@activation_table, {session_id, name}) do
      [{{^session_id, ^name}, %{durable: true}}] ->
        {:reply, {:error, :skill_is_durable}, state}

      _ ->
        :ets.delete(@activation_table, {session_id, name})
        {:reply, :ok, state}
    end
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

  defp session_id(opts), do: Keyword.get(opts, :session_id, self())

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

  defp unwrap_or_false({:error, _reason}), do: false
  defp unwrap_or_false(value) when is_boolean(value), do: value
  defp unwrap_or_false(nil), do: false
  defp unwrap_or_false(_), do: true
end
