defmodule Jido.AI.Model.CapabilityIndex do
  @moduledoc """
  ETS-based capability index for O(1) model lookups by capability.

  This module provides high-performance capability-based model discovery
  by maintaining an inverted index of capabilities to model IDs.

  ## Architecture

  The index uses two ETS tables:
  - `:capability_index` - Maps {capability, value} to list of model IDs
  - `:model_capabilities` - Maps model_id to capabilities map

  ## Performance

  - Index build: O(n * m) where n = models, m = avg capabilities per model
  - Capability lookup: O(1) using ETS key-value access
  - Index updates: O(m) for single model update

  ## Usage

      # Build index from models
      CapabilityIndex.build(models)

      # Fast capability lookup
      {:ok, model_ids} = CapabilityIndex.lookup_by_capability(:tool_call, true)

      # Get model capabilities
      {:ok, capabilities} = CapabilityIndex.get_capabilities(model_id)

      # Check if index exists
      CapabilityIndex.exists?()
  """

  require Logger

  @capability_index_table :jido_capability_index
  @model_capabilities_table :jido_model_capabilities

  @type capability_key :: atom()
  @type capability_value :: term()
  @type model_id :: String.t()

  @doc """
  Builds the capability index from a list of models.

  Creates or recreates the ETS tables and populates them with
  model capability data for fast lookups.

  ## Parameters
    - models: List of Jido.AI.Model structs

  ## Returns
    - `:ok` on success
    - `{:error, reason}` on failure
  """
  @spec build([Jido.AI.Model.t()]) :: :ok | {:error, term()}
  def build(models) when is_list(models) do
    # Create or clear ETS tables
    ensure_tables_exist()
    clear_tables()

    # Populate index
    Enum.each(models, &index_model/1)

    Logger.debug("Built capability index for #{length(models)} models")
    :ok
  rescue
    error ->
      Logger.error("Failed to build capability index: #{inspect(error)}")
      {:error, error}
  end

  @doc """
  Looks up model IDs by a specific capability and value.

  Returns all model IDs that have the specified capability set to the given value.

  ## Parameters
    - capability: Capability key (atom)
    - value: Expected capability value (typically boolean)

  ## Returns
    - `{:ok, [model_ids]}` - list of matching model IDs
    - `{:error, :index_not_found}` - index not built
  """
  @spec lookup_by_capability(capability_key(), capability_value()) ::
          {:ok, [model_id()]} | {:error, :index_not_found}
  def lookup_by_capability(capability, value) do
    if exists?() do
      case :ets.lookup(@capability_index_table, {capability, value}) do
        [{_key, model_ids}] -> {:ok, model_ids}
        [] -> {:ok, []}
      end
    else
      {:error, :index_not_found}
    end
  end

  @doc """
  Gets the capabilities map for a specific model.

  ## Parameters
    - model_id: Model identifier string

  ## Returns
    - `{:ok, capabilities_map}` - model found
    - `{:error, :not_found}` - model not in index
    - `{:error, :index_not_found}` - index not built
  """
  @spec get_capabilities(model_id()) ::
          {:ok, map()} | {:error, :not_found | :index_not_found}
  def get_capabilities(model_id) do
    if exists?() do
      case :ets.lookup(@model_capabilities_table, model_id) do
        [{_id, capabilities}] -> {:ok, capabilities}
        [] -> {:error, :not_found}
      end
    else
      {:error, :index_not_found}
    end
  end

  @doc """
  Checks if the capability index exists and is ready for use.

  ## Returns
    - true if index tables exist
    - false otherwise
  """
  @spec exists?() :: boolean()
  def exists? do
    case :ets.whereis(@capability_index_table) do
      :undefined -> false
      _ -> true
    end
  end

  @doc """
  Updates the index for a single model.

  Useful for incremental index updates when models are added or modified.

  ## Parameters
    - model: Jido.AI.Model struct

  ## Returns
    - `:ok` on success
    - `{:error, :index_not_found}` - index not built
  """
  @spec update_model(Jido.AI.Model.t()) :: :ok | {:error, :index_not_found}
  def update_model(model) do
    if exists?() do
      # Remove old entries for this model
      remove_model_from_index(model.id)

      # Add new entries
      index_model(model)
      :ok
    else
      {:error, :index_not_found}
    end
  end

  @doc """
  Removes a model from the index.

  ## Parameters
    - model_id: Model identifier string

  ## Returns
    - `:ok` on success
    - `{:error, :index_not_found}` - index not built
  """
  @spec remove_model(model_id()) :: :ok | {:error, :index_not_found}
  def remove_model(model_id) do
    if exists?() do
      remove_model_from_index(model_id)
      :ok
    else
      {:error, :index_not_found}
    end
  end

  @doc """
  Clears all data from the index tables.

  ## Returns
    - :ok
  """
  @spec clear() :: :ok
  def clear do
    if exists?() do
      clear_tables()
    end

    :ok
  end

  @doc """
  Gets statistics about the capability index.

  ## Returns
    - `{:ok, stats_map}` - index statistics
    - `{:error, :index_not_found}` - index not built
  """
  @spec stats() :: {:ok, map()} | {:error, :index_not_found}
  def stats do
    if exists?() do
      capability_entries = :ets.info(@capability_index_table, :size)
      model_entries = :ets.info(@model_capabilities_table, :size)
      memory_bytes = :ets.info(@capability_index_table, :memory) * :erlang.system_info(:wordsize)

      {:ok,
       %{
         capability_index_entries: capability_entries,
         model_entries: model_entries,
         memory_bytes: memory_bytes,
         memory_mb: Float.round(memory_bytes / 1_048_576, 2)
       }}
    else
      {:error, :index_not_found}
    end
  end

  # Private helper functions

  defp ensure_tables_exist do
    # Create capability index table if it doesn't exist
    unless exists?() do
      :ets.new(@capability_index_table, [:named_table, :set, :public, read_concurrency: true])
      :ets.new(@model_capabilities_table, [:named_table, :set, :public, read_concurrency: true])
    end
  end

  defp clear_tables do
    if exists?() do
      :ets.delete_all_objects(@capability_index_table)
      :ets.delete_all_objects(@model_capabilities_table)
    end
  end

  defp index_model(%{id: model_id, capabilities: nil}) do
    # Model has no capabilities, just store empty map
    :ets.insert(@model_capabilities_table, {model_id, %{}})
  end

  defp index_model(%{id: model_id, capabilities: capabilities}) when is_map(capabilities) do
    # Store model capabilities
    :ets.insert(@model_capabilities_table, {model_id, capabilities})

    # Index each capability
    Enum.each(capabilities, fn {capability, value} ->
      key = {capability, value}

      # Get existing model list for this capability
      existing_models =
        case :ets.lookup(@capability_index_table, key) do
          [{^key, models}] -> models
          [] -> []
        end

      # Add this model to the list
      updated_models = [model_id | existing_models] |> Enum.uniq()
      :ets.insert(@capability_index_table, {key, updated_models})
    end)
  end

  defp index_model(model) when is_map(model) do
    # Handle models with string keys or no id field
    model_id = get_model_id(model)

    if model_id do
      capabilities = Map.get(model, :capabilities) || Map.get(model, "capabilities") || %{}
      :ets.insert(@model_capabilities_table, {model_id, capabilities})

      # Index capabilities if present
      if is_map(capabilities) and map_size(capabilities) > 0 do
        Enum.each(capabilities, fn {capability, value} ->
          key = {capability, value}

          existing_models =
            case :ets.lookup(@capability_index_table, key) do
              [{^key, models}] -> models
              [] -> []
            end

          updated_models = [model_id | existing_models] |> Enum.uniq()
          :ets.insert(@capability_index_table, {key, updated_models})
        end)
      end
    else
      Logger.debug("Model #{inspect(model)} has no valid ID, skipping index")
    end
  end

  defp index_model(model) do
    # Non-map models, skip
    Logger.debug("Skipping non-map model: #{inspect(model)}")
  end

  # Helper to get model ID from various formats
  defp get_model_id(model) when is_map(model) do
    Map.get(model, :id) || Map.get(model, "id")
  end

  defp get_model_id(_), do: nil

  defp remove_model_from_index(model_id) do
    # Get model's capabilities
    case :ets.lookup(@model_capabilities_table, model_id) do
      [{_id, capabilities}] when is_map(capabilities) ->
        # Remove model from each capability index
        Enum.each(capabilities, fn {capability, value} ->
          key = {capability, value}

          case :ets.lookup(@capability_index_table, key) do
            [{^key, models}] ->
              updated_models = List.delete(models, model_id)

              if updated_models == [] do
                :ets.delete(@capability_index_table, key)
              else
                :ets.insert(@capability_index_table, {key, updated_models})
              end

            [] ->
              :ok
          end
        end)

        # Remove model from capabilities table
        :ets.delete(@model_capabilities_table, model_id)

      _ ->
        :ok
    end
  end
end
