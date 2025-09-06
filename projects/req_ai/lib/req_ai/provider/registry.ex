defmodule ReqAI.Provider.Registry do
  @moduledoc """
  Auto-registration registry for AI provider modules using persistent_term.

  Providers automatically register themselves at compile-time via the DSL macro.
  Provides O(1) lookup without manual maintenance of provider lists.
  """

  alias ReqAI.Error

  @registry_key :req_ai_providers

  @doc """
  Initializes the provider registry.

  This is called automatically at application startup to ensure providers are properly registered.
  """
  @spec initialize() :: :ok
  def initialize do
    # Ensure all provider modules are loaded and registered
    case Application.get_application(__MODULE__) do
      nil ->
        :ok

      app ->
        # Force load all provider modules in the application
        {:ok, modules} = :application.get_key(app, :modules)

        modules
        |> Enum.filter(&is_provider_module?/1)
        |> Enum.each(fn module ->
          try do
            Code.ensure_loaded(module)

            if function_exported?(module, :spec, 0) do
              spec = module.spec()
              register(module, spec.id)
            end
          rescue
            _ -> :ok
          end
        end)
    end

    :ok
  end

  @spec is_provider_module?(module()) :: boolean()
  defp is_provider_module?(module) do
    module_name = Atom.to_string(module)

    String.contains?(module_name, "Providers.") or
      String.ends_with?(module_name, "Provider")
  end

  @doc """
  Registers a provider module with its ID.

  This is called automatically by the DSL macro, not intended for manual use.
  """
  @spec register(module(), atom()) :: :ok
  def register(module, provider_id) when is_atom(provider_id) do
    current_providers = get_all_providers()
    updated_providers = Map.put(current_providers, provider_id, module)
    :persistent_term.put(@registry_key, updated_providers)
    :ok
  end

  @doc """
  Called by the DSL macro after compilation to auto-register the provider.
  """
  def auto_register(env, _bytecode) do
    try do
      spec = env.module.spec()
      register(env.module, spec.id)
    rescue
      # If spec/0 fails, silently ignore - provider may not be fully compiled yet
      _ -> :ok
    end
  end

  defp get_all_providers do
    :persistent_term.get(@registry_key, %{})
  rescue
    ArgumentError -> %{}
  end

  @doc """
  Gets the provider module for the given provider ID.

  Returns `{:ok, module}` if found, `{:error, :not_found}` otherwise.

  ## Examples

      iex> ReqAI.Provider.Registry.fetch(:nonexistent)
      {:error, :not_found}

  """
  @spec fetch(atom()) :: {:ok, module()} | {:error, :not_found}
  def fetch(provider_id) when is_atom(provider_id) do
    case Map.get(get_all_providers(), provider_id) do
      nil -> {:error, :not_found}
      module -> {:ok, module}
    end
  end

  def fetch(_provider_id), do: {:error, :not_found}

  @doc """
  Gets the provider module for the given provider ID, raising if not found.

  ## Examples

      iex> ReqAI.Provider.Registry.fetch!(:nonexistent)
      ** (ReqAI.Error.Invalid.Provider) Unknown provider: nonexistent

  """
  @spec fetch!(atom()) :: module()
  def fetch!(provider_id) do
    case fetch(provider_id) do
      {:ok, module} ->
        module

      {:error, :not_found} ->
        raise Error.Invalid.Provider.exception(provider: provider_id)
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
    Map.keys(get_all_providers())
  end
end
