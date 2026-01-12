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

- [ ] 6.1.1.1 Create `lib/jido_ai/accuracy/confidence_estimator.ex`
- [ ] 6.1.1.2 Add `@moduledoc` explaining confidence estimation
- [ ] 6.1.1.3 Define `@callback estimate/2`:
  ```elixir
  @callback estimate(
    candidate :: Jido.AI.Accuracy.Candidate.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.ConfidenceEstimate.t()} | {:error, term()}
  ```
- [ ] 6.1.1.4 Document estimation methods

### 6.1.2 Confidence Estimate

Define the confidence estimate struct.

- [ ] 6.1.2.1 Create `lib/jido_ai/accuracy/confidence_estimate.ex`
- [ ] 6.1.2.2 Define `defstruct` with fields:
  - `:score` - Confidence score [0-1]
  - `:calibration` - How well-calibrated the estimate is
  - `:method` - Method used for estimation
  - `:reasoning` - Explanation for confidence level
  - `:token_level_confidence` - Per-token confidence if available
  - `:metadata` - Additional metadata
- [ ] 6.1.2.3 Add `@moduledoc` with documentation
- [ ] 6.1.2.4 Implement `new/1` constructor
- [ ] 6.1.2.5 Implement `high_confidence?/1` (threshold: 0.7)
- [ ] 6.1.2.6 Implement `low_confidence?/1` (threshold: 0.4)
- [ ] 6.1.2.7 Implement `medium_confidence?/1`
- [ ] 6.1.2.8 Implement `confidence_level/1` returns :high, :medium, :low

### 6.1.3 Self-Attention Confidence

Use model's own attention patterns/logprobs.

- [ ] 6.1.3.1 Create `lib/jido_ai/accuracy/estimators/attention_confidence.ex`
- [ ] 6.1.3.2 Add `@moduledoc` explaining logprob-based estimation
- [ ] 6.1.3.3 Define configuration schema:
  - `:aggregation` - :min, :mean, :product (default: :product)
  - `:token_threshold` - Minimum per-token confidence
- [ ] 6.1.3.4 Implement `estimate/2` with logprob analysis
- [ ] 6.1.3.5 Use token-level probabilities from response
- [ ] 6.1.3.6 Aggregate to response-level confidence
- [ ] 6.1.3.7 Handle responses without logprobs
- [ ] 6.1.3.8 Implement `token_confidences/1` for analysis

### 6.1.4 Ensemble Confidence

Use multiple methods for confidence estimation.

- [ ] 6.1.4.1 Create `lib/jido_ai/accuracy/estimators/ensemble_confidence.ex`
- [ ] 6.1.4.2 Add `@moduledoc` explaining ensemble approach
- [ ] 6.1.4.3 Define configuration schema:
  - `:estimators` - List of estimator modules
  - `:weights` - Weights for combining estimates
  - `:combination_method` - :mean, :weighted_mean, :voting
- [ ] 6.1.4.4 Implement `estimate/2` with multiple methods
- [ ] 6.1.4.5 Run all estimators in parallel
- [ ] 6.1.4.6 Combine using specified method
- [ ] 6.1.4.7 Handle disagreements between estimators
- [ ] 6.1.4.8 Implement `disagreement_score/2` for analysis

### 6.1.5 Unit Tests for Confidence Estimation

- [ ] Test `ConfidenceEstimate.new/1` creates valid estimate
- [ ] Test `AttentionConfidence.estimate/2` returns score
- [ ] Test `EnsembleConfidence.estimate/2` combines methods
- [ ] Test confidence thresholds work correctly
- [ ] Test `confidence_level/1` returns correct level
- [ ] Test aggregation methods produce different scores
- [ ] Test disagreement score calculated correctly
- [ ] Test handling of missing logprobs

---

## 6.2 Calibration Gate

Route responses based on confidence level.

### 6.2.1 Calibration Gate Module

Create the gate that routes based on confidence.

- [ ] 6.2.1.1 Create `lib/jido_ai/accuracy/calibration_gate.ex`
- [ ] 6.2.1.2 Add `@moduledoc` explaining calibration gate pattern
- [ ] 6.2.1.3 Define configuration schema:
  - `:high_threshold` - Threshold for high confidence (default: 0.7)
  - `:low_threshold` - Threshold for low confidence (default: 0.4)
  - `:medium_action` - Action for medium confidence
  - `:low_action` - Action for low confidence
- [ ] 6.2.1.4 Implement `route/3` with candidate and estimate
- [ ] 6.2.1.5 Define routing logic:
  - High confidence → direct answer
  - Medium confidence → answer with verification
  - Low confidence → abstain or escalate
- [ ] 6.2.1.6 Support custom thresholds
- [ ] 6.2.1.7 Add telemetry for routing decisions
- [ ] 6.2.1.8 Implement `should_route?/2` for pre-check

### 6.2.2 Routing Strategies

Implement specific routing strategies.

- [ ] 6.2.2.1 Implement `direct_answer/1`
  - Return candidate as-is
  - Emit direct_answer telemetry event
- [ ] 6.2.2.2 Implement `answer_with_citations/1`
  - Add source citations if available
  - Include confidence disclaimer
  - Emit citation_added telemetry event
- [ ] 6.2.2.3 Implement `answer_with_tests/1`
  - Suggest verification steps
  - Include test cases if code
  - Emit verification_suggested telemetry event
- [ ] 6.2.2.4 Implement `escalate/1`
  - Format escalation message
  - Include context for escalation
  - Emit escalated telemetry event
- [ ] 6.2.2.5 Implement `abstain/1`
  - Format abstention message
  - Explain uncertainty
  - Emit abstained telemetry event

