# Feature Planning Document: Phase 4.3 - Reflection Loop

**Status:** Completed
**Section:** 4.3 - Reflection Loop
**Dependencies:** Phase 4.1 (Critique Component), Phase 4.2 (Revision Component)
**Branch:** `feature/accuracy-phase-4-3-reflection-loop`

## Problem Statement

The accuracy improvement system currently has:
- Critique capabilities (LLMCritiquer, ToolCritiquer)
- Revision capabilities (LLMReviser, TargetedReviser)

However, it lacks **orchestration** that enables:
1. Iterative refinement through critique-revise cycles
2. Automatic convergence detection
3. Cross-episode learning via reflection memory
4. Tracking of iteration history

**Impact**: Without orchestration, critique and revision are manual one-off operations. The reflection loop automates self-improvement through multiple iterations.

## Solution Overview

Implement reflection loop components that orchestrate iterative refinement:

1. **ReflectionLoop** - Orchestrates generate-critique-revise cycles
2. **Convergence Detection** - Determines when to stop iterating
3. **ReflexionMemory** - Stores and retrieves critique patterns for cross-episode learning

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Loop control | Configurable max iterations | Prevents infinite loops |
| Convergence criteria | Multiple signals | Flexible stopping conditions |
| Memory backend | ETS with optional fallback | Fast in-process storage |
| Similarity for retrieval | Vector embeddings or keyword matching | Scalable pattern matching |
| History tracking | Full iteration history | Enables debugging and analysis |

## Technical Details

### Module Structure

```
lib/jido_ai/accuracy/
├── reflection_loop.ex            # Main loop orchestrator
├── reflexion_memory.ex           # Cross-episode memory
└── convergence.ex                # Convergence detection (module or inline)
```

### Dependencies

- **Existing**: `Candidate`, `CritiqueResult` from Phase 4.1
- **Existing**: `Revision` behavior, revisers from Phase 4.2
- **Existing**: LLM generation via `ReqLLM`
- **New**: ETS tables for reflexion memory
- **Optional**: Similarity metrics from Phase 3

### File Locations

| File | Purpose |
|------|---------|
| `lib/jido_ai/accuracy/reflection_loop.ex` | Main loop orchestrator |
| `lib/jido_ai/accuracy/reflexion_memory.ex` | Memory storage and retrieval |
| `test/jido_ai/accuracy/reflection_loop_test.exs` | Loop tests |
| `test/jido_ai/accuracy/reflexion_memory_test.exs` | Memory tests |

## Success Criteria

1. **ReflectionLoop**: Executes multiple critique-revise iterations
2. **Convergence Detection**: Stops when improvement plateaus
3. **ReflexionMemory**: Stores and retrieves similar critiques
4. **History Tracking**: Maintains full iteration history
5. **Test Coverage**: Minimum 85% for all reflection components
6. **Integration**: Works with existing critiquers and revisers

## Implementation Plan

### Step 1: ReflectionLoop Module (4.3.1)

