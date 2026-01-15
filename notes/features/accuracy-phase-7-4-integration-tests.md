# Phase 7.4: Adaptive Budgeting Integration Tests - Implementation Plan

**Date:** 2026-01-15
**Feature Branch:** `feature/accuracy-phase-7-4-integration-tests`
**Target Branch:** `feature/accuracy`
**Status:** COMPLETED

---

## Overview

This feature implements comprehensive integration tests for Phase 7 (Adaptive Compute Budgeting). These tests verify that difficulty estimation, compute budgeting, and adaptive self-consistency work together correctly to provide cost-efficient accuracy improvements.

---

## Problem Statement

### Current State
Phases 7.1, 7.2, and 7.3 implemented:
- Difficulty estimation (LLM and Heuristic)
- Compute budgeting with global limits
- Adaptive self-consistency with early stopping

However, there are no integration tests that verify these components work together end-to-end.

### Impact
Without integration tests:
- Cannot verify the full adaptive budgeting pipeline works correctly
- No validation of cost-efficiency claims
- Cannot detect regressions in component interactions
- No performance benchmarks for the adaptive system

### Solution
Implement comprehensive integration tests covering:
- End-to-end adaptive budgeting workflow
- Cost-effectiveness validation
- Performance benchmarks
- Cross-component interaction validation

---

## Solution Overview

### Test Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              Integration Test Suite                         │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Query ──→ DifficultyEstimator ──→ ComputeBudgeter          │
│                  │                        │                  │
│                  ▼                        ▼                  │
│            Verify Level            Verify Budget            │
│            (easy/med/hard)          (N, PRM, Search)         │
│                  │                        │                  │
│                  └────────┬───────────────┘                  │
│                           ▼                                  │
│              AdaptiveSelfConsistency                         │
│                           │                                  │
│                           ▼                                  │
│              Verify Early Stopping                          │
│              Verify Actual N Used                            │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

### Test Categories

1. **Adaptive Budgeting Tests (7.4.1)**
   - Easy questions get minimal compute
   - Hard questions get more compute
   - Global budget limits respected
   - Budget exhaustion handled gracefully

2. **Cost-Effectiveness Tests (7.4.2)**
   - Adaptive vs fixed budgeting comparison
   - Early stopping compute savings
   - Heuristic vs LLM estimation trade-offs

3. **Performance Tests (7.4.3)**
   - Difficulty estimation speed
   - Budget allocation overhead

---

## Technical Details

### File Structure

```
test/jido_ai/accuracy/
└── adaptive_test.exs        (NEW) Integration tests for adaptive budgeting
```

### Dependencies

- **Jido.AI.Accuracy.DifficultyEstimate** - For difficulty levels
- **Jido.AI.Accuracy.Estimators.LLMDifficulty** - LLM-based estimation
- **Jido.AI.Accuracy.Estimators.HeuristicDifficulty** - Heuristic estimation
- **Jido.AI.Accuracy.ComputeBudgeter** - For budget allocation
- **Jido.AI.Accuracy.AdaptiveSelfConsistency** - For adaptive sampling
- **Jido.AI.Accuracy.Candidate** - For creating test candidates

### Test Categories and Tags

- `@moduletag :integration` - Marks as integration test
- `@moduletag :adaptive` - Specific to adaptive budgeting
- `@tag :requires_api` - Tests that need LLM API
- `@tag :performance` - Performance benchmarks
- `@tag :cost_effectiveness` - Cost comparison tests

---

## Success Criteria

1. ✅ **Adaptive Budgeting Tests** - All 7.4.1 tests passing
2. ✅ **Cost-Effectiveness Tests** - All 7.4.2 tests passing
3. ✅ **Performance Tests** - All 7.4.3 tests passing
4. ✅ **No regressions** - Existing tests still pass
5. ✅ **Documentation** - Planning and summary documents complete

---

## Implementation Plan

### Step 1: Adaptive Budgeting Tests (7.4.1)

**File:** `test/jido_ai/accuracy/adaptive_test.exs`

**Tests:**
- [x] 7.4.1.1 Create test file structure
- [x] 7.4.1.2 Test: Easy questions get minimal compute
  - Simple math question ("What is 2+2?")
  - Verify difficulty classified as :easy
  - Verify budget has 3 candidates, no PRM/search
