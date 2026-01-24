# Phase 3 Section 3.5: Hybrid Algorithm

**Branch**: `feature/phase3-hybrid-algorithm`
**Status**: Completed
**Created**: 2026-01-04

## Problem Statement

Complex AI workflows often need a mix of sequential and parallel execution. We need an algorithm that combines both patterns, allowing stages to run either sequentially or in parallel, with support for fallback algorithms when primary ones fail.

## Solution Overview

Create `Jido.AI.Algorithms.Hybrid` module that:
1. Uses Base module for standard algorithm infrastructure
2. Processes stages in order, each stage having its own execution mode
3. Supports sequential or parallel execution per stage
4. Provides fallback algorithm support for resilience
5. Chains stage outputs to next stage inputs

## Technical Details

### File Structure

```
lib/jido_ai/
├── algorithms/
│   ├── algorithm.ex   # Behavior (done in 3.1)
│   ├── base.ex        # Base (done in 3.2)
│   ├── sequential.ex  # Sequential (done in 3.3)
│   ├── parallel.ex    # Parallel (done in 3.4)
│   └── hybrid.ex      # Hybrid execution

test/jido_ai/
├── algorithms/
│   └── hybrid_test.exs # Hybrid tests
```

### Stage Structure

```elixir
%{
  algorithms: [AlgorithmA, AlgorithmB],
  mode: :sequential | :parallel,
  # Optional parallel options when mode: :parallel
  merge_strategy: :merge_maps,
  error_mode: :fail_fast,
  max_concurrency: 4
}
```

### Fallback Structure

```elixir
%{
  PrimaryAlgorithm => %{
    fallbacks: [Fallback1, Fallback2],
    timeout: 5000  # optional timeout for primary
  }
}
```

### Context Options

- `:stages` - List of stage definitions to execute in order
- `:fallbacks` - Map of algorithm to fallback configuration

### Execution Flow

1. Process each stage in order
2. For sequential stages: run algorithms in sequence, chain outputs
3. For parallel stages: run algorithms concurrently, merge results
4. Pass stage output as next stage input
5. On error, check for fallbacks and try alternatives

---

## Implementation Plan

### 3.5.1 Module Setup
- [x] 3.5.1.1 Create `lib/jido_ai/algorithms/hybrid.ex` with module documentation
- [x] 3.5.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.5.1.3 Document hybrid execution semantics

### 3.5.2 Execution Stages
- [x] 3.5.2.1 Define stage map structure with algorithms and mode
- [x] 3.5.2.2 Implement `execute/2` that processes stages in order
- [x] 3.5.2.3 Execute each stage according to its mode (sequential/parallel)
- [x] 3.5.2.4 Pass stage output to next stage input

### 3.5.3 Stage Configuration
- [x] 3.5.3.1 Support inline stage definition in context
- [x] 3.5.3.2 Support shorthand for single-algorithm stages
- [x] 3.5.3.3 Validate stage configuration

### 3.5.4 Fallback Support
- [x] 3.5.4.1 Support algorithm to fallbacks mapping in context
- [x] 3.5.4.2 Try primary algorithm first
- [x] 3.5.4.3 Fall back on error
- [x] 3.5.4.4 Support multiple fallback levels

### 3.5.5 Unit Tests for Hybrid Algorithm
- [x] Test execute/2 processes stages in order
- [x] Test sequential stage execution
- [x] Test parallel stage execution
- [x] Test mixed mode stages
- [x] Test stage output passed to next stage
- [x] Test fallback on primary failure
- [x] Test multiple fallback levels
- [x] Test empty stages handling

---

## Success Criteria

1. [x] Hybrid algorithm module created using Base
2. [x] Stages execute in order with correct mode
3. [x] Stage outputs chain to next stage inputs
4. [x] Fallback support works correctly
5. [x] All unit tests pass (29 tests)

## Current Status

**What Works**: All features implemented, 29 tests passing
**How to Run**: `mix test test/jido_ai/algorithms/hybrid_test.exs`

---

## Notes

- Stages are processed sequentially, but each stage's algorithms can run in parallel
- Delegates to Parallel algorithm for parallel stage execution
- Implements sequential execution inline with fallback support
- Fallbacks only work with sequential stages (parallel uses error_mode instead)
- Shorthand: single module treated as sequential stage, map without mode defaults to sequential
