# Task 2.4: Provider Adapter Optimization - Planning Document

## Overview

This document provides a comprehensive plan for optimizing the provider adapter layer in Jido AI, building upon the ReqLLM integration completed in Task 2.3.1. Since ReqLLM delegates to the Req HTTP client (which provides many optimizations out-of-the-box), this task focuses on leveraging and configuring those capabilities rather than reimplementing them.

**Key Context**: Post-Task 2.3.1, all providers delegate to Model.Registry which uses ReqLLM. ReqLLM is built on Req, a batteries-included HTTP client that already provides connection pooling, retries, compression, and caching capabilities.

---

## 1. Problem Statement

### Current State

After Task 2.3.1 migration:
- All providers delegate to `Jido.AI.Model.Registry`
- Registry uses `Jido.AI.Model.Registry.Adapter` to query ReqLLM
- ReqLLM uses Req HTTP client for all network operations
- Req provides connection pooling via Finch
- No explicit optimization configuration at Jido AI layer

### What Needs Optimization

1. **Request Optimization**:
   - Currently using default Req/Finch settings
   - No request batching for model discovery
   - No provider-specific timeout tuning
   - Retry strategies use Req defaults

2. **Response Processing**:
   - No caching of model listings (fetched every time)
   - Streaming responses use default buffering
   - JSON parsing not optimized for large model catalogs
   - No compression negotiation

3. **Connection Management**:
   - Using Req's default Finch pool
   - No provider-specific connection tuning
   - Pool timeouts not optimized per provider
   - No connection reuse metrics

### Why Optimization Matters

1. **Performance**: Model discovery across 57+ providers can be slow
2. **Resource Efficiency**: Unnecessary network calls and parsing overhead
3. **Reliability**: Better retry and timeout handling improves stability
4. **Scalability**: Connection pooling enables concurrent operations

---

## 2. Solution Overview

### High-Level Approach

Rather than reimplementing optimizations, we:
1. **Leverage Req Features**: Configure existing Req/Finch capabilities
2. **Add Jido AI Layer Optimizations**: Cache, batch, and optimize where Req doesn't
3. **Provider-Specific Tuning**: Configure per-provider settings for optimal performance
4. **Telemetry and Monitoring**: Add metrics to validate improvements

### What Req Already Provides

Based on Req documentation analysis:

#### Built-in Optimizations
1. **Connection Pooling** (via Finch):
   - HTTP/1.1 and HTTP/2 connection pooling
   - Configurable pool sizes and timeouts
   - Automatic connection reuse

2. **Retry Handling**:
   - Default retry on transient failures
   - Exponential backoff (1s, 2s, 4s, 8s)
   - Respects `Retry-After` headers
   - Configurable retry strategies

3. **Compression**:
   - Automatic request compression (`:compress_body`)
   - Automatic response decompression
   - Supports gzip encoding

4. **Caching**:
   - HTTP caching support (`:cache` option)
   - Respects cache headers
   - Configurable cache directory

5. **Timeouts**:
   - Connect timeout (default 30s)
   - Receive timeout (default 15s)
   - Pool checkout timeout (default 5s)

### What Jido AI Should Add

1. **Model Registry Caching**:
   - Cache model listings per provider
   - TTL-based invalidation
   - ETS-based for fast in-memory access

2. **Request Batching**:
   - Batch multiple model queries together
   - Reduce round-trips for discovery operations

3. **Provider-Specific Configuration**:
   - Timeout tuning per provider (some slower than others)
   - Retry strategy customization
   - Connection pool sizing

4. **Response Optimization**:
   - Streaming model catalog parsing
   - Lazy model struct creation
   - Optimized JSON decoding for large responses

---

## 3. Technical Details

### 3.1 Files to Modify

#### Core Files

1. **lib/jido_ai/model/registry.ex**
   - Add caching layer for model listings
   - Implement request batching
   - Configure Req options

2. **lib/jido_ai/model/registry/adapter.ex**
   - Add provider-specific Req configuration
   - Implement connection pooling per provider
   - Add retry strategy customization

3. **lib/jido_ai/application.ex**
   - Configure Finch pools at startup
   - Initialize caching infrastructure

#### New Files

