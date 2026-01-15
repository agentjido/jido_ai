# Phase 7.2: Compute Budgeter - Implementation Plan

**Date:** 2026-01-14
**Feature Branch:** `feature/accuracy-phase-7-2-compute-budgeter`
**Target Branch:** `feature/accuracy`
**Status:** COMPLETED

---

## Overview

This feature implements the Compute Budgeter for adaptive compute budgeting (Phase 7.2). The Compute Budgeter allocates computational resources based on query difficulty estimates, enabling efficient resource usage by giving more compute to difficult tasks and less to easy tasks.

---

## Problem Statement

### Current State
Phase 7.1 implemented difficulty estimation, but there is no mechanism to translate difficulty levels into concrete compute allocations. The system needs a way to:
- Map difficulty levels to generation parameters (num_candidates, PRM usage, search)
- Track compute budget usage across multiple queries
- Enforce global budget limits
- Support custom allocation strategies

### Impact
Without the Compute Budgeter:
- Difficulty estimates cannot be acted upon
- No adaptive resource allocation is possible
- Fixed compute budgets waste resources on easy tasks
- Complex queries may not get enough compute

### Solution
Implement a ComputeBudgeter module that:
- Maps difficulty levels to specific compute parameters
- Tracks budget usage across queries
- Supports global budget limits
- Allows custom allocation strategies

---

## Solution Overview

### Architecture

```
DifficultyEstimate → ComputeBudgeter → Allocation
                            │
                            ├── Budget (per difficulty level)
                            ├── Tracking (usage counters)
                            └── Limits (global constraints)
```

### Components

1. **ComputeBudget** - Struct representing a compute allocation
2. **ComputeBudgeter** - Main module for budget allocation and tracking

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Allocation storage | Struct with parameters | Clear, type-safe representation |
| Budget tracking | In-memory counters | Simple, fast, no external deps |
| Global limit | Optional total budget cap | Prevent runaway compute usage |
| Custom strategies | Configurable mapping | Flexibility for different use cases |

---

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── compute_budget.ex                    (NEW) Allocation result struct
└── compute_budgeter.ex                  (NEW) Budget allocation module

test/jido_ai/accuracy/
├── compute_budget_test.exs              (NEW) Struct tests
└── compute_budgeter_test.exs            (NEW) Budgeter tests
```

### Dependencies

- **Jido.AI.Accuracy.DifficultyEstimate** - For difficulty levels
- **Jido.AI.Accuracy.Helpers** - Shared helper functions

---

## Difficulty to Budget Mapping

| Difficulty | num_candidates | use_prm | use_search | search_iterations | max_refinements |
|------------|----------------|---------|------------|-------------------|-----------------|
| Easy       | 3              | false   | false      | N/A               | N/A             |
| Medium     | 5              | true    | false      | N/A               | 1               |
| Hard       | 10             | true    | true       | 50                | 2               |

### Budget Cost Model

Each allocation has an associated "cost" for tracking:

| Resource | Cost Factor |
|----------|-------------|
| Base candidate | 1.0 |
| PRM step | 0.5 |
| Search iteration | 0.01 |
| Refinement | 1.0 |

Example costs:
- Easy: 3 × 1.0 = 3.0
- Medium: 5 × 1.0 + 5 × 0.5 = 7.5
- Hard: 10 × 1.0 + 10 × 0.5 + 50 × 0.01 + 2 × 1.0 = 17.5

---

## Success Criteria

1. ✅ **ComputeBudget struct** with allocation parameters
2. ✅ **ComputeBudgeter module** with allocation functions
3. ✅ **Difficulty-based allocation** maps levels correctly
4. ✅ **Budget tracking** tracks usage correctly
5. ✅ **Global limits** enforced when configured
6. ✅ **Custom strategies** supported via configuration
7. ✅ **Unit tests** with minimum 85% coverage
8. ✅ **No compiler warnings**

---

## Implementation Plan

### Step 1: ComputeBudget Struct

**File:** `lib/jido_ai/accuracy/compute_budget.ex`

Result struct representing a compute allocation.

```elixir
defmodule Jido.AI.Accuracy.ComputeBudget do
  @moduledoc """
  Represents a compute allocation for generation.

  Contains parameters for self-consistency sampling, PRM verification,
  search iterations, and refinement steps.
  """

  defstruct [
    :num_candidates,
    :use_prm,
    :use_search,
    :max_refinements,
    :search_iterations,
    :prm_threshold,
    :cost,
    metadata: %{}
  ]
