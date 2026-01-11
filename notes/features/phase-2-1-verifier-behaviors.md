# Feature Planning Document: Phase 2.1 - Verifier Behaviors and Types

**Status:** Complete
**Completed:** 2026-01-11
**Branch:** `feature/accuracy-phase-2-1-verifier-types`

## Current Status

All implementation tasks for Section 2.1 are complete:

### Completed Tasks
- [x] Created VerificationResult module with full validation
- [x] Created Verifier behavior with required and optional callbacks
- [x] 49 tests for VerificationResult (100% coverage)
- [x] 20 tests for Verifier behavior compliance
- [x] All tests passing (69 new tests total)
- [x] Credo passes with no issues
- [x] No breaking changes to existing code

### Test Results
```
298 accuracy tests passing (up from 229)
100% test coverage for VerificationResult
0 credo issues
```

## Problem Statement

The accuracy improvement system needs a verification layer to evaluate and score candidate responses. Currently:

1. **No Verification Interface**: There is no standard behavior for implementing verifiers that evaluate candidate quality
2. **No Verification Result Type**: There is no structured type to represent verification scores, confidence, and reasoning
3. **Gap in the Pipeline**: The system can generate candidates (Phase 1) but cannot evaluate them to identify the best response

Without verifiers, the system cannot:
- Score candidate responses for quality
- Implement verification-guided search (Section 2.3+)
- Provide feedback for reflection loops
- Support process reward models (PRMs) for step-level scoring

**Impact**: Cannot complete the accuracy improvement pipeline without foundational verification types.

## Solution Overview

Create two core components:

1. **`Jido.AI.Accuracy.VerificationResult`** - A struct representing the result of verification
   - Fields: `candidate_id`, `score`, `confidence`, `reasoning`, `step_scores`, `metadata`
   - Methods: `new/1`, `new!/1`, `pass?/2`, `merge_step_scores/2`, `to_map/1`, `from_map/1`

2. **`Jido.AI.Accuracy.Verifier`** - A behavior defining the verification contract
   - Required callbacks: `verify/2`, `verify_batch/2`
   - Optional callbacks: `supports_streaming?/0`

**Key Design Decisions**:
- Follow the pattern established by `Aggregator` and `Generator` behaviors
- Use plain structs (not Zoi schemas) for VerificationResult (consistent with Candidate)
- Support both outcome-level and step-level scoring (for PRMs)
- Include confidence metrics to support weighted aggregation

## Agent Consultations Performed

- **Explore Agent**: Analyzed existing codebase structure and patterns
  - Identified `Aggregator` behavior as a pattern to follow
  - Found `Candidate` struct design patterns
  - Located serialization patterns in `GenerationResult`

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── verifier.ex                    # New - Verifier behavior
└── verification_result.ex         # New - VerificationResult struct

