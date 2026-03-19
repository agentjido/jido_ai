defmodule Jido.AI.ModelInput do
  @moduledoc false

  @type t :: Jido.AI.model_alias() | ReqLLM.model_input()

  @doc false
  @spec normalize!(t()) :: ReqLLM.model_input()
  def normalize!(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  def normalize!(model) when is_binary(model), do: model
  def normalize!(%LLMDB.Model{} = model), do: model
  def normalize!(model) when is_map(model) and not is_struct(model), do: model

  def normalize!({provider, model_id, provider_opts} = model)
      when is_atom(provider) and is_binary(model_id) and is_list(provider_opts),
      do: model

  def normalize!({provider, provider_opts} = model) when is_atom(provider) and is_list(provider_opts), do: model

  def normalize!(model) do
    raise ArgumentError,
          "invalid model input #{inspect(model)}. " <>
            "Expected a model alias, string spec, ReqLLM tuple spec, inline model map, or %LLMDB.Model{}."
  end

  @doc false
  @spec label(t()) :: String.t()
  def label(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  def label(model) when is_binary(model), do: model

  def label(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} -> LLMDB.Model.spec(normalized)
      _ -> inspect(model)
    end
  end

  @doc false
  @spec fingerprint_segment(t()) :: String.t()
  def fingerprint_segment(model) when is_atom(model), do: Jido.AI.resolve_model(model)
  def fingerprint_segment(model) when is_binary(model), do: model

  def fingerprint_segment(model) do
    model
    |> fingerprint_term()
    |> :erlang.term_to_binary([:deterministic])
    |> Base.url_encode64(padding: false)
  end

  @doc false
  @spec provider_opt_keys(t()) :: %{optional(String.t()) => atom()}
  def provider_opt_keys(model) do
    with {:ok, %LLMDB.Model{} = normalized} <- ReqLLM.model(normalize!(model)),
         {:ok, provider_mod} <- ReqLLM.provider(normalized.provider),
         true <- function_exported?(provider_mod, :provider_schema, 0) do
      provider_mod.provider_schema().schema
      |> Keyword.keys()
      |> Enum.map(&{Atom.to_string(&1), &1})
      |> Map.new()
    else
      _ -> %{}
    end
  end

  defp fingerprint_term(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} ->
        normalized
        |> Map.from_struct()
        |> Enum.reject(fn {_key, value} -> is_nil(value) end)
        |> Map.new()

      _ ->
        model
    end
  end
end
