# Phase 3: Search Controllers

This phase implements search algorithms (beam search, MCTS) that use verifiers to guide exploration. Search controllers improve over simple sampling by systematically exploring the solution space and using verification scores to guide the search toward better solutions.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Search Controller                          │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ Beam     │    │  MCTS    │    │ Diverse  │              │
│  │ Search   │    │          │    │ Decoding │              │
│  └──────────┘    └──────────┘    └──────────┘              │
│        │               │               │                    │
│        └───────────────┴───────────────┘                    │
│                        │                                     │
│                   ┌────▼────┐                               │
│                   │ Verifier│                               │
│                   │ Guidance│                               │
│                   └─────────┘                               │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| SearchController behavior | Interface for search algorithm implementations |
| SearchState | State tracking during search execution |
| BeamSearch | Maintains top-K candidates at each step |
| MCTSNode | Node structure for Monte Carlo Tree Search |
| MCTS | Tree search with UCB1 selection and backpropagation |
| DiverseDecoding | Generates and selects diverse outputs |

---

## 3.1 Search Controller Behavior

Define the behavior for search algorithms that use verifiers to guide exploration.

### 3.1.1 SearchController Behavior Definition

Create the behavior that all search controllers implement.

- [ ] 3.1.1.1 Create `lib/jido_ai/accuracy/search_controller.ex`
- [ ] 3.1.1.2 Add `@moduledoc` explaining search controller concept
- [ ] 3.1.1.3 Define `@callback search/4`:
  ```elixir
  @callback search(
    prompt :: String.t(),
    generator :: module(),
    verifier :: module(),
    opts :: keyword()
  ) :: {:ok, Jido.AI.Accuracy.Candidate.t()} | {:error, term()}
  ```
- [ ] 3.1.1.4 Define `@callback search_stream/4` for streaming results
- [ ] 3.1.1.5 Document search algorithm patterns
- [ ] 3.1.1.6 Define `@type search_option/0` for common options

### 3.1.2 Search State

Define state for search algorithms to track progress.

- [ ] 3.1.2.1 Create `lib/jido_ai/accuracy/search_state.ex`
- [ ] 3.1.2.2 Define `defstruct` with fields:
  - `:nodes` - Current search nodes/candidates
  - `:best_node` - Best node found so far
  - `:iterations` - Number of iterations performed
  - `:budget_remaining` - Compute budget remaining
  - `:converged` - Whether search has converged
  - `:metadata` - Additional state metadata
- [ ] 3.1.2.3 Add `@moduledoc` with documentation
- [ ] 3.1.2.4 Implement `new/1` constructor
- [ ] 3.1.2.5 Implement `update_best/2`
- [ ] 3.1.2.6 Implement `should_stop?/1`
- [ ] 3.1.2.7 Implement `add_node/2`
- [ ] 3.1.2.8 Implement `decrement_budget/2`

### 3.1.3 Unit Tests for Search Types

- [ ] Test `SearchState.new/1` initializes correctly
- [ ] Test `update_best/2` updates when score is higher
- [ ] Test `update_best/2` preserves current best when score is lower
- [ ] Test `should_stop?/1` checks budget and convergence
- [ ] Test `should_stop?/1` returns true when budget exhausted
- [ ] Test `should_stop?/1` returns true when converged
- [ ] Test `add_node/2` appends node to state
- [ ] Test `decrement_budget/2` reduces budget correctly

---

## 3.2 Beam Search

Implement beam search with verifier guidance.

### 3.2.1 BeamSearch Controller

Create the beam search implementation.

- [ ] 3.2.1.1 Create `lib/jido_ai/accuracy/search/beam_search.ex`
- [ ] 3.2.1.2 Add `@moduledoc` explaining beam search algorithm
- [ ] 3.2.1.3 Define configuration schema:
  - `:beam_width` - Number of candidates to maintain (default: 5)
  - `:depth` - Search depth (default: 3)
  - `:branching_factor` - Candidates per beam position
- [ ] 3.2.1.4 Implement `search/4` with beam width parameter
- [ ] 3.2.1.5 Implement initialization: generate N initial candidates
- [ ] 3.2.1.6 Implement expansion: generate N candidates for each beam position
- [ ] 3.2.1.7 Implement verification: verify all expanded candidates
- [ ] 3.2.1.8 Implement selection: keep top-K by verifier score
- [ ] 3.2.1.9 Implement iteration: repeat for specified depth
- [ ] 3.2.1.10 Return best candidate found

### 3.2.2 Beam Search Operations

Implement beam search specific operations.

