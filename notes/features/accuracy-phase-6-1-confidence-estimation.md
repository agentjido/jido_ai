# Feature Planning Document: Phase 6.1 - Confidence Estimation

**Status:** Completed
**Section:** 6.1 - Confidence Estimation
**Phase:** 6 - Uncertainty Estimation and Calibration Gates
**Branch:** `feature/accuracy-phase-6-1-confidence-estimation`

## Problem Statement

The accuracy improvement system needs a way to estimate confidence in model responses. Confidence estimates are essential for:

1. **Calibration Gates** - Route responses based on confidence (direct answer vs. verification vs. abstain)
2. **Selective Generation** - Only answer when confident enough
3. **Uncertainty Quantification** - Distinguish aleatoric vs epistemic uncertainty

Currently, the system has no standardized way to estimate or represent confidence in candidate responses.

## Solution Overview

Implement confidence estimation following the existing patterns in the accuracy system:

1. **ConfidenceEstimator Behavior** - Interface for confidence estimation
2. **ConfidenceEstimate Struct** - Standardized representation of confidence with metadata
3. **AttentionConfidence** - Logprob/token-based confidence estimation
4. **EnsembleConfidence** - Combine multiple estimation methods

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Confidence range | 0.0 to 1.0 | Standard probability scale |
| Confidence levels | high (≥0.7), medium (0.4-0.7), low (<0.4) | Matches calibration gate thresholds |
| Estimator pattern | Struct-based with behavior | Consistent with Verifier, Critique, Revision |
| Token aggregation | Product (default), min, mean | Product gives most conservative estimate |
| Ensemble combination | Weighted mean (default), mean, voting | Flexibility for different use cases |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── confidence_estimator.ex          # Behavior definition
├── confidence_estimate.ex            # Result struct
└── estimators/
    ├── attention_confidence.ex       # Logprob-based estimator
    └── ensemble_confidence.ex        # Multi-method ensemble
