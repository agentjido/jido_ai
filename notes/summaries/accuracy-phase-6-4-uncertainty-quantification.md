# Summary: Phase 6.4 - Uncertainty Quantification Implementation

**Date:** 2025-01-13
**Branch:** `feature/accuracy-phase-6-4-uncertainty-quantification`
**Status:** Complete

## Overview

Implemented uncertainty quantification for Phase 6.4 of the accuracy improvement plan. This provides a way to distinguish between aleatoric (inherent) and epistemic (knowledge-based) uncertainty in queries.

## Files Created

### Core Modules

1. **lib/jido_ai/accuracy/uncertainty_result.ex** (200 lines)
   - Struct representing uncertainty classification results
   - Type helpers: `aleatoric?/1`, `epistemic?/1`, `certain?/1`, `uncertain?/1`
   - Serialization support

2. **lib/jido_ai/accuracy/uncertainty_quantification.ex** (352 lines)
   - Pattern-based uncertainty detection
   - Classification for aleatoric vs epistemic uncertainty
   - Action recommendations based on uncertainty type
   - Custom pattern support

### Tests

3. **test/jido_ai/accuracy/uncertainty_result_test.exs** (139 lines)
   - 20 tests covering struct creation, helpers, serialization

4. **test/jido_ai/accuracy/uncertainty_quantification_test.exs** (273 lines)
   - 30 tests covering classification, detection methods, action recommendations

## Test Results

```
UncertaintyResult:         20 tests, 0 failures
UncertaintyQuantification: 30 tests, 0 failures
-----------------------------------------
Total:                     50 tests, 0 failures
```

## Key Implementation Details

### Uncertainty Types

| Type | Description | Examples |
|------|-------------|----------|
| `:aleatoric` | Inherent uncertainty (cannot be reduced) | "What's the best movie?" |
| `:epistemic` | Lack of knowledge (could be reduced) | "Who will win in 2030?" |
| `:none` | No significant uncertainty | "What is 2+2?" |

### Detection Patterns

**Aleatoric Indicators:**
- Subjective: best, better, worst, favorite, prefer, greatest
- Ambiguity: maybe, possibly, perhaps, depends, could be, might be
- Opinion: think, believe, feel, opinion, view, perspective
- Preference: like, love, enjoy, would rather
- Comparative: more, less, rather, than, compared to

**Epistemic Indicators:**
- Future: will happen, predict, forecast, future of, going to be
- Future questions: who will, what will, when will, where will
- Unanswerable: what is the population of X, who is the CEO of Y

### Classification Logic

```
aleatoric_score = count(aleatoric patterns matching) / total_patterns
epistemic_score = count(epistemic patterns matching) / total_patterns

If both scores < 0.3:
  → :none (certain)
Else if aleatoric_score > epistemic_score * 1.5:
  → :aleatoric
Else if epistemic_score > aleatoric_score * 1.5:
  → :epistemic
Else:
  → :aleatoric (default for mixed)
```

### Action Recommendations

| Uncertainty Type | Action | Description |
|-----------------|--------|-------------|
| `:aleatoric` | `:provide_options` | List multiple valid approaches |
| `:epistemic` (high confidence) | `:abstain` | Admit lack of knowledge |
| `:epistemic` (low confidence) | `:suggest_source` | Recommend where to find answer |
| `:none` | `:answer_directly` | Provide factual answer |

## Integration Points

The uncertainty quantification integrates with:
- **Candidate** struct - For content analysis
- **ConfidenceEstimate** (Phase 6.1) - Can combine with uncertainty type
- **SelectiveGeneration** (Phase 6.3) - Different handling per uncertainty type

## Usage Examples

```elixir
# Default configuration
uq = UncertaintyQuantification.new!(%{})

# Classify a subjective query
{:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What's the best movie?")
# => %UncertaintyResult{uncertainty_type: :aleatoric, ...}

# Classify a factual query
{:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "What is the capital of France?")
# => %UncertaintyResult{uncertainty_type: :none, ...}

# Classify a future speculation
{:ok, result} = UncertaintyQuantification.classify_uncertainty(uq, "Who will win the World Cup?")
# => %UncertaintyResult{uncertainty_type: :epistemic, ...}

# Check uncertainty type
UncertaintyResult.aleatoric?(result)  # => true
UncertaintyResult.certain?(result)     # => false

# Get recommended action
result.suggested_action  # => :provide_options
```

## Design Patterns Used

1. **Struct-based results** - Consistent with ConfidenceEstimate, DecisionResult
2. **Pattern-based detection** - Regex patterns for flexible matching
3. **Helper predicates** - Type checking functions
4. **Serialization support** - `to_map/1`, `from_map/1`
5. **Configurable patterns** - Custom patterns per domain

## Future Work

1. **ML-based classification** - Train a model for better accuracy
2. **Multi-label classification** - Allow both aleatoric and epistemic
3. **Context-aware patterns** - Adjust based on domain and conversation history
4. **Confidence calibration** - Measure classification accuracy
5. **Integration tests** - Phase 6.5 comprehensive integration tests

## Progress on Phase 6

- ✅ 6.1 Confidence Estimation (76 tests)
- ✅ 6.2 Calibration Gate (60 tests)
- ✅ 6.3 Selective Generation (50 tests)
- ✅ 6.4 Uncertainty Quantification (50 tests)
- ⬜ 6.5 Integration Tests
