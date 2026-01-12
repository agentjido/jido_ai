# Feature Planning Document: Phase 3 - Search Controllers

**Status:** In Progress
**Section:** 3 - Search Controllers
**Dependencies:** Phase 1 (Self-Consistency), Phase 2 (Verifier System)
**Branch:** `feature/accuracy-phase-3-search`

## Problem Statement

The accuracy improvement system currently has:
- Self-consistency with candidate generation and aggregation
- Multiple verification methods (outcome, PRM, deterministic, tool-based)
- VerificationRunner for orchestrating verifiers

However, it lacks **search algorithms** that systematically explore the solution space:
1. Current sampling is random - doesn't use verification to guide exploration
2. No beam search for maintaining top-K candidates during generation
3. No MCTS for tree-based reasoning exploration
4. No diverse decoding for ensuring candidate variety
5. Verification is only used for final selection, not exploration guidance

**Impact**: Without search controllers, we miss opportunities to:
- Use verification scores to guide candidate generation (not just selection)
- Explore reasoning trees systematically with MCTS
- Maintain diverse beams of high-quality candidates
- Improve accuracy through guided search vs random sampling

## Solution Overview

Implement search algorithms that use verifiers to guide exploration:

1. **SearchController Behavior** - Interface for all search algorithms
2. **SearchState** - State tracking during search execution
3. **BeamSearch** - Maintain and expand top-K candidates at each step
4. **MCTS** - Tree search with UCB1 selection and backpropagation
5. **DiverseDecoding** - Generate and select diverse outputs with MMR

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Search interface | Behavior pattern | Allows pluggable search algorithms |
| State management | Struct with pure functions | Easier to test and reason about |
| Beam verification | After each expansion | Uses verifier to guide search |
| MCTS simulation | Verifier-guided rollout | Scores paths without full generation |
| Diversity metric | Combined similarity | Jaccard + edit distance for robustness |
| MMR algorithm | Lambda-weighted | Balances relevance and diversity |

## Agent Consultations Performed

### Elixir Expert (for search algorithm patterns)
**Purpose:** Understand Elixir patterns for recursive algorithms and tree structures

**Key Findings:**
- Use tail-recursive functions for deep traversals
- Structs with `@enforce_keys` for type safety
- Use `:persistent_term` for configuration caching if needed
- Stream operations for large candidate lists
- Agent/GenServer not needed for stateless search (use pure functions)

### Senior Engineer Reviewer (for architecture)
**Purpose:** Validate search controller architecture and integration

**Key Findings:**
- SearchController should be a behavior, not a GenServer
- Search algorithms should be stateless (state passed as parameter)
- Integration with existing VerificationRunner via adapter pattern
- Telemetry events for monitoring search progress
- Consider timeout handling for long-running searches

## Technical Details

### File Structure

```
lib/jido_ai/accuracy/
├── search_controller.ex           # Create - Behavior interface
├── search_state.ex                # Create - State tracking
├── search/
│   ├── beam_search.ex             # Create - Beam search implementation
│   ├── mcts.ex                    # Create - MCTS implementation
│   ├── mcts_node.ex               # Create - MCTS node structure
│   └── diverse_decoding.ex        # Create - Diverse decoding
└── similarity.ex                  # Create - Similarity metrics

test/jido_ai/accuracy/
├── search_controller_test.exs     # Create - Behavior tests
├── search_state_test.exs          # Create - State tests
├── search/
│   ├── beam_search_test.exs       # Create - Beam search tests
│   ├── mcts_test.exs              # Create - MCTS tests
│   ├── mcts_node_test.exs         # Create - MCTS node tests
│   └── diverse_decoding_test.exs  # Create - Diverse decoding tests
├── similarity_test.exs            # Create - Similarity tests
└── search_test.exs                # Create - Integration tests
```

### Dependencies

