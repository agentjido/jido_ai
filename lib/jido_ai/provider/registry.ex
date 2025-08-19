defmodule Jido.AI.Provider.Registry do
  @moduledoc """
  Fast, read-only registry for AI provider modules using persistent_term.

  This module provides O(1) lookup for provider modules and handles
  automatic discovery and registration at compile/runtime.
  """

  alias Jido.AI.Error.Invalid

  require Logger

  @registry_key {__MODULE__, :providers}

  @doc """
  Gets the provider module for the given provider ID.

  Returns the module atom for the provider, or an error if not found.

  ## Examples

      iex> Jido.AI.Provider.Registry.fetch(:openrouter)
      {:ok, Jido.AI.Provider.OpenRouter}

      iex> Jido.AI.Provider.Registry.fetch(:nonexistent)
      {:error, :not_found}

  """
  @spec fetch(atom()) :: {:ok, module()} | {:error, :not_found}
  def fetch(provider_id) when is_atom(provider_id) do
    case :persistent_term.get(@registry_key, %{}) do
      %{^provider_id => module} ->
        {:ok, module}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Gets the provider module for the given provider ID, raising if not found.

  ## Examples

      iex> Jido.AI.Provider.Registry.fetch!(:openrouter)
      Jido.AI.Provider.OpenRouter

      iex> Jido.AI.Provider.Registry.fetch!(:nonexistent)
      ** (RuntimeError) Provider not found: :nonexistent

  """
  @spec fetch!(atom()) :: module() | no_return()
  def fetch!(provider_id) do
    case fetch(provider_id) do
      {:ok, module} -> module
      {:error, :not_found} -> raise "Provider not found: #{inspect(provider_id)}"
    end
  end

  @doc """
  Gets the provider module for the given provider ID.

  This is deprecated, use `fetch/1` or `fetch!/1` instead.

  Returns an error for non-atom provider IDs since provider IDs must be atoms.
  """
  @spec get_provider(atom()) :: {:ok, module()} | {:error, Exception.t()}
  @spec get_provider(term()) :: {:error, Exception.t()}
  def get_provider(provider_id) when is_atom(provider_id) do
    case fetch(provider_id) do
      {:ok, module} ->
        {:ok, module}

      {:error, :not_found} ->
        {:error, Invalid.Parameter.exception(parameter: "provider #{provider_id}")}
    end
  end

  def get_provider(provider_id) do
    {:error, Invalid.Parameter.exception(parameter: "provider #{provider_id} (must be atom)")}
  end

  @doc """
  Lists all registered provider IDs.

  ## Examples

      iex> Jido.AI.Provider.Registry.list_providers()
      [:openrouter, :openai, :anthropic]

  """
  @spec list_providers() :: [atom()]
  def list_providers do
    :persistent_term.get(@registry_key, %{})
    |> Map.keys()
  end

  @doc """
  Registers a provider module with the given ID.

  This is typically called during application startup or provider module loading.

  ## Examples

      iex> Jido.AI.Provider.Registry.register(:openrouter, Jido.AI.Provider.OpenRouter)
      :ok

  """
  @spec register(atom(), module()) :: :ok | {:error, {:already_registered, module()}}
  def register(provider_id, module) when is_atom(provider_id) and is_atom(module) do
    current_providers = :persistent_term.get(@registry_key, %{})

    case Map.get(current_providers, provider_id) do
      nil ->
        :persistent_term.put(@registry_key, Map.put(current_providers, provider_id, module))
        :ok

      ^module ->
        # Idempotent registration
        :ok

      other ->
        Logger.warning(
          "Attempted to overwrite provider #{provider_id}: existing=#{inspect(other)}, attempted=#{inspect(module)}"
        )

        {:error, {:already_registered, other}}
    end
  end

  @doc """
  Initializes the provider registry by discovering and registering all provider modules.

  This function scans for modules that implement the `Jido.AI.Provider.Behaviour` behaviour
  and registers them automatically.
  """
  @spec initialize() :: :ok
  def initialize do
    providers = discover_providers()

    # Use Task.async_stream for parallel provider info extraction
    {registry_map, failed_modules} =
      providers
      |> Task.async_stream(&extract_provider_info/1, ordered: false, timeout: 5000)
      |> Enum.reduce({%{}, []}, fn
        {:ok, {:ok, {id, module}}}, {acc, failed} ->
          {Map.put(acc, id, module), failed}

        {:ok, {:error, {module, error}}}, {acc, failed} ->
          {acc, [{module, error} | failed]}

        {:exit, reason}, {acc, failed} ->
          {acc, [{:unknown_module, reason} | failed]}
      end)

    # Log any failures in a batch
    if !Enum.empty?(failed_modules) do
      Logger.warning("Failed to register #{length(failed_modules)} providers: #{inspect(failed_modules)}")
    end

    # Store in persistent_term
    :persistent_term.put(@registry_key, registry_map)
    Logger.debug("Provider registry initialized with #{map_size(registry_map)} providers")

    :ok
  end

  @spec reload() :: :ok
  def reload, do: initialize()

  @doc """
  Clears the provider registry.

  Mainly useful for testing.
  """
  @spec clear() :: :ok
  def clear do
    :persistent_term.erase(@registry_key)
    :ok
  end

  # Private functions

  @doc false
  @spec extract_provider_info(module()) ::
          {:ok, {atom(), module()}} | {:error, {module(), term()}}
  def extract_provider_info(module) do
    provider_info = module.provider_info()
    {:ok, {provider_info.id, module}}
  rescue
    error ->
      {:error, {module, Exception.message(error)}}
  catch
    :exit, reason ->
      {:error, {module, reason}}
  end

  @doc false
  @spec discover_providers() :: [module()]
  def discover_providers do
    case :application.get_key(:jido_ai, :modules) do
      {:ok, modules} -> Enum.filter(modules, &provider_module?/1)
      :undefined -> []
    end
  end

  @doc false
  @spec provider_module?(module()) :: boolean()
  def provider_module?(module) do
    behaviours = module.__info__(:attributes)[:behaviour] || []
    Jido.AI.Provider.Behaviour in behaviours
  rescue
    _ -> false
  end
end
