defmodule Jido.AI.Usage do
  @moduledoc """
  Helpers for merging provider usage metadata.
  """

  @numeric_usage_keys MapSet.new([
                        "accepted_prediction_tokens",
                        "attempts",
                        "audio_tokens",
                        "cache_creation_input_tokens",
                        "cache_read_input_tokens",
                        "cached_input_tokens",
                        "calls",
                        "completion_tokens",
                        "cost",
                        "duration_ms",
                        "images",
                        "input_audio_tokens",
                        "input_cost",
                        "input_tokens",
                        "output_audio_tokens",
                        "output_cost",
                        "output_tokens",
                        "prompt_tokens",
                        "reasoning_tokens",
                        "rejected_prediction_tokens",
                        "requests",
                        "retries",
                        "total",
                        "total_cost",
                        "total_tokens"
                      ])

  @numeric_usage_suffixes [
    "_cost",
    "_count",
    "_duration_ms",
    "_tokens"
  ]

  @doc """
  Normalizes common usage counter keys and numeric counter values.
  """
  @spec normalize(term()) :: map() | nil
  def normalize(nil), do: nil

  def normalize(%{} = usage) do
    Map.new(usage, fn {key, value} ->
      key = normalize_usage_key(key)
      {key, normalize_usage_value(key, value)}
    end)
  end

  def normalize(_usage), do: nil

  @doc """
  Merges two usage maps while summing numeric counters and preserving provider metadata.
  """
  @spec merge(term(), term()) :: map()
  def merge(existing, incoming) do
    Map.merge(usage_map(existing), usage_map(incoming), fn key, left, right ->
      merge_value(key, left, right)
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

  defp usage_map(usage), do: normalize(usage) || %{}

  defp merge_value(key, left, right) do
    if numeric_usage_key?(key) do
      case {numeric_value(left), numeric_value(right)} do
        {{:ok, left}, {:ok, right}} ->
          left + right

        _ ->
          merge_metadata_value(left, right)
      end
    else
      merge_metadata_value(left, right)
    end
  end

  defp merge_metadata_value(left, right) when is_map(left) and is_map(right), do: merge(left, right)
  defp merge_metadata_value(nil, right), do: right
  defp merge_metadata_value(left, nil), do: left
  defp merge_metadata_value(_left, right), do: right

  defp normalize_usage_key("input_tokens"), do: :input_tokens
  defp normalize_usage_key("output_tokens"), do: :output_tokens
  defp normalize_usage_key("total_tokens"), do: :total_tokens
  defp normalize_usage_key("cache_creation_input_tokens"), do: :cache_creation_input_tokens
  defp normalize_usage_key("cache_read_input_tokens"), do: :cache_read_input_tokens
  defp normalize_usage_key(key), do: key

  defp normalize_usage_value(_key, value) when is_map(value), do: normalize(value)

  defp normalize_usage_value(_key, value) when is_list(value) do
    Enum.map(value, fn
      %{} = item -> normalize(item)
      item -> item
    end)
  end

  defp normalize_usage_value(key, value) do
    if numeric_usage_key?(key) do
      case numeric_value(value) do
        {:ok, number} -> number
        :error -> value
      end
    else
      value
    end
  end

  defp numeric_usage_key?(key) when is_atom(key), do: key |> Atom.to_string() |> numeric_usage_key?()

  defp numeric_usage_key?(key) when is_binary(key) do
    MapSet.member?(@numeric_usage_keys, key) or
      Enum.any?(@numeric_usage_suffixes, &String.ends_with?(key, &1))
  end

  defp numeric_usage_key?(_key), do: false

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
