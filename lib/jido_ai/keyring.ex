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

  alias Jido.AI.ReqLlmBridge.KeyringIntegration

  @session_registry :jido_ai_keyring_sessions
  @default_name __MODULE__
  @default_env_table_prefix :jido_ai_env_cache

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

    Logger.debug(
      "[Jido.AI.Keyring] Initializing environment variables with ETS optimization (table: #{env_table_name})"
    )

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
      atom_key = env_var_to_atom(key)
      Map.put(acc, atom_key, value)
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
  @spec env_var_to_atom(String.t()) :: atom()
  defp env_var_to_atom(env_var) do
    env_var
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_]/, "_")
    |> String.to_atom()
  end

  @doc false
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
    * `pid` - The process ID to check session values for (default: current process)

  Returns the value if found, otherwise returns the default value.
  """
  @spec get(GenServer.server(), atom(), term(), pid()) :: term()
  def get(server \\ @default_name, key, default \\ nil, pid \\ self()) when is_atom(key) do
    # Enhanced: Use JidoKeys hybrid integration for better session fallback
    case get_session_value(server, key, pid) do
      nil ->
        # Try ReqLLM.Keys for API keys, then fall back to environment
        get_reqllm_or_env_value(server, key, default)

      value ->
        # Apply security filtering to session values
        filter_sensitive_data(value)
    end
  end

  @doc """
  Gets a value with ReqLLM integration support.

  This function extends the standard get/4 with ReqLLM integration, supporting
  per-request key overrides and unified key precedence across both Jido and ReqLLM systems.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found
    * `pid` - The process ID to check session values for (default: current process)
    * `req_options` - Per-request options (may contain :api_key overrides for ReqLLM calls)

  Returns the value if found, otherwise returns the default value.

  ## Examples

      # Standard usage (backward compatible)
      api_key = Keyring.get_with_reqllm(:openai_api_key, "default")

      # With per-request override for ReqLLM calls
      options = %{api_key: "override-key"}
      api_key = Keyring.get_with_reqllm(:openai_api_key, "default", self(), options)
  """
  @spec get_with_reqllm(GenServer.server(), atom(), term(), pid(), map()) :: term()
  def get_with_reqllm(
        server \\ @default_name,
        key,
        default \\ nil,
        pid \\ self(),
        req_options \\ %{}
      )
      when is_atom(key) do
    # Use the KeyringIntegration module for unified key resolution
    KeyringIntegration.get(server, key, default, pid, req_options)
  end

  @doc """
  Gets a value from the environment-level storage, also checking for LiveBook prefixed keys as fallback.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the environment value if found, otherwise returns the default value.
  """
  @spec get_env_value(GenServer.server(), atom(), term()) :: term()
  def get_env_value(server \\ @default_name, key, default \\ nil) when is_atom(key) do
    # Try ReqLLM.Keys for API keys, then fallback to ETS for compatibility
    case get_reqllm_or_env_value(server, key, nil) do
      ^default ->
        # Fallback to existing ETS-based lookup for backward compatibility
        get_env_value_from_ets(server, key, default)

      value ->
        value
    end
  end

  @doc """
  Gets environment-only values with ReqLLM integration support.

  This function extends get_env_value/3 with ReqLLM awareness for better
  integration with provider-specific environment variables.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to look up (as an atom)
    * `default` - The default value if key is not found

  Returns the environment value if found, otherwise returns the default value.
  """
  @spec get_env_value_with_reqllm(GenServer.server(), atom(), term()) :: term()
  def get_env_value_with_reqllm(server \\ @default_name, key, default \\ nil) when is_atom(key) do
    # Use the KeyringIntegration module for ReqLLM-aware environment resolution
    KeyringIntegration.get_env_value(server, key, default)
  end

  @doc """
  Sets a session-specific value that will override the environment value
  for the specified process.

  ## Parameters

    * `server` - The server to query (default: #{@default_name})
    * `key` - The key to set (as an atom)
    * `value` - The value to store
    * `pid` - The process ID to associate with this value (default: current process)

  Returns `:ok`.
  """
  @spec set_session_value(GenServer.server(), atom(), term(), pid()) :: :ok
  def set_session_value(server \\ @default_name, key, value, pid \\ self()) when is_atom(key) do
    # Apply security filtering before storing session values
    filtered_value = filter_sensitive_data(value)

    registry = GenServer.call(server, :get_registry)
    :ets.insert(registry, {{pid, key}, filtered_value})

    # Log session operations
    safe_log_key_operation(key, :set_session, :keyring)
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
  @spec get_session_value(GenServer.server(), atom(), pid()) :: term() | nil
  def get_session_value(server \\ @default_name, key, pid \\ self()) when is_atom(key) do
    registry = GenServer.call(server, :get_registry)

    case :ets.lookup(registry, {pid, key}) do
      [{{^pid, ^key}, value}] -> value
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
  @spec clear_session_value(GenServer.server(), atom(), pid()) :: :ok
  def clear_session_value(server \\ @default_name, key, pid \\ self()) when is_atom(key) do
    registry = GenServer.call(server, :get_registry)
    :ets.delete(registry, {pid, key})
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

  @doc """
  Sets a runtime configuration value through JidoKeys integration.

  This function provides enhanced runtime configuration capabilities through
  JidoKeys.put/2, allowing for dynamic configuration updates with security filtering.

  ## Parameters

    * `key` - The configuration key (atom or string)
    * `value` - The value to set (must be a binary)

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> Keyring.set_runtime_value(:openai_api_key, "sk-...")
      :ok

      iex> Keyring.set_runtime_value("test_config", "test_value")
      :ok
  """
  @spec set_runtime_value(atom() | String.t(), String.t()) :: :ok | {:error, term()}
  def set_runtime_value(key, value) when is_binary(value) do
    # Use Application environment for runtime configuration
    config_key = reqllm_config_key(key)
    Application.put_env(:req_llm, config_key, value)
    :ok
  rescue
    error ->
      Logger.warning("[Keyring] Failed to set runtime value for #{key}: #{inspect(error)}")
      {:error, error}
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
  def handle_call(
        {:set_test_env_vars, env_vars},
        _from,
        %{keys: keys, env_table: env_table} = state
      )
      when is_map(env_vars) do
    atom_env_vars =
      Enum.reduce(env_vars, %{}, fn {key, value}, acc ->
        atom_key = env_var_to_atom(key)
        Map.put(acc, atom_key, value)
      end)

    # Update both the state and the ETS table
    Enum.each(atom_env_vars, fn {key, value} ->
      :ets.insert(env_table, {key, value})
      # Also insert LiveBook prefixed version
      livebook_key = to_livebook_key(key)
      :ets.insert(env_table, {livebook_key, value})
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
    Dotenvy.env!(key, :string)
  rescue
    _ -> default
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
  @spec get_env_value_from_ets(GenServer.server(), atom(), term()) :: term()
  defp get_env_value_from_ets(server, key, default) do
    # Original ETS-based lookup logic preserved for backward compatibility
    case GenServer.call(server, :get_env_table) do
      {:error, :env_table_not_found} ->
        default

      env_table when is_atom(env_table) or is_reference(env_table) ->
        # First try the regular key in ETS (fast lookup)
        case :ets.lookup(env_table, key) do
          [{^key, value}] ->
            value

          [] ->
            # If not found, try the LiveBook prefixed version
            livebook_key = to_livebook_key(key)

            case :ets.lookup(env_table, livebook_key) do
              [{^livebook_key, value}] -> value
              [] -> default
            end
        end

      _ ->
        default
    end
  end

  @doc false
  @spec to_livebook_key(atom()) :: atom()
  defp to_livebook_key(key) do
    # Convert the key to a string, prefix with "lb_", and convert back to atom
    "lb_#{key}"
    |> String.to_atom()
  end

  # Helper functions for ReqLLM integration and security filtering

  defp get_reqllm_or_env_value(server, key, default) do
    # Try to get value through ReqLLM.Keys for API keys
    provider = extract_provider_from_key(key)

    if provider do
      case ReqLLM.Keys.get(provider, []) do
        {:ok, value, _source} ->
          if is_binary(value) and value != "" do
            value
          else
            get_env_value_from_ets(server, key, default)
          end

        {:error, _} ->
          get_env_value_from_ets(server, key, default)
      end
    else
      # For non-API keys, use standard environment lookup
      get_env_value_from_ets(server, key, default)
    end
  rescue
    _ -> get_env_value_from_ets(server, key, default)
  end

  @doc """
  Filters sensitive data for security purposes.

  ## Parameters
    * `data` - Data to filter (supports various types)

  ## Returns
    * Filtered data with sensitive patterns masked
  """
  @spec filter_sensitive_data(term()) :: term()
  def filter_sensitive_data(data) when is_binary(data) do
    # Apply basic filtering for sensitive patterns
    data_lower = String.downcase(data)

    sensitive_value_patterns = [
      "password",
      "secret",
      "token",
      "bearer",
      "api_key",
      "api-key",
      "apikey"
    ]

    # If the value itself contains sensitive terms and is short, filter it entirely
    should_filter_entire_value =
      Enum.any?(sensitive_value_patterns, fn pattern ->
        String.contains?(data_lower, pattern) and String.length(data) < 200
      end)

    if should_filter_entire_value do
      "[FILTERED]"
    else
      # Otherwise apply pattern-based filtering for specific tokens
      data
      |> String.replace(~r/sk-[a-zA-Z0-9]{6,}/, "[FILTERED]")
      |> String.replace(~r/xoxb-[a-zA-Z0-9\-]{20,}/, "[FILTERED]")
      |> String.replace(~r/ghp_[a-zA-Z0-9]{20,}/, "[FILTERED]")
      |> String.replace(~r/AKIA[0-9A-Z]{16}/, "[FILTERED]")
      |> String.replace(~r/bearer_token_[a-zA-Z0-9]+/i, "[FILTERED]")
    end
  end

  def filter_sensitive_data(data), do: data

  defp reqllm_config_key(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> String.replace("_api_key", "")
    |> String.to_atom()
    |> ReqLLM.Keys.config_key()
  end

  defp reqllm_config_key(key) when is_binary(key) do
    key
    |> String.replace("_api_key", "")
    |> String.to_atom()
    |> ReqLLM.Keys.config_key()
  end

  defp extract_provider_from_key(key) do
    key_str = key |> to_string() |> String.replace("_api_key", "")

    try do
      String.to_atom(key_str)
    rescue
      ArgumentError -> nil
    end
  end

  defp safe_log_key_operation(key, operation, source) do
    safe_key = filter_sensitive_data(to_string(key))
    Logger.debug("[Keyring] #{operation} operation for #{safe_key} from #{source}")
  end
end
