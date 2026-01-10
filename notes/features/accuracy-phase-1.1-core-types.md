# Feature: Accuracy Phase 1.1 - Core Accuracy Types and Behaviors

## Problem Statement

Jido.AI needs foundational types for the accuracy improvement system to support test-time compute scaling algorithms like self-consistency, verification, and search. Currently, there are no structured types to represent:

1. **Candidate responses** - Multiple LLM responses that need to be compared
2. **Generation results** - Aggregated results from multi-candidate generation
3. **Score tracking** - Verification scores for candidate selection

Without these foundational types, implementing the accuracy improvement pipeline (phases 1-8) would require duplicating code and having inconsistent data structures across components.

**Impact**: Cannot implement the accuracy improvement system without these foundational types.

## Solution Overview

Create two core types with proper behaviors:

1. **`Jido.AI.Accuracy.Candidate`** - Represents a single generated response with metadata (id, content, reasoning, score, tokens_used, model, timestamp, metadata)

2. **`Jido.AI.Accuracy.GenerationResult`** - Represents multi-candidate generation results with aggregation metadata (candidates list, total_tokens, best_candidate, aggregation_method, metadata)

**Key Design Decisions**:
- Use plain structs (not Zoi schemas) for these core types - they are data containers, not configuration
- Use `Uniq.uuid/1` for candidate ID generation
- Follow existing Jido.AI code style (see `Jido.AI.Config` and `Jido.AI.Signal`)
- Include comprehensive serialization/deserialization support
- Add proper TypeSpecs for Dialyzer compatibility

## Agent Consultations Performed

**Elixir Code Style Consultation**:
- Reviewed existing modules: `Jido.AI.Config`, `Jido.AI.Signal`
- Identified patterns: `@moduledoc`, `@type`, `@spec`, constructor functions
- Test patterns: `use ExUnit.Case, async: true`, `describe`/`test` blocks

**No additional research needed** - This is straightforward Elixir data structure work following established patterns.

## Technical Details

### File Locations

**New Files**:
- `lib/jido_ai/accuracy/candidate.ex` - Candidate struct and functions
- `lib/jido_ai/accuracy/generation_result.ex` - GenerationResult struct and functions
- `test/jido_ai/accuracy/candidate_test.exs` - Candidate unit tests
- `test/jido_ai/accuracy/generation_result_test.exs` - GenerationResult unit tests

### Dependencies

- **Existing**: `uniq` (already in mix.exs for UUID generation)
- **New**: None required

### Candidate Struct Definition

```elixir
defmodule Jido.AI.Accuracy.Candidate do
  @moduledoc "..."

  defstruct [
    :id,
    :content,
    :reasoning,
    :score,
    :tokens_used,
    :model,
    :timestamp,
    :metadata
  ]

  @type t :: %__MODULE__{
    id: String.t() | nil,
    content: String.t() | nil,
    reasoning: String.t() | nil,
    score: number() | nil,
    tokens_used: non_neg_integer() | nil,
    model: String.t() | nil,
    timestamp: DateTime.t() | nil,
    metadata: map()
  }
end
```

### GenerationResult Struct Definition

```elixir
defmodule Jido.AI.Accuracy.GenerationResult do
  @moduledoc "..."

  defstruct [
    :candidates,
    :total_tokens,
    :best_candidate,
    :aggregation_method,
    :metadata
  ]

  @type t :: %__MODULE__{
    candidates: [Jido.AI.Accuracy.Candidate.t()],
    total_tokens: non_neg_integer(),
    best_candidate: Jido.AI.Accuracy.Candidate.t() | nil,
    aggregation_method: atom(),
    metadata: map()
  }
end
```

## Success Criteria

1. `Candidate.new/2` creates valid candidate with auto-generated UUID and timestamp
2. `Candidate.update_score/2` updates score and returns updated struct
3. `Candidate.to_map/1` and `Candidate.from_map/1` handle serialization
4. `GenerationResult.new/1` creates result from candidate list with computed best_candidate
5. `GenerationResult.best_candidate/1` returns highest-scoring candidate (handles empty list)
6. `GenerationResult.select_by_strategy/2` supports `:best` and `:vote` strategies
7. `GenerationResult.total_tokens/1` sums tokens across all candidates
8. All tests pass (minimum 90% coverage)

## Implementation Plan

### Step 1: Create Accuracy Directory Structure

- [x] Create `lib/jido_ai/accuracy/` directory
- [x] Create `test/jido_ai/accuracy/` directory

### Step 2: Implement Candidate Module (1.1.1)

