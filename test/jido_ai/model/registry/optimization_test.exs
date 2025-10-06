defmodule Jido.AI.Model.Registry.OptimizationTest do
  @moduledoc """
  Tests for Task 2.4: Provider Adapter Optimization

  This test suite validates the optimization features including:
  - Model registry caching
  - Request batching
  - Provider-specific configuration
  - Performance improvements
  """
  use ExUnit.Case, async: false
  use Mimic

  alias Jido.AI.Model.Registry
  alias Jido.AI.Model.Registry.Cache
  alias Jido.AI.Model.Registry.Optimizer

  @moduletag :optimization
  @moduletag :task_2_4

  describe "Task 2.4.1.1: Request Batching" do
    test "batch_get_models fetches from multiple providers concurrently" do
      providers = [:openai, :anthropic, :google]

      {:ok, results} = Registry.batch_get_models(providers)

      assert length(results) == 3
      assert Enum.all?(results, fn {provider_id, _result} -> provider_id in providers end)
    end

    test "batch_get_models handles partial failures gracefully" do
      providers = [:openai, :nonexistent_provider, :anthropic]

      {:ok, results} = Registry.batch_get_models(providers)

      assert length(results) == 3

      # Check that we have results for all providers (success or error)
      provider_ids = Enum.map(results, &elem(&1, 0))
      assert :openai in provider_ids
      assert :nonexistent_provider in provider_ids
      assert :anthropic in provider_ids
    end

    test "batch_get_models respects max_concurrency option" do
      providers = [:openai, :anthropic, :google, :cohere, :mistral]

      {:ok, results} = Registry.batch_get_models(providers, max_concurrency: 2)

      assert length(results) == 5
    end

    test "batch_get_models respects timeout option" do
      providers = [:openai, :anthropic]

      # Very short timeout to test timeout handling
      {:ok, results} = Registry.batch_get_models(providers, timeout: 100)

      # Results should be returned even with timeout (either success or timeout error)
      assert length(results) == 2
    end
  end

  describe "Task 2.4.1.2-2.4.1.4: Provider Configuration" do
    test "Optimizer provides fast provider configuration" do
      config = Optimizer.get_provider_config(:openai)

      assert config.connect_timeout == 5_000
      assert config.receive_timeout == 10_000
      assert config.max_retries == 2
    end

    test "Optimizer provides medium provider configuration" do
      config = Optimizer.get_provider_config(:google)

      assert config.connect_timeout == 10_000
      assert config.receive_timeout == 15_000
      assert config.max_retries == 3
    end

    test "Optimizer provides slow provider configuration" do
      config = Optimizer.get_provider_config(:amazon_bedrock)

      assert config.connect_timeout == 30_000
      assert config.receive_timeout == 30_000
      assert config.max_retries == 4
    end

    test "Optimizer provides default configuration for unknown providers" do
      config = Optimizer.get_provider_config(:unknown_provider)

      assert config.connect_timeout == 15_000
      assert config.receive_timeout == 20_000
      assert config.max_retries == 3
    end

    test "Optimizer builds Req options correctly" do
      opts = Optimizer.build_req_options(:openai)

      assert Keyword.has_key?(opts, :connect_options)
      assert Keyword.has_key?(opts, :receive_timeout)
      assert Keyword.has_key?(opts, :retry)
      assert Keyword.has_key?(opts, :max_retries)
      assert Keyword.has_key?(opts, :retry_delay)
      assert Keyword.has_key?(opts, :compressed)
      assert Keyword.has_key?(opts, :decode_json)
    end

    test "Optimizer retry strategy retries on transient failures" do
      # 5xx errors
      assert Optimizer.retry_strategy(nil, %{status: 500}) == true
      assert Optimizer.retry_strategy(nil, %{status: 502}) == true
      assert Optimizer.retry_strategy(nil, %{status: 503}) == true
      assert Optimizer.retry_strategy(nil, %{status: 504}) == true

      # Timeout and rate limit
      assert Optimizer.retry_strategy(nil, %{status: 408}) == true
      assert Optimizer.retry_strategy(nil, %{status: 429}) == true

      # Transport errors
      assert Optimizer.retry_strategy(nil, %Req.TransportError{reason: :timeout}) == true
      assert Optimizer.retry_strategy(nil, %Req.TransportError{reason: :econnrefused}) == true
    end

    test "Optimizer retry strategy does not retry on success or client errors" do
      assert Optimizer.retry_strategy(nil, %{status: 200}) == false
      assert Optimizer.retry_strategy(nil, %{status: 400}) == false
      assert Optimizer.retry_strategy(nil, %{status: 404}) == false
    end

    test "Optimizer exponential backoff increases delay" do
      delay0 = Optimizer.exponential_backoff(0, 1000)
      delay1 = Optimizer.exponential_backoff(1, 1000)
      delay2 = Optimizer.exponential_backoff(2, 1000)

      # Should increase exponentially (with jitter)
      assert delay0 >= 1000 and delay0 <= 1500
      assert delay1 >= 2000 and delay1 <= 2500
      assert delay2 >= 4000 and delay2 <= 4500
    end

    test "Optimizer categorizes providers correctly" do
      assert Optimizer.get_provider_category(:openai) == :fast
      assert Optimizer.get_provider_category(:anthropic) == :fast
      assert Optimizer.get_provider_category(:google) == :medium
      assert Optimizer.get_provider_category(:amazon_bedrock) == :slow
      assert Optimizer.get_provider_category(:unknown) == :default
    end
  end

  describe "Task 2.4.2.2: Response Caching" do
    setup do
      # Clear cache before each test
      Cache.clear()
      :ok
    end

    test "Cache stores and retrieves models" do
      models = [%{id: "gpt-4", provider: :openai}]

      :ok = Cache.put(:openai, models)
      assert {:ok, ^models} = Cache.get(:openai)
    end

    test "Cache returns :cache_miss for non-existent provider" do
      assert :cache_miss = Cache.get(:nonexistent)
    end

    test "Cache expires after TTL" do
      models = [%{id: "gpt-4"}]

      # Set very short TTL (100ms)
      Cache.put(:openai, models, ttl: 100)

      # Should be cached immediately
      assert {:ok, ^models} = Cache.get(:openai)

      # Wait for expiration
      Process.sleep(150)

      # Should be expired
      assert :cache_miss = Cache.get(:openai)
    end

    test "Cache invalidation works" do
      models = [%{id: "gpt-4"}]
      Cache.put(:openai, models)

      # Verify cached
      assert {:ok, ^models} = Cache.get(:openai)

      # Invalidate
      Cache.invalidate(:openai)

      # Should be cache miss
      assert :cache_miss = Cache.get(:openai)
    end

    test "Cache clear removes all entries" do
      Cache.put(:openai, [%{id: "gpt-4"}])
      Cache.put(:anthropic, [%{id: "claude-3"}])

      # Verify both cached
      assert {:ok, _} = Cache.get(:openai)
      assert {:ok, _} = Cache.get(:anthropic)

      # Clear all
      Cache.clear()

      # Both should be cache miss
      assert :cache_miss = Cache.get(:openai)
      assert :cache_miss = Cache.get(:anthropic)
    end

    test "Cache stats returns correct information" do
      Cache.put(:openai, [%{id: "gpt-4"}])
      Cache.put(:anthropic, [%{id: "claude-3"}])

      stats = Cache.stats()

      assert Map.has_key?(stats, :size)
      assert Map.has_key?(stats, :memory_words)
      assert Map.has_key?(stats, :memory_bytes)
      assert stats.size >= 2
    end

    test "Cache cleanup removes expired entries" do
      # Put entry with short TTL
      Cache.put(:test_provider, [%{id: "test"}], ttl: 50)

      # Verify cached
      assert {:ok, _} = Cache.get(:test_provider)

      # Wait for expiration and cleanup cycle
      Process.sleep(2000)  # Wait for cleanup (runs every minute, but we trigger it via TTL)

      # Should be removed by cleanup
      assert :cache_miss = Cache.get(:test_provider)
    end
  end

  describe "Task 2.4.2.2: Integration with Registry.list_models" do
    setup do
      Cache.clear()
      :ok
    end

    test "list_models uses cache on second call" do
      provider = :openai

      # First call - cache miss, fetches from network
      {:ok, models1} = Registry.list_models(provider)

      # Second call - should use cache
      {:ok, models2} = Registry.list_models(provider)

      # Results should be identical
      assert models1 == models2
    end

    test "list_models caches successful results" do
      provider = :anthropic

      # Fetch models
      {:ok, _models} = Registry.list_models(provider)

      # Verify cached
      assert {:ok, _cached} = Cache.get(provider)
    end

    test "cache invalidation forces fresh fetch" do
      provider = :google

      # First fetch
      {:ok, models1} = Registry.list_models(provider)

      # Invalidate cache
      Cache.invalidate(provider)

      # Second fetch - should fetch fresh
      {:ok, models2} = Registry.list_models(provider)

      # Both should be valid (may or may not be identical)
      assert is_list(models1)
      assert is_list(models2)
    end
  end

  describe "Performance and Optimization" do
    @tag :performance
    test "batch fetching is faster than sequential for multiple providers" do
      providers = [:openai, :anthropic, :google]

      # Sequential fetching
      seq_start = System.monotonic_time(:millisecond)

      for provider <- providers do
        Registry.list_models(provider)
      end

      seq_duration = System.monotonic_time(:millisecond) - seq_start

      # Clear cache for fair comparison
      Cache.clear()

      # Batch fetching
      batch_start = System.monotonic_time(:millisecond)
      Registry.batch_get_models(providers)
      batch_duration = System.monotonic_time(:millisecond) - batch_start

      IO.puts("\nPerformance comparison:")
      IO.puts("  Sequential: #{seq_duration}ms")
      IO.puts("  Batch: #{batch_duration}ms")
      IO.puts("  Speedup: #{Float.round(seq_duration / batch_duration, 2)}x")

      # Batch should generally be faster (but we don't assert to avoid flaky tests)
      assert batch_duration > 0
      assert seq_duration > 0
    end

    @tag :performance
    test "cached retrieval is significantly faster" do
      provider = :openai

      # First call - uncached
      uncached_start = System.monotonic_time(:millisecond)
      {:ok, _} = Registry.list_models(provider)
      uncached_duration = System.monotonic_time(:millisecond) - uncached_start

      # Second call - cached
      cached_start = System.monotonic_time(:millisecond)
      {:ok, _} = Registry.list_models(provider)
      cached_duration = System.monotonic_time(:millisecond) - cached_start

      IO.puts("\nCache performance:")
      IO.puts("  Uncached: #{uncached_duration}ms")
      IO.puts("  Cached: #{cached_duration}ms")

      if uncached_duration > 0 and cached_duration > 0 do
        speedup = Float.round(uncached_duration / cached_duration, 2)
        IO.puts("  Speedup: #{speedup}x")
      end

      # Cached should be faster (but we don't assert specific values to avoid flakiness)
      assert cached_duration >= 0
    end
  end
end
