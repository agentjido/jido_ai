# Phase 7.1: Difficulty Estimation - Implementation Plan

**Date:** 2026-01-14
**Feature Branch:** `feature/accuracy-phase-7-1-difficulty-estimation`
**Target Branch:** `feature/accuracy`
**Status:** COMPLETED

---

## Overview

This feature implements difficulty estimation for adaptive compute budgeting (Phase 7). Difficulty estimation allows the system to classify queries as easy, medium, or hard, enabling efficient resource allocation by giving more compute to difficult tasks and less to easy ones.

---

## Problem Statement

### Current State
The accuracy system currently allocates the same amount of compute resources regardless of query complexity. This is inefficient because:
- Simple questions (e.g., "What is 2+2?") don't need multiple candidates and verification
- Complex questions (e.g., multi-step reasoning) benefit from more compute
- Fixed allocation wastes resources on easy tasks and under-serves hard tasks

### Impact
Without difficulty estimation:
- Higher compute costs than necessary
- Slower response times for simple queries
- Potentially lower accuracy on complex queries

### Solution
Implement difficulty estimators that classify queries by complexity, enabling:
- **Easy queries**: N=3 candidates, no PRM, fast response
- **Medium queries**: N=5 candidates, with PRM
- **Hard queries**: N=10 candidates, PRM + search

---

## Solution Overview

### Architecture

```
Query → DifficultyEstimator → DifficultyEstimate
                                  │
                                  ├── level: :easy | :medium | :hard
                                  ├── score: 0.0 - 1.0
                                  ├── confidence: 0.0 - 1.0
                                  ├── reasoning: explanation
                                  └── features: contributing factors
```

### Components

1. **DifficultyEstimator Behavior** - Interface for difficulty estimation
2. **DifficultyEstimate** - Result struct with level, score, confidence, reasoning
3. **HeuristicDifficultyEstimator** - Fast, rule-based estimation
4. **LLMDifficultyEstimator** - LLM-powered classification

### Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Difficulty levels | 3 levels (easy/medium/hard) | Maps cleanly to compute budgets |
| Score range | 0.0 - 1.0 | Consistent with confidence scores |
| Heuristic priority | Implement first | Faster, no LLM dependency |
| LLM estimator | Optional enhancement | More accurate but slower |

---

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── difficulty_estimator.ex           (NEW) Behavior definition
├── difficulty_estimate.ex             (NEW) Result struct
└── estimators/
    ├── heuristic_difficulty.ex        (NEW) Rule-based estimator
    └── llm_difficulty.ex              (NEW) LLM-based estimator

test/jido_ai/accuracy/
├── difficulty_estimator_test.exs      (NEW) Behavior tests
├── difficulty_estimate_test.exs       (NEW) Struct tests
└── estimators/
    ├── heuristic_difficulty_test.exs  (NEW) Heuristic tests
    └── llm_difficulty_test.exs        (NEW) LLM tests
```

### Dependencies

- **Jido.AI.Accuracy.Helpers** - Shared helper functions (get_attr)
- **Existing patterns** - Follow ConfidenceEstimator pattern

---

## Success Criteria

1. ✅ **DifficultyEstimator behavior** defined with proper callbacks
2. ✅ **DifficultyEstimate struct** with validation and predicates
3. ✅ **HeuristicDifficultyEstimator** classifies queries by complexity
4. ✅ **LLMDifficultyEstimator** uses LLM for classification
5. ✅ **Unit tests** for all components (minimum 85% coverage)
6. ✅ **No compiler warnings**
7. ✅ **Pattern consistency** with existing accuracy modules

---

## Implementation Plan

### Step 1: DifficultyEstimator Behavior

**File:** `lib/jido_ai/accuracy/difficulty_estimator.ex`

Follow the pattern of `ConfidenceEstimator`:

```elixir
defmodule Jido.AI.Accuracy.DifficultyEstimator do
  @moduledoc """
  Behavior for difficulty estimation in adaptive compute budgeting.

  Difficulty estimators analyze queries to determine how complex they are,
  enabling efficient resource allocation by giving more compute to difficult
  tasks and less to easy tasks.
  """

  @callback estimate(
    estimator :: struct(),
    query :: String.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.DifficultyEstimate.t()} | {:error, term()}
