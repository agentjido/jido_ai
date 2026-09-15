defmodule Jido.AI.Models do
  @moduledoc """
  Application model aliases for Jido AI.

  ReqLLM owns model validation, normalization, provider calls, messages,
  responses, tools, and errors. LLMDB owns model records and catalog data.
  This module adds application-level names such as `:fast` and `:capable`.
  Internal identity and provider-option helpers use those same native inputs;
  they do not call a model or define another model value.
  """

  @type alias_name :: atom()

  @configured_aliases Application.compile_env(:jido_ai, :model_aliases, %{})

  @doc "Returns application model aliases merged over the package configuration."
  @spec aliases() :: %{alias_name() => ReqLLM.model_input()}
  def aliases do
    configured = Application.get_env(:jido_ai, :model_aliases, %{})
    configured = if is_map(configured), do: configured, else: %{}
    Map.merge(@configured_aliases, configured)
  end

  @doc "Resolves an alias or passes a native ReqLLM model input through."
  @spec resolve(alias_name() | ReqLLM.model_input()) :: ReqLLM.model_input()
  def resolve(name) when is_atom(name) do
    case Map.fetch(aliases(), name) do
      {:ok, model} ->
        validate_alias!(name, model)

      :error ->
        raise ArgumentError,
              "Unknown model alias: #{inspect(name)}. " <>
                "Available aliases: #{inspect(Map.keys(aliases()))}"
    end
  end

  def resolve(%LLMDB.Model{} = model), do: validate_native!(model)
  def resolve(model) when is_map(model) and not is_struct(model), do: validate_native!(model)
  def resolve(model) when is_binary(model), do: validate_native!(model)

  def resolve({provider, model_id, opts} = model)
      when is_atom(provider) and is_binary(model_id) and is_list(opts),
      do: validate_native!(model)

  def resolve({provider, opts} = model) when is_atom(provider) and is_list(opts),
    do: validate_native!(model)

  def resolve(model), do: raise(ArgumentError, invalid_model_message(model, :invalid_model_input))

  defp validate_alias!(name, model) do
    validate_native!(model)
  rescue
    error in ArgumentError ->
      raise ArgumentError,
            "Invalid model configured for alias #{inspect(name)}: " <> Exception.message(error)
  end

  defp validate_native!(model) do
    if native_input?(model) do
      case ReqLLM.model(model) do
        {:ok, _normalized} -> model
        {:error, reason} -> raise ArgumentError, invalid_model_message(model, reason)
      end
    else
      raise ArgumentError, invalid_model_message(model, :invalid_model_input)
    end
  end

  defp native_input?(%LLMDB.Model{}), do: true
  defp native_input?(model) when is_map(model), do: not is_struct(model)
  defp native_input?(model) when is_binary(model), do: true

  defp native_input?({provider, model_id, opts}),
    do: is_atom(provider) and is_binary(model_id) and is_list(opts)

  defp native_input?({provider, opts}), do: is_atom(provider) and is_list(opts)
  defp native_input?(_model), do: false

  defp invalid_model_message(model, reason) do
    detail = if is_exception(reason), do: Exception.message(reason), else: inspect(reason)
    "Expected a valid ReqLLM model input, got: #{inspect(model)}. #{detail}"
  end

  @doc false
  def label(model) when is_atom(model), do: model |> resolve() |> label()
  def label(model) when is_binary(model), do: model

  def label(model) do
    case ReqLLM.model(model) do
      {:ok, %LLMDB.Model{} = normalized} -> format_label(normalized)
      _ -> inspect(model)
    end
  end

  @doc false
  def fingerprint_segment(model) when is_atom(model),
    do: model |> resolve() |> fingerprint_segment()

  def fingerprint_segment(model) when is_binary(model), do: model

  def fingerprint_segment(model) do
    model
    |> normalized_fingerprint_term()
    |> :erlang.term_to_binary([:deterministic])
    |> Base.url_encode64(padding: false)
  end

  @doc false
  def provider_option_keys(model) do
    with {:ok, %LLMDB.Model{} = normalized} <- ReqLLM.model(resolve(model)),
         provider when is_atom(provider) <- normalized.provider,
         {:ok, provider_module} <- ReqLLM.provider(provider),
         true <- function_exported?(provider_module, :provider_schema, 0) do
      provider_module.provider_schema().schema
      |> Keyword.keys()
      |> Map.new(&{Atom.to_string(&1), &1})
    else
      _ -> %{}
    end
  end

  defp format_label(%LLMDB.Model{} = model) do
    model_id = model.model || model.id

    if (is_atom(model.provider) or is_binary(model.provider)) and is_binary(model_id),
      do: "#{model.provider}:#{model_id}",
      else: inspect(model)
  end

  defp normalized_fingerprint_term(model) do
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
