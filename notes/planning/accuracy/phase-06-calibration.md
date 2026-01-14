# Phase 6: Uncertainty Estimation and Calibration Gates

This phase implements confidence estimation and selective generation. Calibration gates prevent wrong answers by routing responses based on confidence levels - high confidence answers are returned directly, medium confidence answers include verification, and low confidence triggers abstention or escalation.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                 Calibration Gate                             │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Response ──→ Estimate Confidence ──→ Gate Decision          │
│                                         │                    │
│                          ┌──────────────┼──────────────┐    │
│                          ▼              ▼              ▼    │
│                      High          Medium           Low    │
│                     (0.7-1.0)     (0.4-0.7)       (0-0.4)  │
│                        │             │               │      │
│                   ┌────▼────┐   ┌───▼────┐    ┌─────▼────┐  │
│                   │ Direct  │   │With    │    │ Abstain  │  │
│                   │ Answer  │   │Citation│    │Escalate  │  │
│                   └─────────┘   └────────┘    └──────────┘  │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| ConfidenceEstimator behavior | Interface for confidence estimation |
| ConfidenceEstimate | Struct holding confidence score and metadata |
| AttentionConfidence | Estimates from token probabilities |
| EnsembleConfidence | Combines multiple estimation methods |
| CalibrationGate | Routes responses based on confidence |
| SelectiveGeneration | Implements selective answering policy |
| UncertaintyQuantification | Distinguishes aleatoric vs epistemic uncertainty |

---

## 6.1 Confidence Estimation

Estimate confidence in model responses.

### 6.1.1 Confidence Estimator Behavior

Define the behavior for confidence estimation.

- [x] 6.1.1.1 Create `lib/jido_ai/accuracy/confidence_estimator.ex`
- [x] 6.1.1.2 Add `@moduledoc` explaining confidence estimation
- [x] 6.1.1.3 Define `@callback estimate/3`:
  ```elixir
  @callback estimate(
    estimator :: struct(),
    candidate :: Jido.AI.Accuracy.Candidate.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.ConfidenceEstimate.t()} | {:error, term()}
  ```
- [x] 6.1.1.4 Document estimation methods

### 6.1.2 Confidence Estimate

Define the confidence estimate struct.

- [x] 6.1.2.1 Create `lib/jido_ai/accuracy/confidence_estimate.ex`
- [x] 6.1.2.2 Define `defstruct` with fields:
  - `:score` - Confidence score [0-1]
  - `:calibration` - How well-calibrated the estimate is
  - `:method` - Method used for estimation
  - `:reasoning` - Explanation for confidence level
  - `:token_level_confidence` - Per-token confidence if available
  - `:metadata` - Additional metadata
- [x] 6.1.2.3 Add `@moduledoc` with documentation
- [x] 6.1.2.4 Implement `new/1` constructor
- [x] 6.1.2.5 Implement `high_confidence?/1` (threshold: 0.7)
- [x] 6.1.2.6 Implement `low_confidence?/1` (threshold: 0.4)
- [x] 6.1.2.7 Implement `medium_confidence?/1`
- [x] 6.1.2.8 Implement `confidence_level/1` returns :high, :medium, :low

### 6.1.3 Self-Attention Confidence

Use model's own attention patterns/logprobs.

- [x] 6.1.3.1 Create `lib/jido_ai/accuracy/estimators/attention_confidence.ex`
- [x] 6.1.3.2 Add `@moduledoc` explaining logprob-based estimation
- [x] 6.1.3.3 Define configuration schema:
  - `:aggregation` - :min, :mean, :product (default: :product)
  - `:token_threshold` - Minimum per-token confidence
- [x] 6.1.3.4 Implement `estimate/3` with logprob analysis
- [x] 6.1.3.5 Use token-level probabilities from response
- [x] 6.1.3.6 Aggregate to response-level confidence
- [x] 6.1.3.7 Handle responses without logprobs
- [x] 6.1.3.8 Implement `token_confidences/1` for analysis

### 6.1.4 Ensemble Confidence

Use multiple methods for confidence estimation.

