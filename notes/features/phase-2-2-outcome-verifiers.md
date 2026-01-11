# Feature Planning Document: Phase 2.2 - Outcome Verifiers

**Status:** Complete
**Section:** 2.2 - Outcome Verifier
**Dependencies:** Phase 2.1 (Verifier Behaviors) - Complete

## Problem Statement

The accuracy improvement system can now generate candidate responses (Phase 1) and has defined the verification interface (Phase 2.1), but lacked concrete implementations for evaluating candidate quality. Without outcome verifiers:

1. **No Scoring Mechanism**: Candidates cannot be evaluated for correctness or quality
2. **No Best-Answer Selection**: Self-consistency voting cannot be enhanced with verification scores
3. **No Ground Truth Comparison**: Deterministic answers (math, coding) cannot be verified against known correct responses
4. **Blocks Future Phases**: Cannot implement verification-guided search (Section 2.3+) or reflection loops

**Impact**: The verification pipeline is incomplete; candidates are generated but cannot be evaluated to identify the best response.

## Solution Overview

Implemented two concrete verifiers that follow the `Jido.AI.Accuracy.Verifier` behavior:

1. **`Jido.AI.Accuracy.Verifiers.LLMOutcomeVerifier`** - Uses an LLM to score candidate responses
2. **`Jido.AI.Accuracy.Verifiers.DeterministicVerifier`** - Compares candidates against ground truth

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── verifiers/                          # Created
│   ├── llm_outcome_verifier.ex         # Created - LLM-based verification
│   └── deterministic_verifier.ex       # Created - Ground truth comparison
└── verifier.ex                         # Existing - Behavior

test/jido_ai/accuracy/
├── verifiers/                          # Created
│   ├── llm_outcome_verifier_test.exs   # Created - LLM verifier tests
│   └── deterministic_verifier_test.exs # Created - Deterministic verifier tests
```

## Implementation Summary

### Step 1: Create Feature Branch
- [x] Created `feature/accuracy-phase-2-2-outcome-verifiers` from `feature/accuracy`

### Step 2: Create Verifiers Directory
- [x] Created `lib/jido_ai/accuracy/verifiers/` directory
- [x] Created `test/jido_ai/accuracy/verifiers/` directory

### Step 3: Implement DeterministicVerifier (2.2.2)

**File:** `lib/jido_ai/accuracy/verifiers/deterministic_verifier.ex`

- [x] 2.2.2.1 Create module with `@behaviour Jido.AI.Accuracy.Verifier`
- [x] 2.2.2.2 Add comprehensive `@moduledoc`
- [x] 2.2.2.3 Define `defstruct` with configuration fields
- [x] 2.2.2.4 Implement `new/1` constructor
- [x] 2.2.2.5 Implement `new!/1` constructor
- [x] 2.2.2.6 Implement `verify/2` callback
- [x] 2.2.2.7 Implement `verify_batch/2` callback
- [x] 2.2.2.8 Implement `extract_answer/1` helper
- [x] 2.2.2.9 Implement comparison functions (exact, numerical, regex)
- [x] 2.2.2.10 Implement `supports_streaming?/0` -> `false`

### Step 4: Implement LLMOutcomeVerifier (2.2.1)

**File:** `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex`

- [x] 2.2.1.1 Create module with `@behaviour Jido.AI.Accuracy.Verifier`
- [x] 2.2.1.2 Add comprehensive `@moduledoc`
- [x] 2.2.1.3 Define `defstruct` with configuration fields
- [x] 2.2.1.4 Implement `new/1` constructor with validation
- [x] 2.2.1.5 Implement `verify/2` callback with ReqLLM
- [x] 2.2.1.6 Implement prompt template rendering
- [x] 2.2.1.7 Implement score extraction from LLM response
- [x] 2.2.1.8 Implement reasoning extraction
- [x] 2.2.1.9 Implement `verify_batch/2` callback
- [x] 2.2.1.10 Implement retry logic with exponential backoff
- [x] 2.2.1.11 Implement `supports_streaming?/0` -> `true`

### Step 5: Write Unit Tests (2.2.3)

**File:** `test/jido_ai/accuracy/verifiers/deterministic_verifier_test.exs`

- [x] Constructor tests (defaults, custom config, validation)
- [x] verify/2 with exact match
- [x] verify/2 with numerical comparison
- [x] verify/2 with regex patterns
- [x] verify_batch/2 with multiple candidates
- [x] Answer extraction tests
- [x] Edge cases (nil, empty, whitespace)

**File:** `test/jido_ai/accuracy/verifiers/llm_outcome_verifier_test.exs`

- [x] Constructor tests (model, score_range, template)
- [x] Score extraction tests
- [x] Reasoning extraction tests
- [x] Prompt rendering tests
- [x] Content extraction tests
- [x] Batch score extraction tests
- [x] Edge cases

**Total: 119 tests, 0 failures**

### Step 6: Validation and Integration

- [x] Run all accuracy tests to ensure no regressions
- [x] Run `mix credo` - Minor refactoring opportunities (nesting depth 3 vs 2), acceptable
- [x] Check test coverage > 90% (achieved)

## Success Criteria

1. **DeterministicVerifier**: Exact, numerical, and regex comparison working - ✅
2. **LLMOutcomeVerifier**: LLM-based scoring with score/reasoning extraction - ✅
3. **Testing**: 119 tests (exceeded 60 target), >90% coverage - ✅
4. **Code Quality**: Minor credo warnings (nesting depth), follows established patterns - ✅
