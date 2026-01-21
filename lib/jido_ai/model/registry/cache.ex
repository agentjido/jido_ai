defmodule Jido.AI.Model.Registry.Cache do
  @moduledoc """
  ETS-based caching layer for model registry to reduce network calls and improve performance.

  This module provides a simple TTL-based cache for model listings per provider.
  Cache entries automatically expire after the configured TTL and are cleaned up
  periodically.

  ## Features

  - Fast ETS-based storage with read concurrency
  - Configurable TTL per cache entry
  - Automatic cleanup of expired entries
  - Manual invalidation support
  - Thread-safe operations

  ## Usage

      # Get cached models (if available)
      case Cache.get(:openai) do
        {:ok, models} -> models
        :cache_miss -> fetch_from_network()
      end

      # Store models in cache
      Cache.put(:openai, models, ttl: 3_600_000)  # 1 hour

      # Invalidate cache
      Cache.invalidate(:openai)

  ## Performance

  - O(1) lookup via ETS
  - Read concurrency enabled for parallel access
  - Minimal overhead (~0.1ms per operation)
  """

  use GenServer
  require Logger

  @cache_table :jido_model_cache
  # 1 hour in production, 1 second in test (prevents memory accumulation)
  @default_ttl if Mix.env() == :test, do: 1_000, else: 3_600_000
  # 1 minute in production, 1 second in test (aggressive cleanup in tests)
  @cleanup_interval if Mix.env() == :test, do: 1_000, else: 60_000

  # Client API

  @doc """
  Starts the cache GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Retrieves models from cache for a given provider.

  Returns `{:ok, models}` if found and not expired, `:cache_miss` otherwise.

  ## Examples

      iex> Cache.get(:openai)
      {:ok, [%Model{...}]}

      iex> Cache.get(:unknown_provider)
      :cache_miss
  """
  @spec get(atom()) :: {:ok, list()} | :cache_miss
  def get(provider_id) when is_atom(provider_id) do
    case :ets.lookup(@cache_table, provider_id) do
      [{^provider_id, models, expires_at}] ->
        now = System.monotonic_time(:millisecond)

        if now < expires_at do
          emit_telemetry(:hit, provider_id)
          {:ok, models}
        else
          emit_telemetry(:miss, provider_id, %{reason: :expired})
          :cache_miss
        end

      [] ->
        emit_telemetry(:miss, provider_id, %{reason: :not_found})
        :cache_miss
    end
  end

  @doc """
  Stores models in cache for a provider with optional TTL.

  ## Options

    * `:ttl` - Time-to-live in milliseconds (default: 1 hour)

  ## Examples

      Cache.put(:openai, models)
      Cache.put(:openai, models, ttl: 1_800_000)  # 30 minutes
  """
  @spec put(atom(), list(), keyword()) :: :ok
  def put(provider_id, models, opts \\ []) when is_atom(provider_id) and is_list(models) do
    ttl = Keyword.get(opts, :ttl, @default_ttl)
    expires_at = System.monotonic_time(:millisecond) + ttl

    :ets.insert(@cache_table, {provider_id, models, expires_at})
    emit_telemetry(:put, provider_id, %{ttl: ttl, model_count: length(models)})

    :ok
  end

  @doc """
  Invalidates (removes) cached models for a provider.

  ## Examples

      Cache.invalidate(:openai)
  """
  @spec invalidate(atom()) :: :ok
  def invalidate(provider_id) when is_atom(provider_id) do
    :ets.delete(@cache_table, provider_id)
    emit_telemetry(:invalidate, provider_id)

    :ok
  end

  @doc """
  Clears all cached entries.

  ## Examples

      Cache.clear()
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@cache_table)
    emit_telemetry(:clear, :all)

    :ok
  end

  @doc """
  Returns cache statistics.

  ## Examples

      Cache.stats()
      # => %{size: 10, table_info: [...]}
  """
  @spec stats() :: map()
  def stats do
    size = :ets.info(@cache_table, :size)
    memory = :ets.info(@cache_table, :memory)

    %{
      size: size,
      memory_words: memory,
      memory_bytes: memory * :erlang.system_info(:wordsize)
    }
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS table with read concurrency for performance
    :ets.new(@cache_table, [
      :named_table,
      :set,
      :public,
      read_concurrency: true,
      write_concurrency: false
    ])

    schedule_cleanup()

    Logger.debug("Model registry cache initialized",
      table: @cache_table,
      ttl: @default_ttl,
      cleanup_interval: @cleanup_interval
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired_entries()
    schedule_cleanup()

    {:noreply, state}
  end

  # Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired_entries do
    now = System.monotonic_time(:millisecond)

    # Select and delete expired entries
    num_deleted =
      :ets.select_delete(@cache_table, [
        {{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}
      ])

    if num_deleted > 0 do
      emit_telemetry(:cleanup, :expired, %{deleted_count: num_deleted})

      Logger.debug("Cleaned up expired cache entries",
        deleted: num_deleted,
        remaining: :ets.info(@cache_table, :size)
      )
    end

    num_deleted
  end

  defp emit_telemetry(action, provider_id, metadata \\ %{}) do
    :telemetry.execute(
      [:jido, :registry, :cache, action],
      %{count: 1},
      Map.merge(%{provider: provider_id}, metadata)
    )
  end
end