- [x] 6.1.4.1 Create `lib/jido_ai/accuracy/estimators/ensemble_confidence.ex`
- [x] 6.1.4.2 Add `@moduledoc` explaining ensemble approach
- [x] 6.1.4.3 Define configuration schema:
  - `:estimators` - List of estimator modules
  - `:weights` - Weights for combining estimates
  - `:combination_method` - :mean, :weighted_mean, :voting
- [x] 6.1.4.4 Implement `estimate/3` with multiple methods
- [x] 6.1.4.5 Run all estimators in parallel
- [x] 6.1.4.6 Combine using specified method
- [x] 6.1.4.7 Handle disagreements between estimators
- [x] 6.1.4.8 Implement `disagreement_score/2` for analysis

### 6.1.5 Unit Tests for Confidence Estimation

- [x] Test `ConfidenceEstimate.new/1` creates valid estimate (27 tests)
- [x] Test `AttentionConfidence.estimate/3` returns score (23 tests)
- [x] Test `EnsembleConfidence.estimate/3` combines methods (26 tests)
- [x] Test confidence thresholds work correctly
- [x] Test `confidence_level/1` returns correct level
- [x] Test aggregation methods produce different scores
- [x] Test disagreement score calculated correctly
- [x] Test handling of missing logprobs

**Section 6.1 Status: Complete (76 tests passing)**

---

## 6.2 Calibration Gate

Route responses based on confidence level.

### 6.2.1 Calibration Gate Module

Create the gate that routes based on confidence.

- [x] 6.2.1.1 Create `lib/jido_ai/accuracy/calibration_gate.ex`
- [x] 6.2.1.2 Add `@moduledoc` explaining calibration gate pattern
- [x] 6.2.1.3 Define configuration schema:
  - `:high_threshold` - Threshold for high confidence (default: 0.7)
  - `:low_threshold` - Threshold for low confidence (default: 0.4)
  - `:medium_action` - Action for medium confidence
  - `:low_action` - Action for low confidence
- [x] 6.2.1.4 Implement `route/3` with candidate and estimate
- [x] 6.2.1.5 Define routing logic:
  - High confidence → direct answer
  - Medium confidence → answer with verification
  - Low confidence → abstain or escalate
- [x] 6.2.1.6 Support custom thresholds
- [x] 6.2.1.7 Add telemetry for routing decisions
- [x] 6.2.1.8 Implement `should_route?/2` for pre-check

### 6.2.2 Routing Strategies

Implement specific routing strategies.

- [x] 6.2.2.1 Implement `direct_answer/1`
  - Return candidate as-is
  - Emit direct_answer telemetry event
- [x] 6.2.2.2 Implement `answer_with_citations/1`
  - Add source citations if available
  - Include confidence disclaimer
  - Emit citation_added telemetry event
- [x] 6.2.2.3 Implement `answer_with_tests/1` (as `with_verification`)
  - Suggest verification steps
  - Include test cases if code
  - Emit verification_suggested telemetry event
- [x] 6.2.2.4 Implement `escalate/1`
  - Format escalation message
  - Include context for escalation
  - Emit escalated telemetry event
- [x] 6.2.2.5 Implement `abstain/1`
  - Format abstention message
  - Explain uncertainty
  - Emit abstained telemetry event

### 6.2.3 Unit Tests for CalibrationGate

- [x] Test `route/3` routes high confidence correctly
- [x] Test `route/3` routes medium confidence with verification
- [x] Test `route/3` routes low confidence to abstain
- [x] Test custom thresholds work correctly
- [x] Test telemetry emitted for each route
- [x] Test `direct_answer/1` returns candidate unchanged
- [x] Test `answer_with_citations/1` adds citations
- [x] Test `abstain/1` returns abstention message

**Section 6.2 Status: Complete (60 tests passing)**

**Additional:**
- [x] Created `lib/jido_ai/accuracy/routing_result.ex` - Result struct with action helpers
- [x] Created `test/jido_ai/accuracy/routing_result_test.exs` - 28 tests
- [x] Created `test/jido_ai/accuracy/calibration_gate_test.exs` - 32 tests

---

## 6.3 Selective Generation

Skip answering when uncertain.

### 6.3.1 Selective Generation Module

Implement selective answering policy.

