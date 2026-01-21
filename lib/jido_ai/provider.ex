defmodule Jido.AI.Provider do
  use TypedStruct
  require Logger
  alias Jido.AI.Model
  alias Jido.AI.Model.Registry.Adapter
  alias Jido.AI.Provider.Helpers

  # All providers are now backed by ReqLLM
  @legacy_providers []

  @type provider_id :: atom()
  @type provider_type :: :direct | :proxy

  typedstruct do
    @typedoc "An AI model provider"
    field(:id, atom(), enforce: true)
    field(:name, String.t(), enforce: true)
    field(:description, String.t())
    field(:type, provider_type(), default: :direct)
    field(:api_base_url, String.t())
    field(:requires_api_key, boolean(), default: true)
    field(:endpoints, map(), default: %{})
    field(:models, list(), default: [])
    field(:proxy_for, list(String.t()))
  end

  @doc """
  Returns the base directory path for provider-specific files.

  This is where provider configuration, models, and other data files are stored.
  The path is relative to the project root and expands to `./priv/provider/`.
  """
  def base_dir do
    default = Path.join([File.cwd!(), "priv", "provider"])
    Application.get_env(:jido_ai, :provider_base_dir, default)
  end

  @doc """
  Standardizes a model name across providers by removing version numbers and dates.
  This helps match equivalent models from different providers.

  ## Examples
      iex> standardize_model_name("claude-3.7-sonnet-20250219")
      "claude-3.7-sonnet"
      iex> standardize_model_name("gpt-4-0613")
      "gpt-4"
  """
  def standardize_model_name(model) do
    Helpers.standardize_name(model)
  end

  @doc """
  Returns the list of available providers, combining ReqLLM registry with legacy adapters.

  This function discovers providers from:
  1. ReqLLM's dynamic provider registry (50+ providers)
  2. Legacy Jido AI adapter modules
  """
  def providers do
    # Try to get providers from ReqLLM registry first
    reqllm_providers =
      try do
        case Code.ensure_loaded(ReqLLM.Provider.Generated.ValidProviders) do
          {:module, module} ->
            # Get list of ReqLLM providers and convert to legacy format
            module.list()
            |> Enum.map(fn provider_atom ->
              # Check if we have a legacy adapter for this provider
              legacy_adapter = get_legacy_adapter(provider_atom)
              {provider_atom, legacy_adapter || :reqllm_backed}
            end)

          _ ->
            []
        end
      rescue
        _ -> []
      end

    # Merge with legacy providers, preferring legacy adapters when available
    merge_provider_lists(reqllm_providers, @legacy_providers)
  end

  defp get_legacy_adapter(provider_atom) do
    case Enum.find(@legacy_providers, fn {id, _module} -> id == provider_atom end) do
      {_id, module} -> module
      nil -> nil
    end
  end

  defp merge_provider_lists(reqllm_providers, legacy_providers) do
    # Start with legacy providers
    merged = Map.new(legacy_providers)

    # Add ReqLLM providers that aren't already in legacy
    Enum.reduce(reqllm_providers, merged, fn {provider_id, adapter}, acc ->
      Map.put_new(acc, provider_id, adapter)
    end)
    |> Map.to_list()
  end

  @doc """
  Lists all available providers with their metadata.

  Returns provider structs for both ReqLLM-backed and legacy adapter providers.
  """
  def list do
    providers()
    |> Enum.map(fn {provider_id, adapter} ->
      build_provider_struct(provider_id, adapter)
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp build_provider_struct(provider_id, :reqllm_backed) do
    # Build provider struct from ReqLLM metadata
    metadata = get_reqllm_provider_metadata(provider_id)

    %__MODULE__{
      id: provider_id,
      name: metadata[:name] || humanize_provider_name(provider_id),
      description: metadata[:description] || "Provider backed by ReqLLM",
      type: :direct,
      api_base_url: metadata[:base_url],
      requires_api_key: metadata[:requires_api_key] != false,
      # Models will be loaded dynamically
      models: []
    }
  rescue
    _ ->
      # Fallback for providers without metadata
      %__MODULE__{
        id: provider_id,
        name: humanize_provider_name(provider_id),
        description: "Provider available through ReqLLM",
        type: :direct,
        requires_api_key: true,
        models: []
      }
  end

  defp build_provider_struct(_provider_id, module)
       when is_atom(module) and module != :reqllm_backed do
    # Use legacy adapter definition
    if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0) do
      module.definition()
    else
      nil
    end
  end

  defp build_provider_struct(_provider_id, _adapter), do: nil

  defp get_reqllm_provider_metadata(provider_id) do
    # Get metadata directly from ReqLLM registry
    case ReqLLM.Provider.Registry.get_provider_metadata(provider_id) do
      {:ok, metadata} -> metadata
      {:error, _} -> %{}
    end
  end

  defp humanize_provider_name(atom) do
    atom
    |> Atom.to_string()
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  def models(provider, opts \\ []) do
    case get_adapter_module(provider) do
      {:ok, adapter} ->
        adapter.models(provider, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a specific model from a provider by its ID or name.

  ## Parameters

  * `provider` - The provider struct or ID
  * `model` - The ID or name of the model to fetch
  * `opts` - Additional options for the request

  ## Returns

  * `{:ok, model}` - The model was found
  * `{:error, reason}` - The model was not found or an error occurred
  """
  @spec get_model(t() | atom(), String.t(), keyword()) :: {:ok, map()} | {:error, String.t()}
  def get_model(provider, model, opts \\ [])

  def get_model(%__MODULE__{} = provider, model, opts) do
    case get_adapter_module(provider) do
      {:ok, adapter} ->
        if function_exported?(adapter, :get_model, 3) do
          adapter.get_model(provider, model, opts)
        else
          # Fallback implementation if the adapter doesn't implement get_model
          fallback_get_model(provider, model, opts)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_model(provider_id, model, opts)
      when is_atom(provider_id) or is_binary(provider_id) do
    provider_id_atom = ensure_atom(provider_id)

    case get_adapter_by_id(provider_id_atom) do
      {:ok, adapter} ->
        if function_exported?(adapter, :get_model, 3) do
          # Create a minimal provider struct for the adapter
          provider = %__MODULE__{
            id: provider_id_atom,
            name: Atom.to_string(provider_id_atom)
          }

          adapter.get_model(provider, model, opts)
        else
          # Fallback implementation
          {:error, "Provider adapter does not implement get_model/3"}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Fallback implementation for get_model when the adapter doesn't implement it
  defp fallback_get_model(provider, model, opts) do
    case models(provider, opts) do
      {:ok, models} ->
        case Enum.find(models, fn model -> model.id == model end) do
          nil -> {:error, "Model not found: #{model}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_adapter_module(%__MODULE__{id: provider_id}) do
    # Ensure provider_id is an atom
    provider_id_atom = ensure_atom(provider_id)

    # Get current providers list (dynamic)
    current_providers = providers()

    case Enum.find(current_providers, fn {id, _module} -> id == provider_id_atom end) do
      {_id, :reqllm_backed} ->
        # Return a special marker for ReqLLM-backed providers
        {:ok, :reqllm_backed}

      {_id, module} when is_atom(module) ->
        if Code.ensure_loaded?(module) and function_exported?(module, :definition, 0) do
          {:ok, module}
        else
          {:error, "Adapter module #{module} exists but does not implement required functions"}
        end

      nil ->
        {:error, "No adapter found for provider: #{provider_id}"}
    end
  end

  @doc """
  Gets an adapter module by provider ID.

  This is a helper function for getting the adapter module directly by ID.
  """
  def get_adapter_by_id(provider_id) do
    # Ensure provider_id is an atom
    provider_id_atom = ensure_atom(provider_id)

    # Get current providers list (dynamic)
    current_providers = providers()

    case Enum.find(current_providers, fn {id, _module} -> id == provider_id_atom end) do
      {_id, module} -> {:ok, module}
      nil -> {:error, "No adapter found for provider: #{provider_id}"}
    end
  end

  @doc """
  Ensures the given value is an atom.

  Uses safe conversion with `String.to_existing_atom/1` to prevent atom table exhaustion.
  Only converts strings that are already existing atoms (provider names, etc.).
  """
  @spec ensure_atom(atom() | String.t() | term()) :: atom() | term()
  def ensure_atom(id) when is_atom(id), do: id

  def ensure_atom(id) when is_binary(id) do
    String.to_existing_atom(id)
  rescue
    ArgumentError ->
      # If atom doesn't exist, return the string as-is
      # This prevents creating arbitrary atoms from user input
      id
  end

  def ensure_atom(id), do: id

  def call_provider_callback(provider, callback, args) do
    require Logger
    impl = module_for(provider)

    if function_exported?(impl, callback, length(args)) do
      # Call the callback with error handling for runtime errors
      try do
        apply(impl, callback, args)
      rescue
        e in UndefinedFunctionError ->
          Logger.warning(
            "Callback #{inspect(impl)}.#{callback}/#{length(args)} is not defined: #{inspect(e)}"
          )

          {:error, {:callback_not_found, {impl, callback, length(args)}}}

        e in FunctionClauseError ->
          Logger.warning(
            "Callback #{inspect(impl)}.#{callback}/#{length(args)} clause mismatch with args #{inspect(args)}: #{inspect(e)}"
          )

          {:error, {:callback_clause_mismatch, args}}

        e ->
          Logger.warning(
            "Callback #{inspect(impl)}.#{callback}/#{length(args)} failed: #{inspect(e)}"
          )

          {:error, {:callback_failed, inspect(e)}}
      end
    else
      {:error, "#{inspect(impl)} does not implement callback #{callback}/#{length(args)}"}
    end
  end

  # All providers are now ReqLLM-backed, so module_for returns :reqllm_backed
  defp module_for(_provider), do: :reqllm_backed

  @doc """
  Lists all cached models across all providers.

  ## Returns
    - List of model maps, each containing provider information
  """
  def list_all_cached_models do
    # Ensure the base directory exists (with error handling)
    case File.mkdir_p(base_dir()) do
      :ok ->
        :ok

      {:error, reason} ->
        require Logger
        Logger.warning("Failed to create cache directory: #{inspect(reason)}")
    end

    # Find all provider directories
    provider_dirs =
      case File.ls(base_dir()) do
        {:ok, dirs} -> Enum.filter(dirs, &File.dir?(Path.join(base_dir(), &1)))
        {:error, _} -> []
      end

    # Collect models from each provider
    provider_dirs
    |> Enum.flat_map(fn provider_dir ->
      # Safe atom conversion - only convert if provider atom already exists
      provider_id =
        try do
          String.to_existing_atom(provider_dir)
        rescue
          ArgumentError ->
            # Provider directory name not a known provider, skip it
            nil
        end

      # Skip if provider_id couldn't be converted (unknown provider)
      if provider_id == nil do
        []
      else
        models_file = Path.join([base_dir(), provider_dir, "models.json"])

        if File.exists?(models_file) do
          case File.read(models_file) do
            {:ok, json} ->
              case Jason.decode(json) do
                {:ok, %{"data" => models}} when is_list(models) ->
                  Enum.map(models, &Map.put(&1, :provider, provider_id))

                {:ok, models} when is_list(models) ->
                  Enum.map(models, &Map.put(&1, :provider, provider_id))

                _ ->
                  []
              end

            _ ->
              []
          end
        else
          []
        end
      end
    end)
  end

  @doc """
  Retrieves combined information for a model across all providers.

  ## Parameters
    - model_name: The name of the model to search for

  ## Returns
    - `{:ok, model_info}` - Combined model information
    - `{:error, reason}` - Error if model not found
  """
  def get_combined_model_info(model_name) do
    models =
      list_all_cached_models()
      |> Enum.filter(fn model ->
        model = Map.get(model, :id) || Map.get(model, "id")
        standardized_name = standardize_model_name(model)
        standardized_name == model_name
      end)

    if Enum.empty?(models) do
      {:error, "No model found with name: #{model_name}"}
    else
      # Merge information from all matching models
      merged_model = Helpers.merge_model_information(models)
      {:ok, merged_model}
    end
  end

  # Registry-enhanced model discovery methods

  @doc """
  Lists all available models using the enhanced model registry.

  This method leverages the ReqLLM model registry to provide access to 2000+
  models across all providers while maintaining backward compatibility with
  existing cached models.

  ## Parameters
    - provider_id: Optional provider filter (atom)
    - opts: Additional options (keyword list)

  ## Options
    - :source - :registry (default), :cache, or :both
    - :include_capabilities - Include capability metadata (default: false)
    - :refresh - Force refresh from sources (default: false)

  ## Returns
    - `{:ok, models}` - enhanced list with registry data
    - `{:error, reason}` - discovery fails

  ## Examples

      # All models from registry and cache
      {:ok, models} = list_all_models_enhanced()
      length(models) # => 2000+

      # Anthropic models only
      {:ok, models} = list_all_models_enhanced(:anthropic)

      # With capability information
      {:ok, models} = list_all_models_enhanced(nil, include_capabilities: true)

  """
  @spec list_all_models_enhanced(atom() | nil, keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_all_models_enhanced(provider_id \\ nil, opts \\ []) do
    source = Keyword.get(opts, :source, :both)
    _include_capabilities = Keyword.get(opts, :include_capabilities, false)

    try do
      case source do
        :registry ->
          get_models_from_registry_only(provider_id, opts)

        :cache ->
          get_models_from_cache_only(provider_id)

        :both ->
          merge_registry_and_cache_models(provider_id, opts)
      end
    rescue
      error ->
        Logger.error("Error in enhanced model listing: #{inspect(error)}")
        # Fallback to original method
        {:ok, list_all_cached_models()}
    end
  end

  @doc """
  Gets enhanced model information from the registry.

  Provides detailed model information including capabilities, pricing,
  context limits, and other metadata from the ReqLLM registry.

  ## Parameters
    - provider_id: Provider atom (:anthropic, :openai, etc.)
    - model_name: Model identifier string
    - opts: Additional options

  ## Options
    - :enhance_with_cache - Include cached model data (default: true)
    - :include_pricing - Include pricing information (default: false)

  ## Returns
    - `{:ok, enhanced_model}` - comprehensive metadata
    - `{:error, reason}` - model not found or registry unavailable

  ## Examples

      {:ok, model} = get_model_from_registry(:anthropic, "claude-3-5-sonnet")
      model.capabilities.tool_call # => true
      model.limit.context # => 200_000

  """
  @spec get_model_from_registry(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get_model_from_registry(provider_id, model_name, opts \\ []) do
    enhance_with_cache = Keyword.get(opts, :enhance_with_cache, true)

    try do
      case Model.Registry.get_model(provider_id, model_name) do
        {:ok, registry_model} ->
          enhanced_model =
            if enhance_with_cache do
              enhance_registry_model_with_cache(registry_model)
            else
              registry_model
            end

          {:ok, enhanced_model}

        {:error, _reason} ->
          # Fallback to existing get_model implementation
          fallback_get_model_info(provider_id, model_name)
      end
    rescue
      error ->
        Logger.error(
          "Registry model lookup error for #{provider_id}:#{model_name}: #{inspect(error)}"
        )

        fallback_get_model_info(provider_id, model_name)
    end
  end

  @doc """
  Discovers models using advanced filtering capabilities.

  Leverages the ReqLLM registry's rich metadata for sophisticated model
  discovery based on capabilities, cost, context length, and other criteria.

  ## Parameters
    - filters: Keyword list of filtering criteria

  ## Supported Filters
    - :capability - Model capability requirement (:tool_call, :reasoning, etc.)
    - :max_cost_per_token - Maximum cost per token in USD
    - :min_context_length - Minimum context window size
    - :provider - Limit to specific provider(s)
    - :modality - Required modality (:text, :image, :audio)

  ## Returns
    - `{:ok, models}` - filtered and enhanced model list
    - `{:error, reason}` - discovery fails

  ## Examples

      # Find models with tool calling capability
      {:ok, models} = discover_models_by_criteria([capability: :tool_call])

      # Find cost-effective models with large context
      {:ok, models} = discover_models_by_criteria([
        max_cost_per_token: 0.0005,
        min_context_length: 100_000
      ])

      # Find Anthropic models with reasoning
      {:ok, models} = discover_models_by_criteria([
        provider: :anthropic,
        capability: :reasoning
      ])

  """
  @spec discover_models_by_criteria(keyword()) :: {:ok, [map()]} | {:error, term()}
  def discover_models_by_criteria(filters \\ []) do
    case Model.Registry.discover_models(filters) do
      {:ok, registry_models} ->
        # Convert to legacy format for backward compatibility
        legacy_format_models = Enum.map(registry_models, &convert_to_legacy_format/1)
        {:ok, legacy_format_models}

      {:error, reason} ->
        Logger.warning("Registry model discovery failed: #{inspect(reason)}")
        # Fallback to cached models with basic filtering
        cached_models = list_all_cached_models()
        filtered_models = apply_basic_filters(cached_models, filters)
        {:ok, filtered_models}
    end
  rescue
    error ->
      Logger.error("Model discovery error: #{inspect(error)}")
      {:error, "Model discovery failed: #{inspect(error)}"}
  end

  @doc """
  Gets comprehensive model registry statistics.

  Returns detailed information about the model registry including
  provider coverage, capability distribution, and performance metrics.

  ## Returns
    - `{:ok, stats}` - comprehensive registry information
    - `{:error, reason}` - statistics cannot be computed

  ## Example Output

      {:ok, %{
        total_models: 2047,
        registry_models: 2000,
        cached_models: 47,
        provider_coverage: %{anthropic: 15, openai: 25, ...},
        capabilities_distribution: %{tool_call: 1200, reasoning: 800, ...}
      }}

  """
  @spec get_model_registry_stats() :: {:ok, map()} | {:error, term()}
  def get_model_registry_stats do
    case Model.Registry.get_registry_stats() do
      {:ok, registry_stats} ->
        # Enhance with cached model statistics
        cached_models = list_all_cached_models()

        enhanced_stats =
          Map.merge(registry_stats, %{
            cached_models: length(cached_models),
            cache_providers: get_cached_provider_counts(cached_models),
            registry_health: get_registry_health()
          })

        {:ok, enhanced_stats}

      {:error, reason} ->
        # Fallback to cached model statistics only
        cached_models = list_all_cached_models()

        fallback_stats = %{
          total_models: length(cached_models),
          cached_models: length(cached_models),
          registry_models: 0,
          provider_coverage: get_cached_provider_counts(cached_models),
          registry_available: false,
          error: reason
        }

        {:ok, fallback_stats}
    end
  rescue
    error ->
      Logger.error("Registry statistics error: #{inspect(error)}")
      {:error, "Failed to get registry statistics: #{inspect(error)}"}
  end

  # Private helper functions for registry integration

  defp get_models_from_registry_only(provider_id, _opts) do
    case Model.Registry.list_models(provider_id) do
      {:ok, registry_models} ->
        legacy_models = Enum.map(registry_models, &convert_to_legacy_format/1)
        {:ok, legacy_models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_models_from_cache_only(nil) do
    {:ok, list_all_cached_models()}
  end

  defp get_models_from_cache_only(provider_id) do
    cached_models = list_all_cached_models()

    provider_models =
      Enum.filter(cached_models, fn model ->
        model_provider = Map.get(model, :provider) || Map.get(model, "provider")
        model_provider == provider_id
      end)

    {:ok, provider_models}
  end

  defp merge_registry_and_cache_models(provider_id, opts) do
    # Get models from both sources
    registry_result = get_models_from_registry_only(provider_id, opts)
    cache_result = get_models_from_cache_only(provider_id)

    case {registry_result, cache_result} do
      {{:ok, registry_models}, {:ok, cached_models}} ->
        # Merge, preferring registry models but including unique cached models
        merged_models = merge_model_lists(registry_models, cached_models)
        {:ok, merged_models}

      {{:error, _}, {:ok, cached_models}} ->
        Logger.warning("Registry unavailable, using cached models only")
        {:ok, cached_models}
    end
  end

  defp merge_model_lists(registry_models, cached_models) do
    # Create a map of registry models by provider:model key
    registry_map =
      registry_models
      |> Enum.map(fn model ->
        provider = Map.get(model, :provider) || Map.get(model, "provider")
        id = Map.get(model, :id) || Map.get(model, "id")
        key = "#{provider}:#{id}"
        {key, model}
      end)
      |> Enum.into(%{})

    # Add cached models that don't exist in registry
    cached_additions =
      Enum.reject(cached_models, fn cached_model ->
        provider = Map.get(cached_model, :provider) || Map.get(cached_model, "provider")
        id = Map.get(cached_model, :id) || Map.get(cached_model, "id")
        key = "#{provider}:#{id}"
        Map.has_key?(registry_map, key)
      end)

    # Combine registry models with unique cached models
    registry_models ++ cached_additions
  end

  defp enhance_registry_model_with_cache(registry_model) do
    # Try to find corresponding cached model for enhancement
    _provider = registry_model.provider
    model_id = registry_model.id

    case get_combined_model_info(model_id) do
      {:ok, cached_info} ->
        # Merge cached information with registry model
        merge_model_metadata(registry_model, cached_info)

      {:error, _} ->
        # No cached enhancement available
        registry_model
    end
  end

  defp merge_model_metadata(registry_model, cached_info) do
    # Merge cached model information into registry model
    # This preserves existing cached model fields while adding registry enhancements
    Map.merge(cached_info, Map.from_struct(registry_model), fn
      _key, cached_value, nil -> cached_value
      _key, cached_value, registry_value when is_nil(cached_value) -> registry_value
      # Prefer registry data
      _key, _cached_value, registry_value -> registry_value
    end)
  end

  defp convert_to_legacy_format(%Model{} = model) do
    # Convert Model struct to legacy map format for backward compatibility
    Map.from_struct(model)
  end

  defp convert_to_legacy_format(model) when is_map(model) do
    # Already in map format
    model
  end

  defp fallback_get_model_info(_provider_id, model_name) do
    # Use existing get_combined_model_info as fallback
    standardized_name = standardize_model_name(model_name)
    get_combined_model_info(standardized_name)
  end

  defp apply_basic_filters(models, []), do: models

  defp apply_basic_filters(models, filters) do
    Enum.filter(models, fn model ->
      Enum.all?(filters, fn {filter_type, filter_value} ->
        apply_basic_filter(model, filter_type, filter_value)
      end)
    end)
  end

  defp apply_basic_filter(model, :provider, required_provider) do
    model_provider = Map.get(model, :provider) || Map.get(model, "provider")
    model_provider == required_provider
  end

  defp apply_basic_filter(_model, _filter_type, _filter_value) do
    # For advanced filters, allow through (registry would handle them)
    true
  end

  defp get_cached_provider_counts(cached_models) do
    cached_models
    |> Enum.group_by(fn model ->
      Map.get(model, :provider) || Map.get(model, "provider")
    end)
    |> Enum.map(fn {provider, models} -> {provider, length(models)} end)
    |> Enum.into(%{})
  end

  defp get_registry_health do
    case Adapter.get_health_info() do
      {:ok, health} -> Map.put(health, :status, :healthy)
      {:error, reason} -> %{status: :unhealthy, error: reason}
    end
  end
end
