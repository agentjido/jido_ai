# Fix: Remove Unnecessary Model Registry Cache

## Issue Summary

**Problem**: 60GB memory leak during test suite execution causing OOM (Out of Memory) kill after 45-92 seconds.

**Root Cause**: The `Jido.AI.Model.Registry.Cache` GenServer duplicates model metadata that is already instantly available from `ReqLLM.Provider.Registry`. This unnecessary caching layer:

1. Duplicates data already in memory (ReqLLM is a local library, not a network service)
2. Accumulates model data across all test runs with no cleanup between tests
3. Only runs cleanup in `ExUnit.after_suite` which never executes due to OOM kill
4. Adds GenServer overhead and TTL management complexity for zero performance benefit

**Evidence**:
- Model catalog is ~27k entries
- Memory consumption reaches 60GB before crash
- Cache accumulation across ~400-500 tests with no cleanup
- ReqLLM.Provider.Registry provides instant access (compiled data, no I/O)

## Root Cause Analysis

### Why Cache Exists
The cache was likely implemented under the assumption that:
- Model lookups might be expensive
- Repeated lookups need optimization
- Caching would improve performance

### Why Cache is Unnecessary
1. **ReqLLM is Local**: Not a remote service - it's an Elixir library with compiled data
2. **No I/O Operations**: Model metadata is already in memory as Elixir terms
3. **Instant Access**: Direct module access is as fast as ETS lookup
4. **Cache Overhead**: GenServer calls + ETS operations add latency vs direct access
5. **Memory Cost**: Duplicate storage of already-instant data
6. **Complexity**: TTL management, cache invalidation, GenServer supervision

### Why Cache Causes Leak
1. **Shared State**: Cache GenServer runs throughout entire test suite
2. **No Per-Test Cleanup**: Only `ExUnit.after_suite` cleanup which never runs
3. **Accumulation**: Each test module adds to cache without clearing
4. **OOM Before Cleanup**: Test process killed before cleanup can execute

## Solution Overview

**Remove the cache layer entirely** and call `ReqLLM.Provider.Registry` directly from `Jido.AI.Model.Registry`.

**Benefits**:
- Eliminates 60GB memory leak
- Reduces code complexity (remove entire cache module)
- Improves performance (no GenServer/ETS overhead)
- Simplifies architecture (fewer moving parts)
- Easier testing (no shared state between tests)

## Technical Implementation

### Files to Modify

#### 1. lib/jido_ai/application.ex
**Change**: Remove Cache from supervision tree

```elixir
# BEFORE:
children = [
  Jido.AI.Keyring,
  Jido.AI.ReqLlmBridge.ConversationManager,
  Jido.AI.Model.Registry.Cache  # <-- REMOVE THIS
]

# AFTER:
children = [
  Jido.AI.Keyring,
  Jido.AI.ReqLlmBridge.ConversationManager
]
```

#### 2. lib/jido_ai/model/registry.ex
**Change**: Replace cache calls with direct ReqLLM calls

Current cache usage locations:
- Line 80: `case provider_id && Cache.get(provider_id) do`
- Line 126: `Cache.put(pid, models)`

**Strategy**:
- Remove all `alias Jido.AI.Model.Registry.Cache` references
- Replace `Cache.get(provider_id)` with direct `ReqLLM.Provider.Registry.list()` filtered by provider
- Remove `Cache.put()` calls entirely
- Ensure all model lookups go directly to ReqLLM

#### 3. lib/jido_ai/model/registry/cache.ex
**Change**: Delete entire file

This file should be removed completely as it's no longer needed.

#### 4. test/jido_ai/model/registry/cache_test.exs (if exists)
**Change**: Delete cache tests

Remove any tests specifically for the cache module.

### Implementation Steps

1. **Read registry.ex** to understand current cache usage patterns
2. **Identify all cache call sites** in registry.ex
3. **Design ReqLLM direct access pattern** to replace cache
4. **Update registry.ex** with direct ReqLLM calls
5. **Remove cache from application.ex** supervision tree
6. **Delete cache.ex** file
7. **Remove cache tests** if they exist
8. **Run test suite** to verify leak is resolved

### Edge Cases to Consider

1. **Provider ID Resolution**: Ensure ReqLLM provider IDs match Jido provider atoms
2. **Error Handling**: ReqLLM errors should be handled consistently
3. **Performance**: Verify no regressions in model lookup speed
4. **Test Coverage**: Ensure existing registry tests still pass

## Testing Strategy

### Verification Tests

1. **Memory Leak Resolution**:
   - Run `mix test` with `/usr/bin/time -v`
   - Verify Maximum resident set size < 500MB (down from 60GB)
   - Verify tests complete successfully without OOM

2. **Functional Tests**:
   - All existing `registry_test.exs` tests pass
   - Model lookup functionality unchanged
   - Provider resolution works correctly
   - Error handling preserved

3. **Integration Tests**:
   - `model_catalog_integration_test.exs` passes
   - `provider_registry_integration_test.exs` passes
   - No regressions in existing functionality

### Success Criteria

- ✅ Test suite completes without OOM kill
- ✅ Memory usage stays under 500MB during full test run
- ✅ All existing tests pass
- ✅ No performance regressions in model lookups
- ✅ Code is simpler (fewer lines, no cache complexity)

## Rollback Plan

If this fix causes issues:

1. **Revert Strategy**: Git revert the fix commit
2. **Alternative Approaches**:
   - Add per-module cleanup if ETS proves necessary
   - Implement LRU cache with size limits
   - Use process dictionary instead of shared GenServer

## Implementation Checkpoints

- [ ] Planning document created
- [ ] registry.ex analyzed for cache usage
- [ ] Direct ReqLLM access pattern designed
- [ ] registry.ex updated with ReqLLM calls
- [ ] application.ex updated (cache removed)
- [ ] cache.ex file deleted
- [ ] Cache tests removed
- [ ] Test suite run with memory monitoring
- [ ] Memory leak verified as resolved
- [ ] All tests passing

## Notes

- This fix aligns with Elixir best practices: prefer simplicity over premature optimization
- ReqLLM.Provider.Registry is designed for direct access, no caching needed
- Removing shared GenServer state improves test isolation and reliability