**Existing Modules:**
- `Jido.AI.Accuracy.Candidate` - Candidate structure
- `Jido.AI.Accuracy.VerificationResult` - Verification results
- `Jido.AI.Accuracy.VerificationRunner` - For verification
- `Jido.AI.Accuracy.Verifiers.*` - All verifiers
- `Jido.AI.Accuracy.PRMs.*` - Process Reward Models
- `Jido.AI.Accuracy.Generators.LLMGenerator` - Candidate generation

**New Dependencies:**
- None (pure Elixir)

## Success Criteria

| Criterion | Target | Measurement |
|-----------|--------|-------------|
| SearchController behavior defined | ✅ | Clean interface for all search algorithms |
| BeamSearch implemented | ✅ | Top-K maintenance with verifier guidance |
| MCTS implemented | ✅ | UCB1 selection with backpropagation |
| DiverseDecoding implemented | ✅ | MMR-based diverse selection |
| Search outperforms baseline | >5% | Accuracy vs simple self-consistency |
| Test coverage | >85% | ExUnit coveralls |
| All tests passing | ✅ | mix test |
| Credo clean | ✅ | mix credo |

## Implementation Plan

### Step 1: Create Feature Branch (3.0.1)

- [ ] 3.0.1.1 Create `feature/accuracy-phase-3-search` from `feature/accuracy`
- [ ] 3.0.1.2 Verify branch is clean and up to date

### Step 2: SearchController Behavior (3.1)

**File:** `lib/jido_ai/accuracy/search_controller.ex`

- [ ] 3.1.1 Create behavior with `@callback search/4`
- [ ] 3.1.2 Define `@callback search_stream/4` (optional, for future)
- [ ] 3.1.3 Define `@type search_option/0` with common options
- [ ] 3.1.4 Add comprehensive `@moduledoc`
- [ ] 3.1.5 Define `@type search_result/0`

**Options:**
- `:max_iterations` - Max search iterations (default: 10)
- `:timeout` - Per-search timeout in ms (default: 30000)
- `:beam_width` - For beam search (default: 5)
- `:simulations` - For MCTS (default: 100)
- `:exploration_constant` - For MCTS UCB1 (default: 1.414)
- `:diversity_threshold` - For diverse decoding (default: 0.7)
- `:temperature_range` - For generation (default: {0.0, 1.0})

### Step 3: SearchState (3.1.2)

**File:** `lib/jido_ai/accuracy/search_state.ex`

- [ ] 3.1.2.1 Create `defstruct` with fields:
  - `:nodes` - Current search nodes/candidates
  - `:best_node` - Best node found so far
  - `:iterations` - Number of iterations performed
  - `:budget_remaining` - Compute budget remaining
  - `:converged` - Whether search has converged
  - `:metadata` - Additional state metadata
- [ ] 3.1.2.2 Implement `new/1` constructor
- [ ] 3.1.2.3 Implement `update_best/2`
- [ ] 3.1.2.4 Implement `should_stop?/1`
- [ ] 3.1.2.5 Implement `add_node/2`
- [ ] 3.1.2.6 Implement `decrement_budget/2`
- [ ] 3.1.2.7 Implement `converged?/1`

**Convergence criteria:**
- Budget exhausted
- Best score hasn't improved in N iterations
- Max iterations reached

### Step 4: BeamSearch Implementation (3.2)

**File:** `lib/jido_ai/accuracy/search/beam_search.ex`

- [ ] 3.2.1 Create module adopting SearchController behavior
- [ ] 3.2.2 Define `defstruct` with configuration:
  - `:beam_width` - Number of candidates to maintain (default: 5)
  - `:depth` - Search depth (default: 3)
  - `:branching_factor` - Candidates per beam (default: 2)
- [ ] 3.2.3 Implement `search/4`:
  1. Initialize beam with N candidates
  2. For each depth level:
     - Expand each beam position
     - Verify all expansions
     - Select top-K by verifier score
  3. Return best candidate

- [ ] 3.2.4 Implement `initialize_beam/3`
- [ ] 3.2.5 Implement `expand_beam/3`
- [ ] 3.2.6 Implement `verify_expansions/3`
- [ ] 3.2.7 Implement `select_top_k/3`
- [ ] 3.2.8 Implement `is_complete?/2`

