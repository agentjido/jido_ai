defmodule ReqAI.Provider.Registry do
  @moduledoc """
  Simple, compile-time registry for AI provider modules.

  Provides O(1) lookup for provider modules using a simple compile-time map approach.
  Much simpler than jido_ai's persistent_term and auto-discovery system.
  """

  alias ReqAI.Error

  @providers %{
    anthropic: ReqAI.Provider.Anthropic
  }

  @doc """
  Gets the provider module for the given provider ID.

  Returns `{:ok, module}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> ReqAI.Provider.Registry.fetch(:nonexistent)
      {:error, :not_found}

  """
  @spec fetch(atom()) :: {:ok, module()} | {:error, :not_found}
  def fetch(provider_id) when is_atom(provider_id) do
    case Map.get(@providers, provider_id) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  def fetch(_provider_id), do: {:error, :not_found}

  @doc """
  Gets the provider module for the given provider ID, raising if not found.

  ## Examples

      iex> ReqAI.Provider.Registry.fetch!(:nonexistent)
      ** (ReqAI.Error.Invalid.Parameter) Invalid parameter: provider nonexistent

  """
  @spec fetch!(atom()) :: module()
  def fetch!(provider_id) do
    case fetch(provider_id) do
      {:ok, module} ->
        module

      {:error, :not_found} ->
        raise Error.Invalid.Parameter.exception(parameter: "provider #{provider_id}")
    end
  end

  @doc """
  Lists all registered provider IDs.

  ## Examples

      iex> providers = ReqAI.Provider.Registry.list_providers()
      iex> :anthropic in providers
      true

  """
  @spec list_providers() :: [atom()]
  def list_providers do
    Map.keys(@providers)
  end
end
