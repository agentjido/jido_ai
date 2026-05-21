defmodule Jido.AI.Usage do
  @moduledoc """
  Helpers for merging provider usage metadata.
  """

  @doc """
  Merges two usage maps while summing numeric counters and preserving provider metadata.
  """
  @spec merge(map() | nil, map() | nil) :: map()
  def merge(existing, incoming) do
    Map.merge(existing || %{}, incoming || %{}, fn _key, left, right ->
      merge_value(left, right)
    end)
  end

  defp merge_value(left, right) when is_number(left) and is_number(right), do: left + right
  defp merge_value(left, right) when is_map(left) and is_map(right), do: merge(left, right)
  defp merge_value(nil, right), do: right
  defp merge_value(left, nil), do: left
  defp merge_value(_left, right), do: right
end
