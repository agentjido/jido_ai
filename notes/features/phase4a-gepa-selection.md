# Phase 4A.4: GEPA Selection Module

## Summary

Implement the Selection module for GEPA (Genetic-Pareto Prompt Evolution). The Selection module implements Pareto-optimal selection for multi-objective optimization, allowing GEPA to balance competing objectives like accuracy vs. token cost.

## Planning Document

See: `notes/planning/architecture/phase-04A-gepa-strategy.md` (Section 4A.4)

## Problem Statement

After evaluating prompt variants, we need to select which ones survive to the next generation. This requires:
1. Finding Pareto-optimal solutions (non-dominated variants)
2. Handling multiple objectives with different optimization directions
3. Selecting a diverse set of survivors for the next generation

## Technical Design

### Pareto Dominance

A variant A **dominates** variant B if:
- A is at least as good as B on all objectives
- A is strictly better than B on at least one objective

The **Pareto front** is the set of all non-dominated variants.

### Objectives

Each objective has:
- A metric name (e.g., `:accuracy`, `:token_cost`)
- An optimization direction (`:maximize` or `:minimize`)

Default objectives:
- `{:accuracy, :maximize}` - Higher accuracy is better
- `{:token_cost, :minimize}` - Lower cost is better

### Module Structure

```elixir
defmodule Jido.AI.GEPA.Selection do
  # Core functions
  def pareto_front(variants, objectives)
  def dominates?(variant_a, variant_b, objectives)
  def select_survivors(variants, count, opts)

  # Helpers
  def crowding_distance(variants, objectives)
  def nsga2_select(variants, count, objectives)
end
```

### Function Signatures

1. **`pareto_front/2`**
   - Input: `variants` (list), `objectives` (list of `{metric, direction}`)
   - Output: List of non-dominated PromptVariants
   - Algorithm: O(n²) pairwise comparison

2. **`dominates?/3`**
   - Input: `variant_a`, `variant_b`, `objectives`
   - Output: `true` if A dominates B, `false` otherwise

3. **`select_survivors/3`**
   - Input: `variants`, `count`, `opts` (objectives, strategy)
   - Output: List of `count` selected variants
   - Strategies: `:pareto_first`, `:nsga2`, `:weighted`

4. **`crowding_distance/2`**
   - Input: `variants`, `objectives`
   - Output: Map of variant_id -> crowding distance
   - Used for diversity in NSGA-II selection

## Implementation Plan

### Step 1: Create Selection Module Skeleton
- [x] Create `lib/jido_ai/gepa/selection.ex`
- [x] Define module structure and typespecs
- [x] Add @moduledoc with usage examples

### Step 2: Implement dominates?/3
- [x] Compare variants on each objective
- [x] Handle maximize vs minimize directions
- [x] Return true only if strictly dominates

### Step 3: Implement pareto_front/2
- [x] Filter to only evaluated variants
- [x] Find all non-dominated variants
- [x] Return Pareto-optimal set

### Step 4: Implement select_survivors/3
- [x] Implement :pareto_first strategy (Pareto front, then best remaining)
- [x] Implement :nsga2 strategy with non-dominated sorting
- [x] Implement :weighted strategy with custom weights
- [x] Implement crowding distance for diversity
- [x] Support configurable selection count

### Step 5: Add Unit Tests
- [x] Test domination logic (9 tests)
- [x] Test Pareto front calculation (7 tests)
- [x] Test survivor selection (10 tests)
- [x] Test crowding distance (4 tests)
- [x] Test edge cases (5 tests)

## Current Status

**COMPLETED** - 2026-01-05

## Files Created

- `lib/jido_ai/gepa/selection.ex` (~320 lines)
- `test/jido_ai/gepa/selection_test.exs` (~290 lines)

## Test Results

35 tests passing covering:
- Domination logic with various objective combinations
- Pareto front calculation
- Three selection strategies (pareto_first, nsga2, weighted)
- Crowding distance for diversity maintenance
- Edge cases (nil values, zero values, equal variants)

## Dependencies

- `Jido.AI.GEPA.PromptVariant` - For accessing variant metrics
