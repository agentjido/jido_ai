defmodule Sparq.Error do
  @moduledoc """
  Centralized error handling for Sparq execution.
  Provides consistent error types and formatting.
  """

  defexception [:type, :message, :frame_ref, :context_ref, :line, :file]

  @type error_type ::
          :runtime_error
          | :stack_overflow
          | :undefined_variable
          | :type_error
          | :syntax_error
          | :reference_error
          | :function_clause_error
          | :binding_error
          | :match_error
          | :invalid_declaration

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          frame_ref: reference() | nil,
          context_ref: reference() | nil,
          line: integer() | nil,
          file: String.t() | nil
        }

  def new(type, message, opts \\ []) do
    struct(__MODULE__, [type: type, message: message] ++ opts)
  end

  def format_error(%__MODULE__{} = error) do
    location = if error.file, do: "#{error.file}:#{error.line}", else: "unknown location"
    "#{error.type} at #{location}: #{error.message}"
  end

  @doc """
  Converts an exception into a Sparq.Error struct.
  """
  def from_exception(exception) do
    case exception do
      %__MODULE__{} = err -> err
      %MatchError{term: {:error, %__MODULE__{} = err, _ctx}} -> err
      %{message: msg} -> new(:runtime_error, msg)
      error when is_atom(error) -> new(:runtime_error, "#{error}")
      error -> new(:runtime_error, "Unknown error: #{inspect(error)}")
    end
  end

  @doc """
  Converts a caught error into a Sparq.Error struct.
  """
  def from_catch(kind, error) do
    map_error(kind, error)
  end

  # Private helpers for error mapping
  defp map_error(:error, %__MODULE__{} = err), do: err

  defp map_error(:error, {:badmatch, {:error, %__MODULE__{} = err, _ctx}}), do: err

  defp map_error(:error, %{message: msg}), do: new(:runtime_error, msg)

  defp map_error(:throw, value), do: new(:runtime_error, "Uncaught throw: #{inspect(value)}")

  defp map_error(:exit, reason), do: new(:runtime_error, "Process exit: #{inspect(reason)}")

  defp map_error(:error, :function_clause),
    do: new(:function_clause_error, "No matching function clause")

  defp map_error(_kind, error) when is_atom(error), do: new(:runtime_error, "#{error}")

  defp map_error(kind, error),
    do: new(:runtime_error, "Unhandled error: #{inspect(kind)} #{inspect(error)}")
end