end
```

**Tasks:**
- [x] 7.1.1.1 Create file with behavior definition
- [x] 7.1.1.2 Add comprehensive @moduledoc
- [x] 7.1.1.3 Define @callback estimate/3
- [x] 7.1.1.4 Document difficulty levels and usage

---

### Step 2: DifficultyEstimate Struct

**File:** `lib/jido_ai/accuracy/difficulty_estimate.ex`

Follow the pattern of `ConfidenceEstimate`:

```elixir
defmodule Jido.AI.Accuracy.DifficultyEstimate do
  @moduledoc """
  Represents a difficulty estimate for a query.

  ## Fields
  - `:level` - :easy, :medium, or :hard
  - `:score` - Numeric difficulty score (0.0 - 1.0)
  - `:confidence` - Confidence in the estimate (0.0 - 1.0)
  - `:reasoning` - Explanation for difficulty assessment
  - `:features` - Contributing features map
  - `:metadata` - Additional metadata
  """

  @type level :: :easy | :medium | :hard

  defstruct [
    :level,
    :score,
    :confidence,
    :reasoning,
    features: %{},
    metadata: %{}
  ]

  # Constructor, predicates, helpers
end
```

**Tasks:**
- [x] 7.1.2.1 Create file with defstruct
- [x] 7.1.2.2 Add new/1 and new!/1 constructors
- [x] 7.1.2.3 Implement easy?/1, medium?/1, hard?/1 predicates
- [x] 7.1.2.4 Implement to_level/1 for score conversion
- [x] 7.1.2.5 Add validation for score and confidence ranges
- [x] 7.1.2.6 Add to_map/1 and from_map/1 for serialization

---

### Step 3: HeuristicDifficultyEstimator

**File:** `lib/jido_ai/accuracy/estimators/heuristic_difficulty.ex`

Fast, rule-based estimation using query features:

```elixir
defmodule Jido.AI.Accuracy.Estimators.HeuristicDifficulty do
  @moduledoc """
  Fast difficulty estimation using heuristics.

  ## Features
  - Query length
  - Word complexity
  - Domain indicators (math, code, reasoning)
  - Question type indicators
  """

  # Estimate based on weighted features
  def estimate(estimator, query, context)
end
```

**Feature Extraction:**

| Feature | Weight | Indicators |
|---------|--------|------------|
| Length | 0.2 | Character count |
| Complexity | 0.3 | Long words, special chars |
| Domain | 0.3 | math: $\sum$, code: `function`, etc. |
| Question type | 0.2 | why/how vs what/when |

**Scoring:**
- Score < 0.35 → Easy
- Score 0.35 - 0.65 → Medium
- Score > 0.65 → Hard

**Tasks:**
- [x] 7.1.3.1 Create file with @behaviour DifficultyEstimator
- [x] 7.1.3.2 Implement feature extraction (length, complexity, domain)
- [x] 7.1.3.3 Implement weighted scoring
- [x] 7.1.3.4 Implement score to level mapping
- [x] 7.1.3.5 Generate reasoning from features
- [x] 7.1.3.6 Add new/1 and new!/1 constructors

---

### Step 4: LLMDifficultyEstimator

**File:** `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`

LLM-powered classification (optional enhancement):

```elixir
defmodule Jido.AI.Accuracy.Estimators.LLMDifficulty do
  @moduledoc """
  LLM-based difficulty estimation.

  Uses a fast LLM to classify query difficulty with reasoning.
  """

  defstruct [:model, :prompt_template]

  def estimate(estimator, query, context)
end
```

**Prompt Template:**

```
Classify the difficulty of this query: {{query}}

