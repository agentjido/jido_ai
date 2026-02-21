defmodule Jido.AI.Signal.Helpers do
  @moduledoc """
  Shared helpers for signal correlation and standardized error envelopes.
  """

  alias Jido.Signal

  @type error_envelope :: %{
          code: atom(),
          message: String.t(),
          details: map(),
          retryable: boolean()
        }

  @doc """
  Builds a normalized error envelope for signal payloads.
  """
  @spec error_envelope(atom(), String.t(), map(), boolean()) :: error_envelope()
  def error_envelope(code, message, details \\ %{}, retryable \\ false)
      when is_atom(code) and is_binary(message) and is_map(details) and is_boolean(retryable) do
    %{
      code: code,
      message: message,
      details: details,
      retryable: retryable
    }
  end

  @doc """
  Ensures result payloads use `{:ok, term}` or `{:error, envelope}` tuples.
  """
  @spec normalize_result(term(), atom(), String.t()) :: {:ok, term()} | {:error, error_envelope()}
  def normalize_result(result, fallback_code \\ :invalid_result, fallback_message \\ "Invalid result envelope")

  def normalize_result({:ok, _} = result, _fallback_code, _fallback_message), do: result
  def normalize_result({:error, _} = result, _fallback_code, _fallback_message), do: result

  def normalize_result(result, fallback_code, fallback_message) do
    {:error, error_envelope(fallback_code, fallback_message, %{result: inspect(result)})}
  end

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
  Sanitizes streaming deltas by removing control bytes and truncating payload size.
  """
  @spec sanitize_delta(term(), non_neg_integer()) :: String.t()
  def sanitize_delta(delta, max_chars \\ 4_000) when is_integer(max_chars) and max_chars > 0 do
    delta
    |> to_string()
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
    |> String.slice(0, max_chars)
  end

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
