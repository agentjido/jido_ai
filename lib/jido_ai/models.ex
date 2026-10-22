defmodule Jido.AI.Models do
  @moduledoc """
  Resolves application model aliases for Jido AI.

  Define aliases in application configuration:

      config :jido_ai,
        model_aliases: %{
          fast: "openai:gpt-4o-mini"
        }

  Model aliases are atoms. Direct ReqLLM model names are nonempty strings.
  """

  @type alias_name :: atom()
  @type model_name :: String.t()
  @type error_reason ::
          {:unknown_model_alias, alias_name()}
          | {:invalid_model_alias, alias_name(), term()}
          | {:invalid_model, term()}

  @doc "Returns the configured model aliases."
  @spec aliases() :: %{optional(alias_name()) => model_name()}
  def aliases do
    case Application.get_env(:jido_ai, :model_aliases, %{}) do
      aliases when is_map(aliases) -> aliases
      _other -> %{}
    end
  end

  @doc "Resolves an atom alias or passes a direct model name through."
  @spec resolve(alias_name() | model_name()) :: {:ok, model_name()} | {:error, error_reason()}
  def resolve(model) when is_binary(model) and byte_size(model) > 0, do: {:ok, model}

  def resolve(name) when is_atom(name) and name not in [nil, true, false] do
    case Map.fetch(aliases(), name) do
      {:ok, model} when is_binary(model) and byte_size(model) > 0 ->
        {:ok, model}

      {:ok, model} ->
        {:error, {:invalid_model_alias, name, model}}

      :error ->
        {:error, {:unknown_model_alias, name}}
    end
  end

  def resolve(model), do: {:error, {:invalid_model, model}}
end