- [ ] 3.2.2.1 Implement `initialize_beam/3` with initial generation
- [ ] 3.2.2.2 Implement `expand_beam/3` with branching
- [ ] 3.2.2.3 Implement `verify_expansions/3` with verifier
- [ ] 3.2.2.4 Implement `select_top_k/3` for beam maintenance
- [ ] 3.2.2.5 Implement `is_complete?/2` for termination check

### 3.2.3 Unit Tests for BeamSearch

- [ ] Test beam search with width=3
- [ ] Test beam search depth parameter
- [ ] Test top-K selection at each step
- [ ] Test returns best final candidate
- [ ] Test handles empty beam
- [ ] Test beam width=1 degenerates to greedy search
- [ ] Test verifier guides beam toward better solutions
- [ ] Test branching factor affects search breadth

---

## 3.3 MCTS (Monte Carlo Tree Search)

Implement MCTS for reasoning tree exploration.

### 3.3.1 MCTS Node Structure

Define the MCTS tree node structure.

- [ ] 3.3.1.1 Create `lib/jido_ai/accuracy/search/mcts_node.ex`
- [ ] 3.3.1.2 Define `defstruct` with fields:
  - `:state` - The reasoning state at this node
  - `:visits` - Number of times this node was visited
  - `:value` - Cumulative value from this node
  - `:children` - Child nodes
  - `:parent` - Parent node reference
  - `:is_terminal` - Whether this is a terminal node
  - `:candidate` - Associated candidate if terminal
- [ ] 3.3.1.3 Add `@moduledoc` explaining MCTS node concept
- [ ] 3.3.1.4 Implement `new/1` constructor
- [ ] 3.3.1.5 Implement `ucb1_score/2` for selection
- [ ] 3.3.1.6 Implement `add_child/2`
- [ ] 3.3.1.7 Implement `update_value/2`
- [ ] 3.3.1.8 Implement `is_fully_expanded?/1`
- [ ] 3.3.1.9 Implement `best_child/2` for final selection

### 3.3.2 MCTS Controller

Create the MCTS implementation.

- [ ] 3.3.2.1 Create `lib/jido_ai/accuracy/search/mcts.ex`
- [ ] 3.3.2.2 Add `@moduledoc` explaining MCTS algorithm
- [ ] 3.3.2.3 Define configuration schema:
  - `:simulations` - Number of simulations (default: 100)
  - `:exploration_constant` - UCB1 exploration weight (default: 1.414)
  - `:max_depth` - Maximum tree depth
- [ ] 3.3.2.4 Implement `search/4` with simulation budget
- [ ] 3.3.2.5 Implement `selection/1` - tree traversal with UCB1
- [ ] 3.3.2.6 Implement `expansion/1` - add new node
- [ ] 3.3.2.7 Implement `simulation/1` - rollout with verifier
- [ ] 3.3.2.8 Implement `backpropagation/2` - update values
- [ ] 3.3.2.9 Add PRM guidance for simulation scoring

### 3.3.3 MCTS Operations

Implement MCTS algorithm phases.

- [ ] 3.3.3.1 Implement `tree_policy/2` for selection
- [ ] 3.3.3.2 Implement `default_policy/2` for simulation
- [ ] 3.3.3.3 Implement `backup/2` for backpropagation
- [ ] 3.3.3.4 Implement `best_child/3` with temperature parameter
- [ ] 3.3.3.5 Add pruning for memory management

### 3.3.4 Unit Tests for MCTS

- [ ] Test `MCTSNode.new/1` creates valid node
- [ ] Test `ucb1_score/2` balances exploration/exploitation
- [ ] Test MCTS selection phase traverses tree
- [ ] Test MCTS expansion creates children
- [ ] Test MCTS backpropagation updates ancestors
- [ ] Test full MCTS search returns best candidate
- [ ] Test exploration constant affects search behavior
- [ ] Test PRM guidance improves simulation accuracy

---

## 3.4 Diverse Decoding

Implement diverse decoding strategies.

### 3.4.1 DiverseDecoding Controller

Create the diverse decoding implementation.

- [ ] 3.4.1.1 Create `lib/jido_ai/accuracy/search/diverse_decoding.ex`
- [ ] 3.4.1.2 Add `@moduledoc` explaining diverse decoding
- [ ] 3.4.1.3 Define configuration schema:
  - `:num_candidates` - Number of diverse candidates
  - `:diversity_threshold` - Minimum similarity threshold
  - `:temperature_range` - Temperature range for sampling
- [ ] 3.4.1.4 Implement `search/4` with diversity parameter
- [ ] 3.4.1.5 Sample with different temperature/params
- [ ] 3.4.1.6 Implement `compute_similarity/2` between candidates
- [ ] 3.4.1.7 Apply MMR (Maximal Marginal Relevance)
- [ ] 3.4.1.8 Return diverse top candidates

