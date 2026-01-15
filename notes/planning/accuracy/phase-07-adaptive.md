# Phase 7: Adaptive Compute Budgeting

This phase implements difficulty estimation and dynamic compute allocation. Adaptive budgeting ensures efficient use of compute resources by allocating more resources to difficult tasks and fewer resources to easy tasks.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Adaptive Compute Budgeter                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Query ──→ Estimate Difficulty ──→ Allocate Compute          │
│                  │                         │                 │
│                  ▼                         ▼                 │
│            ┌─────┴─────┐         ┌───────┬───────┐          │
│            │   Easy    │         │ Small │ Large │          │
│            │  Medium   │         │budget │budget │          │
│            │   Hard    │         └───────┴───────┘          │
│            └───────────┘                                   │
│                │                                            │
│                ▼                                            │
│            ┌─────┴─────┐                                   │
│            │ Adjust N  │                                   │
│            │ Add PRM   │                                   │
│            │ Add Search│                                   │
│            └───────────┘                                   │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| DifficultyEstimator behavior | Interface for difficulty estimation |
| DifficultyEstimate | Struct holding difficulty assessment |
| LLMDifficultyEstimator | Uses LLM to classify task difficulty |
| ComputeBudgeter | Allocates compute based on difficulty |
| AdaptiveSelfConsistency | Self-consistency with adaptive N |

---

## 7.1 Difficulty Estimator ✅ COMPLETED

Estimate task difficulty to guide resource allocation.

### 7.1.1 Difficulty Estimator Behavior ✅

Define the behavior for difficulty estimation.

- [x] 7.1.1.1 Create `lib/jido_ai/accuracy/difficulty_estimator.ex`
- [x] 7.1.1.2 Add `@moduledoc` explaining difficulty estimation
- [x] 7.1.1.3 Define `@callback estimate/3`:
  ```elixir
  @callback estimate(
    estimator :: struct(),
    query :: String.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.DifficultyEstimate.t()} | {:error, term()}
  ```
- [x] 7.1.1.4 Document difficulty levels

### 7.1.2 Difficulty Estimate ✅

Define the difficulty estimate struct.

- [x] 7.1.2.1 Create `lib/jido_ai/accuracy/difficulty_estimate.ex`
- [x] 7.1.2.2 Define `defstruct` with fields:
  - `:level` - :easy, :medium, or :hard
  - `:score` - Numeric difficulty score
  - `:confidence` - Confidence in estimate
  - `:reasoning` - Explanation for difficulty assessment
  - `:features` - Contributing features (length, domain, etc)
  - `:metadata` - Additional metadata
- [x] 7.1.2.3 Add `@moduledoc` with documentation
- [x] 7.1.2.4 Implement `new/1` constructor
- [x] 7.1.2.5 Implement `easy?/1`
- [x] 7.1.2.6 Implement `medium?/1`
- [x] 7.1.2.7 Implement `hard?/1`
- [x] 7.1.2.8 Implement `to_level/1` for score to level conversion

### 7.1.3 LLM Difficulty Estimator ✅

Use an LLM to estimate difficulty.

- [x] 7.1.3.1 Create `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`
- [x] 7.1.3.2 Add `@moduledoc` explaining LLM-based estimation
- [x] 7.1.3.3 Define configuration schema:
  - `:model` - Model for estimation (default: fast model)
  - `:prompt_template` - Custom classification prompt
- [x] 7.1.3.4 Implement `estimate/3` with classification prompt
- [x] 7.1.3.5 Return difficulty level and reasoning
- [x] 7.1.3.6 Include confidence in estimate
- [x] 7.1.3.7 Handle ambiguous cases

### 7.1.4 Heuristic Difficulty Estimator ✅

Use heuristics for fast difficulty estimation.

- [x] 7.1.4.1 Create `lib/jido_ai/accuracy/estimators/heuristic_difficulty.ex`
- [x] 7.1.4.2 Add `@moduledoc` explaining heuristic approach
- [x] 7.1.4.3 Define configuration schema:
  - `:features` - List of features to use
  - `:weights` - Weights for each feature
