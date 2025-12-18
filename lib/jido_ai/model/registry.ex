defmodule Jido.AI.Model.Registry do
  @moduledoc """
  Unified model registry integrating ReqLLM catalog.

  This module provides a unified interface for model discovery that integrates
  ReqLLM's comprehensive model registry (2000+ models across 57+ providers)
  while maintaining backward compatibility with existing legacy provider adapters.

  ## Primary Functions

  - Model discovery from ReqLLM registry with fallback to legacy adapters
  - Enhanced model metadata with capabilities, pricing, and limits
  - Advanced filtering by capabilities, cost, performance tier
  - Unified model access across all providers

  ## Usage Examples

      # List all available models
      {:ok, models} = Jido.AI.Model.Registry.list_models()

      # Get models from specific provider
      {:ok, models} = Jido.AI.Model.Registry.list_models(:anthropic)

      # Get specific model with enhanced metadata
      {:ok, model} = Jido.AI.Model.Registry.get_model(:anthropic, "claude-3-5-sonnet")

      # Discover models with advanced filtering
      {:ok, models} = Jido.AI.Model.Registry.discover_models([
        capability: :tool_call,
        max_cost_per_token: 0.001,
        min_context_length: 100_000
      ])

  """

  require Logger
  alias Jido.AI.Model.CapabilityIndex
  alias Jido.AI.Model.Registry.Adapter
  alias Jido.AI.Model.Registry.Cache
  alias Jido.AI.Provider

  @type provider_id :: atom()
  @type model_name :: String.t()
  @type model_filter :: [
          capability: atom(),
          max_cost_per_token: float(),
          min_context_length: non_neg_integer(),
          modality: atom(),
          tier: atom()
        ]

  @doc """
  Lists all available models, optionally filtered by provider.

  Returns models from ReqLLM registry as primary source, with fallback to
  legacy provider adapters for backward compatibility.

  ## Parameters
    - provider_id: Optional atom specifying provider (:anthropic, :openai, etc.)

  ## Returns
    - {:ok, models} where models is a list of Jido.AI.Model structs
    - {:error, reason} if discovery fails

  ## Examples

      # All models across all providers
      {:ok, models} = list_models()
      length(models) # => 2000+

      # Models from specific provider
      {:ok, anthropic_models} = list_models(:anthropic)
      length(anthropic_models) # => 15+

  """
  @spec list_models(provider_id() | nil) :: {:ok, [Jido.AI.Model.t()]} | {:error, term()}
  def list_models(provider_id \\ nil) do
    # CRITICAL: Disable caching in test mode to prevent 60GB memory leak
    # Tests call list_models 165+ times, caching 2000+ models each time = OOM
    if Mix.env() == :test do
      # Test mode: fetch directly without caching
      fetch_models_from_registry(provider_id)
    else
      # Production mode: use cache for performance
      case provider_id && Cache.get(provider_id) do
        {:ok, cached_models} ->
          {:ok, cached_models}

        _ ->
          # Cache miss or no provider - fetch and cache
          fetch_and_cache_models(provider_id)
      end
    end
  rescue
    error ->
      Logger.error("Model registry error: #{inspect(error)}")
      {:error, "Failed to discover models: #{inspect(error)}"}
  end

  defp fetch_and_cache_models(provider_id) do
    # Fetch models from registry
    result = fetch_models_from_registry(provider_id)

    # Cache successful results for specific providers (only in non-test mode)
    if Mix.env() != :test do
      case {result, provider_id} do
        {{:ok, models}, pid} when is_atom(pid) and not is_nil(pid) ->
          Cache.put(pid, models)

        _ ->
          :ok
      end
    end

    result
  end

  defp fetch_models_from_registry(provider_id) do
    # Primary path: ReqLLM registry
    case get_models_from_registry(provider_id) do
      {:ok, [_ | _] = registry_models} ->
        # Enhance registry models with legacy adapter data if available
        enhanced_models = enhance_with_legacy_data(registry_models, provider_id)
        {:ok, enhanced_models}

      {:ok, []} when not is_nil(provider_id) ->
        # Fallback to legacy adapter for specific provider
        get_models_from_legacy_adapter(provider_id)

      {:ok, []} ->
        # Fallback to all legacy adapters
        get_models_from_all_legacy_adapters()

      {:error, reason} ->
        Logger.warning(
          "ReqLLM registry unavailable: #{inspect(reason)}, falling back to legacy adapters"
        )

        if provider_id do
          get_models_from_legacy_adapter(provider_id)
        else
          get_models_from_all_legacy_adapters()
        end
    end
  end

  @doc """
  Batch fetches models from multiple providers concurrently.

  This function optimizes model discovery across multiple providers by fetching
  them in parallel, significantly reducing total discovery time.

  ## Parameters
    - provider_ids: List of provider atoms to fetch models from

  ## Options
    - `:max_concurrency` - Maximum concurrent requests (default: 10)
    - `:timeout` - Timeout per provider request in ms (default: 30_000)

  ## Returns
    - `{:ok, results}` where results is a list of `{provider_id, {:ok, models} | {:error, reason}}`

  ## Examples

      # Fetch from multiple providers concurrently
      {:ok, results} = batch_get_models([:openai, :anthropic, :google])

      # With custom concurrency
      {:ok, results} = batch_get_models([:openai, :anthropic], max_concurrency: 5)

  """
  @spec batch_get_models(list(provider_id()), keyword()) ::
          {:ok, list({provider_id(), {:ok, list()} | {:error, term()}})}
  def batch_get_models(provider_ids, opts \\ []) when is_list(provider_ids) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    timeout = Keyword.get(opts, :timeout, 30_000)

    results =
      provider_ids
      |> Task.async_stream(
        fn provider_id ->
          {provider_id, list_models(provider_id)}
        end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.map(fn
        {:ok, result} -> result
        {:exit, reason} -> {:error, {:batch_timeout, reason}}
      end)

    {:ok, results}
  end

  @doc """
  Gets detailed information for a specific model.

  Returns enhanced model metadata combining ReqLLM registry data with
  legacy adapter information when available.

  ## Parameters
    - provider_id: Provider atom (:anthropic, :openai, etc.)
    - model_name: String model identifier ("claude-3-5-sonnet", etc.)

  ## Returns
    - {:ok, model} with enhanced Jido.AI.Model struct
    - {:error, reason} if model not found or unavailable

  ## Examples

      {:ok, model} = get_model(:anthropic, "claude-3-5-sonnet")
      model.capabilities.tool_call # => true
      model.pricing.prompt # => "$3.00 / 1M tokens"

  """
  @spec get_model(provider_id(), model_name()) :: {:ok, Jido.AI.Model.t()} | {:error, term()}
  def get_model(provider_id, model_name) when is_atom(provider_id) and is_binary(model_name) do
    # Primary path: ReqLLM registry
    case Adapter.get_model(provider_id, model_name) do
      {:ok, registry_model} ->
        # Return ReqLLM model directly
        {:ok, registry_model}

      {:error, :not_found} ->
        # Fallback to legacy adapter
        get_model_from_legacy_adapter(provider_id, model_name)

      {:error, reason} ->
        Logger.warning(
          "ReqLLM registry error for #{provider_id}:#{model_name}: #{inspect(reason)}"
        )

        get_model_from_legacy_adapter(provider_id, model_name)
    end
  rescue
    error ->
      Logger.error("Model lookup error for #{provider_id}:#{model_name}: #{inspect(error)}")
      {:error, "Failed to get model: #{inspect(error)}"}
  end

  @doc """
  Discovers models using advanced filtering capabilities.

  Leverages ReqLLM registry's rich metadata for sophisticated model discovery
  based on capabilities, performance, cost, and other criteria.

  ## Parameters
    - filters: Keyword list of filtering criteria

  ## Supported Filters
    - :capability - Filter by model capabilities (:tool_call, :reasoning, etc.)
    - :max_cost_per_token - Maximum cost per token in USD
    - :min_context_length - Minimum context window size
    - :modality - Required input/output modality (:text, :image, :audio)
    - :tier - Performance tier (:premium, :standard, :economy)

  ## Returns
    - {:ok, models} with filtered list of enhanced models
    - {:error, reason} if discovery fails

  ## Examples

      # Find models with tool calling and large context
      {:ok, models} = discover_models([
        capability: :tool_call,
        min_context_length: 128_000
      ])

      # Find cost-effective text models
      {:ok, models} = discover_models([
        modality: :text,
        max_cost_per_token: 0.0005,
        tier: :standard
      ])

  """
  @spec discover_models(model_filter()) :: {:ok, [Jido.AI.Model.t()]} | {:error, term()}
  def discover_models(filters \\ []) do
    start_time = System.monotonic_time(:microsecond)

    # Get all models from registry
    result =
      case list_models() do
        {:ok, models} ->
          # Build capability index if not exists
          ensure_capability_index(models)

          # Apply filters using optimized path
          filtered_models = apply_filters_optimized(models, filters)
          {:ok, filtered_models}

        {:error, reason} ->
          {:error, reason}
      end

    # Emit telemetry event
    duration_us = System.monotonic_time(:microsecond) - start_time

    model_count =
      case result do
        {:ok, models} when is_list(models) -> length(models)
        _ -> 0
      end

    try do
      :telemetry.execute(
        [:jido, :registry, :discover_models],
        %{duration: duration_us * 1.0, model_count: model_count},
        %{filters: filters}
      )
    rescue
      e ->
        Logger.warning("Telemetry execution failed: #{inspect(e)}")
    end

    result
  rescue
    error ->
      Logger.error("Model discovery error: #{inspect(error)}")
      {:error, "Failed to discover models: #{inspect(error)}"}
  end

  @doc """
  Gets comprehensive statistics about the model registry.

  Returns information about provider coverage, model counts, capabilities
  distribution, and other registry metrics.

  ## Returns
    - {:ok, stats} with comprehensive registry statistics
    - {:error, reason} if statistics cannot be computed

  ## Example Output

      {:ok, %{
        total_models: 2047,
        total_providers: 57,
        registry_models: 2000,
        legacy_models: 47,
        capabilities_distribution: %{
          tool_call: 1200,
          reasoning: 800,
          multimodal: 300
        },
        provider_coverage: %{
          anthropic: 15,
          openai: 25,
          google: 12,
          # ...
        }
      }}

  """
  @spec get_registry_stats() :: {:ok, map()} | {:error, term()}
  def get_registry_stats do
    case list_models() do
      {:ok, models} ->
        stats = calculate_registry_statistics(models)
        {:ok, stats}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error ->
      Logger.error("Registry stats error: #{inspect(error)}")
      {:error, "Failed to compute registry statistics: #{inspect(error)}"}
  end

  # Private helper functions

  defp get_models_from_registry(nil) do
    # Get all providers and their models
    case Adapter.list_providers() do
      {:ok, providers} ->
        all_models =
          providers
          |> Enum.flat_map(fn provider ->
            try do
              case Adapter.list_models(provider) do
                {:ok, models} ->
                  # Return ReqLLM models directly
                  models

                {:error, _} ->
                  []
              end
            rescue
              e ->
                Logger.warning("Failed to list models for provider #{provider}: #{inspect(e)}")
                []
            end
          end)

        {:ok, all_models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_models_from_registry(provider_id) when is_atom(provider_id) do
    case Adapter.list_models(provider_id) do
      {:ok, registry_models} ->
        # Return ReqLLM models directly
        {:ok, registry_models}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp enhance_with_legacy_data(registry_models, _provider_id) do
    # For now, return registry models as-is
    # Future: enhance with legacy adapter data where available
    registry_models
  end

  defp get_models_from_legacy_adapter(provider_id) do
    # Use existing Provider module for legacy model discovery
    case Provider.get_adapter_by_id(provider_id) do
      {:ok, adapter} when adapter != :reqllm_backed ->
        # Legacy adapter exists
        provider = %Provider{id: provider_id, name: Atom.to_string(provider_id)}

        case Provider.models(provider, []) do
          {:ok, models} -> {:ok, models}
          {:error, reason} -> {:error, reason}
        end

      {:ok, :reqllm_backed} ->
        # Provider is ReqLLM-backed but registry failed
        {:error, "ReqLLM-backed provider #{provider_id} requires registry access"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_models_from_all_legacy_adapters do
    # Get all cached models using existing Provider methods
    models = Provider.list_all_cached_models()
    {:ok, models}
  end

  defp get_model_from_legacy_adapter(provider_id, model_name) do
    case get_models_from_legacy_adapter(provider_id) do
      {:ok, models} ->
        case Enum.find(models, fn model ->
               model_id = Map.get(model, :id) || Map.get(model, "id")
               model_id == model_name
             end) do
          nil -> {:error, "Model #{model_name} not found for provider #{provider_id}"}
          model -> {:ok, model}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Ensures capability index exists and is up to date
  defp ensure_capability_index(models) do
    unless CapabilityIndex.exists?() do
      case CapabilityIndex.build(models) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning(
            "Failed to build capability index: #{inspect(reason)}, falling back to non-indexed filtering"
          )

          :error
      end
    end
  end

  # Optimized filter application using capability index when possible
  defp apply_filters_optimized(models, []), do: models

  defp apply_filters_optimized(models, filters) do
    # Check if we can use capability index for optimization
    capability_filters = Keyword.get_values(filters, :capability)

    case capability_filters do
      [capability | _] when is_atom(capability) ->
        # Use index for capability filtering
        apply_filters_with_index(models, filters, capability)

      _ ->
        # Fallback to standard filtering
        apply_filters(models, filters)
    end
  end

  # Apply filters using capability index for O(1) capability lookup
  defp apply_filters_with_index(models, filters, capability) do
    # Get candidate models from index
    case CapabilityIndex.lookup_by_capability(capability, true) do
      {:ok, candidate_ids} ->
        # Build a map for O(1) model lookup, handling both atom and string keys
        model_map =
          Map.new(models, fn model ->
            model_id = Map.get(model, :id) || Map.get(model, "id")
            {model_id, model}
          end)

        # Get candidate models
        candidates =
          Enum.flat_map(candidate_ids, fn id ->
            case Map.get(model_map, id) do
              nil -> []
              model -> [model]
            end
          end)

        # Apply remaining filters to candidates only
        remaining_filters = Keyword.delete(filters, :capability)
        apply_filters(candidates, remaining_filters)

      {:error, :index_not_found} ->
        # Index not available, use standard filtering
        apply_filters(models, filters)
    end
  end

  defp apply_filters(models, []), do: models

  defp apply_filters(models, filters) do
    Enum.filter(models, fn model ->
      Enum.all?(filters, fn {filter_type, filter_value} ->
        apply_single_filter(model, filter_type, filter_value)
      end)
    end)
  end

  defp apply_single_filter(model, :capability, required_capability) do
    case model.capabilities do
      nil -> false
      capabilities -> Map.get(capabilities, required_capability, false)
    end
  end

  defp apply_single_filter(model, :max_cost_per_token, max_cost) do
    case get_model_cost_per_token(model) do
      # Unknown cost, allow through
      nil -> true
      cost -> cost <= max_cost
    end
  end

  defp apply_single_filter(model, :min_context_length, min_length) do
    case get_model_context_length(model) do
      # Unknown context length, filter out
      nil -> false
      length -> length >= min_length
    end
  end

  defp apply_single_filter(model, :modality, required_modality) do
    case model.modalities do
      # Assume text if unknown
      nil ->
        required_modality == :text

      modalities ->
        input_modalities = Map.get(modalities, :input, [])
        required_modality in input_modalities
    end
  end

  defp apply_single_filter(model, :tier, required_tier) do
    # Classify models by tier based on pricing and capabilities
    model_tier = classify_model_tier(model)
    model_tier == required_tier
  end

  defp apply_single_filter(model, :provider, required_provider) do
    # Filter models by provider
    provider = Map.get(model, :provider) || Map.get(model, "provider")
    provider == required_provider
  end

  defp apply_single_filter(_model, _filter_type, _filter_value) do
    # Unknown filter type, allow through
    true
  end

  defp get_model_cost_per_token(model) do
    # Extract cost per token from model pricing information
    cost = Map.get(model, :cost) || Map.get(model, "cost")

    case cost do
      nil ->
        nil

      cost when is_map(cost) ->
        # Use input cost as the primary cost metric, handle both atom and string keys
        input_cost = Map.get(cost, :input) || Map.get(cost, "input")
        if is_number(input_cost), do: input_cost, else: nil

      cost when is_number(cost) ->
        cost

      _ ->
        nil
    end
  end

  defp get_model_context_length(model) do
    # Extract context length from model metadata
    endpoints = Map.get(model, :endpoints) || Map.get(model, "endpoints")

    case endpoints do
      nil ->
        nil

      [] ->
        nil

      [endpoint | _] when is_map(endpoint) ->
        context = Map.get(endpoint, :context_length) || Map.get(endpoint, "context_length")
        if is_number(context), do: context, else: nil

      _ ->
        nil
    end
  end

  defp classify_model_tier(model) do
    # Classify model into performance tiers
    # This is a simplified classification
    cost = get_model_cost_per_token(model)
    context = get_model_context_length(model)

    cond do
      is_nil(cost) or is_nil(context) -> :unknown
      is_number(cost) and is_number(context) and cost > 0.001 and context > 100_000 -> :premium
      is_number(cost) and cost > 0.0005 -> :standard
      true -> :economy
    end
  end

  defp calculate_registry_statistics(models) do
    total_models = length(models)

    provider_counts =
      models
      |> Enum.group_by(& &1.provider)
      |> Enum.map(fn {provider, provider_models} -> {provider, length(provider_models)} end)
      |> Enum.into(%{})

    total_providers = map_size(provider_counts)

    # Count registry vs legacy models
    {registry_count, legacy_count} =
      Enum.reduce(models, {0, 0}, fn model, {reg_acc, leg_acc} ->
        case model do
          %ReqLLM.Model{} -> {reg_acc + 1, leg_acc}
          _ -> {reg_acc, leg_acc + 1}
        end
      end)

    # Capability distribution
    capabilities_distribution =
      models
      |> Enum.reduce(%{}, fn model, acc ->
        case model.capabilities do
          nil ->
            acc

          caps ->
            Enum.reduce(caps, acc, fn {cap, enabled}, cap_acc ->
              if enabled do
                Map.update(cap_acc, cap, 1, &(&1 + 1))
              else
                cap_acc
              end
            end)
        end
      end)

    %{
      total_models: total_models,
      total_providers: total_providers,
      registry_models: registry_count,
      legacy_models: legacy_count,
      provider_coverage: provider_counts,
      capabilities_distribution: capabilities_distribution
    }
  end
end