```

### Dependencies

- **Existing**: `Candidate` struct for input
- **Existing**: Behavior patterns from `Verifier`, `Critique`
- **Existing**: Zoi schemas for validation

### ConfidenceEstimate Fields

| Field | Type | Description |
|-------|------|-------------|
| `:score` | `float()` | Confidence score [0-1] |
| `:calibration` | `float() \| nil` | How well-calibrated (optional) |
| `:method` | `atom() \| String.t()` | Estimation method used |
| `:reasoning` | `String.t() \| nil` | Explanation for confidence |
| `:token_level_confidence` | `[float()] \| nil` | Per-token confidence |
| `:metadata` | `map()` | Additional metadata |

## Implementation Plan

### 6.1.1 ConfidenceEstimator Behavior

**File:** `lib/jido_ai/accuracy/confidence_estimator.ex`

- Define behavior with `estimate/2` callback
- Support struct-based implementations
- Add `estimator?/1` helper
- Document estimation methods

### 6.1.2 ConfidenceEstimate Struct

**File:** `lib/jido_ai/accuracy/confidence_estimate.ex`

- Define struct with all fields
- Implement `new/1` with validation
- Add helper functions:
  - `high_confidence?/1` - score ≥ 0.7
  - `medium_confidence?/1` - 0.4 ≤ score < 0.7
  - `low_confidence?/1` - score < 0.4
  - `confidence_level/1` - returns `:high`, `:medium`, or `:low`

### 6.1.3 AttentionConfidence Estimator

**File:** `lib/jido_ai/accuracy/estimators/attention_confidence.ex`

- Use logprobs from Candidate metadata
- Aggregate token probabilities:
  - `:product` - Multiply all (most conservative)
  - `:mean` - Average of all
  - `:min` - Minimum token confidence
- Handle missing logprobs gracefully
- Implement `token_confidences/1` for analysis

### 6.1.4 EnsembleConfidence Estimator

**File:** `lib/jido_ai/accuracy/estimators/ensemble_confidence.ex`

- Run multiple estimators in parallel
- Combination methods:
  - `:weighted_mean` - Weighted average of scores
  - `:mean` - Simple average
  - `:voting` - Majority vote on confidence level
- Implement `disagreement_score/2` for analysis

### 6.1.5 Unit Tests

**File:** `test/jido_ai/accuracy/confidence_estimate_test.exs`
- Test struct creation and validation
- Test confidence level helpers
- Test threshold functions

**File:** `test/jido_ai/accuracy/estimators/attention_confidence_test.exs`
- Test logprob-based estimation
- Test aggregation methods
- Test missing logprob handling

**File:** `test/jido_ai/accuracy/estimators/ensemble_confidence_test.exs`
- Test ensemble combination
- Test disagreement scoring
- Test parallel execution

## Success Criteria

1. **Behavior defined**: ConfidenceEstimator behavior with proper callbacks
2. **Struct created**: ConfidenceEstimate with all fields and helpers
3. **Estimators working**: AttentionConfidence and EnsembleConfidence functional
4. **Tests passing**: All unit tests with >85% coverage
5. **Documentation**: Complete moduledocs and examples

## Current Status

**Status:** Completed

### Implementation Summary

All components have been implemented and tested:

| Component | File | Tests | Status |
|-----------|------|-------|--------|
| ConfidenceEstimator behavior | `lib/jido_ai/accuracy/confidence_estimator.ex` | - | Complete |
| ConfidenceEstimate struct | `lib/jido_ai/accuracy/confidence_estimate.ex` | 27 passing | Complete |
| AttentionConfidence | `lib/jido_ai/accuracy/estimators/attention_confidence.ex` | 23 passing | Complete |
| EnsembleConfidence | `lib/jido_ai/accuracy/estimators/ensemble_confidence.ex` | 26 passing | Complete |

### Test Results

```
ConfidenceEstimate:     27 tests, 0 failures
AttentionConfidence:    23 tests, 0 failures
EnsembleConfidence:     26 tests, 0 failures
Total:                  76 tests, 0 failures
```

### What Works

1. **ConfidenceEstimate struct** with validation and helpers:
   - `new/1` and `new!/1` with score and method validation
   - `high_confidence?/1`, `medium_confidence?/1`, `low_confidence?/1`
   - `confidence_level/1` returns `:high`, `:medium`, or `:low`
   - `to_map/1` and `from_map/1` for serialization

2. **AttentionConfidence estimator**:
   - Logprob-based confidence from token probabilities
   - Aggregation methods: `:product` (default), `:mean`, `:min`
   - Token-level confidence tracking
   - Configurable token threshold

3. **EnsembleConfidence estimator**:
   - Combines multiple estimators
   - Combination methods: `:weighted_mean`, `:mean`, `:voting`
   - Disagreement scoring for consensus analysis
   - Graceful handling of estimator failures

### Known Limitations

1. **Logprobs dependency**: AttentionConfidence requires logprobs in Candidate metadata
2. **No calibration data**: The `:calibration` field is reserved for future use
3. **Struct initialization**: EnsembleConfidence requires valid module names for estimators

### How to Run

```bash
# Run confidence estimation tests
mix test test/jido_ai/accuracy/confidence_estimate_test.exs
mix test test/jido_ai/accuracy/estimators/attention_confidence_test.exs
mix test test/jido_ai/accuracy/estimators/ensemble_confidence_test.exs

# Run all confidence tests together
mix test test/jido_ai/accuracy/confidence_estimate_test.exs test/jido_ai/accuracy/estimators/
```

### Next Steps (Future Work)

1. **6.2 Calibration Data** - Collect calibration dataset to measure estimate accuracy
2. **6.3 Calibration Gates** - Implement routing based on confidence thresholds
3. **Additional estimators**:
   - Semantic consistency estimator
   - Length-based heuristics for when logprobs unavailable
   - Model ensemble estimators (multiple LLM calls)

## Notes/Considerations

### Token Probability Aggregation

The product aggregation (`:product`) multiplies all token probabilities:
```
confidence = exp(sum(logprobs))
```

This is the most conservative (lowest confidence) but most accurate for uncertainty estimation.

### Handling Missing Logprobs

When logprobs are not available:
- AttentionConfidence returns `{:error, :no_logprobs}`
- EnsembleConfidence can still work with other estimators
- Fallback: Use simple length-based heuristics (future enhancement)

### Calibration

The `:calibration` field is reserved for future use with calibration datasets.
It will measure how well the estimated confidence matches actual accuracy.

### Integration with ReqLLM

The Candidate struct should store logprobs from LLM responses in `metadata[:logprobs]`.
This requires coordination with the LLM generator to capture and store this data.
