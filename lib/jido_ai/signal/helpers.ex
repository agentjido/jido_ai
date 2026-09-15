defmodule Jido.AI.Signal.Helpers do
  @moduledoc """
  Shared helpers for signal correlation and signal-safe payload shaping.
  """

  alias Jido.Signal

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

  def sanitize_delta(delta, max_chars)
      when is_binary(delta) and is_integer(max_chars) and max_chars > 0 do
    delta
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F]/u, "")
    |> String.slice(0, max_chars)
  end

  def sanitize_delta(delta, max_chars) when is_integer(max_chars) and max_chars > 0, do: delta

  defp first_present(values), do: Enum.find(values, &(not is_nil(&1)))
end
