defmodule Jido.AI.Model.Options do
  @moduledoc false
  @reqllm_generation_opt_keys_by_string ReqLLM.Provider.Options.all_generation_keys()
                                        |> Enum.map(&{Atom.to_string(&1), &1})
                                        |> Map.new()

  def merge(base, nil, _model) when is_list(base), do: base

  def merge(base, overrides, model) when is_list(base),
    do: Keyword.merge(base, normalize(overrides, model))

  def normalize(value, model),
    do: normalize_llm_opts(value, Jido.AI.Models.provider_option_keys(model))

  @doc false
  def merge_http_options(options, nil), do: options

  def merge_http_options(options, overrides),
    do: Keyword.update(options, :req_http_options, overrides, &Keyword.merge(&1, overrides))

  @doc false
  def normalize_option_names(value) when is_map(value) and not is_struct(value) do
    value
    |> Enum.map(fn {key, entry_value} -> {normalize_llm_opt_key(key), entry_value} end)
    |> normalize_option_names()
  end

  def normalize_option_names(value) when is_list(value) do
    Enum.filter(value, fn
      {key, _} when is_atom(key) and not is_nil(key) -> true
      _ -> false
    end)
  end

  def normalize_option_names(_), do: []

  defp normalize_llm_opts(value, provider_opt_keys_by_string) do
    value
    |> normalize_option_names()
    |> Enum.map(fn {key, entry_value} ->
      {key, normalize_llm_opt_value(key, entry_value, provider_opt_keys_by_string)}
    end)
  end

  defp normalize_llm_opt_key(key) when is_atom(key), do: key

  defp normalize_llm_opt_key(key) when is_binary(key) do
    Map.get(@reqllm_generation_opt_keys_by_string, key) || maybe_to_existing_atom(key)
  end

  defp normalize_llm_opt_key(_), do: nil

  defp normalize_llm_opt_value(:provider_options, value, provider_opt_keys_by_string) do
    normalize_provider_options(value, provider_opt_keys_by_string)
  end

  defp normalize_llm_opt_value(_key, value, _provider_opt_keys_by_string), do: value

  defp normalize_provider_options(value, provider_opt_keys_by_string) when is_list(value) do
    normalize_provider_option_pairs(value, provider_opt_keys_by_string)
  end

  defp normalize_provider_options(value, provider_opt_keys_by_string) when is_map(value) do
    value
    |> Enum.map(fn {key, entry_value} ->
      {normalize_provider_opt_key(key, provider_opt_keys_by_string), entry_value}
    end)
    |> normalize_provider_option_pairs(provider_opt_keys_by_string)
  end

  defp normalize_provider_options(value, _provider_opt_keys_by_string), do: value

  defp normalize_provider_option_pairs(pairs, _provider_opt_keys_by_string) do
    pairs
    |> Enum.reduce([], fn
      {key, value}, acc when is_atom(key) and not is_nil(key) ->
        [{key, value} | acc]

      _other, acc ->
        acc
    end)
    |> Enum.reverse()
  end

  defp normalize_provider_opt_key(key, _provider_opt_keys_by_string) when is_atom(key), do: key

  defp normalize_provider_opt_key(key, provider_opt_keys_by_string) when is_binary(key) do
    Map.get(provider_opt_keys_by_string, key) || maybe_to_existing_atom(key)
  end

  defp normalize_provider_opt_key(_key, _provider_opt_keys_by_string), do: nil

  defp maybe_to_existing_atom(key) when is_binary(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end
end