Respond with JSON:
{
  "level": "easy|medium|hard",
  "confidence": 0.0-1.0,
  "reasoning": "explanation"
}
```

**Tasks:**
- [x] 7.1.4.1 Create file with @behaviour DifficultyEstimator
- [x] 7.1.4.2 Define configuration (model, prompt)
- [x] 7.1.4.3 Implement estimate/3 with LLM call
- [x] 7.1.4.4 Parse JSON response
- [x] 7.1.4.5 Handle errors and timeouts
- [x] 7.1.4.6 Add new/1 and new!/1 constructors

---

### Step 5: Unit Tests

**Test Files:**
- `test/jido_ai/accuracy/difficulty_estimate_test.exs`
- `test/jido_ai/accuracy/estimators/heuristic_difficulty_test.exs`
- `test/jido_ai/accuracy/estimators/llm_difficulty_test.exs`

**Test Coverage:**

| Component | Tests | Coverage Target |
|-----------|-------|-----------------|
| DifficultyEstimate | 15+ | 100% |
| HeuristicDifficulty | 20+ | 90%+ |
| LLMDifficulty | 15+ | 85%+ |

**Test Scenarios:**

DifficultyEstimate:
- [x] new/1 creates valid estimate
- [x] new!/1 raises on invalid input
- [x] easy?/1, medium?/1, hard?/1 predicates
- [x] to_level/1 score conversion
- [x] Validation: score must be 0-1
- [x] Validation: confidence must be 0-1
- [x] Validation: level must be easy/medium/hard
- [x] to_map/1 and from_map/1 serialization

HeuristicDifficulty:
- [x] Simple query → easy
- [x] Complex query → hard
- [x] Medium complexity → medium
- [x] Math queries detected
- [x] Code queries detected
- [x] Reasoning queries detected
- [x] Feature extraction works
- [x] Weighted scoring correct
- [x] Reasoning generated

LLMDifficulty:
- [x] Returns valid difficulty estimate
- [x] Includes confidence
- [x] Includes reasoning
- [x] Handles LLM errors
- [x] Handles timeouts
- [x] Parses JSON correctly
- [x] Invalid JSON handled

**Tasks:**
- [x] 7.1.5.1 Create test file for DifficultyEstimate
- [x] 7.1.5.2 Create test file for HeuristicDifficulty
- [x] 7.1.5.3 Create test file for LLMDifficulty
- [x] 7.1.5.4 Run tests and verify 85%+ coverage
- [x] 7.1.5.5 Fix any compiler warnings

---

## Progress Tracking

- [x] Step 1: DifficultyEstimator behavior
- [x] Step 2: DifficultyEstimate struct
- [x] Step 3: HeuristicDifficultyEstimator
- [x] Step 4: LLMDifficultyEstimator
- [x] Step 5: Unit tests

## Implementation Summary

All components have been implemented and tested successfully:
- **73 tests passing** (32 for DifficultyEstimate, 22 for HeuristicDifficulty, 19 for LLMDifficulty)
- **0 failures**
- Test files:
  - `test/jido_ai/accuracy/difficulty_estimate_test.exs`
  - `test/jido_ai/accuracy/estimators/heuristic_difficulty_test.exs`
  - `test/jido_ai/accuracy/estimators/llm_difficulty_test.exs`

### Key Fixes During Implementation
1. Fixed regex argument order for pipe operator
2. Added empty query validation
3. Implemented batch estimation with proper estimator instance creation
4. Added LLM availability check with fallback simulation

---

## Notes and Considerations

### Priority Order
1. Implement HeuristicDifficulty first (no LLM dependency)
2. Write tests for HeuristicDifficulty
3. Implement LLMDifficulty as optional enhancement
4. Full integration test suite

### Pattern Consistency
- Follow ConfidenceEstimator/ConfidenceEstimate patterns
- Use Helpers.get_attr for attribute access
- Return {:ok, result} | {:error, reason} tuples
- Include comprehensive @moduledoc

### Future Enhancements
- Ensemble difficulty estimation (combine heuristic + LLM)
- Adaptive feature weights based on feedback
- Domain-specific estimators
- Cached difficulty estimates for repeated queries

---

**Last Updated:** 2026-01-14