4. **lib/jido_ai/model/registry/cache.ex** (new)
   - ETS-based model listing cache
   - TTL management
   - Cache invalidation

5. **lib/jido_ai/model/registry/optimizer.ex** (new)
   - Provider-specific configuration
   - Performance metrics collection
   - Adaptive optimization

### 3.2 Req Configuration Options

Based on Req documentation, these options are available:

```elixir
# Connection pooling (via Finch)
connect_options: [
  timeout: 30_000,              # Connection timeout
  protocols: [:http1, :http2],  # Supported protocols
  pool_timeout: 5_000,          # Pool checkout timeout
  receive_timeout: 15_000       # Response receive timeout
]

# Retry configuration
retry: :safe_transient,         # Retry strategy
max_retries: 3,                 # Maximum retry attempts
retry_delay: fn count -> ...    # Custom backoff function
retry_log_level: :warning       # Log level for retries

# Caching
cache: true,                    # Enable HTTP caching
cache_dir: "path/to/cache"      # Cache directory

# Compression
compressed: true,               # Request compression
compress_body: true             # Compress request body

# Response handling
decode_body: true,              # Auto-decode JSON
decode_json: []                 # Jason.decode!/2 options
```

### 3.3 Provider-Specific Settings

Different providers have different performance characteristics:

```elixir
# Fast providers (OpenAI, Anthropic)
@fast_provider_config %{
  connect_timeout: 5_000,
  receive_timeout: 10_000,
  max_retries: 2
}

# Medium providers (Google, Mistral)
@medium_provider_config %{
  connect_timeout: 10_000,
  receive_timeout: 15_000,
  max_retries: 3
}

# Slow providers (Regional, Self-hosted)
@slow_provider_config %{
  connect_timeout: 30_000,
  receive_timeout: 30_000,
  max_retries: 4
}
```

---

## 4. Implementation Plan

### Task 2.4.1: Request Optimization

#### 2.4.1.1: Implement Request Batching

**Goal**: Reduce network round-trips for model discovery

**Implementation**:
```elixir
# In lib/jido_ai/model/registry.ex
defmodule Jido.AI.Model.Registry do
  def batch_get_models(provider_ids) when is_list(provider_ids) do
    # Use Task.async_stream for concurrent requests
    provider_ids
    |> Task.async_stream(&list_models/1,
         max_concurrency: 10,
         timeout: 30_000)
    |> Enum.map(fn {:ok, result} -> result end)
  end
end
```

**Benefits**:
- Parallel model fetching across providers
- Reduced total discovery time
- Better resource utilization

**Testing**:
- Benchmark sequential vs batched discovery
- Verify all models retrieved correctly
- Test error handling with partial failures

#### 2.4.1.2: Add Connection Pooling Optimization

**Goal**: Configure provider-specific Finch pools

**Implementation**:
```elixir
# In lib/jido_ai/application.ex
def start(_type, _args) do
  children = [
    Jido.AI.Keyring,
    Jido.AI.ReqLlmBridge.ConversationManager,
    # Add custom Finch pool
    {Finch,
     name: JidoAI.Finch,
     pools: %{
       # Fast providers - smaller pool, shorter timeouts
       default: [
         size: 10,
         count: 2,
         conn_opts: [
           timeout: 5_000
         ],
         pool_max_idle_time: 30_000
       ]
     }}
  ]

  opts = [strategy: :one_for_one, name: Jido.AI.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**Benefits**:
- Reuse connections across requests
- Reduced connection overhead
- Better concurrency support

**Testing**:
- Monitor connection reuse metrics
- Test concurrent request handling
- Verify no connection leaks

#### 2.4.1.3: Configure Optimal Timeout Values

**Goal**: Provider-specific timeout tuning

**Implementation**:
```elixir
# In lib/jido_ai/model/registry/optimizer.ex
defmodule Jido.AI.Model.Registry.Optimizer do
  @provider_configs %{
    openai: %{
      connect_timeout: 5_000,
      receive_timeout: 10_000,
      pool_timeout: 3_000
    },
    anthropic: %{
      connect_timeout: 5_000,
      receive_timeout: 10_000,
      pool_timeout: 3_000
    },
    google: %{
      connect_timeout: 10_000,
      receive_timeout: 15_000,
      pool_timeout: 5_000
    },
    # Regional/slower providers
    default: %{
      connect_timeout: 30_000,
      receive_timeout: 30_000,
      pool_timeout: 5_000
    }
  }

  def get_provider_config(provider_id) do
    Map.get(@provider_configs, provider_id, @provider_configs.default)
  end