**Algorithm:**
```
1. Generate N initial candidates (beam_width)
2. Verify all candidates, keep top-K
3. For each remaining depth level:
   a. For each candidate in beam, generate M expansions
   b. Verify all expansions
   c. Keep top-K across all expansions
4. Return best candidate from final beam
```

### Step 5: MCTS Implementation (3.3)

**File:** `lib/jido_ai/accuracy/search/mcts_node.ex`

- [ ] 3.3.1.1 Create `defstruct` with fields:
  - `:state` - Reasoning state at this node
  - `:visits` - Visit count
  - `:value` - Cumulative value
  - `:children` - Child nodes
  - `:parent` - Parent reference
  - `:is_terminal` - Terminal flag
  - `:candidate` - Associated candidate
  - `:action` - Action leading to this node
- [ ] 3.3.1.2 Implement `new/1`
- [ ] 3.3.1.3 Implement `ucb1_score/2`:
  ```elixir
  ucb1 = (value / visits) + c * sqrt(ln(parent_visits) / visits)
  ```
- [ ] 3.3.1.4 Implement `add_child/2`
- [ ] 3.3.1.5 Implement `update_value/2`
- [ ] 3.3.1.6 Implement `is_fully_expanded?/1`
- [ ] 3.3.1.7 Implement `best_child/2`

**File:** `lib/jido_ai/accuracy/search/mcts.ex`

- [ ] 3.3.2.1 Create module adopting SearchController behavior
- [ ] 3.3.2.2 Define `defstruct` with configuration:
  - `:simulations` - Number of simulations (default: 100)
  - `:exploration_constant` - UCB1 c parameter (default: 1.414)
  - `:max_depth` - Max tree depth (default: 10)
- [ ] 3.3.2.3 Implement `search/4`:
  1. Initialize root node
  2. For N simulations:
     - Selection: traverse tree with UCB1
     - Expansion: add new node
     - Simulation: rollout with verifier
     - Backpropagation: update values
  3. Return best child

- [ ] 3.3.2.4 Implement `selection/1` - tree_policy
- [ ] 3.3.2.5 Implement `expansion/1`
- [ ] 3.3.2.6 Implement `simulation/1` - default_policy with verifier
- [ ] 3.3.2.7 Implement `backpropagation/2` - backup
- [ ] 3.3.2.8 Implement `best_child/3`

**Algorithm:**
```
1. Initialize root with empty state
2. For each simulation:
   a. Select: traverse tree using UCB1
   b. Expand: add new child if not fully expanded
   c. Simulate: generate candidate, score with verifier
   d. Backpropagate: update all ancestors
3. Return child with highest visit ratio (value/visits)
```

### Step 6: DiverseDecoding Implementation (3.4)

**File:** `lib/jido_ai/accuracy/similarity.ex`

- [ ] 3.4.2.1 Implement `jaccard_similarity/2`:
  ```elixir
  intersection / union of token sets
  ```
- [ ] 3.4.2.2 Implement `edit_distance_similarity/2`:
  ```elixir
  1 - (edit_distance / max_length)
  ```
- [ ] 3.4.2.3 Implement `combined_similarity/3`:
  ```elixir
  weighted average of Jaccard and edit distance
  ```

**File:** `lib/jido_ai/accuracy/search/diverse_decoding.ex`

- [ ] 3.4.1.1 Create module adopting SearchController behavior
- [ ] 3.4.1.2 Define `defstruct` with configuration:
  - `:num_candidates` - Number of candidates (default: 10)
  - `:diversity_threshold` - Min similarity threshold (default: 0.7)
  - `:temperature_range` - Temperature range (default: {0.0, 1.0})
  - `:lambda` - MMR relevance/diversity tradeoff (default: 0.5)
- [ ] 3.4.1.3 Implement `search/4`:
  1. Generate N candidates with varied temperatures
  2. Score all candidates with verifier
  3. Apply MMR to select diverse top-K
  4. Return best (most relevant) from selected set

