# Feature Planning: Integration Tests (Phase 8.5)

## Status

**Status**: In Progress
**Created**: 2025-01-17
**Branch**: `feature/accuracy-phase-8-5-integration-tests`

---

## Problem Statement

Phase 8 of the accuracy plan has implemented all core components (pipeline, presets, telemetry, strategy integration), but lacks comprehensive integration tests to verify:

1. **End-to-end pipeline functionality** - The complete pipeline works correctly across all stages
2. **Accuracy improvement** - The pipeline actually improves over baseline LLM calls
3. **Preset behavior** - Each preset (:fast, :balanced, :accurate, :coding, :research) behaves as intended
4. **Performance characteristics** - Latency, cost tracking, and telemetry overhead
5. **Reliability** - Error handling, calibration behavior, budget enforcement
6. **Strategy integration** - Proper integration with ReAct and directive execution

**Impact**:
- Without comprehensive tests, we cannot verify the accuracy pipeline provides real value
- Cannot guarantee preset behaviors match their intent
- Cannot measure actual accuracy improvements
- Risk of regressions in future development

---

## Solution Overview

Create comprehensive integration test suite that validates:

1. **End-to-End Pipeline Tests** - Full pipeline execution with realistic queries
2. **Accuracy Validation Tests** - Compare pipeline vs baseline, ablation studies
3. **Performance Tests** - Measure latency, cost, telemetry overhead
4. **Reliability Tests** - Error handling, calibration, budget limits
5. **Strategy Integration Tests** - Directive execution, ReAct integration

**Key Design Decisions**:

1. **Mock generators for most tests** - Avoid API costs/flakiness while testing logic
2. **Separate API integration tests** - Tagged with `:requires_api` for optional real API testing
3. **Use existing test structure** - Extend `pipeline_test.exs` and `integration_test.exs`
4. **Focus on observable behaviors** - Test what users experience (accuracy, latency, cost)
5. **Minimal external dependencies** - Tests should run without external services

---

## Agent Consultations Performed

### Codebase Research: Existing Tests
**Consulted**: `test/jido_ai/accuracy/pipeline_test.exs`, `test/jido_ai/accuracy/integration_test.exs`
**Findings**:
- `pipeline_test.exs` has unit tests for pipeline module
- `integration_test.exs` has some end-to-end tests but focuses on SelfConsistency
- No tests for complete Pipeline with all stages
- No tests for preset behaviors
- No tests for accuracy validation

### Codebase Research: Pipeline Stages
**Consulted**: `lib/jido_ai/accuracy/pipeline.ex`, `lib/jido_ai/accuracy/presets.ex`
**Findings**:
- Pipeline has 7 stages: difficulty_estimation, rag, generation, verification, search, reflection, calibration
- 5 presets defined: :fast, :balanced, :accurate, :coding, :research
- Each preset has specific configuration for stages and parameters

---

## Technical Details

### File Structure

```
test/jido_ai/accuracy/
├── pipeline_e2e_test.exs         # NEW - End-to-end pipeline tests
├── accuracy_validation_test.exs   # NEW - Accuracy improvement validation
├── performance_test.exs           # NEW - Performance tests
├── reliability_test.exs           # NEW - Reliability tests
├── strategy_integration_test.exs  # NEW - Strategy integration tests
```

### Test Categories

#### 8.5.1 End-to-End Pipeline Tests
- Math problems (easy, medium, hard)
- Coding problems
- Research/factual questions
- Preset behavior comparison

#### 8.5.2 Accuracy Validation Tests
- Pipeline vs baseline comparison
- Ablation studies (remove each stage, measure impact)
- Preset intent validation

#### 8.5.3 Performance Tests
- Latency measurement (< 30s for typical query)
- Cost tracking accuracy
- Telemetry overhead (< 5%)

#### 8.5.4 Reliability Tests
- Error handling at each stage
- Calibration prevents wrong answers
- Budget limit enforcement

#### 8.5.5 Strategy Integration Tests
- Directive execution
- Signal emission
- ReAct agent integration

### Mock Generators

Tests will use mock generators to avoid API calls:

```elixir
# Simple mock generator
defmodule MockGenerator do
  def math_generator(query, _context) do
    answer = solve_math(query)
    {:ok, Candidate.new!(%{content: answer, score: 0.9})}
  end
end
```

---

## Success Criteria

1. ✅ End-to-end tests cover math, coding, and research queries
2. ✅ All 5 presets tested for expected behavior
3. ✅ Accuracy improvement measured (even with mocks)
4. ✅ Performance characteristics validated
5. ✅ Error handling verified at each stage
6. ✅ Strategy integration tests pass
7. ✅ All tests run without external dependencies (except optional API tests)

---

## Implementation Plan

### Step 1: End-to-End Pipeline Tests (8.5.1)

**File**: `test/jido_ai/accuracy/pipeline_e2e_test.exs`

**Tasks**:
- [ ] 1.1 Create test file with module and setup
- [ ] 1.2 Test: Complete pipeline on math problem
  - Run full pipeline
  - Verify all stages execute
  - Verify correct answer
  - Check trace completeness
- [ ] 1.3 Test: Complete pipeline on coding problem
  - Code generation task
  - Verify compilation check
- [ ] 1.4 Test: Complete pipeline on research question
  - Factual QA task
  - Verify RAG stage behavior
