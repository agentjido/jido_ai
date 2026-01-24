# Feature Planning Document: Phase 6.3 - Selective Generation

**Status:** Completed
**Section:** 6.3 - Selective Generation
**Phase:** 6 - Uncertainty Estimation and Calibration Gates
**Branch:** `feature/accuracy-phase-6-3-selective-generation`

## Problem Statement

The accuracy improvement system needs a way to decide whether to answer or abstain based on expected value calculation. Selective generation optimizes the trade-off between:

1. **Answering** - Potential reward if correct, penalty if wrong
2. **Abstaining** - Neutral outcome (neither reward nor penalty)

Currently, the calibration gate (Phase 6.2) always routes responses, but doesn't consider the economic trade-off of answering vs abstaining.

## Solution Overview

Implement a SelectiveGeneration module that:

1. Calculates the expected value (EV) of answering based on confidence
2. Compares EV against the neutral outcome of abstaining
3. Returns the answer if EV is positive, abstains otherwise
4. Supports domain-specific reward/penalty configurations

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| EV formula | `confidence * reward - (1-confidence) * penalty` | Standard expected value calculation |
| Abstention EV | 0 (neutral) | Baseline comparison |
| Default reward | 1.0 | Normalized scale |
| Default penalty | 1.0 | Equal cost/benefit by default |
| Decision result | Struct with decision and reasoning | Type-safe, extensible |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── selective_generation.ex           # Main module
└── decision_result.ex                 # Decision result struct
```

### Dependencies

- **Existing**: `ConfidenceEstimate` from Phase 6.1
- **Existing**: `Candidate` struct for responses
- **Existing**: `CalibrationGate` patterns from Phase 6.2

### SelectiveGeneration Fields

| Field | Type | Description |
|-------|------|-------------|
| `:confidence_threshold` | `float()` | Minimum confidence to answer (optional, for simple thresholding) |
| `:reward` | `float()` | Reward for correct answer (default: 1.0) |
| `:penalty` | `float()` | Penalty for wrong answer (default: 1.0) |
| `:use_ev` | `boolean()` | Use expected value calculation (default: true) |

### DecisionResult Struct

```elixir
defstruct [
  :decision,        # :answer or :abstain
  :candidate,       # The (possibly modified) candidate
  :confidence,      # Original confidence score
  :ev_answer,       # Expected value of answering
  :ev_abstain,      # Expected value of abstaining (always 0)
  :reasoning        # Human-readable explanation
]
```

## Implementation Plan

### 6.3.1 DecisionResult Struct

**File:** `lib/jido_ai/accuracy/decision_result.ex`

- Define struct with decision, candidate, EV values
- Implement `new/1` with validation
- Add helper functions:
  - `answered?/1`
  - `abstained?/1`
  - `to_map/1`, `from_map/1`

### 6.3.2 SelectiveGeneration Module

**File:** `lib/jido_ai/accuracy/selective_generation.ex`

- Define SelectiveGeneration struct
- Implement `new/1` with validation
- Implement `answer_or_abstain/3` - main decision function
- Implement `calculate_ev/4` - expected value calculation
- Support custom reward/penalty values
- Generate abstention messages when needed

### 6.3.3 Expected Value Calculation

The expected value formula:

```
EV(answer) = confidence * reward - (1 - confidence) * penalty
EV(abstain) = 0

