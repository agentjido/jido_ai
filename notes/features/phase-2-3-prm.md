# Feature Planning Document: Phase 2.3 - Process Reward Model (PRM)

**Status:** Complete
**Section:** 2.3 - Process Reward Model
**Dependencies:** Phase 2.1 (Verifier Behaviors) - Complete, Phase 2.2 (Outcome Verifiers) - Complete
**Branch:** `feature/accuracy-phase-2-3-prm`

## Problem Statement

The accuracy improvement system can generate candidate responses (Phase 1), has verification interfaces (Phase 2.1), and has outcome verifiers that score final answers (Phase 2.2). However, it lacks **step-level verification** capabilities. Without Process Reward Models (PRMs):

1. **No Intermediate Step Evaluation**: Cannot score individual reasoning steps for early error detection
2. **No Process-Based Guidance**: Verification-guided search (Phase 3) cannot evaluate partial solutions
3. **Limited Error Localization**: Cannot identify which specific step in a reasoning chain is incorrect
4. **Weaker Reflection**: Reflection loops cannot target specific problematic steps

**Impact**: The system can only verify final answers, missing opportunities for early error detection and process-guided search.

## Solution Overview

Implement Process Reward Model (PRM) behavior and LLM-based PRM implementation for step-level reasoning evaluation:

1. **`Jido.AI.Accuracy.Prm`** - Behavior defining step-level verification interface
2. **`Jido.AI.Accuracy.Prms.LLMPrm`** - LLM-based step scoring implementation
3. **`Jido.AI.Accuracy.PrmAggregation`** - Strategies for combining step scores into candidate scores

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── prm.ex                           # Create - PRM behavior
├── prms/                            # Create - PRM implementations
│   └── llm_prm.ex                   # Create - LLM-based PRM
└── prm_aggregation.ex               # Create - Aggregation strategies