- [x] 7.1.4.4 Implement `estimate/3` using heuristics
- [x] 7.1.4.5 Extract features: length, complexity indicators, domain
- [x] 7.1.4.6 Calculate weighted score
- [x] 7.1.4.7 Map score to difficulty level

### 7.1.5 Unit Tests for Difficulty Estimation ✅

**73 tests passing, 0 failures**

- [x] Test `LLMDifficultyEstimator.estimate/3` returns level
- [x] Test harder questions get higher difficulty
- [x] Test confidence is included in estimate
- [x] Test `HeuristicDifficultyEstimator` is faster than LLM
- [x] Test heuristic features extracted correctly
- [x] Test score to level conversion
- [x] Test difficulty level predicates work

---

## 7.2 Compute Budgeter ✅ COMPLETED

Allocate compute based on difficulty.

**86 tests passing, 0 failures**

### 7.2.1 Compute Budgeter Module ✅

Create the budget allocation module.

- [x] 7.2.1.1 Create `lib/jido_ai/accuracy/compute_budget.ex`
- [x] 7.2.1.2 Create `lib/jido_ai/accuracy/compute_budgeter.ex`
- [x] 7.2.1.3 Add `@moduledoc` explaining budget allocation
- [x] 7.2.1.4 Define configuration schema:
  - `:easy_budget` - Budget for easy tasks
  - `:medium_budget` - Budget for medium tasks
  - `:hard_budget` - Budget for hard tasks
  - `:global_limit` - Overall budget limit
- [x] 7.2.1.5 Implement `allocate/3` with difficulty and options
- [x] 7.2.1.6 Map difficulty to parameters:
  - Easy: N=3 candidates, no PRM
  - Medium: N=5 candidates, PRM
  - Hard: N=10 candidates, PRM + search
- [x] 7.2.1.7 Support custom allocation strategies
- [x] 7.2.1.8 Respect global budget limits
- [x] 7.2.1.9 Implement `remaining_budget/1`

### 7.2.2 Budget Allocation ✅

Implement difficulty-specific allocation.

- [x] 7.2.2.1 Implement `allocate_for_easy/1`
  - num_candidates: 3
  - use_prm: false
  - use_search: false
- [x] 7.2.2.2 Implement `allocate_for_medium/1`
  - num_candidates: 5
  - use_prm: true
  - use_search: false
- [x] 7.2.2.3 Implement `allocate_for_hard/1`
  - num_candidates: 10
  - use_prm: true
  - use_search: true
  - search_iterations: 50
- [x] 7.2.2.4 Implement `custom_allocation/3`

### 7.2.3 Budget Tracking ✅

Track and manage budget usage.

- [x] 7.2.3.1 Implement `track_usage/2`
- [x] 7.2.3.2 Implement `check_budget/2`
- [x] 7.2.3.3 Implement `reset_budget/1`
- [x] 7.2.3.4 Implement `budget_exhausted?/1`

### 7.2.4 Unit Tests for ComputeBudgeter ✅

- [x] Test `allocate/3` returns appropriate parameters
- [x] Test easy tasks get minimal compute
- [x] Test hard tasks get maximum compute
- [x] Test global budget limits respected
- [x] Test budget tracking works
- [x] Test budget exhaustion detected
- [x] Test custom allocation strategies

---

## 7.3 Adaptive Self-Consistency ✅ COMPLETED

Adjust sample count based on difficulty and early stopping.

### 7.3.1 Adaptive Self-Consistency Module ✅

Create self-consistency with adaptive N.

- [x] 7.3.1.1 Create `lib/jido_ai/accuracy/adaptive_self_consistency.ex`
- [x] 7.3.1.2 Add `@moduledoc` explaining adaptive approach
- [x] 7.3.1.3 Define configuration schema:
  - `:min_candidates` - Minimum candidates (default: 3)
  - `:max_candidates` - Maximum candidates (default: 20)
  - `:early_stop_threshold` - Consensus for early stop
  - `:difficulty_estimator` - Difficulty estimator module
- [x] 7.3.1.4 Implement `run/3` with difficulty estimation
- [x] 7.3.1.5 Adjust sample count dynamically
- [x] 7.3.1.6 Stop early if consensus reached
- [x] 7.3.1.7 Return result with metadata about actual N used

