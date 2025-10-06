defmodule Jido.AI.Model.Registry.Adapter do
  @moduledoc """
  Adapter for ReqLLM.Provider.Registry integration.

  This module provides a clean interface to ReqLLM's provider registry,
  abstracting the ReqLLM-specific APIs and providing error handling and
  logging for the Jido AI model discovery system.

  The adapter handles:
  - Provider enumeration from ReqLLM registry
  - Model listing for specific providers
  - Individual model metadata retrieval
  - Error handling and fallback mechanisms
  - Performance monitoring and logging
  """

  require Logger

  @type provider_id :: atom()
  @type model_name :: String.t()
  @type reqllm_model :: ReqLLM.Model.t()

  @doc """
  Lists all available providers from ReqLLM registry.

  ## Returns
    - {:ok, providers} where providers is a list of provider atoms
    - {:error, reason} if registry is unavailable

  ## Examples

      {:ok, providers} = list_providers()
      providers # => [:anthropic, :openai, :google, :mistral, ...]
      length(providers) # => 57+

  """
  @spec list_providers() :: {:ok, [provider_id()]} | {:error, term()}
  def list_providers do
    case Code.ensure_loaded(ReqLLM.Provider.Registry) do
      {:module, _module} ->
        providers = ReqLLM.Provider.Registry.list_providers()

        Logger.debug("Registry adapter: discovered #{length(providers)} providers")
        {:ok, providers}

      {:error, reason} ->
        Logger.warning("ReqLLM.Provider.Registry not available: #{inspect(reason)}")
        {:error, :registry_unavailable}
    end
  rescue
    error ->
      Logger.error("Error listing providers from ReqLLM registry: #{inspect(error)}")
      {:error, {:registry_error, error}}
  end

  @doc """
  Lists all available models for a specific provider.

  ## Parameters
    - provider_id: Provider atom (:anthropic, :openai, etc.)

  ## Returns
    - {:ok, models} where models is a list of ReqLLM.Model structs
    - {:error, reason} if provider not found or registry unavailable

  ## Examples

      {:ok, models} = list_models(:anthropic)
      models # => [%ReqLLM.Model{provider: :anthropic, model: "claude-3-5-sonnet", ...}, ...]
      length(models) # => 15+

  """
  @spec list_models(provider_id()) :: {:ok, [reqllm_model()]} | {:error, term()}
  def list_models(provider_id) when is_atom(provider_id) do
    case Code.ensure_loaded(ReqLLM.Provider.Registry) do
      {:module, _module} ->
        case ReqLLM.Provider.Registry.list_models(provider_id) do
          {:ok, model_names} when is_list(model_names) ->
            # Convert model names to ReqLLM.Model structs
            models =
              model_names
              |> Enum.map(fn model_name ->
                case get_model_struct(provider_id, model_name) do
                  {:ok, model} ->
                    model

                  {:error, _} ->
                    # Create minimal model struct if metadata unavailable
                    ReqLLM.Model.new(provider_id, model_name)
                end
              end)
              |> Enum.reject(&is_nil/1)

            Logger.debug("Registry adapter: found #{length(models)} models for #{provider_id}")
            {:ok, models}

          {:error, :provider_not_found} ->
            Logger.warning("Provider #{provider_id} not found in ReqLLM registry")
            {:error, :provider_not_found}

          {:error, reason} ->
            Logger.warning("Error listing models for #{provider_id}: #{inspect(reason)}")
            {:error, reason}

          model_names when is_list(model_names) ->
            # Direct list of model names (legacy format)
            models =
              Enum.map(model_names, fn model_name ->
                ReqLLM.Model.new(provider_id, model_name)
              end)

            Logger.debug(
              "Registry adapter: found #{length(models)} models for #{provider_id} (legacy format)"
            )

            {:ok, models}

          other ->
            Logger.warning(
              "Unexpected response from ReqLLM registry for #{provider_id}: #{inspect(other)}"
            )

            {:error, :unexpected_response}
        end

      {:error, reason} ->
        Logger.warning("ReqLLM.Provider.Registry not available: #{inspect(reason)}")
        {:error, :registry_unavailable}
    end
  rescue
    error ->
      Logger.error(
        "Error listing models for #{provider_id} from ReqLLM registry: #{inspect(error)}"
      )

      {:error, {:registry_error, error}}
  end

  @doc """
  Gets detailed information for a specific model.

  ## Parameters
    - provider_id: Provider atom (:anthropic, :openai, etc.)
    - model_name: String model identifier ("claude-3-5-sonnet", etc.)

  ## Returns
    - {:ok, model} with enhanced ReqLLM.Model struct
    - {:error, reason} if model not found or registry unavailable

  ## Examples

      {:ok, model} = get_model(:anthropic, "claude-3-5-sonnet")
      model.capabilities.tool_call # => true
      model.limit.context # => 200_000

  """
  @spec get_model(provider_id(), model_name()) :: {:ok, reqllm_model()} | {:error, term()}
  def get_model(provider_id, model_name) when is_atom(provider_id) and is_binary(model_name) do
    case Code.ensure_loaded(ReqLLM.Provider.Registry) do
      {:module, _module} ->
        case get_model_struct(provider_id, model_name) do
          {:ok, model} ->
            Logger.debug("Registry adapter: found model #{provider_id}:#{model_name}")
            {:ok, model}

          {:error, reason} ->
            Logger.debug(
              "Model #{provider_id}:#{model_name} not found in registry: #{inspect(reason)}"
            )

            {:error, :not_found}
        end

      {:error, reason} ->
        Logger.warning("ReqLLM.Provider.Registry not available: #{inspect(reason)}")
        {:error, :registry_unavailable}
    end
  rescue
    error ->
      Logger.error(
        "Error getting model #{provider_id}:#{model_name} from ReqLLM registry: #{inspect(error)}"
      )

      {:error, {:registry_error, error}}
  end

  @doc """
  Checks if a model exists in the ReqLLM registry.

  ## Parameters
    - provider_id: Provider atom
    - model_name: String model identifier

  ## Returns
    - true if model exists
    - false if model not found or registry unavailable

  ## Examples

      model_exists?(:anthropic, "claude-3-5-sonnet") # => true
      model_exists?(:anthropic, "nonexistent-model") # => false

  """
  @spec model_exists?(provider_id(), model_name()) :: boolean()
  def model_exists?(provider_id, model_name) do
    case get_model(provider_id, model_name) do
      {:ok, _model} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Gets comprehensive registry health and performance information.

  Returns information about registry availability, response times,
  provider coverage, and error rates for monitoring purposes.

  ## Returns
    - {:ok, health_info} with detailed health metrics
    - {:error, reason} if health check fails

  ## Example Output

      {:ok, %{
        registry_available: true,
        provider_count: 57,
        total_models: 2000,
        avg_response_time_ms: 0.8,
        error_rate: 0.01,
        last_sync: ~U[2024-01-15 10:30:00Z]
      }}

  """
  @spec get_health_info() :: {:ok, map()} | {:error, term()}
  def get_health_info do
    start_time = System.monotonic_time(:millisecond)

    case list_providers() do
      {:ok, providers} ->
        end_time = System.monotonic_time(:millisecond)
        response_time = end_time - start_time

        # Sample a few providers to check model availability
        sample_providers = Enum.take(providers, 3)

        total_models =
          sample_providers
          |> Enum.map(fn provider ->
            case list_models(provider) do
              {:ok, models} -> length(models)
              {:error, _} -> 0
            end
          end)
          |> Enum.sum()

        # Estimate total models based on sample
        estimated_total =
          if length(sample_providers) > 0 do
            trunc(total_models * length(providers) / length(sample_providers))
          else
            0
          end

        health_info = %{
          registry_available: true,
          provider_count: length(providers),
          sampled_providers: length(sample_providers),
          estimated_total_models: estimated_total,
          response_time_ms: response_time,
          timestamp: DateTime.utc_now()
        }

        {:ok, health_info}

      {:error, reason} ->
        health_info = %{
          registry_available: false,
          error: reason,
          timestamp: DateTime.utc_now()
        }

        {:ok, health_info}
    end
  rescue
    error ->
      Logger.error("Error getting registry health info: #{inspect(error)}")
      {:error, {:health_check_failed, error}}
  end

  # Private helper functions

  defp get_model_struct(provider_id, model_name) do
    case ReqLLM.Provider.Registry.get_model(provider_id, model_name) do
      {:ok, model} when is_struct(model, ReqLLM.Model) ->
        {:ok, model}

      {:ok, model_info} when is_map(model_info) ->
        # Convert model info map to ReqLLM.Model struct
        model = create_model_from_info(provider_id, model_name, model_info)
        {:ok, model}

      {:error, reason} ->
        {:error, reason}

      other ->
        Logger.warning("Unexpected model format from registry: #{inspect(other)}")

        # Create minimal model as fallback
        model = ReqLLM.Model.new(provider_id, model_name)
        {:ok, model}
    end
  rescue
    error ->
      Logger.debug(
        "Error getting model struct for #{provider_id}:#{model_name}: #{inspect(error)}"
      )

      {:error, error}
  end

  defp create_model_from_info(provider_id, model_name, model_info) do
    # Extract relevant fields from model info map
    base_model = ReqLLM.Model.new(provider_id, model_name)

    # Enhance with available metadata
    enhanced_model =
      base_model
      |> maybe_add_limit(model_info)
      |> maybe_add_capabilities(model_info)
      |> maybe_add_modalities(model_info)
      |> maybe_add_cost(model_info)

    enhanced_model
  end

  defp maybe_add_limit(model, info) do
    case extract_limit_info(info) do
      nil -> model
      limit -> %{model | limit: limit}
    end
  end

  defp maybe_add_capabilities(model, info) do
    case extract_capabilities(info) do
      nil -> model
      capabilities -> %{model | capabilities: capabilities}
    end
  end

  defp maybe_add_modalities(model, info) do
    case extract_modalities(info) do
      nil -> model
      modalities -> %{model | modalities: modalities}
    end
  end

  defp maybe_add_cost(model, info) do
    case extract_cost_info(info) do
      nil -> model
      cost -> %{model | cost: cost}
    end
  end

  defp extract_limit_info(info) do
    # Extract context length and output limits from model info
    context =
      get_nested_value(info, ["limit", "context"]) ||
        get_nested_value(info, ["context_length"]) ||
        get_nested_value(info, [:limit, :context]) ||
        get_nested_value(info, [:context_length])

    output =
      get_nested_value(info, ["limit", "output"]) ||
        get_nested_value(info, ["max_tokens"]) ||
        get_nested_value(info, [:limit, :output]) ||
        get_nested_value(info, [:max_tokens])

    if context || output do
      %{
        context: context,
        output: output
      }
    else
      nil
    end
  end

  defp extract_capabilities(info) do
    # Extract capabilities from model info
    caps =
      get_nested_value(info, ["capabilities"]) ||
        get_nested_value(info, [:capabilities]) ||
        %{}

    if map_size(caps) > 0 do
      %{
        reasoning: Map.get(caps, "reasoning") || Map.get(caps, :reasoning) || false,
        tool_call: Map.get(caps, "tool_call") || Map.get(caps, :tool_call) || false,
        temperature: Map.get(caps, "temperature") || Map.get(caps, :temperature) || true,
        attachment: Map.get(caps, "attachment") || Map.get(caps, :attachment) || false
      }
    else
      nil
    end
  end

  defp extract_modalities(info) do
    # Extract input/output modalities
    modalities =
      get_nested_value(info, ["modalities"]) ||
        get_nested_value(info, [:modalities])

    if modalities do
      input_modalities = parse_modalities(modalities["input"] || modalities[:input] || ["text"])

      output_modalities =
        parse_modalities(modalities["output"] || modalities[:output] || ["text"])

      %{
        input: input_modalities,
        output: output_modalities
      }
    else
      nil
    end
  end

  defp extract_cost_info(info) do
    # Extract cost information
    cost =
      get_nested_value(info, ["cost"]) ||
        get_nested_value(info, [:cost]) ||
        get_nested_value(info, ["pricing"]) ||
        get_nested_value(info, [:pricing])

    if cost do
      %{
        input: cost["input"] || cost[:input],
        output: cost["output"] || cost[:output]
      }
    else
      nil
    end
  end

  defp parse_modalities(modality_list) when is_list(modality_list) do
    Enum.map(modality_list, fn
      modality when is_atom(modality) -> modality
      modality when is_binary(modality) -> String.to_atom(modality)
      _ -> :text
    end)
  end

  defp parse_modalities(_), do: [:text]

  defp get_nested_value(map, []), do: map

  defp get_nested_value(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> nil
      value -> get_nested_value(value, rest)
    end
  end

  defp get_nested_value(_, _), do: nil
end