end
```

**Benefits**:
- Faster failures for fast providers
- Adequate time for slow providers
- Better user experience

**Testing**:
- Test timeout behavior per provider
- Verify appropriate error messages
- Benchmark response times

#### 2.4.1.4: Implement Adaptive Retry Strategies

**Goal**: Provider-specific retry configuration

**Implementation**:
```elixir
# In lib/jido_ai/model/registry/adapter.ex
defp build_req_options(provider_id) do
  base_opts = [
    retry: &retry_strategy/2,
    max_retries: get_max_retries(provider_id),
    retry_delay: &exponential_backoff/1,
    retry_log_level: :info
  ]

  merge_provider_config(base_opts, provider_id)
end

defp retry_strategy(req, response_or_error) do
  case response_or_error do
    %{status: status} when status in [408, 429, 500, 502, 503, 504] ->
      true
    %Req.TransportError{reason: reason} when reason in [:timeout, :econnrefused] ->
      true
    _ ->
      false
  end
end

defp exponential_backoff(retry_count) do
  # 1s, 2s, 4s, 8s with jitter
  base_delay = :math.pow(2, retry_count) * 1000
  jitter = :rand.uniform(500)
  trunc(base_delay + jitter)
end
```

**Benefits**:
- Better handling of transient failures
- Reduced error rates
- Improved reliability

**Testing**:
- Test retry behavior under simulated failures
- Verify backoff timing
- Check max retry limits

### Task 2.4.2: Response Processing Optimization

#### 2.4.2.1: Implement Streaming Response Buffering

**Goal**: Optimize streaming response handling

**Implementation**:
```elixir
# In lib/jido_ai/req_llm_bridge/streaming_adapter.ex
# Already exists, enhance with buffering

def adapt_stream(req_llm_stream, opts \\ []) do
  buffer_size = Keyword.get(opts, :buffer_size, 100)

  req_llm_stream
  |> Stream.chunk_every(buffer_size)
  |> Stream.flat_map(&process_chunk_batch/1)
  # ... existing transformation
end

defp process_chunk_batch(chunks) do
  # Process multiple chunks together for efficiency
  Enum.map(chunks, &transform_chunk/1)
end
```

**Benefits**:
- Reduced per-chunk overhead
- Better throughput for streaming
- Smoother user experience

**Testing**:
- Benchmark streaming performance
- Test with various buffer sizes
- Verify no data loss

#### 2.4.2.2: Add Response Caching for Idempotent Requests

**Goal**: Cache model listings to reduce network calls

**Implementation**:
```elixir
# In lib/jido_ai/model/registry/cache.ex (new file)
defmodule Jido.AI.Model.Registry.Cache do
  use GenServer

  @cache_table :jido_model_cache
  @default_ttl 3_600_000  # 1 hour

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    :ets.new(@cache_table, [:named_table, :set, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  def get(provider_id) do
    case :ets.lookup(@cache_table, provider_id) do
      [{^provider_id, models, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, models}
        else
          :cache_miss
        end
      [] ->
        :cache_miss
    end
  end

  def put(provider_id, models, ttl \\ @default_ttl) do
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@cache_table, {provider_id, models, expires_at})
    :ok
  end

  def invalidate(provider_id) do
    :ets.delete(@cache_table, provider_id)
    :ok
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)  # Every minute
  end

  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@cache_table, [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", now}], [true]}
    ])
    schedule_cleanup()
    {:noreply, state}
  end
end
```

**Benefits**:
- Dramatically reduced network calls
- Faster model discovery
- Lower API costs

**Testing**:
- Test cache hit/miss scenarios
- Verify TTL expiration
- Test cache invalidation
- Benchmark cache performance

#### 2.4.2.3: Optimize JSON Parsing for Large Responses

**Goal**: Efficient JSON parsing for model catalogs

**Implementation**:
```elixir
# In lib/jido_ai/model/registry/adapter.ex
defp build_req_options(provider_id) do
  [
    decode_json: [
      keys: :atoms!,           # Faster atom key conversion
      strings: :copy           # Reduce binary fragmentation
    ],
    receive_timeout: 30_000    # Adequate for large responses
  ]