- [ ] 3.4.1.4 Implement `sample_diverse/3`
- [ ] 3.4.1.5 Implement `compute_similarity/2`
- [ ] 3.4.3.1 Implement `mmr_select/4`:
  ```elixir
  mmr_score = lambda * relevance - (1 - lambda) * max_similarity_to_selected
  ```

**MMR Algorithm:**
```
1. Score all candidates with verifier (relevance)
2. Initialize selected = []
3. While selected < K:
   a. For each unselected candidate:
      score = lambda * relevance - (1 - lambda) * max_sim_to_selected
   b. Add candidate with highest score to selected
4. Return selected candidates
```

### Step 7: Unit Tests (3.1-3.4)

**File:** `test/jido_ai/accuracy/search_state_test.exs`

- [ ] Test `new/1` initializes correctly
- [ ] Test `update_best/2` updates when score is higher
- [ ] Test `update_best/2` preserves current best when lower
- [ ] Test `should_stop?/1` checks budget and convergence
- [ ] Test `should_stop?/1` returns true when budget exhausted
- [ ] Test `should_stop?/1` returns true when converged
- [ ] Test `add_node/2` appends node to state
- [ ] Test `decrement_budget/2` reduces budget correctly

**File:** `test/jido_ai/accuracy/search/beam_search_test.exs`

- [ ] Test beam search with width=3
- [ ] Test beam search depth parameter
- [ ] Test top-K selection at each step
- [ ] Test returns best final candidate
- [ ] Test handles empty beam
- [ ] Test beam width=1 degenerates to greedy search
- [ ] Test verifier guides beam toward better solutions
- [ ] Test branching factor affects search breadth

**File:** `test/jido_ai/accuracy/search/mcts_node_test.exs`

- [ ] Test `new/1` creates valid node
- [ ] Test `ucb1_score/2` balances exploration/exploitation
- [ ] Test `ucb1_score/2` handles unvisited nodes
- [ ] Test `add_child/2` adds child correctly
- [ ] Test `update_value/2` accumulates values
- [ ] Test `is_fully_expanded?/1` checks expansion
- [ ] Test `best_child/2` returns highest-value child

**File:** `test/jido_ai/accuracy/search/mcts_test.exs`

- [ ] Test MCTS selection phase traverses tree
- [ ] Test MCTS expansion creates children
- [ ] Test MCTS backpropagation updates ancestors
- [ ] Test full MCTS search returns best candidate
- [ ] Test exploration constant affects search behavior
- [ ] Test PRM guidance improves simulation accuracy
- [ ] Test max_depth is respected

**File:** `test/jido_ai/accuracy/search/diverse_decoding_test.exs`

- [ ] Test diverse sampling produces variety
- [ ] Test similarity computation accuracy
- [ ] Test MMR ranking promotes diversity
- [ ] Test returns specified number of candidates
- [ ] Test diversity threshold affects selection
- [ ] Test lambda parameter balances relevance/diversity

**File:** `test/jido_ai/accuracy/similarity_test.exs`

- [ ] Test Jaccard similarity for identical strings
- [ ] Test Jaccard similarity for disjoint strings
- [ ] Test Jaccard similarity for partial overlap
- [ ] Test edit distance similarity
- [ ] Test combined similarity with weights

### Step 8: Integration Tests (3.5)

**File:** `test/jido_ai/accuracy/search_test.exs`

- [ ] 3.5.1.2 Test: Beam search finds better answer than greedy
- [ ] 3.5.1.3 Test: Beam width impact (1, 3, 5)
- [ ] 3.5.1.4 Test: MCTS explores reasoning space
- [ ] 3.5.1.5 Test: MCTS with PRM guidance
- [ ] 3.5.1.6 Test: Diverse decoding produces variety
- [ ] 3.5.2.1 Test: Beam search scales linearly with width
- [ ] 3.5.2.2 Test: MCTS completes within budget
- [ ] 3.5.2.3 Test: Diverse decoding is faster than MCTS
- [ ] 3.5.3.1 Test: Search algorithms outperform simple sampling
- [ ] 3.5.3.2 Test: Verifier guidance improves search

