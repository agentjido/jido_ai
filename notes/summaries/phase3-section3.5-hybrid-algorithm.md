# Phase 3 Section 3.5: Hybrid Algorithm - Summary

**Branch**: `feature/phase3-hybrid-algorithm`
**Date**: 2026-01-04
**Status**: Completed

## What Was Implemented

Created the `Jido.AI.Algorithms.Hybrid` module that combines sequential and parallel execution in configurable stages, with fallback support for resilient workflows.

## Files Created

1. **`lib/jido_ai/algorithms/hybrid.ex`** - Hybrid execution algorithm
2. **`test/jido_ai/algorithms/hybrid_test.exs`** - 29 comprehensive tests

## Technical Details

### Execution Flow

1. Stages are processed in order
2. Each stage runs according to its mode (:sequential or :parallel)
3. The output of each stage becomes the input to the next
4. If any stage fails, execution halts (unless fallbacks are configured)

### Context Options

- `:stages` - List of stage definitions to execute in order
- `:fallbacks` - Map of algorithm to fallback configuration

### Stage Definition

Each stage is a map with:
- `:algorithms` - (required) List of algorithm modules
- `:mode` - (required) `:sequential` or `:parallel`

For parallel stages, additional options:
- `:merge_strategy` - How to merge results (default: `:merge_maps`)
- `:error_mode` - Error handling (default: `:fail_fast`)
- `:max_concurrency` - Max parallel tasks
- `:timeout` - Per-task timeout

### Stage Shorthand

Single algorithm modules are normalized to sequential stages:
```elixir
stages = [
  ValidateInput,  # Equivalent to %{algorithms: [ValidateInput], mode: :sequential}
  %{algorithms: [FetchA, FetchB], mode: :parallel}
]
```

### Fallback Support

Fallbacks are configured as a map in the context:
```elixir
context = %{
  stages: [...],
  fallbacks: %{
    UnreliableAlgorithm => %{
      fallbacks: [Fallback1, Fallback2],
      timeout: 5000
    }
  }
}
```

When the primary algorithm fails, fallbacks are tried in order. Fallbacks only apply to sequential stages (parallel stages use `error_mode` instead).

### Telemetry Events

- `[:jido, :ai, :algorithm, :hybrid, :start]` - Execution started
- `[:jido, :ai, :algorithm, :hybrid, :stop]` - Execution completed
- `[:jido, :ai, :algorithm, :hybrid, :stage, :start]` - Stage started
- `[:jido, :ai, :algorithm, :hybrid, :stage, :stop]` - Stage completed

## Test Coverage

29 tests covering:
- Module setup and metadata
- Basic execute with empty/single/multiple stages
- Sequential stage execution (order, chaining, error halting)
- Parallel stage execution (concurrency, merge strategy, error mode)
- Multi-stage execution (order, output chaining, mixed modes)
- Stage shorthand (single module, map without mode)
- Fallback support (single fallback, multiple levels, all failures)
- can_execute?/2 validation
- Telemetry emission (start/stop, stage events)
- Integration with run_with_hooks

## Usage Example

```elixir
context = %{
  stages: [
    # Stage 1: Validate (sequential)
    %{algorithms: [ValidateSchema, NormalizeData], mode: :sequential},

    # Stage 2: Fetch from multiple sources (parallel)
    %{
      algorithms: [FetchFromAPI, FetchFromDB, FetchFromCache],
      mode: :parallel,
      merge_strategy: :merge_maps,
      error_mode: :ignore_errors
    },

    # Stage 3: Process and save (sequential)
    %{algorithms: [TransformData, SaveResults], mode: :sequential}
  ],
  fallbacks: %{
    FetchFromAPI => %{fallbacks: [FetchFromBackupAPI]}
  }
}

{:ok, result} = Hybrid.execute(input, context)
```

## Design Decisions

1. **Delegates to Parallel**: For parallel stages, delegates to the existing Parallel algorithm
2. **Inline sequential execution**: Implements sequential logic directly with fallback support
3. **Stage normalization**: Supports shorthand for simpler stage definitions
4. **Fallbacks for sequential only**: Parallel stages use error_mode for flexibility

## Next Steps

Section 3.6 (Composite Algorithm) will provide composition operators for building complex algorithm structures.