end
```

**Benefits**:
- Faster JSON decoding
- Reduced memory fragmentation
- Better performance with large catalogs

**Testing**:
- Benchmark JSON parsing performance
- Test with large model catalogs (ReqLLM has 2000+ models)
- Monitor memory usage

#### 2.4.2.4: Implement Response Compression

**Goal**: Reduce bandwidth usage

**Implementation**:
```elixir
# In lib/jido_ai/model/registry/adapter.ex
defp build_req_options(provider_id) do
  [
    compressed: true,          # Request compressed responses
    headers: [
      "accept-encoding": "gzip, deflate"
    ]
  ]
end
```

**Benefits**:
- Reduced bandwidth usage
- Faster response transfer
- Lower costs for metered connections

**Testing**:
- Verify compression is negotiated
- Test decompression correctness
- Benchmark transfer speeds

---

## 5. Success Criteria

### Performance Targets

1. **Model Discovery Performance**:
   - Single provider: < 500ms (cached), < 2s (uncached)
   - All providers: < 10s (parallel batching)
   - 80% cache hit rate after warmup

2. **Connection Efficiency**:
   - 90%+ connection reuse rate
   - < 100ms pool checkout time
   - No connection leaks

3. **Retry Effectiveness**:
   - < 1% requests fail after retries
   - Average 1.2 requests per operation (including retries)
   - Exponential backoff observed in logs

4. **Response Processing**:
   - JSON parsing: < 10ms per 100 models
   - Streaming: < 5ms latency per chunk
   - Memory usage: < 50MB for full catalog

### Functional Requirements

1. **Request Batching**:
   - Batch discovery across multiple providers works
   - Partial failures don't block whole batch
   - Results correctly associated with providers

2. **Connection Pooling**:
   - Connections properly reused
   - Provider-specific pools configured
   - Graceful degradation on pool exhaustion

3. **Caching**:
   - Model listings cached per provider
   - TTL expiration works correctly
   - Manual invalidation supported
   - Cache survives application restarts (optional)

4. **Compression**:
   - Response compression negotiated
   - Decompression transparent to consumers
   - Fallback to uncompressed if needed

### Quality Requirements

1. **Backward Compatibility**:
   - All existing tests pass
   - No breaking changes to public APIs
   - Performance improvements transparent

2. **Error Handling**:
   - Timeouts produce clear errors
   - Retry failures logged appropriately
   - Cache errors don't crash operations

3. **Monitoring**:
   - Telemetry events for key operations
   - Cache hit/miss metrics
   - Connection pool metrics
   - Retry attempt metrics

---

## 6. Testing Strategy

### Unit Tests

#### 2.4.1.1 - Request Batching Tests
```elixir
defmodule Jido.AI.Model.RegistryBatchingTest do
  test "batch_get_models fetches from multiple providers concurrently" do
    providers = [:openai, :anthropic, :google]
    {:ok, results} = Registry.batch_get_models(providers)

    assert length(results) == 3
    assert Enum.all?(results, &match?({:ok, _models}, &1))
  end

  test "batch handles partial failures gracefully" do
    providers = [:openai, :invalid_provider, :anthropic]
    {:ok, results} = Registry.batch_get_models(providers)

    assert length(results) == 3
    assert {:error, _} = Enum.at(results, 1)
  end
end
```

#### 2.4.1.2 - Connection Pooling Tests
```elixir
defmodule Jido.AI.Model.Registry.PoolingTest do
  test "connection pool properly configured" do
    config = Optimizer.get_provider_config(:openai)

    assert config.connect_timeout == 5_000
    assert config.pool_timeout == 3_000
  end

  test "connections reused across requests" do
    # Make multiple requests to same provider
    for _ <- 1..10 do
      Registry.list_models(:openai)
    end

    # Check Finch metrics show connection reuse
    metrics = Finch.get_pool_status(JidoAI.Finch, :default)
    assert metrics.connections_reused > 5
  end
