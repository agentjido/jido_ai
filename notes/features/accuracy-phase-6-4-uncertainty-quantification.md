# Feature Planning Document: Phase 6.4 - Uncertainty Quantification

**Status:** Completed
**Section:** 6.4 - Uncertainty Quantification
**Phase:** 6 - Uncertainty Estimation and Calibration Gates
**Branch:** `feature/accuracy-phase-6-4-uncertainty-quantification`

## Problem Statement

The accuracy improvement system needs a way to distinguish between different types of uncertainty in model responses. Not all uncertainty is the same:

1. **Aleatoric uncertainty** - Inherent uncertainty in the data that cannot be reduced with more information
   - Ambiguous questions ("What's the best movie?")
   - Subjective content ("Is this painting beautiful?")
   - Multiple valid interpretations ("How do you solve this problem?")

2. **Epistemic uncertainty** - Uncertainty due to lack of knowledge that could be reduced with more information
   - Out-of-domain queries
   - Missing facts
   - Insufficient training data

Currently, the system has confidence estimates (Phase 6.1) but no mechanism to classify the type of uncertainty, which is important for choosing the right response strategy.

## Solution Overview

Implement an UncertaintyQuantification module that:

1. Classifies uncertainty as aleatoric or epistemic
2. Provides detection methods for each type
3. Recommends actions based on uncertainty type
4. Works with existing confidence estimation

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Classification approach | Pattern-based heuristics | Practical, extensible |
| Uncertainty result | Struct with type and confidence | Type-safe, consistent with other modules |
| Action recommendations | Per-type strategies | Aleatoric needs different handling than epistemic |
| Detection methods | Configurable patterns | Allow domain customization |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── uncertainty_quantification.ex   # Main module
└── uncertainty_result.ex            # Result struct
```

### Dependencies

- **Existing**: `ConfidenceEstimate` from Phase 6.1
- **Existing**: `Candidate` struct for content analysis
- **Existing**: Pattern matching heuristics

### Uncertainty Types

| Type | Description | Example |
|------|-------------|---------|
| `:aleatoric` | Inherent uncertainty | "What's the best movie?" |
| `:epistemic` | Lack of knowledge | "What is the population of Mars colony 7?" |
| `:none` | No uncertainty (confident) | "What is 2+2?" |

### UncertaintyResult Struct

```elixir
defstruct [
  :uncertainty_type,    # :aleatoric, :epistemic, or :none
  :confidence,          # Confidence in the classification
  :reasoning,           # Explanation for the classification
  :suggested_action,    # Recommended action
  :metadata             # Additional metadata
]
```

### Detection Patterns

**Aleatoric Indicators:**
- Subjective words: "best", "favorite", "beautiful", "better"
- Ambiguity markers: "or", "maybe", "possibly", "depends"
- Opinion questions: "Do you think...", "Would you agree..."
- Multiple interpretations: "In what way...", "How should I..."

**Epistemic Indicators:**
- Unknown entities/names
- Out-of-domain topics
- Factual queries about recent events
- Specific technical details not in training data

## Implementation Plan

### 6.4.1 UncertaintyResult Struct

**File:** `lib/jido_ai/accuracy/uncertainty_result.ex`

- Define struct with uncertainty type, confidence, reasoning
- Implement `new/1` with validation
- Add helper functions:
  - `aleatoric?/1`, `epistemic?/1`, `certain?/1`
  - `to_map/1`, `from_map/1`

### 6.4.2 UncertaintyQuantification Module

**File:** `lib/jido_ai/accuracy/uncertainty_quantification.ex`

- Define UncertaintyQuantification struct with patterns
- Implement `classify_uncertainty/2` - main classification function
- Implement `detect_aleatoric/2` - aleatoric detection
- Implement `detect_epistemic/2` - epistemic detection
- Implement `recommend_action/2` - action suggestions
- Support custom detection patterns

### 6.4.3 Action Recommendations

**For Aleatoric Uncertainty:**
- Acknowledge the subjectivity
- Provide multiple perspectives
- Offer clarifying questions
- Avoid definitive answers

**For Epistemic Uncertainty:**
- Admit lack of knowledge
- Suggest information sources
- Offer to help find the answer
- Avoid hallucination

### 6.4.4 Unit Tests

**File:** `test/jido_ai/accuracy/uncertainty_result_test.exs`
- Test struct creation and validation
- Test helper functions
- Test serialization

**File:** `test/jido_ai/accuracy/uncertainty_quantification_test.exs`
- Test classification of various queries
- Test aleatoric detection
- Test epistemic detection
- Test action recommendations
- Test custom patterns

## Success Criteria

1. **Module created**: UncertaintyQuantification with proper struct and validation
2. **Classification working**: Distinguishes aleatoric from epistemic
3. **Detection methods**: Pattern-based detection for both types
4. **Actions recommended**: Different actions for different uncertainty types
5. **Tests passing**: All unit tests with >85% coverage
6. **Documentation**: Complete moduledocs and examples

## Current Status

**Status:** Completed

### Implementation Summary

All components have been implemented and tested:

| Component | File | Tests | Status |
|-----------|------|-------|--------|
| UncertaintyResult struct | `lib/jido_ai/accuracy/uncertainty_result.ex` | 20 passing | Complete |
| UncertaintyQuantification module | `lib/jido_ai/accuracy/uncertainty_quantification.ex` | 30 passing | Complete |

### Test Results

```
UncertaintyResult:         20 tests, 0 failures
UncertaintyQuantification: 30 tests, 0 failures
Total:                     50 tests, 0 failures
```

### What Works

1. **UncertaintyResult struct** with type helpers:
   - `aleatoric?/1`, `epistemic?/1`, `certain?/1`, `uncertain?/1`
   - `to_map/1`, `from_map/1` for serialization

2. **UncertaintyQuantification** classification:
   - `classify_uncertainty/2` - Main classification function
   - `detect_aleatoric/2` - Aleatoric pattern matching
   - `detect_epistemic/2` - Epistemic pattern matching
   - `recommend_action/2` - Action suggestions based on type

3. **Default Aleatoric Patterns**:
   - Subjective adjectives: best, better, worst, favorite
   - Ambiguity markers: maybe, possibly, perhaps
   - Opinion words: think, believe, feel
   - Preference words: like, love, enjoy
   - Comparative: more, less, rather, than

4. **Default Epistemic Patterns**:
   - Future speculation: will happen, predict, forecast
   - Future tense: who will, what will, when will
   - Unanswerable questions: population of X, CEO of Y

### Uncertainty Classification Examples

| Query | Type | Reason |
|-------|------|--------|
| "What's the best movie?" | Aleatoric | Subjective ("best") |
| "What's your favorite color?" | Aleatoric | Preference ("favorite") |
| "What is the capital of France?" | None | Factual |
| "Who will be president in 2030?" | Epistemic | Future speculation |

### Action Recommendations

- **Aleatoric**: `:provide_options` - List multiple perspectives
- **Epistemic (high)**: `:abstain` - Admit lack of knowledge
- **Epistemic (low)**: `:suggest_source` - Recommend where to find answer
- **Certain**: `:answer_directly` - Provide factual answer

### Known Limitations

1. **Pattern-based** - Heuristic approach may have false positives/negatives
2. **Single label** - Returns only one uncertainty type (not hybrid)
3. **English-specific** - Patterns are tuned for English queries
4. **Context unaware** - Doesn't consider conversation history

### How to Run

```bash
# Run uncertainty tests
mix test test/jido_ai/accuracy/uncertainty_result_test.exs
mix test test/jido_ai/accuracy/uncertainty_quantification_test.exs

