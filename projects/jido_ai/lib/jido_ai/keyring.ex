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
  @default_env_table_prefix :jido_ai_env_cache

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
    * `:env_table_name` - The name for the environment cache table (default: dynamic based on process name)

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @default_name)
    registry = Keyword.get(opts, :registry, @session_registry)
    env_table_name = Keyword.get(opts, :env_table_name, generate_env_table_name(name))

    ensure_session_registry(registry)
    GenServer.start_link(__MODULE__, {registry, env_table_name}, name: name)
  end

  @impl true
  def init({registry, env_table_name}) do
    # Load environment data
    env = load_from_env()
    app_env = load_from_app_env()
    keys = Map.merge(app_env, env)

    # Create ETS table for fast environment lookups with unique name
    # Clean up any existing table first
    if :ets.whereis(env_table_name) != :undefined do
      :ets.delete(env_table_name)
    end

    env_table = :ets.new(env_table_name, [:set, :protected, :named_table, read_concurrency: true])

    # Populate ETS table with environment values and LiveBook variants
    Enum.each(keys, fn {key, value} ->
      :ets.insert(env_table, {key, value})
      # Also insert LiveBook prefixed version
      livebook_key = to_livebook_key(key)
      :ets.insert(env_table, {livebook_key, value})
    end)

    {:ok, %{keys: keys, registry: registry, env_table: env_table, env_table_name: env_table_name}}
  end

  @doc false
  defp load_from_env do
    env_dir_prefix = Path.expand("./envs/")
    current_env = get_environment()

    env_sources =
      Dotenvy.source!([
        Path.join(File.cwd!(), ".env"),
        Path.absname(".env", env_dir_prefix),
        Path.absname(".#{current_env}.env", env_dir_prefix),
        Path.absname(".#{current_env}.overrides.env", env_dir_prefix),
        System.get_env()
      ])

    Enum.reduce(env_sources, %{}, fn {key, value}, acc ->
      str_key = normalize_env_key(key)
      Map.put(acc, str_key, value)
    end)
  rescue
    _ -> %{}
  end

  @doc false
  @spec get_environment() :: atom()
  defp get_environment do
    # First try to use Mix.env() which works in dev, test
    if function_exported?(Mix, :env, 0) do
      Mix.env()
    else
      # In production releases, check for config
      Application.get_env(:jido_ai, :env, :prod)
    end
  end

  @doc false
  @spec normalize_env_key(String.t()) :: String.t()
  defp normalize_env_key(env_var) do
    env_var
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
  end

  @doc false
  defp load_from_app_env do
    case Application.get_env(:jido_ai, :keyring) do
      nil ->
        %{}

      config when is_map(config) ->
        Enum.reduce(config, %{}, fn {key, value}, acc ->
          str_key = norm_key(key)
          Map.put(acc, str_key, value)
        end)

      _ ->
        %{}
    end
  end

  @doc """
  Lists all available keys in the keyring.

  Returns a list of strings representing the available environment-level keys.
  Does not include session-specific overrides.
  """
  @spec list(GenServer.server()) :: [String.t()]
  def list(server \\ @default_name) do
    GenServer.call(server, :list_keys)
  end

  @doc """
  Gets a value from the keyring, checking session values first, then environment values.

  ## Parameters

    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the value if found, otherwise returns the default value.
  """
  @spec get(atom() | String.t(), term()) :: term()
  def get(key, default \\ nil) when is_atom(key) or is_binary(key) do
    get(@default_name, key, default, self())
  end

  @doc """
  Gets a value from the keyring with custom server.

  ## Parameters

    * `server` - The server to query
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the value if found, otherwise returns the default value.
  """
  @spec get(GenServer.server(), atom() | String.t(), term()) :: term()
  def get(server, key, default) when is_atom(key) or is_binary(key) do
    get(server, key, default, self())
  end

  @doc """
  Gets a value from the keyring with custom server and pid.

  ## Parameters

    * `server` - The server to query
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found
    * `pid` - The process ID to check session values for (default: current process)

  Returns the value if found, otherwise returns the default value.
  """
  @spec get(GenServer.server(), atom() | String.t(), term(), pid()) :: term()
  def get(server, key, default, pid) when is_atom(key) or is_binary(key) do
    case get_session_value(server, key, pid) do
      nil -> get_env_value(server, key, default)
      value -> value
    end
  end

  @doc """
  Gets a value from the environment-level storage, also checking for LiveBook prefixed keys as fallback.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom or string)
    * `default` - The default value if key is not found

  Returns the environment value if found, otherwise returns the default value.
  """
  @spec get_env_value(GenServer.server(), atom() | String.t(), term()) :: term()
  def get_env_value(server \\ @default_name, key, default \\ nil) when is_atom(key) or is_binary(key) do
    env_table = env_table_name(server)

    case :ets.whereis(env_table) do
      :undefined ->
        # Fallback for rare race conditions
        case GenServer.call(server, :get_env_table) do
          {:error, :env_table_not_found} -> default
          table -> do_env_lookup(table, key, default)
        end

      _table ->
        do_env_lookup(env_table, key, default)
    end
  end

  @doc """
  Returns the ETS table name used for environment variable lookups.
  """
  @spec env_table_name(GenServer.server()) :: atom()
  def env_table_name(server \\ @default_name), do: generate_env_table_name(server)

  defp do_env_lookup(table, key, default) do
    bin_key = norm_key(key)

    case :ets.lookup(table, bin_key) do
      [{^bin_key, v}] ->
        v

      [] ->
        lb = "lb_" <> bin_key

        case :ets.lookup(table, lb) do
          [{^lb, v}] -> v
          [] -> default
        end
    end
  end

  @doc """
  Sets a session-specific value that will override the environment value
  for the specified process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to set (as an atom or string)
    * `value` - The value to store
    * `pid` - The process ID to associate with this value (default: current process)

  Returns `:ok`.
  """
  @spec set_session_value(GenServer.server(), atom() | String.t(), term(), pid()) :: :ok
  def set_session_value(server \\ @default_name, key, value, pid \\ self()) when is_atom(key) or is_binary(key) do
    registry = GenServer.call(server, :get_registry)
    normalized_key = if is_binary(key), do: String.to_atom(key), else: key
    :ets.insert(registry, {{pid, normalized_key}, value})
    :ok
  end

  @doc """
  Gets a session-specific value for the specified process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `pid` - The process ID to get the value for (default: current process)

  Returns the session value if found, otherwise returns `nil`.
  """
  @spec get_session_value(GenServer.server(), atom() | String.t(), pid()) :: term() | nil
  def get_session_value(server \\ @default_name, key, pid \\ self()) when is_atom(key) or is_binary(key) do
    registry = GenServer.call(server, :get_registry)
    normalized_key = if is_binary(key), do: String.to_atom(key), else: key

    case :ets.lookup(registry, {pid, normalized_key}) do
      [{{^pid, ^normalized_key}, value}] -> value
      [] -> nil
    end
  end

  @doc """
  Clears a session-specific value for the specified process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to clear (as an atom)
    * `pid` - The process ID to clear the value for (default: current process)

  Returns `:ok`.
  """
  @spec clear_session_value(GenServer.server(), atom() | String.t(), pid()) :: :ok
  def clear_session_value(server \\ @default_name, key, pid \\ self()) when is_atom(key) or is_binary(key) do
    registry = GenServer.call(server, :get_registry)
    normalized_key = if is_binary(key), do: String.to_atom(key), else: key
    :ets.delete(registry, {pid, normalized_key})
    :ok
  end

  @doc """
  Clears all session-specific values for the specified process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `pid` - The process ID to clear all values for (default: current process)

  Returns `:ok`.
  """
  @spec clear_all_session_values(GenServer.server(), pid()) :: :ok
  def clear_all_session_values(server \\ @default_name, pid \\ self()) do
    registry = GenServer.call(server, :get_registry)
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
  def handle_call(:get_env_table, _from, %{env_table: env_table} = state) when env_table != nil do
    {:reply, env_table, state}
  end

  @impl true
  def handle_call(:get_env_table, _from, state) do
    {:reply, {:error, :env_table_not_found}, state}
  end

  @impl true
  def handle_call({:clear_and_set_test_env_vars, env_vars}, _from, %{env_table: env_table} = state)
      when is_map(env_vars) do
    # Clear all existing environment variables
    :ets.delete_all_objects(env_table)

    str_env_vars =
      Enum.reduce(env_vars, %{}, fn {key, value}, acc ->
        str_key = normalize_env_key(key)
        Map.put(acc, str_key, value)
      end)

    # Update the ETS table with only the new variables
    Enum.each(str_env_vars, fn {key, value} ->
      :ets.insert(env_table, {key, value})
      # Also insert LiveBook prefixed version
      livebook_key = to_livebook_key(key)
      :ets.insert(env_table, {livebook_key, value})
    end)

    # Replace the state keys entirely
    {:reply, :ok, %{state | keys: str_env_vars}}
  end

  # Backward compatibility for old handler name
  @impl true
  def handle_call({:set_test_env_vars, env_vars}, from, state) do
    handle_call({:clear_and_set_test_env_vars, env_vars}, from, state)
  end

  @doc """
  Sets test environment variables for testing purposes.
  This replaces all existing environment variables with the provided ones.

  ## Parameters

    * `env_vars` - A map of environment variables to set
    * `server` - The keyring server name (optional)

  Returns :ok on success.
  """
  @spec set_test_env_vars(map(), atom()) :: :ok
  def set_test_env_vars(env_vars, server \\ @default_name) when is_map(env_vars) do
    GenServer.call(server, {:set_test_env_vars, env_vars})
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
    Dotenvy.env!(key, :string)
  rescue
    _ -> default
  end

  @doc """
  Checks if a key has a value and the value is non-empty.

  ## Parameters

    * `key` - The key to check
    * `server` - The keyring server to query (default: #{@default_name})

  Returns `true` if the key has a non-empty value, `false` otherwise.
  """
  @spec has_value?(atom()) :: boolean()
  def has_value?(key) when is_atom(key) do
    has_value?(key, @default_name)
  end

  @spec has_value?(String.t()) :: boolean()
  def has_value?(""), do: false

  def has_value?(key) when is_binary(key) do
    atom_key = String.to_atom(key)
    has_value?(atom_key)
  end

  @spec has_value?(atom(), GenServer.server()) :: boolean()
  def has_value?(key, server) when is_atom(key) do
    value = get(server, key, nil, self())
    value_exists?(value)
  end

  @doc """
  Checks if a value exists.

  Returns `true` if the value is not nil, `false` otherwise.
  """
  @spec value_exists?(term()) :: boolean()
  def value_exists?(nil), do: false
  def value_exists?(_), do: true

  @impl true
  @spec terminate(term(), map()) :: :ok
  def terminate(_reason, %{env_table_name: env_table_name}) do
    # Clean up the ETS table to prevent conflicts on restart
    if :ets.whereis(env_table_name) != :undefined do
      :ets.delete(env_table_name)
    end

    :ok
  end

  def terminate(_reason, _state), do: :ok

  @doc false
  @spec ensure_session_registry(atom()) :: atom()
  defp ensure_session_registry(registry_name) do
    if :ets.whereis(registry_name) == :undefined do
      :ets.new(registry_name, [:set, :public, :named_table])
    end
  end

  @doc false
  @spec generate_env_table_name(atom()) :: atom()
  defp generate_env_table_name(name) do
    case name do
      @default_name -> @default_env_table_prefix
      _ -> :"#{@default_env_table_prefix}_#{name}"
    end
  end

  @doc false
  @spec to_livebook_key(String.t()) :: String.t()
  defp to_livebook_key(key) do
    "lb_#{key}"
  end

  @spec norm_key(atom() | String.t()) :: String.t()
  defp norm_key(k) when is_atom(k), do: Atom.to_string(k)
  defp norm_key(k) when is_binary(k), do: k
end