- [x] 7.4.1.3 Test: Hard questions get more compute
  - Complex reasoning question
  - Verify difficulty classified as :hard
  - Verify budget has 10+ candidates, PRM+search enabled
- [x] 7.4.1.4 Test: Global budget respected
  - Multiple queries with budget limit
  - Verify total cost within limit
  - Verify budget_exhausted error when exceeded
- [x] 7.4.1.5 Test: Budget exhaustion handled gracefully
  - Exhaust budget mid-sequence
  - Verify error returned, not crash

---

### Step 2: Cost-Effectiveness Tests (7.4.2)

**Tests:**
- [x] 7.4.2.1 Test: Adaptive vs fixed budgeting
  - Compare easy question with adaptive vs fixed N=10
  - Verify adaptive uses fewer candidates
  - Verify similar accuracy
- [x] 7.4.2.2 Test: Early stopping saves compute
  - Use generator with consistent answers
  - Verify early_stopped = true
  - Verify actual_n < initial_n
- [x] 7.4.2.3 Test: Heuristic vs LLM estimation
  - Same query, both estimators
  - Compare speed (heuristic should be faster)
  - Verify both produce valid difficulty levels

---

### Step 3: Performance Tests (7.4.3)

**Tests:**
- [x] 7.4.3.1 Test: Difficulty estimation speed
  - Measure heuristic estimation time
  - Verify < 10ms for typical query
- [x] 7.4.3.2 Test: Budget allocation overhead
  - Measure allocation time
  - Verify minimal overhead (< 1ms)
- [x] 7.4.3.3 Test: Query length scaling
  - Compare short vs long query estimation time
  - Verify both complete in reasonable time

---

## Test Design Patterns

### Mock Generators

For testing without actual LLM calls, use mock generators:

```elixir
# Consistent generator (triggers early stopping)
consistent_generator = fn _query ->
  {:ok, Candidate.new!(%{
    id: Uniq.UUID.uuid4(),
    content: "The answer is: 42",
    model: "test"
  })}
end

# Varied generator (no early stopping)
varied_generator = fn _query ->
  {:ok, Candidate.new!(%{
    id: Uniq.UUID.uuid4(),
    content: "Answer #{:rand.uniform()}",
    model: "test"
  })}
end
```

### Difficulty Verification

```elixir
# Verify difficulty classification
assert {:ok, estimate} = HeuristicDifficulty.estimate(estimator, query)
assert estimate.level == :easy
```

### Budget Verification

```elixir
# Verify budget parameters
assert {:ok, budget, _budgeter} = ComputeBudgeter.allocate(budgeter, estimate)
assert budget.num_candidates == 3  # For easy
assert budget.use_prm == false
```

---

## Notes and Considerations

### Test Isolation

- Use `async: false` for integration tests
- Mock generators should be deterministic where possible
- Clean up any state between tests

### API Dependencies

- Tests marked with `:requires_api` need live LLM access
- These tests may be flaky due to API variability
- Use `@tag :flaky` for known unstable tests

### Performance Benchmarks

- Performance tests measure time, not correctness
- Results may vary by system load
- Use assertions with reasonable tolerances

### Integration with Existing Tests

- New tests should not break existing unit tests
- Reuse existing test helpers and fixtures
- Follow existing naming conventions

---

## Progress Tracking

- [x] Step 1: Adaptive Budgeting Tests (7.4.1)
- [x] Step 2: Cost-Effectiveness Tests (7.4.2)
- [x] Step 3: Performance Tests (7.4.3)
- [x] Documentation updates

---

## Implementation Results

### Tests Created: 15 tests, all passing

**7.4.1 Adaptive Budgeting Tests (6 tests):**
- Easy questions get minimal compute
- Hard questions get more compute
- Medium questions get medium compute
- Global budget is respected
- Budget exhaustion handled gracefully

**7.4.2 Cost-Effectiveness Tests (5 tests):**
- Adaptive vs fixed budgeting - easy uses fewer candidates
- Early stopping saves compute with consensus
- No early stopping without consensus
- Heuristic vs LLM estimation comparison
- Hard question gets higher N than easy

**7.4.3 Performance Tests (3 tests):**
- Heuristic difficulty estimation is fast
- Budget allocation has minimal overhead
- Difficulty estimation scales with query length

**End-to-End Tests (2 tests):**
- Full workflow: estimate -> budget -> generate with early stop
- Full workflow with budget tracking across multiple queries

---

**Last Updated:** 2026-01-15