**Purpose**: Orchestrate the generate-critique-revise cycle

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/reflection_loop.ex`
- [x] Add `@moduledoc` explaining reflection loop pattern
- [x] Define configuration struct:
  ```elixir
  defstruct [
    max_iterations: 3,
    critiquer: nil,
    reviser: nil,
    convergence_threshold: 0.1,
    generator: nil
  ]
  ```
- [x] Implement `run/3` with prompt, initial_candidate, and config
- [x] Implement `run_iteration/3` for single critique-revise cycle
- [x] Implement `check_convergence/3` for convergence checking
- [x] Track iteration history in state
- [x] Support max_iterations limit
- [x] Return best candidate across iterations
- [x] Write tests

### Step 2: Convergence Detection (4.3.2)

**Purpose**: Determine when to stop iterating

**Tasks**:
- [x] Implement `check_convergence/3`:
  - Detect no new issues (severity plateau)
  - Detect score plateau (minimal improvement)
  - Detect max iterations reached
- [x] Implement `has_converged?/2` helper
- [x] Implement `improvement_score/2` to measure delta
- [x] Write tests for convergence scenarios

### Step 3: ReflexionMemory (4.3.3)

**Purpose**: Store and retrieve critique patterns for cross-episode learning

**Tasks**:
- [x] Create `lib/jido_ai/accuracy/reflexion_memory.ex`
- [x] Add `@moduledoc` explaining reflexion pattern
- [x] Define configuration struct:
  ```elixir
  defstruct [
    storage: :ets,  # :ets or :memory (in-process)
    max_entries: 1000,
    similarity_threshold: 0.7
  ]
  ```
- [x] Implement `new/1` constructor with ETS table setup
- [x] Implement `store/2` for critique storage
- [x] Implement `retrieve_similar/2` for similarity-based lookup
- [x] Implement `format_for_prompt/1` to format memories as few-shot examples
- [x] Implement `clear/1` for memory clearing
- [x] Implement `count/1` for entry count
- [x] Write tests

### Step 4: Unit Tests (4.3.4)

**Tests to write**:

- [x] `reflection_loop_test.exs`:
  - Test `run/3` executes multiple iterations
  - Test convergence detection stops loop
  - Test max_iterations limit enforced
  - Test iteration history tracked
  - Test best candidate selection

- [x] `reflexion_memory_test.exs`:
  - Test `store/2` saves critiques
  - Test `retrieve_similar/2` finds similar entries
  - Test `format_for_prompt/1` formats for LLM
  - Test `clear/1` empties memory
  - Test `max_entries` limit enforced
  - Test cross-episode learning

## Current Status

**Status**: Completed

**Completed**:
- Created feature branch `feature/accuracy-phase-4-3-reflection-loop`
- Created planning document
- Implemented ReflectionLoop module with full orchestration
- Implemented Convergence Detection (low severity, minimal change, score plateau)
- Implemented ReflexionMemory with ETS storage and Jaccard similarity
- All 62 tests passing (29 ReflectionLoop + 33 ReflexionMemory)

**What Works**:
- `ReflectionLoop.run/3` executes multiple critique-revise iterations
- Convergence detection stops on low severity, minimal content change, or score plateau
- Max iterations limit is enforced
- Iteration history is tracked with full candidate/critique details
- Best candidate selection across iterations
- ReflexionMemory stores and retrieves similar critiques via keyword matching
- Cross-episode learning via memory context injection

**How to Run**:
```bash
# Run reflection loop tests
mix test test/jido_ai/accuracy/reflection_loop_test.exs

# Run reflexion memory tests
mix test test/jido_ai/accuracy/reflexion_memory_test.exs

# Run all tests
mix test test/jido_ai/accuracy/reflection_loop_test.exs test/jido_ai/accuracy/reflexion_memory_test.exs
```

**Known Limitations**:
- Similarity matching uses keyword-based Jaccard similarity (can upgrade to embeddings)
- Memory is ETS-based (in-process only, can add persistent backend)
- Generator integration returns first candidate from list (could add selection logic)

## Notes/Considerations

### Convergence Criteria

The loop should converge when:
1. No new issues are found (critique severity plateaus)
2. Score improvement is below threshold
3. Max iterations reached (safety limit)

### Reflexion Memory Design

Based on the Reflexion paper (Lighthizer et al., 2023):
- Store past mistakes and corrections
- Retrieve similar past examples as few-shot context
- Use for cross-episode learning

Storage format:
```elixir
%{
  prompt_hash: "sha256 of prompt",
  prompt: "original question",
  mistake: "what went wrong",
  correction: "how it was fixed",
  timestamp: DateTime.utc_now()
}
```

### Similarity Matching

For retrieval similarity:
- Option 1: Simple keyword matching (faster, simpler)
- Option 2: Embedding similarity (more accurate, requires embedding model)

Start with keyword matching, can upgrade to embeddings later.

### Integration with Existing Components

ReflectionLoop uses:
- **Critiquer** (from 4.1): `LLMCritiquer` or `ToolCritiquer`
- **Reviser** (from 4.2): `LLMReviser` or `TargetedReviser`
- **Generator** (from 1.x): `LLMGenerator` for initial response

### Future Enhancements

1. **Adaptive iteration count**: Adjust max_iterations based on task complexity
2. **Multi-critique aggregation**: Combine multiple critiquers
3. **Confidence-weighted selection**: Use verifier scores for candidate selection
4. **Persistent memory**: Database backend for reflexion memory