- [x] 1.1.1.1 Create `lib/jido_ai/accuracy/candidate.ex`
- [x] 1.1.1.2 Define `defstruct` with all required fields
- [x] 1.1.1.3 Add comprehensive `@moduledoc`
- [x] 1.1.1.4 Add `@type t()` definition with proper specs
- [x] 1.1.1.5 Implement `new/1` constructor with UUID and timestamp generation
- [x] 1.1.1.6 Implement `update_score/2` for score updates
- [x] 1.1.1.7 Implement `to_map/1` for serialization
- [x] 1.1.1.8 Implement `from_map/1` for deserialization with validation

### Step 3: Implement GenerationResult Module (1.1.2)

- [x] 1.1.2.1 Create `lib/jido_ai/accuracy/generation_result.ex`
- [x] 1.1.2.2 Define `defstruct` with all required fields
- [x] 1.1.2.3 Add comprehensive `@moduledoc`
- [x] 1.1.2.4 Add `@type t()` definition with proper specs
- [x] 1.1.2.5 Implement `new/1` with candidate list (auto-compute best_candidate)
- [x] 1.1.2.6 Implement `best_candidate/1` to get top scored
- [x] 1.1.2.7 Implement `total_tokens/1` for cost tracking
- [x] 1.1.2.8 Implement `select_by_strategy/2` for different selection methods
- [x] 1.1.2.9 Implement `candidates/1` to get candidate list
- [x] 1.1.2.10 Implement `add_candidate/2` to append single candidate

### Step 4: Write Candidate Unit Tests (1.1.3)

- [x] Test `new/1` creates valid candidate with required fields
- [x] Test `new/1` auto-generates UUID and timestamp
- [x] Test `update_score/2` updates score and returns updated struct
- [x] Test `to_map/1` serializes to map
- [x] Test `from_map/1` deserializes from map
- [x] Test `from_map/1` handles invalid data gracefully

### Step 5: Write GenerationResult Unit Tests (1.1.3)

- [x] Test `new/1` creates result from candidate list
- [x] Test `new/1` computes best_candidate correctly
- [x] Test `best_candidate/1` returns highest scored candidate
- [x] Test `best_candidate/1` handles empty list
- [x] Test `select_by_strategy/2` with `:best` strategy
- [x] Test `select_by_strategy/2` with `:vote` strategy
- [x] Test `total_tokens/1` sums tokens correctly
- [x] Test `add_candidate/2` appends candidate to list
- [x] Test serialization round-trip

### Step 6: Verify All Tests Pass

- [x] Run `mix test test/jido_ai/accuracy/` - 75 tests passing
- [x] Verify test coverage (Candidate: 30 tests, GenerationResult: 45 tests)
- [x] Run `mix credo` - no warnings for accuracy modules
- [ ] Run `mix dialyzer` - skipped (dialyzer not configured in this environment)

## Current Status

**Status**: ✅ Complete
**What works**:
- `Candidate` module with `new/1`, `new!/1`, `update_score/2`, `to_map/1`, `from_map/1`
- `GenerationResult` module with `new/2`, `new!/2`, `best_candidate/1`, `total_tokens/1`, `select_by_strategy/2`, `add_candidate/2`, serialization
- Full test coverage: 75 tests passing (30 for Candidate, 45 for GenerationResult)
- Proper error handling for invalid inputs

**What's next**: Mark tasks complete in phase plan, write summary, commit and merge
**How to run tests**: `mix test test/jido_ai/accuracy/`

## Implementation Notes

- **ID Generation**: Uses `Jido.Util.generate_id()` with prefix "candidate_"
- **Timestamp Handling**: ISO8601 string serialization for JSON compatibility
- **Serialization**: Full round-trip support with `to_map/1` and `from_map/1`
- **Error Handling**: Added catch-all clauses to handle invalid inputs gracefully
- **Code Quality**: Credo passes with no issues for accuracy modules
- **Cyclomatic Complexity**: Reduced by extracting `extract_attrs_from_map/1` helper function

## Notes/Considerations

- **UUID Generation**: Used `Jido.Util.generate_id()` (from jido dep) with "candidate_" prefix
- **Timestamp Handling**: ISO8601 string serialization for JSON compatibility
- **Serialization**: Convert structs to maps for JSON compatibility
- **Score Comparison**: Handle `nil` scores (treat as 0 or lowest priority)
- **Best Candidate**: Computed on `new/1` - re-computed when candidates are added
- **Vote Strategy**: Simple majority for now - full implementation in Phase 1.3
- **Directory Layout**: This is the first accuracy module - establishes pattern for future phases
- **Test Isolation**: All tests run with `async: true` for parallel execution
