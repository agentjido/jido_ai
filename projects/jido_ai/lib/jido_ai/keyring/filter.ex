defmodule Jido.AI.Keyring.Filter do
  @moduledoc """
  Logger filter that sanitizes sensitive data from log output.

  This filter automatically redacts sensitive information like API keys, tokens,
  passwords, and secrets from log messages to prevent accidental exposure in
  log files or monitoring systems.

  ## Sensitive Keys

  The filter identifies and redacts the following patterns:
  - API keys (any key containing "api_key", "apikey", "key")
  - Tokens (any key containing "token", "auth", "bearer")
  - Passwords and secrets (any key containing "password", "secret", "pass")
  - Private keys and certificates (any key containing "private", "cert", "pem")

  ## Usage

  Add to your logger configuration:

      config :logger, :console,
        format: {Jido.AI.Keyring.Filter, :format}

  """

  @redacted_text "[REDACTED]"

  # Get sensitive patterns - defined as function to avoid compile-time reference issues
  defp sensitive_patterns do
    [
      ~r/(^|[^a-z0-9])api[_-]?key($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])(access|session)?[_-]?token($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])bearer($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])auth($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])password|pass(word)?($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])secret($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])(private|encryption|signing|access|session)?[_-]?key($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])cert($|[^a-z0-9])/i,
      ~r/(^|[^a-z0-9])pem($|[^a-z0-9])/i
    ]
  end

  @doc """
  Custom format function for logger that automatically filters sensitive data.

  This function is used as a logger formatter to automatically sanitize
  log messages and metadata before they are output.
  """
  @spec format(Logger.level(), Logger.message(), term(), Logger.metadata()) ::
          IO.chardata()
  def format(level, message, _ts, metadata) do
    msg = sanitize_logger_message(message)
    md = sanitize_data(metadata)
    ["[", to_string(level), "] ", msg, " ", inspect(md), "\n"] |> IO.iodata_to_binary()
  end

  @doc """
  Filters sensitive data from logger events.

  This function processes logger events and redacts any sensitive information
  found in the message or metadata.

  ## Parameters

    * `log_event` - The logger event tuple to filter

  Returns the filtered log event with sensitive data redacted.
  """
  @spec filter_sensitive_data(tuple()) :: tuple()
  def filter_sensitive_data(log_event) do
    case log_event do
      {level, gl, {Logger, msg, ts, md}} ->
        filtered_msg = sanitize_data(msg)
        filtered_md = sanitize_data(md)
        {level, gl, {Logger, filtered_msg, ts, filtered_md}}

      log_event ->
        log_event
    end
  end

  @doc """
  Sanitizes data by redacting sensitive information.

  This function recursively processes various data structures (maps, keyword lists,
  tuples, lists, strings) to find and redact sensitive data.

  ## Parameters

    * `data` - The data structure to sanitize

  Returns the sanitized data with sensitive information redacted.
  """
  @spec sanitize_data(term()) :: term()
  def sanitize_data(data) when is_map(data) do
    Enum.reduce(data, %{}, fn {key, value}, acc ->
      if sensitive_key?(key) do
        Map.put(acc, key, @redacted_text)
      else
        Map.put(acc, key, sanitize_data(value))
      end
    end)
  end

  def sanitize_data(data) when is_list(data) do
    if Keyword.keyword?(data) do
      # Handle keyword lists specially
      Enum.map(data, fn {key, value} ->
        if sensitive_key?(key) do
          {key, @redacted_text}
        else
          {key, sanitize_data(value)}
        end
      end)
    else
      # Handle regular lists - but only if it's actually a list
      try do
        Enum.map(data, &sanitize_data/1)
      rescue
        _ -> data
      end
    end
  end

  def sanitize_data(data) when is_tuple(data) do
    data
    |> Tuple.to_list()
    |> Enum.map(&sanitize_data/1)
    |> List.to_tuple()
  end

  def sanitize_data(data) when is_binary(data) do
    # Check if the string looks like a sensitive value (long base64-like strings)
    if looks_like_sensitive_value?(data) do
      @redacted_text
    else
      data
    end
  end

  def sanitize_data(data) when is_atom(data), do: data
  def sanitize_data(data) when is_number(data), do: data
  def sanitize_data(data) when is_pid(data), do: data
  def sanitize_data(data) when is_reference(data), do: data
  def sanitize_data(data) when is_function(data), do: data

  def sanitize_data(data), do: data

  @doc """
  Checks if a key indicates sensitive data.

  ## Parameters

    * `key` - The key to check (atom, string, or other term)

  Returns `true` if the key indicates sensitive data, `false` otherwise.
  """
  @spec sensitive_key?(term()) :: boolean()
  def sensitive_key?(key) when is_atom(key) do
    key
    |> Atom.to_string()
    |> sensitive_key?()
  end

  def sensitive_key?(key) when is_binary(key) do
    Enum.any?(sensitive_patterns(), &Regex.match?(&1, key))
  end

  def sensitive_key?(_), do: false

  @doc """
  Checks if a string value looks like sensitive data.

  This heuristic identifies potential API keys, tokens, or other secrets
  based on common patterns (long alphanumeric strings, base64-like format).

  ## Parameters

    * `value` - The string value to check

  Returns `true` if the value looks like sensitive data, `false` otherwise.
  """
  @spec looks_like_sensitive_value?(binary()) :: boolean()
  def looks_like_sensitive_value?(value) when is_binary(value) do
    # Check for common patterns of API keys and tokens
    cond do
      # Long base64-like strings (common for API keys)
      String.length(value) > 20 and Regex.match?(~r/^[A-Za-z0-9+\/=_-]+$/, value) ->
        true

      String.length(value) > 50 and String.contains?(value, ".") and
          Regex.match?(~r/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/, value) ->
        true

      Regex.match?(~r/^(gh[pousr]_|glpat-|gho_|ghu_|ghs_|ghr_)/, value) ->
        true

      Regex.match?(~r/^AKIA[0-9A-Z]{16}$/, value) ->
        true

      Regex.match?(~r/^sk-[A-Za-z0-9]{32,}$/, value) ->
        true

      true ->
        false
    end
  end

  def looks_like_sensitive_value?(_), do: false

  defp sanitize_logger_message(fun) when is_function(fun, 0), do: sanitize_logger_message(fun.())

  defp sanitize_logger_message(iodata) when is_binary(iodata) or is_list(iodata),
    do: iodata |> IO.iodata_to_binary() |> sanitize_data()

  defp sanitize_logger_message(other), do: other |> to_string() |> sanitize_data()
end
