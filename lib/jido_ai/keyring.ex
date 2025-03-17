defmodule Jido.AI.Keyring do
  @moduledoc """
  A GenServer that manages environment variables and application configuration.

  This module serves as the source of truth for configuration values, with a hierarchical loading priority:

  1. Session values (per-process overrides)
  2. Environment variables (via Dotenvy)
  3. Application environment (under :jido_ai, :keyring)
  4. Default values

  The keyring supports both global environment values and process-specific session values,
  allowing for flexible configuration management in different contexts.

  ## Usage

      # Get a value (checks session then environment)
      value = Keyring.get(:my_key, "default")

      # Set a session-specific override
      Keyring.set_session_value(:my_key, "override")

      # Clear session values
      Keyring.clear_session_value(:my_key)
      Keyring.clear_all_session_values()

  """

  use GenServer
  require Logger

  @session_registry :jido_ai_keyring_sessions
  @default_name __MODULE__

  @doc false
  @spec ensure_session_registry(atom()) :: atom()
  defp ensure_session_registry(registry_name) do
    if :ets.whereis(registry_name) == :undefined do
      :ets.new(registry_name, [:set, :public, :named_table])
    end
  end

  @doc """
  Returns the child specification for starting the keyring under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    name = Keyword.get(opts, :name, @default_name)

    %{
      id: name,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @doc """
  Starts the keyring process.

  ## Options

    * `:name` - The name to register the process under (default: #{@default_name})
    * `:registry` - The name for the ETS registry table (default: #{@session_registry})

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    registry = Keyword.get(opts, :registry, @session_registry)

    ensure_session_registry(registry)
    GenServer.start_link(__MODULE__, registry, name: name)
  end

  @impl true
  @spec init(atom()) :: {:ok, map()}
  def init(registry) do
    env = load_from_env()
    app_env = load_from_app_env()
    keys = Map.merge(app_env, env)

    Logger.debug("[Jido.AI.Keyring] Initializing environment variables")

    {:ok, %{keys: keys, registry: registry}}
  end

  @doc false
  @spec load_from_env() :: map()
  defp load_from_env do
    env_dir_prefix = Path.expand("./envs/")

    Dotenvy.source!([
      Path.join(File.cwd!(), ".env"),
      Path.absname(".env", env_dir_prefix),
      Path.absname(".#{Mix.env()}.env", env_dir_prefix),
      Path.absname(".#{Mix.env()}.overrides.env", env_dir_prefix),
      System.get_env()
    ])
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      atom_key = env_var_to_atom(key)
      Map.put(acc, atom_key, value)
    end)
  end

  @doc false
  @spec env_var_to_atom(String.t()) :: atom()
  defp env_var_to_atom(env_var) do
    env_var
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  @doc false
  @spec load_from_app_env() :: map()
  defp load_from_app_env do
    case Application.get_env(:jido_ai, :keyring) do
      nil -> %{}
      config when is_map(config) -> config
      _ -> %{}
    end
  end

  @doc """
  Lists all available keys in the keyring.

  Returns a list of atoms representing the available environment-level keys.
  Does not include session-specific overrides.
  """
  @spec list(GenServer.server()) :: [atom()]
  def list(server \\ @default_name) do
    GenServer.call(server, :list_keys)
  end

  @doc """
  Gets a value from the keyring, checking session values first, then environment values.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the value if found, otherwise returns the default value.
  """
  @spec get(GenServer.server(), atom(), term()) :: term()
  def get(server \\ @default_name, key, default \\ nil) when is_atom(key) do
    case get_session_value(server, key) do
      nil -> get_env_value(server, key, default)
      value -> value
    end
  end

  @doc """
  Gets a value from the environment-level storage.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the environment value if found, otherwise returns the default value.
  """
  @spec get_env_value(GenServer.server(), atom(), term()) :: term()
  def get_env_value(server \\ @default_name, key, default \\ nil) when is_atom(key) do
    GenServer.call(server, {:get_value, key, default})
  end

  @doc """
  Sets a session-specific value that will override the environment value
  for the current process only.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to set (as an atom)
    * `value` - The value to store

  Returns `:ok`.
  """
  @spec set_session_value(GenServer.server(), atom(), term()) :: :ok
  def set_session_value(server \\ @default_name, key, value) when is_atom(key) do
    registry = GenServer.call(server, :get_registry)
    pid = self()
    :ets.insert(registry, {{pid, key}, value})
    :ok
  end

  @doc """
  Gets a session-specific value for the current process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)

  Returns the session value if found, otherwise returns `nil`.
  """
  @spec get_session_value(GenServer.server(), atom()) :: term() | nil
  def get_session_value(server \\ @default_name, key) when is_atom(key) do
    registry = GenServer.call(server, :get_registry)
    pid = self()

    case :ets.lookup(registry, {pid, key}) do
      [{{^pid, ^key}, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Clears a session-specific value for the current process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to clear (as an atom)

  Returns `:ok`.
  """
  @spec clear_session_value(GenServer.server(), atom()) :: :ok
  def clear_session_value(server \\ @default_name, key) when is_atom(key) do
    registry = GenServer.call(server, :get_registry)
    pid = self()
    :ets.delete(registry, {pid, key})
    :ok
  end

  @doc """
  Clears all session-specific values for the current process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})

  Returns `:ok`.
  """
  @spec clear_all_session_values(GenServer.server()) :: :ok
  def clear_all_session_values(server \\ @default_name) do
    registry = GenServer.call(server, :get_registry)
    pid = self()
    :ets.match_delete(registry, {{pid, :_}, :_})
    :ok
  end

  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
  def handle_call({:get_value, key, default}, _from, %{keys: keys} = state) do
    {:reply, Map.get(keys, key, default), state}
  end

  @impl true
  def handle_call(:list_keys, _from, %{keys: keys} = state) do
    {:reply, Map.keys(keys), state}
  end

  @impl true
  def handle_call(:get_registry, _from, %{registry: registry} = state) do
    {:reply, registry, state}
  end

  @impl true
  def handle_call({:set_test_env_vars, env_vars}, _from, %{keys: keys} = state)
      when is_map(env_vars) do
    atom_env_vars =
      Enum.reduce(env_vars, %{}, fn {key, value}, acc ->
        atom_key = env_var_to_atom(key)
        Map.put(acc, atom_key, value)
      end)

    new_keys = Map.merge(keys, atom_env_vars)
    {:reply, :ok, %{state | keys: new_keys}}
  end

  @doc """
  Gets an environment variable with a default value.

  ## Parameters

    * `key` - The environment variable name
    * `default` - The default value if not found

  Returns the environment variable value if found, otherwise returns the default value.
  """
  @spec get_env_var(String.t(), term()) :: String.t() | term()
  def get_env_var(key, default \\ nil) do
    try do
      Dotenvy.env!(key, :string)
    rescue
      _ -> default
    end
  end

  @doc """
  Checks if a value exists and is non-empty.

  Returns `true` if the value is a non-empty string, `false` otherwise.
  """
  @spec has_value?(term()) :: boolean()
  def has_value?(nil), do: false
  def has_value?(""), do: false
  def has_value?(value) when is_binary(value), do: true
  def has_value?(_), do: false
end