- [x] 6.3.1.1 Create `lib/jido_ai/accuracy/selective_generation.ex`
- [x] 6.3.1.2 Add `@moduledoc` explaining selective generation
- [x] 6.3.1.3 Define configuration schema:
  - `:reward` - Reward for correct answer (default: 1.0)
  - `:penalty` - Penalty for wrong answer (default: 1.0)
  - `:confidence_threshold` - Minimum confidence to answer (optional)
  - `:use_ev` - Use expected value calculation (default: true)
- [x] 6.3.1.4 Implement `answer_or_abstain/3`
- [x] 6.3.1.5 Calculate expected value of answering
- [x] 6.3.1.6 Compare penalty of wrong answer
- [x] 6.3.1.7 Return answer or abstention
- [x] 6.3.1.8 Implement `calculate_ev/2` for EV calculation

### 6.3.2 Expected Value Calculation

Calculate the expected value of answering vs abstaining.

- [x] 6.3.2.1 Implement `calculate_ev/2`
  - EV(answer) = confidence * reward - (1 - confidence) * penalty
  - EV(abstain) = 0 (neutral)
- [x] 6.3.2.2 Support custom reward/penalty values
- [x] 6.3.2.3 Handle domain-specific costs

### 6.3.3 Unit Tests for SelectiveGeneration

- [x] Test answers when confidence is high
- [x] Test abstains when confidence is low
- [x] Test expected value calculation
- [x] Test custom penalty thresholds
- [x] Test abstention message formatting

**Section 6.3 Status: Complete (50 tests passing)**

**Additional:**
- [x] Created `lib/jido_ai/accuracy/decision_result.ex` - Decision result struct
- [x] Created `test/jido_ai/accuracy/decision_result_test.exs` - 18 tests
- [x] Created `test/jido_ai/accuracy/selective_generation_test.exs` - 32 tests

---

## 6.4 Uncertainty Quantification

Quantify different types of uncertainty.

### 6.4.1 Uncertainty Quantification Module

Distinguish aleatoric vs epistemic uncertainty.

- [x] 6.4.1.1 Create `lib/jido_ai/accuracy/uncertainty_quantification.ex`
- [x] 6.4.1.2 Add `@moduledoc` explaining uncertainty types
- [x] 6.4.1.3 Define `@type uncertainty_type/0`:
  - `:aleatoric` - Inherent uncertainty in the data
  - `:epistemic` - Uncertainty due to lack of knowledge
- [x] 6.4.1.4 Implement `classify_uncertainty/2`
- [x] 6.4.1.5 Detect aleatoric uncertainty (inherent)
- [x] 6.4.1.6 Detect epistemic uncertainty (knowledge gap)
- [x] 6.4.1.7 Recommend actions based on type

### 6.4.2 Uncertainty Detection

Implement detection methods for each uncertainty type.

- [x] 6.4.2.1 Implement `detect_aleatoric/2`
  - Check for ambiguity in query
  - Check for subjective content
  - Check for multiple valid answers
- [x] 6.4.2.2 Implement `detect_epistemic/2`
  - Check for out-of-domain query
  - Check for missing information
  - Check RAG retrieval quality (pattern-based)

### 6.4.3 Unit Tests for Uncertainty

- [x] Test uncertainty classification
- [x] Test aleatoric detection for ambiguous queries
- [x] Test epistemic detection for out-of-domain queries
- [x] Test action recommendations differ by type

**Section 6.4 Status: Complete (50 tests passing)**

**Additional:**
- [x] Created `lib/jido_ai/accuracy/uncertainty_result.ex` - Result struct
- [x] Created `test/jido_ai/accuracy/uncertainty_result_test.exs` - 20 tests
- [x] Created `test/jido_ai/accuracy/uncertainty_quantification_test.exs` - 30 tests

---

## 6.5 Phase 6 Integration Tests

Comprehensive integration tests for calibration functionality.

### 6.5.1 Calibration Gate Tests

- [x] 6.5.1.1 Create `test/jido_ai/accuracy/calibration_test.exs`
- [x] 6.5.1.2 Test: High confidence routed directly
  - Generate high confidence response
  - Verify direct answer returned
