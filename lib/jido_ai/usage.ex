defmodule Jido.AI.Usage do
  @moduledoc """
  Helpers for merging provider usage metadata.
  """

  @doc """
  Merges two usage maps while summing numeric counters and preserving provider metadata.
  """
  @spec merge(term(), term()) :: map()
  def merge(existing, incoming) do
    Map.merge(usage_map(existing), usage_map(incoming), fn _key, left, right ->
      merge_value(left, right)
    end)
  end

  @doc """
  Adds `:total_tokens` when input and output token counters are available.
  """
  @spec ensure_total_tokens(map()) :: map()
  def ensure_total_tokens(%{} = usage) do
    total_tokens = Map.get(usage, :total_tokens)

    with false <- is_number(total_tokens),
         {:ok, input_tokens} <- numeric_value(Map.get(usage, :input_tokens)),
         {:ok, output_tokens} <- numeric_value(Map.get(usage, :output_tokens)) do
      Map.put(usage, :total_tokens, input_tokens + output_tokens)
    else
      _ -> usage
    end
  end

  defp usage_map(%{} = usage), do: normalize_usage_values(usage)
  defp usage_map(_usage), do: %{}

  defp merge_value(left, right) do
    case {numeric_value(left), numeric_value(right)} do
      {{:ok, left}, {:ok, right}} ->
        left + right

      _ ->
        merge_metadata_value(left, right)
    end
  end

  defp merge_metadata_value(left, right) when is_map(left) and is_map(right), do: merge(left, right)
  defp merge_metadata_value(nil, right), do: right
  defp merge_metadata_value(left, nil), do: left
  defp merge_metadata_value(_left, right), do: right

  defp normalize_usage_values(usage) do
    Map.new(usage, fn {key, value} -> {key, normalize_usage_value(value)} end)
  end

  defp normalize_usage_value(value) when is_map(value), do: normalize_usage_values(value)

  defp normalize_usage_value(value) when is_list(value) do
    Enum.map(value, &normalize_usage_value/1)
  end

  defp normalize_usage_value(value) do
    case numeric_value(value) do
      {:ok, number} -> number
      :error -> value
    end
  end

  defp numeric_value(value) when is_integer(value) or is_float(value), do: {:ok, value}

  defp numeric_value(value) when is_binary(value) do
    value = String.trim(value)

    case parse_integer(value) do
      {:ok, _int} = parsed -> parsed
      :error -> parse_float(value)
    end
  end

  defp numeric_value(_value), do: :error

  defp parse_integer(""), do: :error

  defp parse_integer(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> :error
    end
  end

  defp parse_float(""), do: :error

  defp parse_float(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> :error
    end
  end
end
