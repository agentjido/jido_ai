defmodule Jido.AI.ReqLlmBridge.ErrorHandler do
  @moduledoc """
  Centralized error handling and formatting for ReqLLM tool execution.

  This module provides consistent error formatting and handling across the ReqLLM
  integration system. It converts various error types from tool execution into
  standardized formats that are meaningful to both ReqLLM and consuming applications.

  ## Features

  - Standardized error format across all ReqLLM integration components
  - Sensitive information sanitization for security
  - Error categorization for better debugging and monitoring
  - Context preservation for error tracking
  - JSON-serializable error structures

  ## Usage

      # Format various error types
      formatted = ErrorHandler.format_error({:validation_error, "field", "message"})
      formatted = ErrorHandler.format_error({:timeout, 5000})
      formatted = ErrorHandler.format_error(%{type: "custom_error", details: "info"})

      # Sanitize errors for logging
      safe_error = ErrorHandler.sanitize_error_for_logging(error_with_secrets)
  """

  require Logger

  @type error_reason :: atom() | String.t() | map() | tuple()
  @type formatted_error :: map()

  @doc """
  Formats errors into a consistent structure for ReqLLM tool execution.

  Takes various error formats and converts them into a standardized structure
  that provides meaningful information while ensuring sensitive data is not exposed.
  The formatted errors are JSON-serializable and suitable for ReqLLM consumption.

  ## Parameters

  - `error`: Error in various formats (tuple, map, string, etc.)

  ## Returns

  - Formatted error map with consistent structure

  ## Examples

      iex> ErrorHandler.format_error({:validation_error, "name", "required field missing"})
      %{
        type: "validation_error",
        field: "name",
        message: "required field missing",
        category: "parameter_error"
      }

      iex> ErrorHandler.format_error({:timeout, 5000})
      %{
        type: "execution_timeout",
        message: "Operation timed out after 5000ms",
        category: "execution_error"
      }
  """
  @spec format_error(error_reason()) :: formatted_error()
  def format_error(error)

  # Validation errors
  def format_error({:validation_error, field, message}) do
    %{
      type: "validation_error",
      field: to_string(field),
      message: to_string(message),
      category: "parameter_error"
    }
  end

  def format_error({:parameter_validation_error, field, details}) do
    %{
      type: "parameter_validation_error",
      field: to_string(field),
      message: "Parameter validation failed",
      details: format_nested_error(details),
      category: "parameter_error"
    }
  end

  def format_error({:parameter_conversion_error, field, reason}) do
    %{
      type: "parameter_conversion_error",
      field: to_string(field),
      message: "Failed to convert parameter",
      details: format_nested_error(reason),
      category: "parameter_error"
    }
  end

  # Execution errors
  def format_error({:execution_timeout, timeout}) do
    %{
      type: "execution_timeout",
      message: "Operation timed out after #{timeout}ms",
      timeout: timeout,
      category: "execution_error"
    }
  end

  def format_error({:action_execution_error, reason}) do
    %{
      type: "action_execution_error",
      message: "Action execution failed",
      details: format_nested_error(reason),
      category: "execution_error"
    }
  end

  def format_error({:execution_exception, exception, stacktrace}) do
    %{
      type: "execution_exception",
      message: to_string(exception),
      stacktrace: format_stacktrace(stacktrace),
      category: "execution_error"
    }
  end

  # Serialization errors
  def format_error({:serialization_error, reason}) do
    %{
      type: "serialization_error",
      message: "Failed to serialize result to JSON",
      details: format_nested_error(reason),
      category: "serialization_error"
    }
  end

  # Schema and compatibility errors
  def format_error({:schema_error, reason}) do
    %{
      type: "schema_error",
      message: "Schema validation or conversion failed",
      details: format_nested_error(reason),
      category: "configuration_error"
    }
  end

  def format_error({:incompatible_action, action_module, reason}) do
    %{
      type: "incompatible_action",
      message: "Action module is not compatible with ReqLLM",
      action_module: to_string(action_module),
      details: format_nested_error(reason),
      category: "configuration_error"
    }
  end

  # Tool configuration errors
  def format_error({:tool_configuration_error, reason}) do
    %{
      type: "tool_configuration_error",
      message: "Tool configuration is invalid",
      details: format_nested_error(reason),
      category: "configuration_error"
    }
  end

  # Circuit breaker errors
  def format_error({:circuit_breaker_open, action_module}) do
    %{
      type: "circuit_breaker_open",
      message: "Tool temporarily unavailable due to repeated failures",
      action_module: to_string(action_module),
      category: "availability_error"
    }
  end

  # Generic map errors
  def format_error(%{type: type} = error) when is_map(error) do
    error
    |> Map.put(:category, categorize_error_type(type))
    |> sanitize_error_data()
  end

  def format_error(%{reason: reason} = error) when is_map(error) do
    error
    |> Map.put(:type, reason)
    |> Map.put(:category, categorize_error_type(reason))
    |> sanitize_error_data()
  end

  # String errors
  def format_error(error) when is_binary(error) do
    %{
      type: "generic_error",
      message: error,
      category: "unknown_error"
    }
  end

  # Atom errors
  def format_error(error) when is_atom(error) do
    %{
      type: to_string(error),
      message: "Error: #{error}",
      category: categorize_error_type(error)
    }
  end

  # Tuple errors (catch-all)
  def format_error({error_type, details}) when is_atom(error_type) do
    %{
      type: to_string(error_type),
      message: "Error occurred",
      details: format_nested_error(details),
      category: categorize_error_type(error_type)
    }
  end

  # Exception structs
  def format_error(%{__exception__: true} = exception) do
    %{
      type: "exception",
      message: Exception.message(exception),
      exception_type: exception.__struct__ |> to_string(),
      category: "execution_error"
    }
  end

  # Fallback for unknown error formats
  def format_error(error) do
    %{
      type: "unknown_error",
      message: "An unexpected error occurred",
      details: inspect(error),
      category: "unknown_error"
    }
  end

  @doc """
  Sanitizes error data by removing sensitive information.

  Removes or masks sensitive information like passwords, tokens, and API keys
  from error data to prevent accidental exposure in logs or error responses.

  ## Parameters

  - `error_data`: Error data that may contain sensitive information

  ## Returns

  - Sanitized error data safe for logging and external consumption

  ## Examples

      iex> error_with_secret = %{password: "secret123", message: "Auth failed"}
      iex> ErrorHandler.sanitize_error_for_logging(error_with_secret)
      %{password: "[REDACTED]", message: "Auth failed"}
  """
  @spec sanitize_error_for_logging(any()) :: any()
  def sanitize_error_for_logging(error_data) when is_map(error_data) do
    sensitive_keys = [:password, :token, :secret, :api_key, :private_key, :auth, :credential]

    error_data
    |> Enum.map(fn {key, value} ->
      if key in sensitive_keys or contains_sensitive_pattern?(to_string(key)) do
        {key, "[REDACTED]"}
      else
        {key, sanitize_error_for_logging(value)}
      end
    end)
    |> Map.new()
  end

  def sanitize_error_for_logging(error_data) when is_list(error_data) do
    Enum.map(error_data, &sanitize_error_for_logging/1)
  end

  def sanitize_error_for_logging(error_data) when is_binary(error_data) do
    error_data
    |> sanitize_sensitive_patterns()
  end

  def sanitize_error_for_logging(error_data), do: error_data

  @doc """
  Categorizes errors into logical groups for monitoring and debugging.

  Groups errors into categories that help with debugging, monitoring, and
  error handling strategies. This is useful for error aggregation and
  alerting systems.

  ## Parameters

  - `error_type`: The error type (atom or string)

  ## Returns

  - String category name

  ## Examples

      iex> ErrorHandler.categorize_error_type("validation_error")
      "parameter_error"

      iex> ErrorHandler.categorize_error_type("timeout")
      "execution_error"
  """
  @spec categorize_error_type(atom() | String.t()) :: String.t()
  def categorize_error_type(error_type) do
    error_string = to_string(error_type)

    cond do
      String.contains?(error_string, ["validation", "parameter", "conversion"]) ->
        "parameter_error"

      String.contains?(error_string, ["timeout", "execution", "action", "exception"]) ->
        "execution_error"

      String.contains?(error_string, ["serialization", "json", "encoding"]) ->
        "serialization_error"

      String.contains?(error_string, ["schema", "configuration", "incompatible"]) ->
        "configuration_error"

      String.contains?(error_string, ["circuit", "availability", "service"]) ->
        "availability_error"

      String.contains?(error_string, ["network", "connection", "transport"]) ->
        "network_error"

      true ->
        "unknown_error"
    end
  end

  @doc """
  Creates a standardized error response for tool execution failures.

  Provides a consistent error response format that can be returned by tool
  callbacks when execution fails. This ensures error responses are properly
  formatted for ReqLLM consumption.

  ## Parameters

  - `error`: The original error
  - `context`: Additional context information (optional)

  ## Returns

  - Standardized error response map

  ## Examples

      iex> error_response = ErrorHandler.create_tool_error_response(
      ...>   {:validation_error, "name", "required"},
      ...>   %{action_module: MyAction, user_id: 123}
      ...> )
      iex> error_response.error
      true
  """
  @spec create_tool_error_response(any(), map()) :: map()
  def create_tool_error_response(error, context \\ %{}) do
    formatted_error = format_error(error)

    %{
      error: true,
      type: formatted_error.type,
      message: formatted_error.message,
      category: formatted_error.category,
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      context: sanitize_context(context)
    }
    |> merge_error_details(formatted_error)
  end

  # Private helper functions

  defp format_nested_error(error) when is_map(error) do
    sanitize_error_data(error)
  end

  defp format_nested_error(error) when is_binary(error) do
    error
  end

  defp format_nested_error(error) do
    inspect(error)
  end

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    # Limit stacktrace length
    |> Enum.take(10)
    |> Enum.map(&Exception.format_stacktrace_entry/1)
  end

  defp format_stacktrace(stacktrace) do
    inspect(stacktrace)
  end

  defp sanitize_error_data(error_data) when is_map(error_data) do
    error_data
    # Remove internal Elixir fields
    |> Map.drop([:__struct__, :__exception__])
    |> sanitize_error_for_logging()
  end

  defp contains_sensitive_pattern?(key_string) do
    sensitive_patterns = ~w[password pass pwd token secret key auth credential]
    Enum.any?(sensitive_patterns, &String.contains?(String.downcase(key_string), &1))
  end

  defp sanitize_sensitive_patterns(text) do
    # Redact common sensitive patterns in text
    text
    |> String.replace(~r/password[=:]\s*\S+/i, "password=[REDACTED]")
    |> String.replace(~r/token[=:]\s*\S+/i, "token=[REDACTED]")
    |> String.replace(~r/api_?key[=:]\s*\S+/i, "api_key=[REDACTED]")
  end

  defp sanitize_context(context) when is_map(context) do
    context
    |> Map.drop([:password, :token, :secret, :api_key, :private_key])
    |> Map.take([:action_module, :user_id, :request_id, :timestamp])
  end

  defp sanitize_context(context), do: context

  defp merge_error_details(base_response, formatted_error) do
    case Map.get(formatted_error, :details) do
      nil -> base_response
      details -> Map.put(base_response, :details, details)
    end
    |> case do
      response ->
        case Map.get(formatted_error, :field) do
          nil -> response
          field -> Map.put(response, :field, field)
        end
    end
  end
end