- [x] 6.5.1.3 Test: Medium confidence adds verification
  - Generate medium confidence response
  - Verify citations/tests added
- [x] 6.5.1.4 Test: Low confidence abstains
  - Generate low confidence response
  - Verify abstention or escalation

### 6.5.2 Calibration Quality Tests

- [x] 6.5.2.1 Test: Confidence is well-calibrated
  - Compare confidence vs accuracy
  - Measure calibration error
  - Verify error is acceptable
- [x] 6.5.2.2 Test: Selective generation improves reliability
  - Compare error rate with/without selective
  - Verify selective has fewer errors
- [x] 6.5.2.3 Test: Expected value calculation optimal
  - Compare EV-based vs threshold-based
  - Verify EV improves decisions

### 6.5.3 Uncertainty Tests

- [x] 6.5.3.1 Test: Aleatoric vs epistemic distinguished
  - Query with inherent ambiguity
  - Query with missing knowledge
  - Verify different classifications
- [x] 6.5.3.2 Test: Actions match uncertainty type
  - Aleatoric → provide options
  - Epistemic → abstain or gather info

**Section 6.5 Status: Complete (16 tests passing)**

**Additional:**
- [x] Fixed bug in UncertaintyQuantification (duplicate new/1 function)
- [x] Created integration test file with 16 comprehensive tests
- [x] End-to-end pipeline tests for subjective, factual, and speculative queries

---

## 6.6 Phase 6 Review Fixes

Address all blockers, concerns, and improvements from the comprehensive Phase 6 review.

### 6.6.1 Security Fixes
- [x] HIGH: Validate logprob bounds (must be <= 0.0)
- [x] MEDIUM: Add upper bounds to reward/penalty values (max: 1000.0)
- [x] MEDIUM: Validate ensemble weights are in [0, 1] range
- [x] MEDIUM: Add regex complexity limits (max 500 chars, 50 patterns)

### 6.6.2 Code Quality Improvements
- [x] Extract ~180 lines of duplicated `get_attr` helpers to shared module
- [x] Document atom conversion fallback behavior
- [x] Add epsilon tolerance for float comparisons

### 6.6.3 QA Fixes
- [x] Eliminate all 5 compiler warnings
- [x] Add 12 new validation/security tests

**Branch:** `feature/accuracy-phase-6-review-fixes`
**Status:** Completed (2026-01-14)
**Tests:** 262 Phase 6 tests passing (+12 new tests added)

---

## Phase 6 Success Criteria

1. ✅ **Confidence estimation**: Produces calibrated confidence scores
2. ✅ **Calibration gate**: Routes based on confidence level
3. ✅ **Selective generation**: Reduces wrong answers
4. ✅ **Calibration quality**: Confidence matches accuracy
5. ✅ **Uncertainty types**: Aleatoric vs epistemic distinguished
6. ✅ **Test coverage**: 96% for Phase 6 modules
7. ✅ **Security**: All HIGH and MEDIUM security issues addressed
8. ✅ **Code quality**: Duplicated code eliminated, no compiler warnings

---

## Phase 6 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/confidence_estimator.ex`
- `lib/jido_ai/accuracy/confidence_estimate.ex`
- `lib/jido_ai/accuracy/estimators/attention_confidence.ex`
- `lib/jido_ai/accuracy/estimators/ensemble_confidence.ex`
- `lib/jido_ai/accuracy/calibration_gate.ex`
- `lib/jido_ai/accuracy/selective_generation.ex`
- `lib/jido_ai/accuracy/uncertainty_quantification.ex`

**Test Files:**
- `test/jido_ai/accuracy/confidence_estimator_test.exs`
- `test/jido_ai/accuracy/confidence_estimate_test.exs`
- `test/jido_ai/accuracy/estimators/attention_confidence_test.exs`
- `test/jido_ai/accuracy/estimators/ensemble_confidence_test.exs`
- `test/jido_ai/accuracy/calibration_gate_test.exs`
- `test/jido_ai/accuracy/selective_generation_test.exs`
- `test/jido_ai/accuracy/uncertainty_quantification_test.exs`
- `test/jido_ai/accuracy/calibration_test.exs`
