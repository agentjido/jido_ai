# Feature Planning Document: Phase 6.5 - Phase 6 Integration Tests

**Status:** Complete
**Section:** 6.5 - Phase 6 Integration Tests
**Phase:** 6 - Uncertainty Estimation and Calibration Gates
**Branch:** `feature/accuracy-phase-6-5-integration-tests`

## Problem Statement

Phase 6 has implemented four major components:
- 6.1 Confidence Estimation (76 tests)
- 6.2 Calibration Gate (60 tests)
- 6.3 Selective Generation (50 tests)
- 6.4 Uncertainty Quantification (50 tests)

While each component has unit tests, there are no integration tests that verify:
1. The components work together correctly as a system
2. The calibration gate properly routes candidates based on confidence
3. The calibration quality (confidence matches accuracy)
4. Selective generation actually improves reliability
5. Uncertainty quantification integrates with the other components

Integration tests are needed to ensure the Phase 6 components work together in realistic scenarios.

## Solution Overview

Create comprehensive integration tests that verify:
1. **Calibration Gate integration** - End-to-end routing based on confidence
2. **Calibration quality** - Measure how well confidence matches accuracy
3. **Uncertainty integration** - Uncertainty classification with other components

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Test file structure | Single integration test file with multiple contexts | Easier to maintain, follows existing pattern |
| Test data | Mock candidates with predefined confidence scores | Deterministic tests, no LLM calls |
| Calibration quality measurement | Statistical measures (ECE, reliability diagrams) | Standard calibration metrics |
| Selective generation comparison | A/B test style comparison | Shows actual improvement |

## Technical Details

### Module Structure

```
test/jido_ai/accuracy/
└── calibration_test.exs    # Integration tests for all Phase 6 components
```

### Dependencies

**Existing Phase 6 components to integrate:**
- `ConfidenceEstimate` (Phase 6.1)
- `CalibrationGate` (Phase 6.2)
- `SelectiveGeneration` (Phase 6.3)
- `UncertaintyQuantification` (Phase 6.4)
- `RoutingResult` (6.2 support)
- `DecisionResult` (6.3 support)
- `UncertaintyResult` (6.4 support)
- `Candidate` (shared)
- `Estimators` (AttentionConfidence, EnsembleConfidence)

## Success Criteria

1. **Integration test file created** - `calibration_test.exs` with comprehensive tests
2. **Gate integration tests** - High/medium/low confidence routing verified
3. **Quality tests** - Calibration error measured and acceptable
4. **Uncertainty tests** - Aleatoric vs epistemic properly distinguished
5. **All tests passing** - 100% pass rate on integration tests
6. **Documentation** - Clear test descriptions showing integration points

## Implementation Plan

### 6.5.1 Calibration Gate Integration Tests

**File:** `test/jido_ai/accuracy/calibration_test.exs`

**Tests:**
1. **High confidence routed directly** ✅
   - Create candidate with high confidence (≥0.7)
   - Route through CalibrationGate
   - Verify `:direct` action returned
   - Verify content unchanged

2. **Medium confidence adds verification** ✅
   - Create candidate with medium confidence (0.4-0.7)
   - Route through CalibrationGate with `:with_verification`
   - Verify verification content added
   - Verify confidence included in response

3. **Medium confidence with citations** ✅
   - Route with `:with_citations` action
   - Verify citation-style verification added

4. **Low confidence abstains** ✅
   - Create candidate with low confidence (<0.4)
   - Route through CalibrationGate with `:abstain`
   - Verify abstention message returned
   - Verify original content not exposed

5. **Low confidence escalates** ✅
   - Route with `:escalate` action
   - Verify escalation message returned

6. **Custom thresholds work** ✅
   - Create gate with custom thresholds
   - Verify routing respects custom values

### 6.5.2 Calibration Quality Tests

