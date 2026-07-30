defmodule Jido.AI.Signal.Helpers do
  @moduledoc """
  Shared helpers for signal correlation and signal-safe payload shaping.
  """

  alias Jido.AI.Error
  alias Jido.Signal

  @type error_envelope :: Error.error_envelope()

  @doc """
  Builds a normalized AI runtime error envelope.

  Prefer `Jido.AI.Error.error_envelope/4` for new runtime code.
  """
  @deprecated "Use Jido.AI.Error.error_envelope/4"
  @spec error_envelope(atom(), String.t(), map(), boolean()) :: error_envelope()
  defdelegate error_envelope(type, message, details \\ %{}, retryable? \\ false), to: Error

  @doc """
  Normalizes arbitrary error values into the canonical AI error envelope.

  Prefer `Jido.AI.Error.normalize/4` for new runtime code.
  """
  @deprecated "Use Jido.AI.Error.normalize/4"
  @spec normalize_error(term(), atom(), String.t(), map()) :: error_envelope()
  def normalize_error(
        reason,
        fallback_type \\ :execution_error,
        fallback_message \\ "Execution failed",
        extra_details \\ %{}
      ) do
    Error.normalize(reason, fallback_type, fallback_message, extra_details)
  end

  @doc """
  Ensures result payloads use `{:ok, term, effects}` or `{:error, reason, effects}` tuples.

  Prefer `Jido.AI.Error.normalize_result/3` for new runtime code.
  """
  @deprecated "Use Jido.AI.Error.normalize_result/3"
  @spec normalize_result(term(), atom(), String.t()) ::
          {:ok, term(), [term()]} | {:error, error_envelope(), [term()]}
  defdelegate normalize_result(result, fallback_type \\ :invalid_result, fallback_message \\ "Invalid result envelope"),
    to: Error

  @doc """
  Returns whether a result or error should be treated as retryable by runtime policy.

  Prefer `Jido.AI.Error.retryable?/1` for new runtime code.
  """
  @deprecated "Use Jido.AI.Error.retryable?/1"
  @spec retryable?(term()) :: boolean()
  defdelegate retryable?(reason), to: Error

  @doc """
  Extracts the best available request/call correlation identifier from signal data.
  """
  @spec correlation_id(Signal.t() | map() | nil) :: String.t() | nil
  def correlation_id(%Signal{data: data}), do: correlation_id(data)

  def correlation_id(%{} = data) do
    first_present([
      Map.get(data, :request_id),
      Map.get(data, "request_id"),
      Map.get(data, :call_id),
      Map.get(data, "call_id"),
      Map.get(data, :run_id),
      Map.get(data, "run_id"),
      Map.get(data, :id),
      Map.get(data, "id")
    ])
  end

  def correlation_id(_), do: nil

  @doc """
  Sanitizes text deltas by removing control bytes and truncating payload size.

  Non-text deltas, such as complete content parts, pass through unchanged.
  """
  @spec sanitize_delta(term(), pos_integer()) :: term()
  def sanitize_delta(delta, max_chars \\ 4_000)

  def sanitize_delta(delta, max_chars) when is_binary(delta) and is_integer(max_chars) and max_chars > 0 do
    delta
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
    |> String.slice(0, max_chars)
  end

  def sanitize_delta(delta, max_chars) when is_integer(max_chars) and max_chars > 0, do: delta

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