end
```

#### 2.4.1.3 - Timeout Configuration Tests
```elixir
defmodule Jido.AI.Model.Registry.TimeoutTest do
  test "fast provider uses short timeout" do
    config = Optimizer.get_provider_config(:openai)
    assert config.connect_timeout == 5_000
  end

  test "slow provider uses long timeout" do
    config = Optimizer.get_provider_config(:local_provider)
    assert config.connect_timeout == 30_000
  end

  test "timeout errors properly handled" do
    # Simulate timeout
    assert {:error, %Req.TransportError{reason: :timeout}} =
      Registry.list_models(:slow_provider)
  end
end
```

#### 2.4.1.4 - Retry Strategy Tests
```elixir
defmodule Jido.AI.Model.Registry.RetryTest do
  test "retries on transient failures" do
    # Mock provider that fails twice then succeeds

    {:ok, _models} = Registry.list_models(:flaky_provider)

    # Check logs show 2 retry attempts
    assert_logged(:info, "Retrying request (attempt 1)")
    assert_logged(:info, "Retrying request (attempt 2)")
  end

  test "exponential backoff applied" do
    # Check retry delays increase exponentially
    delays = capture_retry_delays()

    assert Enum.at(delays, 0) in 1000..1500
    assert Enum.at(delays, 1) in 2000..2500
    assert Enum.at(delays, 2) in 4000..4500
  end
end
```

#### 2.4.2.2 - Caching Tests
```elixir
defmodule Jido.AI.Model.Registry.CacheTest do
  test "cache stores and retrieves models" do
    models = [%Model{id: "gpt-4"}]

    :ok = Cache.put(:openai, models)
    assert {:ok, ^models} = Cache.get(:openai)
  end

  test "cache expires after TTL" do
    models = [%Model{id: "gpt-4"}]
    Cache.put(:openai, models, 100)  # 100ms TTL

    assert {:ok, ^models} = Cache.get(:openai)
    Process.sleep(150)
    assert :cache_miss = Cache.get(:openai)
  end

  test "cache invalidation works" do
    models = [%Model{id: "gpt-4"}]
    Cache.put(:openai, models)

    Cache.invalidate(:openai)
    assert :cache_miss = Cache.get(:openai)
  end
end
```

### Integration Tests

#### Full Stack Optimization Tests
```elixir
defmodule Jido.AI.Model.Registry.IntegrationTest do
  test "model discovery uses cache on second call" do
    # First call - cache miss
    start = System.monotonic_time(:millisecond)
    {:ok, models1} = Registry.list_models(:openai)
    time1 = System.monotonic_time(:millisecond) - start

    # Second call - cache hit
    start = System.monotonic_time(:millisecond)
    {:ok, models2} = Registry.list_models(:openai)
    time2 = System.monotonic_time(:millisecond) - start

    assert models1 == models2
    assert time2 < time1 / 10  # Cache should be 10x faster
  end

  test "compression reduces bandwidth" do
    # Monitor network bytes transferred
    {:ok, _models} = Registry.list_models(:openai)

    # Check compression was used
    assert_telemetry_event([:req, :response, :compression], %{
      ratio: ratio
    })

    assert ratio > 0.5  # At least 50% compression
  end
end
```

### Performance Benchmarks

```elixir
defmodule Jido.AI.Model.RegistryBenchmark do
  use Benchee

  def run do
    Benchee.run(%{
      "list_models (cached)" => fn ->
        Registry.list_models(:openai)
      end,
      "list_models (uncached)" => fn ->
        Cache.invalidate(:openai)
        Registry.list_models(:openai)
      end,
      "batch_get_models (10 providers)" => fn ->
        providers = [:openai, :anthropic, :google, ...]
        Registry.batch_get_models(providers)
      end
    })
  end
