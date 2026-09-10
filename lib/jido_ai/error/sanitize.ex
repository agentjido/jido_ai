defmodule Jido.AI.Error.Sanitize do
  @moduledoc """
  Sanitization helpers for user-safe error messaging.
  """

  @reason_messages %{
    enomem: "Resource limit exceeded",
    econnrefused: "Connection failed",
    timeout: "Request timed out",
    not_found: "Resource not found",
    unauthorized: "Authentication required",
    forbidden: "Access denied",
    invalid_input: "Invalid input provided",
    validation_error: "Validation failed"
  }

  @doc """
  Produces a user-safe error message from any error term.
  """
  @spec sanitize_error_message(term(), keyword()) :: String.t()
  def sanitize_error_message(error, opts \\ []) do
    include_code? = Keyword.get(opts, :include_code, true)
    verbose? = Keyword.get(opts, :verbose, false)

    base_message = generic_error_message(error)

    if include_code? do
      code = error_code(error)
      if verbose?, do: "#{base_message} (#{code})", else: base_message
    else
      base_message
    end
  end

  @doc """
  Returns both user-facing and log-facing error representations.
  """
  @spec sanitize_error_for_display(term()) :: %{user_message: String.t(), log_message: String.t()}
  def sanitize_error_for_display(error) do
    %{
      user_message: sanitize_error_message(error),
      log_message: format_error_for_log(error)
    }
  end

  defp generic_error_message(error) do
    cond do
      match?(%{__struct__: _, __exception__: true, file: _, line: _}, error) ->
        "An error occurred while processing your request"

      is_tuple(error) and tuple_size(error) > 0 ->
        case elem(error, 0) do
          reason when is_atom(reason) -> generic_reason_message(reason)
          _ -> "An error occurred"
        end

      is_binary(error) ->
        "An error occurred"

      is_atom(error) ->
        generic_reason_message(error)

      true ->
        "An error occurred"
    end
  end

  defp generic_reason_message(reason) when is_atom(reason) do
    Map.get(@reason_messages, reason, "An error occurred")
  end

  defp error_code(error) do
    cond do
      is_atom(error) -> error
      is_tuple(error) and tuple_size(error) > 0 -> elem(error, 0)
      true -> :error
    end
  end

  defp format_error_for_log(error) do
    inspect(error, limit: :infinity, printable_limit: :infinity)
  rescue
    _ ->
      struct_mod =
        case error do
          %{__struct__: mod} -> inspect(mod)
          _ -> "unknown"
        end

      "#{struct_mod}: [error data too large]"
  end
end