test/jido_ai/accuracy/
├── prm_test.exs                     # Create - PRM behavior tests
├── prms/                            # Create - PRM implementation tests
│   └── llm_prm_test.exs             # Create - LLM PRM tests
└── prm_aggregation_test.exs         # Create - Aggregation tests
```

## Implementation Plan

### Step 1: Create PRM Behavior (2.3.1)

**File:** `lib/jido_ai/accuracy/prm.ex`

- [x] 2.3.1.1 Create module with `@moduledoc` explaining PRM concept
- [x] 2.3.1.2 Define `@callback score_step/3`:
  ```elixir
  @callback score_step(
    step :: String.t(),
    context :: map(),
    opts :: keyword()
  ) :: {:ok, number()} | {:error, term()}
  ```
- [x] 2.3.1.3 Define `@callback score_trace/3`:
  ```elixir
  @callback score_trace(
    trace :: [String.t()],
    context :: map(),
    opts :: keyword()
  ) :: {:ok, [number()]} | {:error, term()}
  ```
- [x] 2.3.1.4 Define `@callback classify_step/3` for correct/incorrect/neutral
- [x] 2.3.1.5 Document PRM usage patterns in module docs

### Step 2: Implement LLM-Based PRM (2.3.2)

**File:** `lib/jido_ai/accuracy/prms/llm_prm.ex`

- [x] 2.3.2.1 Create module with `@behaviour Jido.AI.Accuracy.Prm`
- [x] 2.3.2.2 Add comprehensive `@moduledoc` explaining LLM-based PRM
- [x] 2.3.2.3 Define `defstruct` with configuration fields:
  - `:model` - Model for PRM scoring
  - `:prompt_template` - Step evaluation prompt
  - `:score_range` - {min, max} range for step scores
  - `:temperature` - Temperature for LLM calls
  - `:timeout` - Timeout for LLM calls in ms
- [x] 2.3.2.4 Implement `new/1` constructor with validation
- [x] 2.3.2.5 Implement `new!/1` constructor
- [x] 2.3.2.6 Implement `score_step/3` with evaluation prompt
- [x] 2.3.2.7 Implement `score_trace/3` with batch step scoring
- [x] 2.3.2.8 Implement `classify_step/3` for step classification
- [x] 2.3.2.9 Add default prompt template for step evaluation
- [x] 2.3.2.10 Extract step scores from LLM responses
- [x] 2.3.2.11 Support step context from previous steps
- [x] 2.3.2.12 Implement parallel step scoring option

### Step 3: Implement PRM Aggregation (2.3.3)

**File:** `lib/jido_ai/accuracy/prm_aggregation.ex`

- [x] 2.3.3.1 Create module with aggregation strategies
- [x] 2.3.3.2 Add comprehensive `@moduledoc` explaining strategies
- [x] 2.3.3.3 Implement `sum_scores/1` for total score
- [x] 2.3.3.4 Implement `product_scores/1` for probability-style
- [x] 2.3.3.5 Implement `min_score/1` for bottleneck approach
- [x] 2.3.3.6 Implement `max_score/1` for best-step approach
- [x] 2.3.3.7 Implement `weighted_average/2` for custom weights
- [x] 2.3.3.8 Implement `aggregate/2` with strategy selection
- [x] 2.3.3.9 Add `normalize_scores/2` for score normalization

### Step 4: Create PRMs Directory

- [x] Create `lib/jido_ai/accuracy/prms/` directory
- [x] Create `test/jido_ai/accuracy/prms/` directory

### Step 5: Write Unit Tests (2.3.4)

**File:** `test/jido_ai/accuracy/prm_test.exs`

- [x] Test PRM behavior documentation exists
- [x] Test callback types are defined

**File:** `test/jido_ai/accuracy/prms/llm_prm_test.exs`

- [x] Constructor tests (defaults, custom config, validation)
- [x] `score_step/3` tests (single step evaluation)
- [x] `score_trace/3` tests (multi-step evaluation)
- [x] `classify_step/3` tests (correct/incorrect/neutral)
- [x] Score extraction tests (various formats)
- [x] Prompt rendering tests
- [x] Context propagation tests
- [x] Parallel scoring tests
- [x] Edge cases (empty step, nil trace, etc.)

**File:** `test/jido_ai/accuracy/prm_aggregation_test.exs`

- [x] `sum_scores/1` tests
- [x] `product_scores/1` tests
- [x] `min_score/1` tests
- [x] `max_score/1` tests
- [x] `weighted_average/2` tests
- [x] `aggregate/2` with strategy selection
- [x] `normalize_scores/2` tests
- [x] Edge cases (empty list, single score, nil values)

### Step 6: Validation and Integration

- [x] Run all accuracy tests to ensure no regressions
- [x] Run `mix credo` and fix any issues
- [x] Check test coverage > 90%
- [x] Run `mix format` to ensure formatting

## Success Criteria

1. **PRM Behavior**: Clean interface for step-level verification
2. **LLMPrm**: LLM-based step scoring with classification
3. **Aggregation**: Multiple strategies for combining step scores
4. **Testing**: 50+ tests, >90% coverage
5. **Code Quality**: No credo warnings, follows established patterns

## Notes/Considerations

### Step Score Format

Step scores will be extracted from LLM responses using regex patterns similar to outcome verifiers:
- `Step Score: <number>` or `Score: <number>`
- Can handle decimal values and different ranges

### Step Classification

The `classify_step/3` callback will return:
- `:correct` - Step is logically sound and correct
- `:incorrect` - Step has errors or flaws
- `:neutral` - Step is ambiguous or cannot be determined

### Aggregation Strategies

Different aggregation strategies suit different use cases:
- **Sum**: Total score across all steps (good for overall quality)
- **Product**: Probability-style (any bad step kills score)
- **Min**: Bottleneck detection (weakest step determines quality)
- **Max**: Best-step approach (at least one good step)
- **Weighted Average**: Custom importance per step

### Context Propagation

When scoring traces, each step can have context from:
- The original prompt/question
- Previous step scores
- Current step index

## Current Status

**Status:** Complete ✅

**What's Done:**
- Feature branch created (`feature/accuracy-phase-2-3-prm`)
- Planning document created and all tasks completed
- PRM behavior implemented with step-level verification callbacks
- LLM-based PRM implemented with EEx templates, retry logic, and parallel scoring
- PRM aggregation strategies implemented (sum, product, min, max, average, weighted average)
- 124 tests written with >90% coverage (all passing)
- Code formatted and credo warnings addressed

**Implementation Summary:** See `notes/summaries/phase-2-3-prm.md`

**What's Next:**
- Awaiting user approval to commit and merge feature branch
- Proceed to Section 2.4: Tool-based verifiers