end
```

---

## 7. Implementation Steps

### Phase 1: Foundation (2-3 hours)

1. **Create Cache Infrastructure**
   - Implement `lib/jido_ai/model/registry/cache.ex`
   - Add to supervision tree
   - Write cache unit tests

2. **Create Optimizer Module**
   - Implement `lib/jido_ai/model/registry/optimizer.ex`
   - Define provider configurations
   - Write configuration tests

3. **Update Application Supervisor**
   - Configure custom Finch pool
   - Initialize cache
   - Add telemetry handlers

### Phase 2: Request Optimization (3-4 hours)

1. **Implement Request Batching (2.4.1.1)**
   - Add `batch_get_models/1` function
   - Test concurrent fetching
   - Benchmark improvements

2. **Configure Connection Pooling (2.4.1.2)**
   - Update Finch pool settings
   - Add provider-specific pools
   - Monitor connection reuse

3. **Add Timeout Configuration (2.4.1.3)**
   - Implement provider timeout settings
   - Update Registry.Adapter
   - Test timeout behavior

4. **Implement Retry Strategies (2.4.1.4)**
   - Add retry configuration
   - Implement backoff logic
   - Test retry behavior

### Phase 3: Response Optimization (2-3 hours)

1. **Enhance Streaming (2.4.2.1)**
   - Update StreamingAdapter with buffering
   - Test streaming performance
   - Benchmark improvements

2. **Integrate Caching (2.4.2.2)**
   - Update Registry to use cache
   - Add cache warming on startup
   - Monitor cache hit rates

3. **Optimize JSON Parsing (2.4.2.3)**
   - Configure JSON decode options
   - Test with large catalogs
   - Benchmark parsing speed

4. **Enable Compression (2.4.2.4)**
   - Configure compression settings
   - Test compression negotiation
   - Monitor bandwidth savings

### Phase 4: Testing & Validation (2-3 hours)

1. **Unit Testing**
   - Write comprehensive unit tests
   - Test error scenarios
   - Verify all configurations

2. **Integration Testing**
   - End-to-end optimization tests
   - Performance benchmarks
   - Cache behavior validation

3. **Performance Validation**
   - Run benchmarks against baselines
   - Verify performance targets met
   - Document improvements

### Phase 5: Documentation & Monitoring (1-2 hours)

1. **Add Telemetry Events**
   - Cache hit/miss events
   - Connection pool events
   - Retry attempt events

2. **Update Documentation**
   - Document configuration options
   - Add optimization guide
   - Update module docs

3. **Create Migration Guide**
   - Document new features
   - Provide tuning examples
   - Add troubleshooting tips

---

## 8. Risks and Mitigations

### High Risk

**Risk**: Cache invalidation bugs lead to stale data
- **Impact**: Users see outdated model lists
- **Mitigation**:
  - Conservative TTL (1 hour)
  - Manual invalidation API
  - Comprehensive cache tests
  - Monitoring for staleness

**Risk**: Connection pool exhaustion under load
- **Impact**: Requests timeout or fail
- **Mitigation**:
  - Monitor pool metrics
  - Implement graceful degradation
  - Add pool size alerting
  - Load testing before deployment

### Medium Risk

**Risk**: Provider-specific timeouts too aggressive
- **Impact**: Unnecessary failures for slow providers
- **Mitigation**:
  - Conservative initial timeouts
  - Monitoring and tuning
  - Provider-specific overrides
  - Gradual optimization

**Risk**: Memory usage increases with caching
- **Impact**: Higher memory consumption
- **Mitigation**:
  - Monitor cache size
  - Implement cache size limits
  - Use TTL to bound growth
  - Profile memory usage

### Low Risk

**Risk**: JSON parsing optimization breaks edge cases
- **Impact**: Some models fail to parse
- **Mitigation**:
  - Comprehensive test coverage
  - Fallback to default parsing
  - Error monitoring

---

## 9. Monitoring and Telemetry

### Key Metrics

1. **Cache Performance**:
   - `[:jido, :registry, :cache, :hit]` - Cache hit count
   - `[:jido, :registry, :cache, :miss]` - Cache miss count
   - `[:jido, :registry, :cache, :size]` - Cache entry count
   - `[:jido, :registry, :cache, :eviction]` - TTL evictions

2. **Connection Pool**:
   - `[:finch, :pool, :checkout]` - Pool checkout timing
   - `[:finch, :pool, :reuse]` - Connection reuse count
   - `[:finch, :pool, :size]` - Active connections

3. **Request Performance**:
   - `[:jido, :registry, :discover_models]` - Discovery timing
   - `[:jido, :registry, :batch_get_models]` - Batch timing
   - `[:req, :request, :retry]` - Retry attempts

4. **Response Processing**:
   - `[:req, :response, :compression]` - Compression ratio
   - `[:jido, :registry, :json_parse]` - JSON parse timing
   - `[:jido, :streaming, :chunk]` - Streaming chunk rate

### Telemetry Implementation

```elixir
defmodule Jido.AI.Model.Registry.Telemetry do
  def attach do
    events = [
      [:jido, :registry, :cache, :hit],
      [:jido, :registry, :cache, :miss],
      [:jido, :registry, :discover_models],
      [:jido, :registry, :batch_get_models]
    ]

    :telemetry.attach_many(
      "jido-registry-telemetry",
      events,
      &handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, metadata, _config) do
    # Log or send to monitoring service
    Logger.debug("Telemetry: #{inspect(event)}",
      measurements: measurements,
      metadata: metadata
    )
  end