### 7.3.2 Early Stopping ✅

Implement early stopping logic.

- [x] 7.3.2.1 Implement `check_consensus/3`
- [x] 7.3.2.2 Calculate agreement level
- [x] 7.3.2.3 Stop if confidence threshold met
- [x] 7.3.2.4 Implement `agreement_score/2`

### 7.3.3 Dynamic N Adjustment ✅

Implement dynamic sample count adjustment.

- [x] 7.3.3.1 Implement `adjust_n/4` based on difficulty
- [x] 7.3.3.2 Implement `increase_n/3` for hard tasks
- [x] 7.3.3.3 Implement `decrease_n/3` for easy tasks

### 7.3.4 Unit Tests for Adaptive Self-Consistency ✅

- [x] Test easy tasks use fewer samples
- [x] Test hard tasks use more samples
- [x] Test early stopping triggers
- [x] Test early stopping saves compute
- [x] Test consensus calculation
- [x] Test dynamic N adjustment

---

## 7.4 Phase 7 Integration Tests ✅ COMPLETED

Comprehensive integration tests for adaptive budgeting.

### 7.4.1 Adaptive Budgeting Tests ✅

- [x] 7.4.1.1 Create `test/jido_ai/accuracy/adaptive_test.exs`
- [x] 7.4.1.2 Test: Easy questions get minimal compute
  - Simple math question
  - Verify small N used
  - Verify fast completion
- [x] 7.4.1.3 Test: Hard questions get more compute
  - Complex reasoning question
  - Verify large N used
  - Verify higher accuracy
- [x] 7.4.1.4 Test: Global budget respected
  - Multiple queries with budget limit
  - Verify total within limit
- [x] 7.4.1.5 Test: Budget exhaustion handled
  - Exhaust budget mid-task
  - Verify graceful degradation

### 7.4.2 Cost-Effectiveness Tests ✅

- [x] 7.4.2.1 Test: Adaptive budgeting improves cost-efficiency
  - Compare fixed vs adaptive budgeting
  - Verify similar accuracy, lower cost
- [x] 7.4.2.2 Test: Early stopping saves compute
  - Questions with early consensus
  - Verify reduced samples
  - Measure time savings
- [x] 7.4.2.3 Test: Heuristic vs LLM difficulty estimation
  - Compare speed and accuracy
  - Verify trade-off is acceptable

### 7.4.3 Performance Tests ✅

- [x] 7.4.3.1 Test: Difficulty estimation is fast
  - Measure estimation time
  - Verify < 1 second (actual: < 1ms)
- [x] 7.4.3.2 Test: Budget allocation is efficient
  - Measure allocation overhead
  - Verify minimal (actual: < 1ms)

---

## Phase 7 Success Criteria

1. **Difficulty estimation**: Accurately classifies task difficulty
2. **Compute allocation**: Maps difficulty to appropriate parameters
3. **Adaptive behavior**: Adjusts based on task difficulty
4. **Cost efficiency**: Maintains accuracy with lower average cost
5. **Early stopping**: Consensus detection saves compute
6. **Test coverage**: Minimum 85% for Phase 7 modules

---

## Phase 7 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/difficulty_estimator.ex`
- `lib/jido_ai/accuracy/difficulty_estimate.ex`
- `lib/jido_ai/accuracy/estimators/llm_difficulty.ex`
- `lib/jido_ai/accuracy/estimators/heuristic_difficulty.ex`
- `lib/jido_ai/accuracy/compute_budgeter.ex`
- `lib/jido_ai/accuracy/adaptive_self_consistency.ex`

**Test Files:**
- `test/jido_ai/accuracy/difficulty_estimator_test.exs`
- `test/jido_ai/accuracy/difficulty_estimate_test.exs`
- `test/jido_ai/accuracy/estimators/llm_difficulty_test.exs`
- `test/jido_ai/accuracy/estimators/heuristic_difficulty_test.exs`
- `test/jido_ai/accuracy/compute_budgeter_test.exs`
- `test/jido_ai/accuracy/adaptive_self_consistency_test.exs`
- `test/jido_ai/accuracy/adaptive_test.exs`