Decision:
- If EV(answer) > 0 → Answer
- If EV(answer) <= 0 → Abstain
```

### 6.3.4 Unit Tests

**File:** `test/jido_ai/accuracy/decision_result_test.exs`
- Test struct creation
- Test helper functions
- Test serialization

**File:** `test/jido_ai/accuracy/selective_generation_test.exs`
- Test answering when confidence is high
- Test abstaining when confidence is low
- Test EV calculation with various parameters
- Test custom reward/penalty values
- Test abstention message formatting

## Success Criteria

1. **Module created**: SelectiveGeneration with proper struct and validation
2. **EV calculation**: Correct expected value computation
3. **Decision making**: Answers when positive EV, abstains otherwise
4. **Tests passing**: All unit tests with >85% coverage
5. **Documentation**: Complete moduledocs and examples

## Current Status

**Status:** Completed

### Implementation Summary

All components have been implemented and tested:

| Component | File | Tests | Status |
|-----------|------|-------|--------|
| DecisionResult struct | `lib/jido_ai/accuracy/decision_result.ex` | 18 passing | Complete |
| SelectiveGeneration module | `lib/jido_ai/accuracy/selective_generation.ex` | 32 passing | Complete |

### Test Results

```
DecisionResult:       18 tests, 0 failures
SelectiveGeneration:  32 tests, 0 failures
Total:                50 tests, 0 failures
```

### What Works

1. **DecisionResult struct** with decision helpers:
   - `answered?/1`, `abstained?/1`
   - `to_map/1`, `from_map/1` for serialization

2. **SelectiveGeneration** EV-based decision making:
   - `calculate_ev/2` - Expected value calculation
   - `answer_or_abstain/3` - Main decision function
   - Custom reward/penalty support
   - Optional threshold mode (when `use_ev: false`)

3. **Expected Value Formula**:
   ```
   EV(answer) = confidence * reward - (1 - confidence) * penalty
   EV(abstain) = 0
   Decision: Answer if EV(answer) > 0, else abstain
   ```

4. **Domain-specific configurations**:
   - Medical: `penalty: 10.0` (very high cost for errors)
   - Legal: `penalty: 20.0` (extremely high cost)
   - Creative: `penalty: 0.5` (more permissive)

### Known Limitations

1. **Linear EV calculation** - Assumes linear reward/penalty scaling
2. **Static parameters** - Reward/penalty don't adapt per query
3. **No learning** - System doesn't learn from past decisions

### How to Run

```bash
# Run selective generation tests
mix test test/jido_ai/accuracy/decision_result_test.exs
mix test test/jido_ai/accuracy/selective_generation_test.exs

# Run all selective generation tests together
mix test test/jido_ai/accuracy/decision_result_test.exs test/jido_ai/accuracy/selective_generation_test.exs
```

### Next Steps (Future Work)

1. **6.4 Uncertainty Quantification** - Distinguish aleatoric vs epistemic uncertainty
2. **Adaptive thresholds** - Learn optimal parameters from feedback
3. **Context-aware penalties** - Adjust penalty based on query type
4. **Calibration** - Measure actual vs estimated accuracy

## Notes/Considerations

### Threshold vs EV

Two modes of operation:
1. **Simple threshold**: If confidence >= threshold, answer
2. **EV-based**: Calculate expected value and decide economically

The EV-based approach is more nuanced as it considers:
- Relative costs of false positives vs false negatives
- Domain-specific reward structures
- Risk tolerance

### Abstention Messages

When abstaining, the system should:
1. Explain the decision was based on confidence
2. Not blame the user for asking
3. Be concise but helpful

### Domain-Specific Costs

Different domains have different costs:
- **Medical**: High penalty for wrong answers (safety-critical)
- **Creative**: Lower penalty, more acceptable to be wrong
- **Legal**: Very high penalty for incorrect legal advice

The reward/penalty parameters allow tuning per domain.

### Integration with CalibrationGate

SelectiveGeneration can be used alongside CalibrationGate:
1. CalibrationGate routes based on fixed thresholds
2. SelectiveGeneration makes economic decisions
3. Can be combined: gate for routing, selective for final answer/abstain

### Edge Cases

- **Confidence = 0.5** with equal reward/penalty: EV = 0, should abstain
- **Confidence = 0.0**: EV = -penalty, always abstain
- **Confidence = 1.0**: EV = reward, always answer
- **Zero penalty**: Always answer (no cost to being wrong)