end
```

---

## 10. Migration and Rollout

### Compatibility

All optimizations are **internal improvements** with:
- No breaking API changes
- Transparent to existing code
- Backward compatible behavior
- Opt-in advanced features

### Rollout Plan

1. **Phase 1**: Deploy with optimizations disabled
   - Verify deployment success
   - Monitor baseline metrics

2. **Phase 2**: Enable caching
   - Start with long TTL (1 hour)
   - Monitor cache effectiveness
   - Tune TTL based on metrics

3. **Phase 3**: Enable connection optimizations
   - Apply provider configs gradually
   - Monitor connection metrics
   - Adjust pool sizes as needed

4. **Phase 4**: Enable full optimizations
   - Compression, retry strategies
   - Monitor performance improvements
   - Document final configuration

### Feature Flags

```elixir
config :jido_ai, :optimizations,
  caching_enabled: true,
  cache_ttl: 3_600_000,
  connection_pooling: true,
  compression: true,
  adaptive_retries: true,
  request_batching: true
```

---

## 11. Expected Outcomes

### Performance Improvements

Based on optimization techniques:

1. **Model Discovery**:
   - Cached: 20-50x faster (~50ms vs 1-2s)
   - Batched: 5-10x faster for multiple providers
   - Overall: 70-90% reduction in discovery time

2. **Network Efficiency**:
   - 50-70% bandwidth reduction (compression)
   - 90%+ connection reuse
   - 50-80% fewer total requests (caching)

3. **Reliability**:
   - <1% failure rate (with retries)
   - Better handling of transient failures
   - Graceful degradation under load

### Resource Savings

1. **API Calls**: 80%+ reduction (caching)
2. **Bandwidth**: 50%+ reduction (compression + caching)
3. **Latency**: 70%+ reduction (connection reuse + caching)

---

## 12. Future Enhancements

Beyond Task 2.4 scope, future improvements could include:

1. **Adaptive Timeout Tuning**: Machine learning-based timeout optimization
2. **Predictive Caching**: Pre-fetch popular models
3. **Load Balancing**: Distribute across multiple provider endpoints
4. **Circuit Breakers**: Automatic fallback for failing providers
5. **Request Coalescing**: Merge duplicate concurrent requests
6. **Persistent Cache**: Survive application restarts
7. **Smart Batching**: Adaptive batch sizes based on load

---

## Conclusion

Task 2.4 focuses on leveraging Req's built-in optimization capabilities and adding Jido AI-specific enhancements where needed. The key insight is that ReqLLM already provides a solid foundation through Req, so we optimize configuration and add strategic caching rather than reimplementing low-level optimizations.

**Key Success Factors**:
1. Leverage existing Req/Finch features
2. Add caching for significant performance gains
3. Provider-specific tuning for optimal behavior
4. Comprehensive testing and monitoring
5. Gradual rollout with feature flags

**Primary Deliverables**:
1. Model registry caching layer
2. Provider-specific Req configuration
3. Request batching for concurrent operations
4. Enhanced telemetry and monitoring
5. Comprehensive test suite
6. Performance benchmarks

This plan balances performance improvements with maintainability, leveraging existing infrastructure while adding targeted optimizations where they provide the most value.