### 3.4.2 Similarity Computation

Implement similarity metrics for diversity.

- [ ] 3.4.2.1 Create `lib/jido_ai/accuracy/similarity.ex`
- [ ] 3.4.2.2 Implement `jaccard_similarity/2` for token overlap
- [ ] 3.4.2.3 Implement `cosine_similarity/2` for embedding-based
- [ ] 3.4.2.4 Implement `edit_distance_similarity/2` for string-based
- [ ] 3.4.2.5 Implement `combined_similarity/3` with weights

### 3.4.3 MMR Algorithm

Implement Maximal Marginal Relevance.

- [ ] 3.4.3.1 Implement `mmr_select/4` for diverse selection
- [ ] 3.4.3.2 Balance relevance and diversity
- [ ] 3.4.3.3 Use lambda parameter for trade-off

### 3.4.4 Unit Tests for DiverseDecoding

- [ ] Test diverse sampling produces variety
- [ ] Test similarity computation accuracy
- [ ] Test MMR ranking promotes diversity
- [ ] Test returns specified number of candidates
- [ ] Test diversity threshold affects selection
- [ ] Test lambda parameter balances relevance/diversity

---

## 3.5 Phase 3 Integration Tests

Comprehensive integration tests for search algorithms.

### 3.5.1 Search Algorithm Tests

- [ ] 3.5.1.1 Create `test/jido_ai/accuracy/search_test.exs`
- [ ] 3.5.1.2 Test: Beam search finds better answer than greedy
  - Compare beam search vs single generation
  - Verify beam search has higher accuracy
- [ ] 3.5.1.3 Test: Beam width impact
  - Run beam search with width=1,3,5
  - Compare accuracy vs compute tradeoff
- [ ] 3.5.1.4 Test: MCTS explores reasoning space
  - Run MCTS on math problem
  - Verify tree exploration
  - Check final answer quality
- [ ] 3.5.1.5 Test: MCTS with PRM guidance
  - Compare MCTS with/without PRM
  - Verify PRM improves search efficiency
- [ ] 3.5.1.6 Test: Diverse decoding produces variety
  - Generate candidates with diverse decoding
  - Measure pairwise diversity
  - Verify diversity threshold met

### 3.5.2 Performance Tests

- [ ] 3.5.2.1 Test: Beam search scales linearly with width
  - Measure time for different widths
  - Verify linear scaling
- [ ] 3.5.2.2 Test: MCTS completes within budget
  - Run with various simulation counts
  - Verify budget enforcement
- [ ] 3.5.2.3 Test: Diverse decoding is faster than MCTS
  - Compare time to completion
  - Verify diverse decoding is simpler

### 3.5.3 Quality Tests

- [ ] 3.5.3.1 Test: Search algorithms outperform simple sampling
  - Baseline: self-consistency
  - Compare: beam search, MCTS
  - Measure accuracy improvement
- [ ] 3.5.3.2 Test: Verifier guidance improves search
  - Run with random selection
  - Run with verifier guidance
  - Compare results

---

## Phase 3 Success Criteria

1. **SearchController behavior**: Clean interface for search algorithms
2. **Beam search**: Maintains and expands top-K candidates
3. **MCTS**: Explores reasoning tree with UCB1 selection
4. **Diverse decoding**: Generates and selects diverse outputs
5. **Verifier integration**: All search algorithms use verifiers for guidance
6. **Improvement over baseline**: Search outperforms simple sampling
7. **Test coverage**: Minimum 85% for Phase 3 modules

---

## Phase 3 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/search_controller.ex`
- `lib/jido_ai/accuracy/search_state.ex`
- `lib/jido_ai/accuracy/search/beam_search.ex`
- `lib/jido_ai/accuracy/search/mcts.ex`
- `lib/jido_ai/accuracy/search/mcts_node.ex`
- `lib/jido_ai/accuracy/search/diverse_decoding.ex`
- `lib/jido_ai/accuracy/similarity.ex`

**Test Files:**
- `test/jido_ai/accuracy/search_controller_test.exs`
- `test/jido_ai/accuracy/search_state_test.exs`
- `test/jido_ai/accuracy/search/beam_search_test.exs`
- `test/jido_ai/accuracy/search/mcts_test.exs`
- `test/jido_ai/accuracy/search/mcts_node_test.exs`
- `test/jido_ai/accuracy/search/diverse_decoding_test.exs`
- `test/jido_ai/accuracy/similarity_test.exs`
- `test/jido_ai/accuracy/search_test.exs`