## Notes/Considerations

### Complexity Considerations

1. **Beam Search Complexity:**
   - Time: O(depth * beam_width * branching_factor * verification_time)
   - Space: O(beam_width * candidate_size)

2. **MCTS Complexity:**
   - Time: O(simulations * max_depth * (selection + simulation))
   - Space: O(simulations * max_depth * node_size)
   - Consider pruning for memory management

3. **Diverse Decoding Complexity:**
   - Time: O(num_candidates^2 * similarity_time)
   - Space: O(num_candidates * candidate_size)

### Testing Strategy

1. **Mock verifiers** for deterministic testing
2. **Use small beam widths/simulations** for fast tests
3. **Tag performance tests** as `@tag :performance` to exclude from CI
4. **Use `@tag :requires_api`** for tests needing actual LLM calls

### Future Enhancements

1. **Adaptive beam width** based on verification scores
2. **Transposition tables** for MCTS to reuse subtrees
3. **Parallel MCTS** with multiple trees
4. **Ensemble search** combining multiple algorithms

## Current Status

**Phase:** Complete
**Branch:** `feature/accuracy-phase-3-search`
**Last Updated:** 2025-01-12

**Implementation Summary:**

### Completed Steps

1. ✅ Created feature branch `feature/accuracy-phase-3-search`
2. ✅ Implemented `SearchController` behavior (`lib/jido_ai/accuracy/search_controller.ex`)
3. ✅ Implemented `SearchState` (`lib/jido_ai/accuracy/search_state.ex`) - 54 tests passing
4. ✅ Implemented `BeamSearch` (`lib/jido_ai/accuracy/search/beam_search.ex`) - 32 tests passing
5. ✅ Implemented `MCTSNode` (`lib/jido_ai/accuracy/search/mcts_node.ex`) - 39 tests passing
6. ✅ Implemented `MCTS` (`lib/jido_ai/accuracy/search/mcts.ex`) - 32 tests passing
7. ✅ Implemented `Similarity` metrics (`lib/jido_ai/accuracy/similarity.ex`) - 27 tests passing
8. ✅ Implemented `DiverseDecoding` (`lib/jido_ai/accuracy/search/diverse_decoding.ex`) - 35 tests passing
9. ✅ Created integration tests (`test/jido_ai/accuracy/search_test.exs`) - 17 tests passing

### Test Results

**Total Phase 3 Tests:** 236 tests, 0 failures

- `search_state_test.exs` - 54 tests
- `beam_search_test.exs` - 32 tests
- `mcts_node_test.exs` - 39 tests
- `mcts_test.exs` - 32 tests
- `similarity_test.exs` - 27 tests
- `diverse_decoding_test.exs` - 35 tests
- `search_test.exs` (integration) - 17 tests

### Files Created

**Implementation:**
- `lib/jido_ai/accuracy/search_controller.ex` - Behavior interface
- `lib/jido_ai/accuracy/search_state.ex` - State tracking
- `lib/jido_ai/accuracy/search/beam_search.ex` - Beam search algorithm
- `lib/jido_ai/accuracy/search/mcts_node.ex` - MCTS node structure
- `lib/jido_ai/accuracy/search/mcts.ex` - MCTS algorithm
- `lib/jido_ai/accuracy/similarity.ex` - Similarity metrics
- `lib/jido_ai/accuracy/search/diverse_decoding.ex` - Diverse decoding with MMR

**Tests:**
- `test/jido_ai/accuracy/search_state_test.exs`
- `test/jido_ai/accuracy/search/beam_search_test.exs`
- `test/jido_ai/accuracy/search/mcts_node_test.exs`
- `test/jido_ai/accuracy/search/mcts_test.exs`
- `test/jido_ai/accuracy/search/diverse_decoding_test.exs`
- `test/jido_ai/accuracy/similarity_test.exs`
- `test/jido_ai/accuracy/search_test.exs`

**Next Steps:**
1. Run quality checks (credo, dialyzer, coverage)
2. Merge to `feature/accuracy` branch
