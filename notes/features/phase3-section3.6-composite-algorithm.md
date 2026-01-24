# Phase 3 Section 3.6: Composite Algorithm

**Branch**: `feature/phase3-composite-algorithm`
**Status**: Completed
**Created**: 2026-01-04

## Problem Statement

Complex AI workflows require compositional patterns beyond simple sequential or parallel execution. We need operators that allow building algorithms from smaller pieces, with support for conditional execution, repetition, and dynamic composition at runtime.

## Solution Overview

Create `Jido.AI.Algorithms.Composite` module that:
1. Uses Base module for standard algorithm infrastructure
2. Provides composition operators (sequence, parallel, choice, repeat)
3. Supports dynamic composition at runtime
4. Enables conditional execution with predicate functions
5. Allows nested compositions for complex workflows

## Technical Details

### File Structure

```
lib/jido_ai/
├── algorithms/
│   ├── algorithm.ex   # Behavior (done in 3.1)
│   ├── base.ex        # Base (done in 3.2)
│   ├── sequential.ex  # Sequential (done in 3.3)
│   ├── parallel.ex    # Parallel (done in 3.4)
│   ├── hybrid.ex      # Hybrid (done in 3.5)
│   └── composite.ex   # Composite operators

test/jido_ai/
├── algorithms/
│   └── composite_test.exs # Composite tests
```

### Composition Operators

```elixir
# Sequential composition
Composite.sequence([AlgoA, AlgoB, AlgoC])

# Parallel composition
Composite.parallel([AlgoA, AlgoB], merge_strategy: :merge_maps)

# Choice/conditional selection
Composite.choice(fn input -> condition end, AlgoA, AlgoB)

# Repeat execution
Composite.repeat(Algorithm, times: 3)
Composite.repeat(Algorithm, while: fn result -> condition end)
```

### Dynamic Composition

```elixir
# Runtime composition
algo1 = Composite.sequence([A, B])
algo2 = Composite.parallel([C, D])
combined = Composite.compose(algo1, algo2)

# Nested compositions
nested = Composite.sequence([
  Composite.parallel([A, B]),
  C,
  Composite.choice(predicate, D, E)
])
```

### Conditional Execution

```elixir
# Predicate function
Composite.when_cond(fn input -> input.valid? end, Algorithm)

# Pattern matching on input
Composite.when_cond(%{type: :premium}, PremiumAlgorithm)
```

---

## Implementation Plan

### 3.6.1 Module Setup
- [x] 3.6.1.1 Create `lib/jido_ai/algorithms/composite.ex` with module documentation
- [x] 3.6.1.2 Use `Jido.AI.Algorithms.Base` with name and description
- [x] 3.6.1.3 Document composition patterns

### 3.6.2 Composition Operators
- [x] 3.6.2.1 Implement `sequence/1` for sequential composition
- [x] 3.6.2.2 Implement `parallel/1` for parallel composition
- [x] 3.6.2.3 Implement `choice/3` for conditional selection
- [x] 3.6.2.4 Implement `repeat/2` for repeated execution

### 3.6.3 Dynamic Composition
- [x] 3.6.3.1 Implement `compose/2` for runtime composition
- [x] 3.6.3.2 Support nested compositions
- [x] 3.6.3.3 Validate composition graph

### 3.6.4 Conditional Execution
- [x] 3.6.4.1 Implement `when_cond/2` for conditional execution
- [x] 3.6.4.2 Support predicate functions
- [x] 3.6.4.3 Support pattern matching on input

### 3.6.5 Unit Tests for Composite Algorithm
- [x] Test sequence/1 creates sequential composite
- [x] Test parallel/1 creates parallel composite
- [x] Test choice/3 selects based on condition
- [x] Test repeat/2 executes multiple times
- [x] Test compose/2 combines algorithms dynamically
- [x] Test nested compositions
- [x] Test when_cond/2 conditional execution
- [x] Test predicate function evaluation

---

## Success Criteria

1. [x] Composite algorithm module created using Base
2. [x] All composition operators work correctly
3. [x] Dynamic composition supports nesting
4. [x] Conditional execution works with predicates
5. [x] All unit tests pass (53 tests)

## Current Status

**What Works**: All features implemented, 53 tests passing, 194 total algorithm tests passing
**How to Run**: `mix test test/jido_ai/algorithms/composite_test.exs`

---

## Notes

- Composition operators return structs (not modules) that can be executed
- Implements own sequential/parallel execution to handle composite structs
- Supports deeply nested compositions
- Predicates can be functions or pattern maps
- Telemetry events emitted for each composition type