- [ ] 1.5 Test: Presets behave as expected
  - Test :fast preset (minimal candidates, no PRM)
  - Test :balanced preset (moderate candidates)
  - Test :accurate preset (maximum candidates)
  - Test :coding preset (code-specific stages)
  - Test :research preset (RAG-focused)

---

### Step 2: Accuracy Validation Tests (8.5.2)

**File**: `test/jido_ai/accuracy/accuracy_validation_test.exs`

**Tasks**:
- [ ] 2.1 Create test file
- [ ] 2.2 Test: Pipeline improves over baseline
  - Compare pipeline vs simple LLM call
  - Use mock with known failure rate
  - Measure improvement
- [ ] 2.3 Test: Each component contributes (ablation)
  - Run without verification
  - Run without search
  - Run without reflection
  - Compare results
- [ ] 2.4 Test: Presets match intent
  - Fast is fastest (fewest candidates)
  - Accurate has most candidates
  - Balanced is middle ground

---

### Step 3: Performance Tests (8.5.3)

**File**: `test/jido_ai/accuracy/performance_test.exs`

**Tasks**:
- [ ] 3.1 Create test file
- [ ] 3.2 Test: Pipeline latency is acceptable
  - Measure end-to-end latency
  - Verify < 30 seconds for typical query
- [ ] 3.3 Test: Cost tracking is accurate
  - Mock generator with known token counts
  - Verify total token count
- [ ] 3.4 Test: Telemetry overhead is minimal
  - Run with telemetry on/off
  - Compare performance

---

### Step 4: Reliability Tests (8.5.4)

**File**: `test/jido_ai/accuracy/reliability_test.exs`

**Tasks**:
- [ ] 4.1 Create test file
- [ ] 4.2 Test: Pipeline handles errors gracefully
  - Mock failure at each stage
  - Verify fallback behavior
- [ ] 4.3 Test: Calibration prevents wrong answers
  - Low confidence candidates
  - Verify abstention
- [ ] 4.4 Test: Budget limits are enforced
  - Set strict budget
  - Verify pipeline respects limit

---

### Step 5: Strategy Integration Tests (8.5.5)

**File**: `test/jido_ai/accuracy/strategy_integration_test.exs`

**Tasks**:
- [ ] 5.1 Create test file
- [ ] 5.2 Test: Directive execution
  - Execute AccuracyDirective
  - Verify result signal
- [ ] 5.3 Test: Signal emission
  - Verify accuracy.result signal
  - Verify accuracy.error signal

---

## Current Status

### What Works
- Feature branch created
- Existing test infrastructure reviewed
- Planning document created

### What's Next
- Implement end-to-end pipeline tests
- Implement accuracy validation tests
- Implement performance tests
- Implement reliability tests
- Implement strategy integration tests
- Update planning document as implementation progresses

### How to Run Tests
```bash
# Run all integration tests
MIX_ENV=test mix test test/jido_ai/accuracy/pipeline_e2e_test.exs

# Run specific test category
mix test test/jido_ai/accuracy/performance_test.exs
mix test test/jido_ai/accuracy/reliability_test.exs

# Run with API integration (optional)
mix test --include requires_api
```

---

## Notes and Considerations

### Test Design Principles
1. **Deterministic** - Use mocks to avoid flaky tests
2. **Fast** - Tests should complete quickly
3. **Isolated** - Each test should be independent
4. **Clear** - Test names should describe what they validate

### Mock Strategy
- Use `Mox` for external dependencies
- Create deterministic mock responses
- Simulate failure cases

### Future Enhancements
1. Real API integration tests (opt-in via tags)
2. Benchmark suite for performance regression
3. Accuracy benchmarks on standard datasets
4. Continuous accuracy monitoring in CI

---

## Implementation Checklist

- [ ] Step 1: End-to-End Pipeline Tests
  - [ ] 1.1 Create test file
  - [ ] 1.2 Math problem tests
  - [ ] 1.3 Coding problem tests
  - [ ] 1.4 Research question tests
  - [ ] 1.5 Preset behavior tests

- [ ] Step 2: Accuracy Validation Tests
  - [ ] 2.1 Create test file
  - [ ] 2.2 Baseline comparison tests
  - [ ] 2.3 Ablation study tests
  - [ ] 2.4 Preset intent tests

- [ ] Step 3: Performance Tests
  - [ ] 3.1 Create test file
  - [ ] 3.2 Latency tests
  - [ ] 3.3 Cost tracking tests
  - [ ] 3.4 Telemetry overhead tests

- [ ] Step 4: Reliability Tests
  - [ ] 4.1 Create test file
  - [ ] 4.2 Error handling tests
  - [ ] 4.3 Calibration tests
  - [ ] 4.4 Budget limit tests

- [ ] Step 5: Strategy Integration Tests
  - [ ] 5.1 Create test file
  - [ ] 5.2 Directive execution tests
  - [ ] 5.3 Signal emission tests

- [ ] Step 6: Documentation
  - [ ] 6.1 Update feature planning document
  - [ ] 6.2 Create summary document
  - [ ] 6.3 Update phase-08-integration.md

---

## References

- **Phase 8 Plan**: `notes/planning/accuracy/phase-08-integration.md`
- **Pipeline Module**: `lib/jido_ai/accuracy/pipeline.ex`
- **Presets Module**: `lib/jido_ai/accuracy/presets.ex`
- **Existing Tests**: `test/jido_ai/accuracy/pipeline_test.exs`