end
```

**Tasks:**
- [x] 7.2.1.1 Create file with defstruct
- [x] 7.2.1.2 Add new/1 and new!/1 constructors
- [x] 7.2.1.3 Implement easy/0, medium/0, hard/0 presets
- [x] 7.2.1.4 Implement cost calculation
- [x] 7.2.1.5 Add to_map/1 and from_map/1 serialization
- [x] 7.2.1.6 Add validation helpers

---

### Step 2: ComputeBudgeter Module

**File:** `lib/jido_ai/accuracy/compute_budgeter.ex`

Main module for budget allocation and tracking.

```elixir
defmodule Jido.AI.Accuracy.ComputeBudgeter do
  @moduledoc """
  Allocates compute resources based on difficulty estimates.

  Maps difficulty levels to generation parameters and tracks usage.
  """

  defstruct [
    :easy_budget,
    :medium_budget,
    :hard_budget,
    :global_limit,
    :used_budget,
    :allocation_count
  ]
end
```

**Tasks:**
- [x] 7.2.2.1 Create file with defstruct
- [x] 7.2.2.2 Add new/1 and new!/1 constructors
- [x] 7.2.2.3 Implement allocate/3 for difficulty-based allocation
- [x] 7.2.2.4 Implement allocate_for_easy/1
- [x] 7.2.2.5 Implement allocate_for_medium/1
- [x] 7.2.2.6 Implement allocate_for_hard/1
- [x] 7.2.2.7 Implement custom_allocation/4

---

### Step 3: Budget Tracking

Implement tracking and management functions.

**Tasks:**
- [x] 7.2.3.1 Implement track_usage/2
- [x] 7.2.3.2 Implement check_budget/2
- [x] 7.2.3.3 Implement remaining_budget/1
- [x] 7.2.3.4 Implement budget_exhausted?/1
- [x] 7.2.3.5 Implement reset_budget/1
- [x] 7.2.3.6 Implement get_usage_stats/1

---

### Step 4: Unit Tests

**Test Files:**
- `test/jido_ai/accuracy/compute_budget_test.exs`
- `test/jido_ai/accuracy/compute_budgeter_test.exs`

**Test Scenarios:**

ComputeBudget:
- [x] new/1 creates valid budget
- [x] new!/1 raises on invalid input
- [x] easy/0 preset returns correct defaults
- [x] medium/0 preset returns correct defaults
- [x] hard/0 preset returns correct defaults
- [x] Cost calculation is correct
- [x] Serialization works

ComputeBudgeter:
- [x] allocate/3 returns correct parameters for each difficulty
- [x] Easy tasks get minimal compute (N=3, no PRM)
- [x] Medium tasks get medium compute (N=5, with PRM)
- [x] Hard tasks get maximum compute (N=10, PRM + search)
- [x] Budget tracking accumulates correctly
- [x] Global limit is respected
- [x] Budget exhaustion is detected
- [x] Custom allocation strategies work
- [x] Reset budget clears tracking
- [x] Usage stats are accurate

**Tasks:**
- [x] 7.2.4.1 Create test file for ComputeBudget
- [x] 7.2.4.2 Create test file for ComputeBudgeter
- [x] 7.2.4.3 Run tests and verify 85%+ coverage
- [x] 7.2.4.4 Fix any compiler warnings

---

## Progress Tracking

- [x] Step 1: ComputeBudget struct
- [x] Step 2: ComputeBudgeter module
- [x] Step 3: Budget tracking
- [x] Step 4: Unit tests

## Implementation Summary

All components have been implemented and tested successfully:
- **86 tests passing** (36 for ComputeBudget, 50 for ComputeBudgeter)
- **0 failures**
- Test files:
  - `test/jido_ai/accuracy/compute_budget_test.exs`
  - `test/jido_ai/accuracy/compute_budgeter_test.exs`

---

## Notes and Considerations

### Priority Order
1. Implement ComputeBudget struct first (simple)
2. Implement ComputeBudgeter with basic allocation
3. Add budget tracking
4. Write comprehensive tests

### Pattern Consistency
- Follow DifficultyEstimate pattern for struct design
- Use Helpers.get_attr for attribute access
- Return {:ok, result} | {:error, reason} tuples
- Include comprehensive @moduledoc with examples

### Future Enhancements
- Persistent budget storage (ETS/database)
- Time-based budget windows
- Priority queues for budget allocation
- Multi-tenant budget isolation
- Budget prediction based on historical usage

### Edge Cases to Handle
- Global limit set too low (should error on construct)
- Negative budget values (validation)
- Concurrent access (consider GenServer if needed)
- Budgeter state mutations (return new struct)

---

**Last Updated:** 2026-01-14
