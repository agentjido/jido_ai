defmodule Jido.AI.Models do
  @moduledoc """
  Application model aliases for Jido AI.

  ReqLLM owns model validation, normalization, provider calls, messages,
  responses, tools, and errors. LLMDB owns model records and catalog data.
  This module adds only application-level names such as `:fast` and
  `:capable`.
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

  @doc false
  @deprecated "Use aliases/0"
  def model_aliases, do: aliases()

  @doc false
  @deprecated "Use resolve/1"
  def resolve_model(model), do: resolve(model)

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
end
