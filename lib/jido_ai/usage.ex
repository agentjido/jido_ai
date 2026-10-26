defmodule Jido.AI.Usage do
  @moduledoc "Aggregates normalized usage across all model calls in one request."

  @counter_keys [
    :input_tokens,
    :output_tokens,
    :total_tokens,
    :cache_read_tokens,
    :cache_write_tokens,
    :reasoning_tokens,
    :compute_units,
    :input_cost,
    :output_cost,
    :total_cost
  ]

  @doc "Returns a normalized zero usage value."
  @spec zero() :: map()
  def zero, do: ReqLLM.Usage.normalize(nil) |> Map.put(:input_includes_cached, nil)

  @doc "Adds one provider usage value to request totals."
  @spec add(map(), map()) :: map()
  def add(total, usage) when is_map(total) and is_map(usage) do
    normalized = ReqLLM.Usage.normalize(usage)

    totals =
      Enum.reduce(@counter_keys, total, fn key, acc ->
        Map.put(acc, key, number(acc[key]) + number(normalized[key]))
      end)

    totals
    |> Map.put(:input, totals.input_tokens)
    |> Map.put(:output, totals.output_tokens)
    |> Map.put(:cached_tokens, totals.cache_read_tokens)
    |> Map.put(:cache_creation_tokens, totals.cache_write_tokens)
    |> Map.put(
      :cache_write_tokens_by_ttl,
      add_groups(total[:cache_write_tokens_by_ttl], normalized[:cache_write_tokens_by_ttl])
    )
    |> Map.put(
      :input_includes_cached,
      combine_cache_semantics(total[:input_includes_cached], cache_semantics(normalized))
    )
  end

  defp add_groups(left, right) do
    Map.merge(group(left), group(right), fn _ttl, first, second ->
      number(first) + number(second)
    end)
  end

  defp group(value) when is_map(value), do: value
  defp group(_value), do: %{}
  defp number(value) when is_number(value), do: value
  defp number(_value), do: 0

  defp cache_semantics(usage) do
    if Enum.any?(@counter_keys, &(number(usage[&1]) > 0)),
      do: usage[:input_includes_cached],
      else: nil
  end

  defp combine_cache_semantics(value, nil), do: value
  defp combine_cache_semantics(nil, value), do: value
  defp combine_cache_semantics(value, value), do: value
  defp combine_cache_semantics(_left, _right), do: :mixed
end
