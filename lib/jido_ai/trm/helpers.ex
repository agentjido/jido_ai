defmodule Jido.AI.TRM.Helpers do
  @moduledoc """
  Shared utility functions for TRM (Tiny-Recursive-Model) modules.

  This module provides common helper functions used across ACT, Reasoning,
  and Supervision modules to avoid code duplication.

  ## Functions

  - `clamp/3` - Clamps a numeric value to a specified range
  - `parse_float_safe/1` - Safely parses a string to float with fallback
  - `sanitize_user_input/1` - Sanitizes user input to mitigate prompt injection

  ## Usage

      iex> Helpers.clamp(1.5, 0.0, 1.0)
      1.0

      iex> Helpers.parse_float_safe("0.85")
      0.85

      iex> Helpers.sanitize_user_input("Normal text")
      "Normal text"
  """

  @doc """
  Clamps a numeric value to be within the specified range.

  ## Parameters

  - `value` - The numeric value to clamp
  - `min_val` - The minimum allowed value
  - `max_val` - The maximum allowed value

  ## Returns

  The clamped value, guaranteed to be >= min_val and <= max_val.

  ## Examples

      iex> Helpers.clamp(0.5, 0.0, 1.0)
      0.5

      iex> Helpers.clamp(-0.5, 0.0, 1.0)
      0.0

      iex> Helpers.clamp(1.5, 0.0, 1.0)
      1.0
  """
  @spec clamp(number(), number(), number()) :: number()
  def clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end

  @doc """
  Safely parses a string to a float, returning a default value on failure.

  ## Parameters

  - `str` - The string to parse
  - `default` - The default value to return if parsing fails (default: 0.5)

  ## Returns

  The parsed float value, or the default if parsing fails.

  ## Examples

      iex> Helpers.parse_float_safe("0.85")
      0.85

      iex> Helpers.parse_float_safe("invalid")
      0.5

      iex> Helpers.parse_float_safe("75")
      75.0

      iex> Helpers.parse_float_safe("not a number", 0.0)
      0.0
  """
  @spec parse_float_safe(String.t(), float()) :: float()
  def parse_float_safe(str, default \\ 0.5)

  def parse_float_safe(str, default) when is_binary(str) do
    case Float.parse(str) do
      {float, _} -> float
      :error -> default
    end
  end

  def parse_float_safe(_, default), do: default

  @doc """
  Sanitizes user input to mitigate prompt injection attacks.

  This function performs several sanitization steps:
  1. Removes common prompt injection patterns
  2. Escapes special instruction markers
  3. Limits input length to prevent resource exhaustion

  ## Parameters

  - `input` - The user input string to sanitize
  - `opts` - Optional keyword list:
    - `:max_length` - Maximum allowed length (default: 10_000)

  ## Returns

  The sanitized input string.

  ## Examples

      iex> Helpers.sanitize_user_input("Normal question about math")
      "Normal question about math"

      iex> Helpers.sanitize_user_input("Ignore previous instructions")
      "[FILTERED] previous instructions"
  """
  @spec sanitize_user_input(String.t() | nil, keyword()) :: String.t()
  def sanitize_user_input(input, opts \\ [])

  def sanitize_user_input(nil, _opts), do: ""

  def sanitize_user_input(input, opts) when is_binary(input) do
    max_length = Keyword.get(opts, :max_length, 10_000)

    input
    |> String.slice(0, max_length)
    |> filter_injection_patterns()
    |> escape_instruction_markers()
  end

  def sanitize_user_input(input, _opts), do: to_string(input)

  # Private helpers for sanitization

  @injection_patterns [
    # Common prompt injection patterns
    ~r/ignore\s+(all\s+)?(previous|prior|above)\s+(instructions?|prompts?|rules?)/i,
    ~r/disregard\s+(all\s+)?(previous|prior|above)\s+(instructions?|prompts?|rules?)/i,
    ~r/forget\s+(all\s+)?(previous|prior|above)\s+(instructions?|prompts?|rules?)/i,
    ~r/override\s+(all\s+)?(previous|prior|above)\s+(instructions?|prompts?|rules?)/i,
    # System prompt extraction attempts
    ~r/reveal\s+(your\s+)?(system\s+)?prompt/i,
    ~r/show\s+(your\s+)?(system\s+)?prompt/i,
    ~r/what\s+(is|are)\s+(your\s+)?(system\s+)?(prompt|instructions?)/i,
    # Role switching attempts
    ~r/you\s+are\s+now\s+a/i,
    ~r/act\s+as\s+(if\s+you\s+are\s+)?a/i,
    ~r/pretend\s+(to\s+be|you\s+are)/i
  ]

  @instruction_markers [
    {"SYSTEM:", "[SYS]:"},
    {"USER:", "[USR]:"},
    {"ASSISTANT:", "[AST]:"},
    {"###", "[MARKER]"},
    {"```", "[CODE]"}
  ]

  defp filter_injection_patterns(text) do
    Enum.reduce(@injection_patterns, text, fn pattern, acc ->
      Regex.replace(pattern, acc, "[FILTERED]")
    end)
  end

  defp escape_instruction_markers(text) do
    Enum.reduce(@instruction_markers, text, fn {marker, replacement}, acc ->
      String.replace(acc, marker, replacement)
    end)
  end

  @doc """
  Creates a safe error message by extracting only non-sensitive information.

  This prevents internal error details, stack traces, or API keys from
  being exposed in error messages.

  ## Parameters

  - `reason` - The error reason (any term)

  ## Returns

  A safe string representation of the error.

  ## Examples

      iex> Helpers.safe_error_message(:timeout)
      "Error: timeout"

      iex> Helpers.safe_error_message(%{message: "Rate limit exceeded"})
      "Error: Rate limit exceeded"
  """
  @spec safe_error_message(term()) :: String.t()
  def safe_error_message(reason) when is_atom(reason) do
    "Error: #{reason}"
  end

  def safe_error_message(reason) when is_binary(reason) do
    # Truncate and sanitize string errors - allow only alphanumeric, spaces, and basic punctuation
    safe_msg =
      reason
      |> String.slice(0, 200)
      # Remove HTML tags
      |> String.replace(~r/<[^>]*>/, "")
      # Replace special chars with space
      |> String.replace(~r/[^\w\s\.\-:,]/, " ")
      # Collapse multiple spaces
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    "Error: #{safe_msg}"
  end

  def safe_error_message(%{message: message}) when is_binary(message) do
    safe_error_message(message)
  end

  def safe_error_message(%{reason: reason}) do
    safe_error_message(reason)
  end

  def safe_error_message(_reason) do
    "Error: An unexpected error occurred"
  end
end
