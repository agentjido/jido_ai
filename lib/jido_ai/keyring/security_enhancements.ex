defmodule Jido.AI.Keyring.SecurityEnhancements do
  @moduledoc """
  Security enhancements through JidoKeys integration.

  Provides comprehensive credential filtering, log redaction, and
  secure handling of sensitive data throughout the keyring system.

  ## Features

  - Automatic credential filtering for sensitive patterns
  - Safe error handling without information disclosure
  - Enhanced logging with redaction capabilities
  - Input validation and sanitization
  - Process isolation verification

  ## Usage

  This module is used internally by the Keyring system to provide
  enhanced security features while maintaining compatibility.
  """

  require Logger
  alias Jido.AI.Keyring.JidoKeysHybrid

  @sensitive_patterns [
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
    "client_secret",
    "session_token",
    "refresh_token",
    "access_token"
  ]

  @doc """
  Filters credential data comprehensively to prevent exposure.

  Applies multiple layers of filtering to ensure sensitive data
  is properly masked across different data types.

  ## Parameters

    * `data` - Data to filter (supports various types)

  ## Returns

    * Filtered data with sensitive patterns masked

  ## Examples

      iex> SecurityEnhancements.filter_credential_data("api_key=sk-1234")
      "api_key=[FILTERED]"

      iex> SecurityEnhancements.filter_credential_data(%{password: "secret123"})
      %{password: "[FILTERED]"}
  """
  @spec filter_credential_data(term()) :: term()
  def filter_credential_data(data) when is_binary(data) do
    JidoKeysHybrid.filter_sensitive_data(data)
  end

  def filter_credential_data(data) when is_map(data) do
    # Filter map values that might contain credentials
    Map.new(data, fn {key, value} ->
      filtered_value =
        case is_sensitive_key?(key) do
          true -> filter_credential_data(to_string(value))
          false -> value
        end

      {key, filtered_value}
    end)
  end

  def filter_credential_data(data) when is_list(data) do
    # Filter list items that might be sensitive
    Enum.map(data, &filter_credential_data/1)
  end

  def filter_credential_data(data), do: data

  @doc """
  Determines if a key represents sensitive information.

  Checks key names against common patterns used for sensitive data
  to determine if filtering should be applied.

  ## Parameters

    * `key` - The key to check (atom or string)

  ## Returns

    * `true` if key appears to be sensitive, `false` otherwise
  """
  @spec is_sensitive_key?(atom() | String.t()) :: boolean()
  def is_sensitive_key?(key) when is_atom(key) do
    is_sensitive_key?(Atom.to_string(key))
  end

  def is_sensitive_key?(key) when is_binary(key) do
    key_lower = String.downcase(key)
    Enum.any?(@sensitive_patterns, &String.contains?(key_lower, &1))
  end

  def is_sensitive_key?(_), do: false

  @doc """
  Logs operations safely with automatic credential filtering.

  Provides enhanced logging for debugging while ensuring no sensitive
  data is exposed in log output.

  ## Parameters

    * `operation` - The type of operation being logged
    * `key` - The key being operated on
    * `details` - Additional details (map)

  ## Examples

      iex> SecurityEnhancements.safe_log_operation(:get, :api_key, %{source: :session})
      :ok
  """
  @spec safe_log_operation(atom(), atom() | String.t(), map()) :: :ok
  def safe_log_operation(operation, key, details \\ %{}) do
    # Enhanced logging with automatic credential filtering
    filtered_details = filter_credential_data(details)
    safe_key = filter_credential_data(to_string(key))

    Logger.debug(
      "[Keyring-Security] #{operation} operation for #{safe_key}",
      filtered_details
    )
  end

  @doc """
  Validates and filters input data comprehensively.

  Provides comprehensive input validation and filtering to ensure
  data integrity and security before processing.

  ## Parameters

    * `key` - The key to validate
    * `value` - The value to validate and filter

  ## Returns

    * `{:ok, validated_key, filtered_value}` on success
    * `{:error, reason}` on validation failure
  """
  @spec validate_and_filter_input(term(), term()) :: {:ok, atom(), term()} | {:error, term()}
  def validate_and_filter_input(key, value) do
    with {:ok, validated_key} <- validate_key(key),
         {:ok, filtered_value} <- validate_and_filter_value(value) do
      {:ok, validated_key, filtered_value}
    end
  end

  @doc """
  Handles keyring errors with security-aware messaging.

  Provides enhanced error handling with automatic credential filtering
  and prevents information disclosure through error messages.

  ## Parameters

    * `operation` - The operation that failed
    * `key` - The key involved in the failure
    * `error` - The original error
    * `context` - Additional context (optional)

  ## Returns

    * Sanitized error tuple
  """
  @spec handle_keyring_error(atom(), atom() | String.t(), term(), map()) :: {:error, String.t()}
  def handle_keyring_error(operation, key, error, context \\ %{}) do
    # Enhanced error handling with automatic credential filtering
    safe_key = filter_credential_data(to_string(key))
    safe_context = filter_credential_data(context)

    error_details = %{
      operation: operation,
      key: safe_key,
      error: sanitize_error(error),
      context: safe_context,
      timestamp: DateTime.utc_now()
    }

    # Log with redaction
    log_with_redaction(:error, "Keyring operation failed", error_details)

    # Return filtered error for external consumption
    format_safe_error(operation, safe_key, error)
  end

  @doc """
  Logs messages with comprehensive redaction applied.

  Applies multiple layers of filtering and redaction to log messages
  to prevent any sensitive data exposure.

  ## Parameters

    * `level` - Log level (atom)
    * `message` - Message to log
    * `metadata` - Additional metadata (list)
  """
  @spec log_with_redaction(atom(), String.t(), list() | map()) :: :ok
  def log_with_redaction(level, message, metadata \\ []) do
    # Apply comprehensive filtering before logging
    filtered_message = filter_credential_data(message)
    filtered_metadata = filter_log_metadata(metadata)

    Logger.log(level, filtered_message, [{:keyring_filtered, true} | filtered_metadata])
  end

  @doc """
  Validates that process isolation is maintained properly.

  Comprehensive validation of process isolation to ensure session
  values don't leak between processes.

  ## Parameters

    * `server` - The Keyring server
    * `test_key` - Key to use for testing
    * `test_value` - Value to use for testing

  ## Returns

    * `:ok` if isolation is properly maintained
    * `{:error, reason}` if isolation is compromised
  """
  @spec validate_process_isolation(GenServer.server(), atom(), String.t()) ::
          :ok | {:error, term()}
  def validate_process_isolation(server, test_key, test_value) do
    try do
      parent_pid = self()

      # Set value in current process
      :ok = Jido.AI.Keyring.set_session_value(server, test_key, test_value, parent_pid)

      # Spawn child process and verify isolation
      child_task =
        Task.async(fn ->
          child_pid = self()

          # Child should not see parent's session value
          child_value = Jido.AI.Keyring.get_session_value(server, test_key, child_pid)

          # Set different value in child
          child_test_value = "child_#{test_value}"
          :ok = Jido.AI.Keyring.set_session_value(server, test_key, child_test_value, child_pid)

          {child_value, child_test_value}
        end)

      {child_session_value, _child_set_value} = Task.await(child_task)

      # Verify isolation
      cond do
        child_session_value != nil ->
          {:error, "Session values leaked between processes"}

        true ->
          # Verify parent value unchanged
          parent_value = Jido.AI.Keyring.get_session_value(server, test_key, parent_pid)

          if parent_value == test_value do
            :ok
          else
            {:error, "Parent session value corrupted"}
          end
      end
    rescue
      error ->
        {:error, error}
    end
  end

  @doc """
  Tests comprehensive credential filtering functionality.

  Runs a series of tests to verify that credential filtering
  is working correctly across different scenarios.

  ## Returns

    * `:ok` if all filtering tests pass
    * `{:error, failed_tests}` if any tests fail
  """
  @spec test_credential_filtering() :: :ok | {:error, list()}
  def test_credential_filtering() do
    test_cases = [
      {"api_key_test", "sk-1234567890abcdef", true},
      {"normal_key", "normal_value", false},
      {"password_field", "super_secret_password", true},
      {"auth_token", "bearer_token_12345", true},
      {"regular_config", "some_config_value", false}
    ]

    failed_tests =
      Enum.reduce(test_cases, [], fn {key, value, should_filter}, acc ->
        filtered_value = filter_credential_data(value)

        case {should_filter, filtered_value == value} do
          {true, true} ->
            # Expected filtering but value unchanged
            [{"#{key}: expected filtering but value unchanged", value, filtered_value} | acc]

          {false, false} ->
            # Expected no filtering but value changed
            [{"#{key}: expected no filtering but value changed", value, filtered_value} | acc]

          _ ->
            # Test passed
            acc
        end
      end)

    case failed_tests do
      [] -> :ok
      failures -> {:error, failures}
    end
  end

  # Private helper functions

  @spec validate_key(term()) :: {:ok, atom()} | {:error, term()}
  defp validate_key(key) when is_atom(key), do: {:ok, key}

  defp validate_key(key) when is_binary(key) do
    case JidoKeysHybrid.validate_and_convert_key(key) do
      {:ok, atom} -> {:ok, atom}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_key(_), do: {:error, :invalid_key_type}

  @spec validate_and_filter_value(term()) :: {:ok, term()} | {:error, term()}
  defp validate_and_filter_value(value) when is_binary(value) do
    # Apply credential filtering to values before storage/processing
    filtered = filter_credential_data(value)
    {:ok, filtered}
  end

  defp validate_and_filter_value(value), do: {:ok, value}

  @spec sanitize_error(term()) :: term()
  defp sanitize_error({:error, reason}) when is_binary(reason) do
    filter_credential_data(reason)
  end

  defp sanitize_error(error), do: error

  @spec format_safe_error(atom(), String.t(), term()) :: {:error, String.t()}
  defp format_safe_error(operation, key, _original_error) do
    # Return generic error messages to prevent information leakage
    {:error, "#{operation} operation failed for key: #{key}"}
  end

  @spec filter_log_metadata(term()) :: list()
  defp filter_log_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.to_list()
    |> filter_log_metadata()
  end

  defp filter_log_metadata(metadata) when is_list(metadata) do
    Enum.map(metadata, fn
      {key, value} when is_binary(value) ->
        {key, filter_credential_data(value)}

      {key, value} when is_map(value) ->
        {key, filter_credential_data(value)}

      item ->
        item
    end)
  end

  defp filter_log_metadata(metadata), do: [metadata]
end
