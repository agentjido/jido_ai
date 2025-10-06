defmodule Jido.AI.Keyring.JidoKeysHybrid do
  @moduledoc """
  Hybrid integration module that bridges Jido.AI.Keyring with JidoKeys
  while maintaining full backward compatibility and process isolation.

  This module implements the delegation pattern where:
  - Global configuration delegates to JidoKeys for enhanced security
  - Process-specific sessions remain in Jido's ETS system
  - All existing APIs work unchanged

  ## Features

  - Enhanced security through JidoKeys credential filtering
  - Runtime configuration updates via JidoKeys.put/2
  - Safe atom conversion to prevent memory leaks
  - Comprehensive error handling with detailed messaging
  - Full backward compatibility with existing Keyring APIs

  ## Usage

  This module is used internally by Jido.AI.Keyring to provide enhanced
  functionality while maintaining API compatibility.
  """

  require Logger

  @doc """
  Gets a global configuration value through JidoKeys with enhanced security filtering.

  This function delegates to JidoKeys for global configuration lookup while
  applying security filtering to prevent sensitive data exposure.

  ## Parameters

    * `key` - The configuration key (atom or string)
    * `default` - Default value if key is not found

  ## Returns

    * The filtered value if found, otherwise the default value

  ## Examples

      iex> JidoKeysHybrid.get_global_value(:openai_api_key, nil)
      "[FILTERED]"

      iex> JidoKeysHybrid.get_global_value(:normal_key, "default")
      "some_value"
  """
  @spec get_global_value(atom() | String.t(), term()) :: term()
  def get_global_value(key, default) do
    normalized_key = normalize_key(key)

    case get_jido_keys_value(normalized_key) do
      nil -> default
      value -> filter_sensitive_value(value, key)
    end
  end

  @doc """
  Sets a runtime configuration value through JidoKeys.

  Uses JidoKeys.put/2 for runtime configuration updates with
  automatic credential filtering before storage.

  ## Parameters

    * `key` - The configuration key
    * `value` - The value to set (must be a binary)

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> JidoKeysHybrid.set_runtime_value(:test_key, "test_value")
      :ok
  """
  @spec set_runtime_value(atom() | String.t(), String.t()) :: :ok | {:error, term()}
  def set_runtime_value(key, value) when is_binary(value) do
    normalized_key = normalize_key(key)
    filtered_value = filter_sensitive_value(value, key)

    try do
      JidoKeys.put(normalized_key, filtered_value)
      :ok
    rescue
      error ->
        Logger.warning(
          "[Keyring-JidoKeys] Failed to set runtime value for #{normalized_key}: #{inspect(error)}"
        )

        {:error, error}
    end
  end

  @doc """
  Gets a filtered value with JidoKeys security features applied.

  This is the primary interface for getting configuration values with
  enhanced security filtering and safe error handling.

  ## Parameters

    * `key` - The configuration key
    * `default` - Default value if not found

  ## Returns

    * Filtered configuration value or default
  """
  @spec get_filtered_value(atom() | String.t(), term()) :: term()
  def get_filtered_value(key, default) do
    get_global_value(key, default)
  end

  @doc """
  Validates and converts a key to a safe atom using JidoKeys.

  Uses JidoKeys.to_llm_atom/1 for safe atom conversion that prevents
  memory leaks from untrusted input.

  ## Parameters

    * `key` - The key to validate and convert

  ## Returns

    * `{:ok, atom()}` on successful conversion
    * `{:error, reason}` on failure
  """
  @spec validate_and_convert_key(term()) :: {:ok, atom()} | {:error, term()}
  def validate_and_convert_key(key) when is_atom(key), do: {:ok, key}

  def validate_and_convert_key(key) when is_binary(key) do
    case JidoKeys.to_llm_atom(key) do
      atom when is_atom(atom) -> {:ok, atom}
      # If string returned, try existing atom
      ^key -> {:ok, String.to_existing_atom(key)}
    end
  rescue
    ArgumentError ->
      # Key doesn't exist as atom, return as string for compatibility
      {:ok, key}

    error ->
      {:error, error}
  end

  def validate_and_convert_key(_), do: {:error, :invalid_key_type}

  @doc """
  Gets a value with session fallback functionality.

  Checks session values first (maintaining process isolation), then
  falls back to JidoKeys global configuration.

  ## Parameters

    * `server` - The Keyring server
    * `key` - The configuration key
    * `default` - Default value
    * `pid` - Process ID for session isolation

  ## Returns

    * The resolved value with proper precedence
  """
  @spec get_with_session_fallback(GenServer.server(), atom(), term(), pid()) :: term()
  def get_with_session_fallback(server, key, default, pid) do
    case get_session_value_direct(server, key, pid) do
      nil -> get_global_value(key, default)
      session_value -> filter_sensitive_value(session_value, key)
    end
  end

  @doc """
  Ensures session isolation by maintaining ETS-based storage.

  This function maintains the existing session isolation patterns
  while adding JidoKeys security filtering.

  ## Parameters

    * `server` - The Keyring server
    * `key` - The session key
    * `value` - The value to store
    * `pid` - Process ID for isolation

  ## Returns

    * `:ok` on success
    * `{:error, reason}` on failure
  """
  @spec ensure_session_isolation(GenServer.server(), atom(), term(), pid()) ::
          :ok | {:error, term()}
  def ensure_session_isolation(server, key, value, pid) do
    registry = GenServer.call(server, :get_registry)
    filtered_value = filter_sensitive_value(value, key)

    :ets.insert(registry, {{pid, key}, filtered_value})
    :ok
  rescue
    error ->
      {:error, error}
  catch
    :exit, reason ->
      {:error, reason}
  end

  @doc """
  Filters sensitive data using JidoKeys security features.

  Applies comprehensive credential filtering to prevent sensitive
  data exposure in logs, storage, or external interfaces.

  ## Parameters

    * `data` - Data to filter (any type)

  ## Returns

    * Filtered data with sensitive patterns masked
  """
  @spec filter_sensitive_data(term()) :: term()
  def filter_sensitive_data(data) when is_binary(data) do
    # Apply JidoKeys filtering if available
    cond do
      function_exported?(JidoKeys.LogFilter, :filter, 2) ->
        JidoKeys.LogFilter.filter(data, :all)

      function_exported?(JidoKeys.LogFilter, :filter, 1) ->
        JidoKeys.LogFilter.filter(data)

      true ->
        # Fallback filtering for basic patterns
        apply_basic_filtering(data)
    end
  end

  def filter_sensitive_data(data), do: data

  @doc """
  Safely logs key operations with automatic credential filtering.

  Provides enhanced logging for debugging while ensuring no sensitive
  data is exposed in log output.

  ## Parameters

    * `key` - The key being operated on
    * `operation` - The type of operation
    * `source` - The source of the operation
  """
  @spec safe_log_key_operation(atom() | String.t(), atom(), atom()) :: :ok
  def safe_log_key_operation(key, operation, source) do
    safe_key = filter_sensitive_data(to_string(key))
    Logger.debug("[Keyring-JidoKeys] #{operation} operation for #{safe_key} from #{source}")
  end

  # Private helper functions

  @spec normalize_key(atom() | String.t()) :: atom() | String.t()
  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    # Use JidoKeys safe atom conversion if available
    case validate_and_convert_key(key) do
      {:ok, atom} when is_atom(atom) -> atom
      {:ok, string} when is_binary(string) -> string
      # Return original key on error
      {:error, _} -> key
    end
  end

  defp normalize_key(key), do: key

  @spec get_jido_keys_value(atom() | String.t()) :: term() | nil
  defp get_jido_keys_value(key) do
    case JidoKeys.get(key, nil) do
      nil -> nil
      value -> value
    end
  rescue
    error ->
      Logger.debug("[Keyring-JidoKeys] Error getting value for #{key}: #{inspect(error)}")
      nil
  end

  @spec filter_sensitive_value(term(), atom() | String.t()) :: term()
  defp filter_sensitive_value(value, key) when is_binary(value) do
    if sensitive_key?(key) do
      filter_sensitive_data(value)
    else
      value
    end
  end

  defp filter_sensitive_value(value, _key), do: value

  @spec sensitive_key?(atom() | String.t()) :: boolean()
  defp sensitive_key?(key) when is_atom(key) do
    sensitive_key?(Atom.to_string(key))
  end

  defp sensitive_key?(key) when is_binary(key) do
    key_lower = String.downcase(key)

    sensitive_patterns = [
      "api_key",
      "password",
      "secret",
      "token",
      "auth",
      "credential",
      "private_key",
      "access_key",
      "bearer",
      "jwt",
      "oauth",
      "client_secret"
    ]

    Enum.any?(sensitive_patterns, &String.contains?(key_lower, &1))
  end

  defp sensitive_key?(_), do: false

  @spec get_session_value_direct(GenServer.server(), atom(), pid()) :: term() | nil
  defp get_session_value_direct(server, key, pid) do
    registry = GenServer.call(server, :get_registry)

    case :ets.lookup(registry, {pid, key}) do
      [{{^pid, ^key}, value}] -> value
      [] -> nil
    end
  rescue
    error ->
      Logger.debug("[Keyring-JidoKeys] Error getting session value for #{key}: #{inspect(error)}")

      nil
  end

  @spec apply_basic_filtering(String.t()) :: String.t()
  defp apply_basic_filtering(data) do
    # Basic fallback filtering for common patterns
    data
    |> String.replace(~r/sk-[a-zA-Z0-9]{20,}/, "[FILTERED]")
    |> String.replace(~r/xoxb-[a-zA-Z0-9\-]{50,}/, "[FILTERED]")
    |> String.replace(~r/ghp_[a-zA-Z0-9]{36}/, "[FILTERED]")
    |> String.replace(~r/AKIA[0-9A-Z]{16}/, "[FILTERED]")
  end
end