test/jido_ai/accuracy/
├── verifier_test.exs              # New - Behavior compliance tests
└── verification_result_test.exs   # New - Struct operations tests
```

### Dependencies

**Existing Modules**:
- `Jido.AI.Accuracy.Candidate` - For type references in behavior
- `Jido.AI.Accuracy.Config` - For default configuration values

**New Dependencies**: None required

### VerificationResult Struct Definition

```elixir
defmodule Jido.AI.Accuracy.VerificationResult do
  @moduledoc """
  Represents the result of verifying a candidate response.

  Contains the verification score, confidence, optional reasoning,
  and step-level scores for process reward models.
  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: %__MODULE__{
    candidate_id: String.t() | nil,
    score: number() | nil,
    confidence: number() | nil,
    reasoning: String.t() | nil,
    step_scores: %{String.t() => number()} | nil,
    metadata: map()
  }

  defstruct [
    :candidate_id,
    :score,
    :confidence,
    :reasoning,
    :step_scores,
    metadata: %{}
  ]
end
```

### Verifier Behavior Definition

```elixir
defmodule Jido.AI.Accuracy.Verifier do
  @moduledoc """
  Behavior for candidate verifiers in the accuracy improvement system.

  Verifiers evaluate candidate responses to determine quality and correctness.
  Each verifier implements the verify/2 callback to score candidates.
  """

  alias Jido.AI.Accuracy.{Candidate, VerificationResult}

  @type t :: module()
  @type opts :: keyword()
  @type context :: map()

  @type verify_result :: {:ok, VerificationResult.t()} | {:error, term()}
  @type verify_batch_result :: {:ok, [VerificationResult.t()]} | {:error, term()}

  @callback verify(
    candidate :: Candidate.t(),
    context :: context()
  ) :: verify_result()

  @callback verify_batch(
    candidates :: [Candidate.t()],
    context :: context()
  ) :: verify_batch_result()

  @callback supports_streaming?() :: boolean()

  @optional_callbacks [supports_streaming?: 0]
end
```

## Implementation Plan

### Step 1: Create Feature Branch

- [x] Create `feature/accuracy-phase-2-1-verifier-types` from `feature/accuracy`

### Step 2: Create VerificationResult Module (2.1.2)

**File**: `lib/jido_ai/accuracy/verification_result.ex`

- [x] 2.1.2.1 Create module with `@moduledoc` explaining verification results
- [x] 2.1.2.2 Define `defstruct` with fields
- [x] 2.1.2.3 Add `@type t()` definition
- [x] 2.1.2.4 Implement `new/1` constructor with validation
- [x] 2.1.2.5 Implement `new!/1` constructor (raises on error)
- [x] 2.1.2.6 Implement `pass?/2` for threshold checking
- [x] 2.1.2.7 Implement `merge_step_scores/2` for PRM aggregation
- [x] 2.1.2.8 Implement `to_map/1` for serialization
- [x] 2.1.2.9 Implement `from_map/1` for deserialization
- [x] 2.1.2.10 Implement `from_map!/1` for deserialization with errors

### Step 3: Create Verifier Behavior (2.1.1)

**File**: `lib/jido_ai/accuracy/verifier.ex`

- [x] 2.1.1.1 Create behavior module with comprehensive `@moduledoc`
- [x] 2.1.1.2 Document the verification pattern and use cases
- [x] 2.1.1.3 Define `@callback verify/2`
- [x] 2.1.1.4 Define `@callback verify_batch/2`
- [x] 2.1.1.5 Define optional `@callback supports_streaming?/0`
- [x] 2.1.1.6 Add type definitions for callback signatures
- [x] 2.1.1.7 Add `@optional_callbacks` directive

### Step 4: Write VerificationResult Unit Tests (2.1.3)

**File**: `test/jido_ai/accuracy/verification_result_test.exs`

- [x] Test `new/1` creates valid result with all fields
- [x] Test `new/1` with minimal required fields
- [x] Test `new!/1` raises on invalid input
- [x] Test `pass?/2` returns true when score >= threshold
- [x] Test `pass?/2` returns false when score < threshold
- [x] Test `pass?/2` handles nil score (returns false)
- [x] Test `merge_step_scores/2` combines step score maps
- [x] Test `merge_step_scores/2` handles empty maps
- [x] Test `merge_step_scores/2` overwrites duplicate keys
- [x] Test `to_map/1` serializes all fields correctly
- [x] Test `from_map/1` deserializes from map with string keys
- [x] Test `from_map/1` deserializes from map with atom keys
- [x] Test `from_map/1` handles invalid input
- [x] Test `from_map!/1` raises on invalid input
- [x] Test serialization round-trip (to_map -> from_map)

### Step 5: Write Verifier Behavior Unit Tests (2.1.4)

**File**: `test/jido_ai/accuracy/verifier_test.exs`

- [x] Create mock verifier implementation for testing
- [x] Test mock verifier implements all required callbacks
- [x] Test `verify/2` returns VerificationResult
- [x] Test `verify/2` handles errors correctly
- [x] Test `verify_batch/2` returns list of results
- [x] Test `verify_batch/2` handles empty list
- [x] Test `verify_batch/2` propagates errors
- [x] Test `supports_streaming?/0` optional callback

### Step 6: Validation and Integration

- [x] Run all accuracy tests to ensure no regressions
- [x] Run `mix credo` - ensure no warnings
- [x] Run `mix docs` - verify documentation generates
- [x] Check test coverage is > 90% (100% for VerificationResult)

## Success Criteria

1. **VerificationResult Module**: ✅ COMPLETE
   - `new/1` creates valid results from attribute maps
   - `pass?/2` correctly evaluates thresholds
   - `merge_step_scores/2` aggregates PRM step scores
   - Serialization round-trip works correctly

2. **Verifier Behavior**: ✅ COMPLETE
   - Behavior compiles with all callbacks defined
   - Type specs are complete and valid
   - Documentation covers verification patterns

3. **Testing**: ✅ COMPLETE
   - All tests pass (69 new tests, exceeding 20 minimum)
   - Test coverage 100% for VerificationResult
   - Mock verifier implementation demonstrates behavior usage

4. **Code Quality**: ✅ COMPLETE
   - `mix credo` passes with no warnings
   - Code follows existing accuracy module patterns
   - Documentation is complete with examples

## Testing Strategy

### Unit Tests for VerificationResult

| Test Case | Description |
|-----------|-------------|
| Constructor tests | Verify `new/1` and `new!/1` handle valid/invalid input |
| Score validation | Verify score is numeric when present |
| Confidence range | Verify confidence is in [0, 1] when present |
| Threshold check | Verify `pass?/2` correctly evaluates against threshold |
| Step aggregation | Verify `merge_step_scores/2` combines maps correctly |
| Serialization | Verify `to_map/1` and `from_map/1` round-trip correctly |
| Edge cases | Verify nil fields, empty maps, invalid types |

### Unit Tests for Verifier Behavior

| Test Case | Description |
|-----------|-------------|
| Callback compliance | Verify mock implements all required callbacks |
| Single verification | Verify `verify/2` returns proper result type |
| Batch verification | Verify `verify_batch/2` handles multiple candidates |
| Error handling | Verify errors are returned correctly |
| Empty input | Verify empty candidate list is handled |
| Optional callbacks | Verify `supports_streaming?/0` works when implemented |

## Notes

- VerificationResult follows the same pattern as Candidate struct (plain struct, not Zoi)
- The Verifier behavior follows the pattern established by Aggregator behavior
- Serialization methods (to_map/from_map) support future caching and persistence needs
- Step scores support Process Reward Models (PRMs) for evaluating reasoning traces

## Current Status

*Waiting for developer confirmation to proceed with implementation.*