### 6.2.3 Unit Tests for CalibrationGate

- [ ] Test `route/3` routes high confidence correctly
- [ ] Test `route/3` routes medium confidence with verification
- [ ] Test `route/3` routes low confidence to abstain
- [ ] Test custom thresholds work correctly
- [ ] Test telemetry emitted for each route
- [ ] Test `direct_answer/1` returns candidate unchanged
- [ ] Test `answer_with_citations/1` adds citations
- [ ] Test `abstain/1` returns abstention message

---

## 6.3 Selective Generation

Skip answering when uncertain.

### 6.3.1 Selective Generation Module

Implement selective answering policy.

- [ ] 6.3.1.1 Create `lib/jido_ai/accuracy/selective_generation.ex`
- [ ] 6.3.1.2 Add `@moduledoc` explaining selective generation
- [ ] 6.3.1.3 Define configuration schema:
  - `:confidence_threshold` - Minimum confidence to answer
  - `:penalty_threshold` - Cost of wrong answer vs abstention
  - `:abstention_message` - Message when abstaining
- [ ] 6.3.1.4 Implement `answer_or_abstain/3`
- [ ] 6.3.1.5 Calculate expected value of answering
- [ ] 6.3.1.6 Compare penalty of wrong answer
- [ ] 6.3.1.7 Return answer or abstention
- [ ] 6.3.1.8 Implement `expected_value/3` for EV calculation

### 6.3.2 Expected Value Calculation

Calculate the expected value of answering vs abstaining.

- [ ] 6.3.2.1 Implement `calculate_ev/3`
  - EV(answer) = confidence * reward - (1 - confidence) * penalty
  - EV(abstain) = 0 (neutral)
- [ ] 6.3.2.2 Support custom reward/penalty values
- [ ] 6.3.2.3 Handle domain-specific costs

### 6.3.3 Unit Tests for SelectiveGeneration

- [ ] Test answers when confidence is high
- [ ] Test abstains when confidence is low
- [ ] Test expected value calculation
- [ ] Test custom penalty thresholds
- [ ] Test abstention message formatting

---

## 6.4 Uncertainty Quantification

Quantify different types of uncertainty.

### 6.4.1 Uncertainty Quantification Module

Distinguish aleatoric vs epistemic uncertainty.

- [ ] 6.4.1.1 Create `lib/jido_ai/accuracy/uncertainty_quantification.ex`
- [ ] 6.4.1.2 Add `@moduledoc` explaining uncertainty types
- [ ] 6.4.1.3 Define `@type uncertainty_type/0`:
  - `:aleatoric` - Inherent uncertainty in the data
  - `:epistemic` - Uncertainty due to lack of knowledge
- [ ] 6.4.1.4 Implement `classify_uncertainty/2`
- [ ] 6.4.1.5 Detect aleatoric uncertainty (inherent)
- [ ] 6.4.1.6 Detect epistemic uncertainty (knowledge gap)
- [ ] 6.4.1.7 Recommend actions based on type

### 6.4.2 Uncertainty Detection

Implement detection methods for each uncertainty type.

- [ ] 6.4.2.1 Implement `detect_aleatoric/2`
  - Check for ambiguity in query
  - Check for subjective content
  - Check for multiple valid answers
- [ ] 6.4.2.2 Implement `detect_epistemic/2`
  - Check for out-of-domain query
  - Check for missing information
  - Check RAG retrieval quality

### 6.4.3 Unit Tests for Uncertainty

- [ ] Test uncertainty classification
- [ ] Test aleatoric detection for ambiguous queries
- [ ] Test epistemic detection for out-of-domain queries
- [ ] Test action recommendations differ by type

---

## 6.5 Phase 6 Integration Tests

Comprehensive integration tests for calibration functionality.

### 6.5.1 Calibration Gate Tests

- [ ] 6.5.1.1 Create `test/jido_ai/accuracy/calibration_test.exs`
- [ ] 6.5.1.2 Test: High confidence routed directly
  - Generate high confidence response
  - Verify direct answer returned
- [ ] 6.5.1.3 Test: Medium confidence adds verification
  - Generate medium confidence response
  - Verify citations/tests added
- [ ] 6.5.1.4 Test: Low confidence abstains
  - Generate low confidence response
  - Verify abstention or escalation

### 6.5.2 Calibration Quality Tests

- [ ] 6.5.2.1 Test: Confidence is well-calibrated
  - Compare confidence vs accuracy
  - Measure calibration error
  - Verify error is acceptable
- [ ] 6.5.2.2 Test: Selective generation improves reliability
  - Compare error rate with/without selective
  - Verify selective has fewer errors
- [ ] 6.5.2.3 Test: Expected value calculation optimal
  - Compare EV-based vs threshold-based
  - Verify EV improves decisions

### 6.5.3 Uncertainty Tests

- [ ] 6.5.3.1 Test: Aleatoric vs epistemic distinguished
  - Query with inherent ambiguity
  - Query with missing knowledge
  - Verify different classifications
- [ ] 6.5.3.2 Test: Actions match uncertainty type
  - Aleatoric → provide options
  - Epistemic → abstain or gather info

---

## Phase 6 Success Criteria

1. **Confidence estimation**: Produces calibrated confidence scores
2. **Calibration gate**: Routes based on confidence level
3. **Selective generation**: Reduces wrong answers
4. **Calibration quality**: Confidence matches accuracy
5. **Uncertainty types**: Aleatoric vs epistemic distinguished
6. **Test coverage**: Minimum 85% for Phase 6 modules

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