# Run all uncertainty tests together
mix test test/jido_ai/accuracy/uncertainty_result_test.exs test/jido_ai/accuracy/uncertainty_quantification_test.exs
```

### Next Steps (Future Work)

1. **6.5 Integration Tests** - Comprehensive Phase 6 integration tests
2. **ML-based classification** - Train a model for better accuracy
3. **Multi-label classification** - Allow both uncertainty types
4. **Domain-specific patterns** - Customize patterns per domain

## Notes/Considerations

### Hybrid Uncertainty

Some queries may have both aleatoric and epistemic components:
- "Who is the best director of movies about Mars?"

The system should classify based on the dominant uncertainty type.

### Confidence vs Uncertainty

- Low confidence doesn't always mean uncertainty (could be wrong)
- High confidence with aleatoric uncertainty should still acknowledge subjectivity
- Epistemic uncertainty often correlates with low confidence

### Pattern Limitations

Pattern-based detection is heuristic and may:
- Have false positives (aleatoric patterns in factual queries)
- Miss subtle uncertainty indicators
- Need domain-specific tuning

### Integration with Selective Generation

- Aleatoric uncertainty: May answer with qualifiers
- Epistemic uncertainty: Should abstain or escalate
- This connects with Phase 6.3's selective generation

### Future Enhancements

1. **ML-based classification** - Train a model to classify uncertainty
2. **Context-aware patterns** - Adjust patterns based on domain
3. **Multi-label classification** - Allow both uncertainty types
4. **Confidence calibration** - Measure classification accuracy
