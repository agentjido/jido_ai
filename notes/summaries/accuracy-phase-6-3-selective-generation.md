# Summary: Phase 6.3 - Selective Generation Implementation

**Date:** 2025-01-13
**Branch:** `feature/accuracy-phase-6-3-selective-generation`
**Status:** Complete

## Overview

Implemented selective generation for Phase 6.3 of the accuracy improvement plan. This provides an economic decision-making framework for choosing whether to answer or abstain based on expected value calculations.

## Files Created

### Core Modules

1. **lib/jido_ai/accuracy/decision_result.ex** (183 lines)
   - Struct representing selective generation decisions
   - Decision helpers: `answered?/1`, `abstained?/1`
   - Serialization support

2. **lib/jido_ai/accuracy/selective_generation.ex** (346 lines)
   - Main selective generation module with EV calculation
   - Configurable reward/penalty parameters
   - Optional threshold mode

### Tests

3. **test/jido_ai/accuracy/decision_result_test.exs** (133 lines)
   - 18 tests covering struct creation, helpers, serialization

4. **test/jido_ai/accuracy/selective_generation_test.exs** (275 lines)
   - 32 tests covering EV calculation, decision making, domain scenarios

## Test Results

```
DecisionResult:       18 tests, 0 failures
SelectiveGeneration:  32 tests, 0 failures
-----------------------------------------
Total:                50 tests, 0 failures
```

## Key Implementation Details

### Expected Value Formula

```
EV(answer) = confidence * reward - (1 - confidence) * penalty
EV(abstain) = 0

Decision:
- If EV(answer) > 0 → Answer
- If EV(answer) <= 0 → Abstain
```

### Default Behavior (reward=1.0, penalty=1.0)

| Confidence | EV | Decision |
|------------|-----|----------|
| 0.9 | +0.8 | Answer |
| 0.7 | +0.4 | Answer |
| 0.5 | 0.0 | Abstain |
| 0.3 | -0.4 | Abstain |
| 0.1 | -0.8 | Abstain |

### Domain-Specific Configurations

**Medical (Safety-Critical):**
```elixir
sg = SelectiveGeneration.new!(%{
  reward: 1.0,
  penalty: 10.0  # Very high cost for wrong answers
})
# At 0.9 confidence: EV = 0.9*1 - 0.1*10 = -0.1 (abstain)
```

**Creative (Permissive):**
```elixir
sg = SelectiveGeneration.new!(%{
  reward: 1.0,
  penalty: 0.5   # Lower cost for being wrong
})
# At 0.4 confidence: EV = 0.4*1 - 0.6*0.5 = 0.1 (answer)
```

**Legal (High Stakes):**
```elixir
sg = SelectiveGeneration.new!(%{
  reward: 1.0,
  penalty: 20.0  # Extremely high cost
})
# At 0.95 confidence: EV = 0.95*1 - 0.05*20 = -0.05 (abstain)
```

### DecisionResult Struct

```elixir
defstruct [
  :decision,        # :answer or :abstain
  :candidate,       # The (possibly modified) candidate
  :confidence,      # Original confidence score
  :ev_answer,       # Expected value of answering
  :ev_abstain,      # Expected value of abstaining (always 0)
  :reasoning,       # Human-readable explanation
  :metadata         # Additional metadata
]
```

## Integration Points

The selective generation integrates with:
- **ConfidenceEstimate** (Phase 6.1) - Input for EV calculation
- **Candidate** - The content being evaluated
- **CalibrationGate** (Phase 6.2) - Can be used alongside for routing

## Usage Examples

```elixir
# Default configuration
sg = SelectiveGeneration.new!(%{})

candidate = Candidate.new!(%{content: "The answer is 42"})
estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :attention})

{:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
# => %DecisionResult{decision: :answer, ev_answer: 0.6, ...}

# Check decision
DecisionResult.answered?(result)  # => true
DecisionResult.abstained?(result) # => false

# Custom reward/penalty
sg = SelectiveGeneration.new!(%{
  reward: 2.0,
  penalty: 5.0
})

# Simple threshold mode (no EV calculation)
sg = SelectiveGeneration.new!(%{
  use_ev: false,
  confidence_threshold: 0.7
})
```

## Abstention Message Format

```
I'm not confident enough to provide a reliable answer.

Confidence: 0.300
Expected value: -0.400

The risk of providing incorrect information outweighs the potential benefit.
Please consider:
- Rephrasing your question with more specific details
- Providing additional context
- Consulting a more specialized source
```

## Design Patterns Used

1. **Struct-based results** - Consistent with ConfidenceEstimate, RoutingResult
2. **Configuration struct** - SelectiveGeneration with parameters
3. **Helper predicates** - `answered?/1`, `abstained?/1`
4. **Serialization support** - `to_map/1`, `from_map/1`
5. **Economic decision model** - Expected value maximization

## Future Work

1. **6.4 Uncertainty Quantification** - Distinguish aleatoric vs epistemic uncertainty
2. **Adaptive parameters** - Learn optimal reward/penalty from feedback
3. **Context-aware penalties** - Adjust based on query type and domain
4. **Calibration** - Measure actual vs estimated confidence accuracy
5. **Multi-arm bandit** - Explore-exploit for parameter tuning