**Tests:**
1. **Confidence is well-calibrated** ✅
   - Create test dataset with known accuracy
   - Compare predicted confidence vs actual accuracy
   - Calculate Expected Calibration Error (ECE)
   - Verify ECE is acceptable (<0.15)

2. **Selective generation improves reliability** ✅
   - Simulate responses with varying confidence
   - Compare error rate with/without selective generation
   - Verify selective has fewer errors
   - Measure precision improvement

3. **Expected value calculation optimal** ✅
   - Compare EV-based decisions vs threshold-based
   - Verify EV produces better economic outcomes
   - Test with different reward/penalty ratios

### 6.5.3 Uncertainty Integration Tests

**Tests:**
1. **Aleatoric vs epistemic distinguished** ✅
   - Query with inherent ambiguity (aleatoric)
   - Query with missing knowledge (epistemic)
   - Verify different classifications returned
   - Verify scores differ appropriately

2. **Actions match uncertainty type** ✅
   - Aleatoric → `:provide_options`
   - Epistemic (high) → `:abstain`
   - Epistemic (low) → `:suggest_source`
   - Certain → `:answer_directly`

3. **Uncertainty + confidence integration** ✅
   - High confidence + aleatoric = still acknowledge subjectivity
   - Low confidence + epistemic = abstain
   - Test combined decision making

4. **Calibration gate respects uncertainty type** ✅
   - Verify proper routing based on both confidence and uncertainty

## Current Status

**Status:** Complete ✅

### Progress

| Section | Tests | Status |
|---------|-------|--------|
| 6.5.1 Calibration Gate Tests | 6 tests | Complete ✅ |
| 6.5.2 Calibration Quality Tests | 3 tests | Complete ✅ |
| 6.5.3 Uncertainty Tests | 4 tests | Complete ✅ |
| End-to-end integration | 3 tests | Complete ✅ |
| **Total** | **16 tests** | **All passing ✅** |

## What Works

1. **Calibration Gate Integration** (6 tests)
   - High confidence (≥0.7) → direct answer
   - Medium confidence (0.4-0.7) → verification/citations
   - Low confidence (<0.4) → abstain/escalate
   - Custom thresholds work correctly

2. **Calibration Quality Tests** (3 tests)
   - Expected Calibration Error (ECE) calculation works
   - Selective generation reduces error rate
   - EV-based decisions outperform threshold-based

3. **Uncertainty Integration** (4 tests)
   - Aleatoric vs epistemic classification works
   - Actions match uncertainty type correctly
   - Combined confidence + uncertainty decisions work

4. **End-to-End Integration** (3 tests)
   - Full calibration pipeline for subjective queries
   - Full calibration pipeline for factual queries
   - Full calibration pipeline for speculative queries

## Bug Fixes Made

During implementation, discovered and fixed a bug in `UncertaintyQuantification`:
- Removed duplicate `def new/1` function that was causing pattern match failures
- Fixed defstruct to use default pattern values instead of nil
- Removed unused `get_attr/2` function

## Notes/Considerations

### Test Isolation

Integration tests do not call actual LLMs. All test data uses:
- Mock candidates with predefined content
- Mock confidence estimates with known scores
- Deterministic results

### Calibration Metrics

**Expected Calibration Error (ECE):**
- Divide confidence range into bins (10 bins of 0.1)
- For each bin, calculate accuracy of samples
- ECE = sum(|confidence - accuracy| * samples) / total_samples

### Selective Generation Simulation

To verify "selective generation improves reliability":
1. Created mock dataset with varying confidence and known correctness
2. Calculated error rate without selective generation (all answered)
3. Calculated error rate with selective generation (abstain when EV < 0)
4. Verified selective has lower error rate

### Future Enhancements

1. **Real LLM integration** - Test with actual model responses
2. **Domain-specific calibration** - Measure calibration per domain
3. **A/B testing framework** - Compare different calibration strategies
4. **Regression tests** - Catch calibration drift over time
