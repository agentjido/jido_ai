defmodule JidoKeys.LogFilter do
  @moduledoc """
  Logger filter to redact sensitive information from log messages.

  This filter automatically detects and redacts potential secrets, API keys,
  tokens, passwords, and other sensitive data from log messages to prevent
  accidental exposure in logs.

  ## Configuration

  The filter can be configured via application config:

      config :jido_keys, JidoKeys.LogFilter,
        enabled: true,
        redaction_text: "[REDACTED]"

  ## Integration

  To use this filter, add it to your Logger configuration:

      config :logger, :console,
        metadata_filter: {JidoKeys.LogFilter, :filter}

  ## Detection Patterns

  The filter detects secrets based on:
  - Environment variable names containing sensitive keywords
  - Key-value patterns in log messages
  - Common secret formats (API keys, tokens, etc.)
  """

  @type log_event :: :logger.log_event()
  @type filter_result :: :ignore | :stop | log_event()
  @type filter_config :: term()

  @redaction_text "[REDACTED]"

  @secret_keywords [
    "api_key",
    "api-key",
    "apikey",
    "token",
    "password",
    "secret",
    "auth",
    "credential",
    "private_key",
    "private-key",
    "access_token",
    "access-token",
    "refresh_token",
    "refresh-token",
    "jwt",
    "bearer",
    "oauth",
    "auth_token",
    "auth-token"
  ]

  @doc """
  :logger filter function that redacts sensitive information from log events.

  This function is compatible with Erlang/OTP :logger filters.
  """
  @spec filter(log_event(), filter_config()) :: filter_result()
  def filter(log_event, _filter_config) do
    if enabled?() do
      filter_log_event(log_event)
    else
      log_event
    end
  end

  @doc """
  Legacy Logger filter function for backward compatibility.
  """
  @spec filter(term()) :: term()
  def filter({level, pid, {logger, message, metadata, opts}} = event) when is_atom(level) do
    if enabled?() do
      filtered_message = redact_secrets(message)
      filtered_metadata = redact_metadata(metadata)

      {level, pid, {logger, filtered_message, filtered_metadata, opts}}
    else
      event
    end
  end

  def filter(event), do: event

  @doc false
  @spec filter_log_event(log_event()) :: log_event()
  defp filter_log_event(%{msg: msg, meta: meta} = log_event) do
    filtered_msg = filter_message(msg)
    filtered_meta = redact_metadata(meta)

    %{log_event | msg: filtered_msg, meta: filtered_meta}
  end

  defp filter_log_event(log_event), do: log_event

  @doc false
  @spec filter_message(term()) :: term()
  defp filter_message({:string, message}) when is_binary(message) do
    {:string, redact_secrets(message)}
  end

  defp filter_message({:report, report}) when is_map(report) do
    {:report, redact_metadata(report)}
  end

  defp filter_message({:report, report}) when is_list(report) do
    {:report, redact_metadata(report)}
  end

  defp filter_message(msg), do: msg

  @doc """
  Redacts sensitive information from a string message.

  ## Examples

      iex> JidoKeys.LogFilter.redact_secrets("API_KEY=sk-1234567890")
      "API_KEY=[REDACTED]"

      iex> JidoKeys.LogFilter.redact_secrets("Normal log message")
      "Normal log message"

  """
  @spec redact_secrets(String.t()) :: String.t()
  def redact_secrets(message) when is_binary(message) do
    redaction_text = get_redaction_text()

    message
    |> redact_key_value_patterns(redaction_text)
    |> redact_bearer_tokens(redaction_text)
    |> redact_url_credentials(redaction_text)
    |> redact_openai_keys(redaction_text)
  end

  def redact_secrets(message), do: message

  @doc false
  @spec redact_key_value_patterns(String.t(), String.t()) :: String.t()
  defp redact_key_value_patterns(message, redaction_text) do
    # Match key=value and key: value patterns for sensitive keys
    pattern =
      ~r/(?i)(\b(?:api[_-]?key|apikey|token|password|secret|auth[_-]?token|credential|private[_-]?key|jwt[_-]?secret)\b)(\s*[=:]\s*)(["\']?)([^"'\s\n\r,}]+)(["\']?)/

    Regex.replace(pattern, message, "\\1\\2#{redaction_text}")
  end

  @doc false
  @spec redact_bearer_tokens(String.t(), String.t()) :: String.t()
  defp redact_bearer_tokens(message, redaction_text) do
    pattern = ~r/\b(bearer|Bearer)\s+([A-Za-z0-9+\/=_-]+)/
    Regex.replace(pattern, message, "\\1 #{redaction_text}")
  end

  @doc false
  @spec redact_url_credentials(String.t(), String.t()) :: String.t()
  defp redact_url_credentials(message, redaction_text) do
    pattern = ~r/(\w+:\/\/[^:]+:)([^@\s]+)(@)/
    Regex.replace(pattern, message, "\\1#{redaction_text}\\3")
  end

  @doc false
  @spec redact_openai_keys(String.t(), String.t()) :: String.t()
  defp redact_openai_keys(message, redaction_text) do
    pattern = ~r/\b(sk-[A-Za-z0-9]{32,})\b/
    Regex.replace(pattern, message, redaction_text)
  end

  @doc """
  Redacts sensitive information from log metadata.

  ## Examples

      iex> metadata = %{api_key: "secret", normal_key: "value"}
      iex> JidoKeys.LogFilter.redact_metadata(metadata)
      %{api_key: "[REDACTED]", normal_key: "value"}

  """
  @spec redact_metadata(map() | keyword()) :: map() | keyword()
  def redact_metadata(metadata) when is_map(metadata) do
    redaction_text = get_redaction_text()

    metadata
    |> Enum.map(fn {key, value} ->
      if sensitive_key?(key) do
        {key, redaction_text}
      else
        {key, redact_if_string(value)}
      end
    end)
    |> Enum.into(%{})
  end

  def redact_metadata(metadata) when is_list(metadata) do
    redaction_text = get_redaction_text()

    Enum.map(metadata, fn
      {key, value} ->
        if sensitive_key?(key) do
          {key, redaction_text}
        else
          {key, redact_if_string(value)}
        end

      other ->
        other
    end)
  end

  def redact_metadata(metadata), do: metadata

  @doc """
  Checks if a key name indicates it might contain sensitive information.

  ## Examples

      iex> JidoKeys.LogFilter.sensitive_key?("api_key")
      true

      iex> JidoKeys.LogFilter.sensitive_key?(:password)
      true

      iex> JidoKeys.LogFilter.sensitive_key?("user_name")
      false

  """
  @spec sensitive_key?(atom() | String.t()) :: boolean()
  def sensitive_key?(key) when is_atom(key) do
    key |> Atom.to_string() |> sensitive_key?()
  end

  def sensitive_key?(key) when is_binary(key) do
    normalized_key = String.downcase(key)

    Enum.any?(@secret_keywords, fn keyword ->
      String.contains?(normalized_key, keyword)
    end)
  end

  def sensitive_key?(_), do: false

  @doc """
  Checks if logging filter is enabled.

  Defaults to true if not configured.

  ## Examples

      iex> JidoKeys.LogFilter.enabled?()
      true

  """
  @spec enabled?() :: boolean()
  def enabled? do
    Application.get_env(:jido_keys, __MODULE__, [])
    |> Keyword.get(:enabled, true)
  end

  @doc """
  Gets the redaction text to use for filtering.

  ## Examples

      iex> JidoKeys.LogFilter.get_redaction_text()
      "[REDACTED]"

  """
  @spec get_redaction_text() :: String.t()
  def get_redaction_text do
    Application.get_env(:jido_keys, __MODULE__, [])
    |> Keyword.get(:redaction_text, @redaction_text)
  end

  @doc """
  Configures the log filter for redacting secrets.

  ## Options

    * `:enabled` - Boolean to enable/disable filtering (default: true)
    * `:redaction_text` - Text to use for redacted values (default: "[REDACTED]")

  ## Examples

      iex> JidoKeys.LogFilter.configure(enabled: false)
      :ok

      iex> JidoKeys.LogFilter.configure(redaction_text: "***HIDDEN***")
      :ok

  """
  @spec configure(keyword()) :: :ok
  def configure(opts \\ []) do
    current_config = Application.get_env(:jido_keys, __MODULE__, [])
    new_config = Keyword.merge(current_config, opts)

    Application.put_env(:jido_keys, __MODULE__, new_config)

    :ok
  end

  @doc false
  @spec redact_if_string(term()) :: term()
  defp redact_if_string(value) when is_binary(value) do
    redact_secrets(value)
  end

  defp redact_if_string(value), do: value
end
