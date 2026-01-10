# Phase 1: Self-Consistency and Best-of-N Sampling

This phase implements the foundational multi-candidate generation and selection mechanisms that form the basis for test-time compute scaling. Self-consistency generates multiple candidate responses and selects the best answer through aggregation strategies like majority voting and best-of-N.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   AccuracyRunner                            │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │  Generator   │→ │  Candidates  │→ │   Aggregator │      │
│  │   (N samples)│  │   (array)    │  │  (vote/pick) │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│         │                                  │                │
│         │                                  ▼                │
│         │                           ┌──────────────┐       │
│         │                           │ Best Answer  │       │
│         │                           └──────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| Candidate | Struct representing a single response with metadata |
| GenerationResult | Struct holding multiple candidates with aggregation metadata |
| Generator | Behavior for generating multiple candidate responses |
| LLMGenerator | LLM-based implementation with parallel sampling |
| Aggregator | Behavior for selecting best candidate from N samples |
| MajorityVote | Self-consistency through majority voting on final answers |
| BestOfN | Selection based on pre-assigned scores (from verifier) |
| Weighted | Combines multiple aggregation strategies with weights |
| SelfConsistency | High-level runner orchestrating generation and aggregation |

---

## 1.1 Core Accuracy Types and Behaviors

Define the foundational types and behaviors for the accuracy improvement system. These types are used across all phases.

### 1.1.1 Candidate Representation

Define the structure for representing generated candidate responses.

- [x] 1.1.1.1 Create `lib/jido_ai/accuracy/candidate.ex`
- [x] 1.1.1.2 Define `defstruct` with fields:
  - `:id` - Unique identifier for this candidate (UUID)
  - `:content` - The generated response text
  - `:reasoning` - The reasoning trace (if applicable)
  - `:score` - The assigned score (from verifier or aggregation)
  - `:tokens_used` - Number of tokens consumed
  - `:model` - The model that generated this candidate
  - `:timestamp` - When this candidate was generated
  - `:metadata` - Additional metadata (temperature, etc.)
- [x] 1.1.1.3 Add `@moduledoc` with documentation
- [x] 1.1.1.4 Add `@type t()` definition
- [x] 1.1.1.5 Implement `new/1` constructor function
- [x] 1.1.1.6 Implement `update_score/2` for score updates
- [x] 1.1.1.7 Implement `to_map/1` for serialization
- [x] 1.1.1.8 Implement `from_map/1` for deserialization

### 1.1.2 Generation Result

Define the result type for multi-candidate generation operations.

- [x] 1.1.2.1 Create `lib/jido_ai/accuracy/generation_result.ex`
- [x] 1.1.2.2 Define `defstruct` with fields:
  - `:candidates` - List of Candidate structs
  - `:total_tokens` - Total tokens used across all candidates
  - `:best_candidate` - The highest-scoring candidate
  - `:aggregation_method` - How candidates were aggregated
  - `:metadata` - Generation metadata
- [x] 1.1.2.3 Add `@moduledoc` with documentation
- [x] 1.1.2.4 Add `@type t()` definition
- [x] 1.1.2.5 Implement `new/1` with candidate list
- [x] 1.1.2.6 Implement `best_candidate/1` to get top scored
- [x] 1.1.2.7 Implement `total_tokens/1` for cost tracking
- [x] 1.1.2.8 Implement `select_by_strategy/2` for different selection methods
- [x] 1.1.2.9 Implement `candidates/1` to get candidate list
- [x] 1.1.2.10 Implement `add_candidate/2` to append single candidate

### 1.1.3 Unit Tests for Core Types

Comprehensive unit tests for candidate and generation result types.

- [x] Test `Candidate.new/1` creates valid candidate with required fields
- [x] Test `Candidate.update_score/2` updates score and returns updated struct
- [x] Test `Candidate.to_map/1` serializes to map
- [x] Test `Candidate.from_map/1` deserializes from map
- [x] Test `GenerationResult.new/1` creates result from candidate list
- [x] Test `GenerationResult.best_candidate/1` returns highest scored candidate
- [x] Test `GenerationResult.best_candidate/1` handles empty list
- [x] Test `GenerationResult.select_by_strategy/2` with `:best` strategy
- [x] Test `GenerationResult.select_by_strategy/2` with `:vote` strategy
- [x] Test `GenerationResult.total_tokens/1` sums tokens correctly
- [x] Test `GenerationResult.add_candidate/2` appends candidate to list
- [x] Test serialization and deserialization round-trip

---

## 1.2 Candidate Generator

Generate multiple candidate responses from a single prompt using various sampling strategies.

### 1.2.1 Generator Behavior

Define the behavior for candidate generators.

- [ ] 1.2.1.1 Create `lib/jido_ai/accuracy/generator.ex`
- [ ] 1.2.1.2 Define `@moduledoc` with behavior documentation
- [ ] 1.2.1.3 Define `@callback generate_candidates/2`:
  ```elixir
  @callback generate_candidates(
    prompt :: String.t(),
    opts :: keyword()
  ) :: {:ok, [Jido.AI.Accuracy.Candidate.t()]} | {:error, term()}
  ```
- [ ] 1.2.1.4 Define `@callback generate_candidates_async/2`:
  ```elixir
  @callback generate_candidates_async(
    prompt :: String.t(),
    opts :: keyword()
  ) :: Task.t()
  ```
- [ ] 1.2.1.5 Define `@callback generate_with_reasoning/2` for CoT prompts
- [ ] 1.2.1.6 Define `@type t/0` for generator configuration
- [ ] 1.2.1.7 Define `@type opts/0` for generator options

### 1.2.2 LLM Generator Implementation

Implement the standard LLM-based candidate generator.

- [ ] 1.2.2.1 Create `lib/jido_ai/accuracy/generators/llm_generator.ex`
- [ ] 1.2.2.2 Add `@moduledoc` explaining LLM sampling approach
- [ ] 1.2.2.3 Implement `init/1` for configuration
- [ ] 1.2.2.4 Define configuration schema with Zoi:
  - `:model` - Model to use (default: "anthropic:claude-haiku-4-5")
  - `:num_candidates` - Number of candidates to generate
  - `:temperature_range` - Range for temperature variation
  - `:timeout` - Per-candidate timeout
- [ ] 1.2.2.5 Implement `generate_candidates/2` with N samples
- [ ] 1.2.2.6 Support `temperature_range` option for varied sampling
- [ ] 1.2.2.7 Add parallel generation via `Task.async_stream`
- [ ] 1.2.2.8 Handle rate limiting and retry logic
- [ ] 1.2.2.9 Implement token counting for cost tracking
- [ ] 1.2.2.10 Implement `generate_with_reasoning/2` for CoT prompts
- [ ] 1.2.2.11 Implement `generate_candidates_async/2` returning Task

### 1.2.3 Unit Tests for Generator

- [ ] Test `generate_candidates/2` returns N candidates
- [ ] Test candidates have different content with varied temperature
- [ ] Test parallel generation completes successfully
- [ ] Test token counting is accurate
- [ ] Test rate limiting triggers retry
- [ ] Test error handling for API failures
- [ ] Test `generate_candidates_async/2` returns Task
- [ ] Test `generate_with_reasoning/2` preserves reasoning traces
- [ ] Test temperature_range produces diverse outputs
- [ ] Test timeout is enforced per candidate

---

## 1.3 Candidate Aggregation

Implement voting and selection strategies to pick the best candidate.

### 1.3.1 Aggregator Behavior

Define the behavior for candidate aggregation.

- [ ] 1.3.1.1 Create `lib/jido_ai/accuracy/aggregator.ex`
- [ ] 1.3.1.2 Define `@moduledoc` with behavior documentation
- [ ] 1.3.1.3 Define `@callback aggregate/2`:
  ```elixir
  @callback aggregate(
    candidates :: [Jido.AI.Accuracy.Candidate.t()],
    opts :: keyword()
  ) :: {:ok, Jido.AI.Accuracy.Candidate.t()} | {:error, term()}
  ```
- [ ] 1.3.1.4 Document aggregation strategies in module docs

### 1.3.2 Majority Vote Aggregator

Implement self-consistency through majority voting on final answers.

- [ ] 1.3.2.1 Create `lib/jido_ai/accuracy/aggregators/majority_vote.ex`
- [ ] 1.3.2.2 Add `@moduledoc` explaining majority voting approach
- [ ] 1.3.2.3 Implement `extract_answer/1` to parse final answer
- [ ] 1.3.2.4 Support common answer formats:
  - Final answer in quotes
  - "Answer:" prefix
  - "Therefore" prefix
  - Last line as answer
- [ ] 1.3.2.5 Implement `count_votes/1` for vote tallying
- [ ] 1.3.2.6 Implement `aggregate/2` with tie-breaking logic
- [ ] 1.3.2.7 Add support for fuzzy matching of similar answers
- [ ] 1.3.2.8 Return vote confidence percentage
- [ ] 1.3.2.9 Implement `vote_distribution/1` for analysis

### 1.3.3 Best-of-N Aggregator

Implement selection based on pre-assigned scores.

- [ ] 1.3.3.1 Create `lib/jido_ai/accuracy/aggregators/best_of_n.ex`
- [ ] 1.3.3.2 Add `@moduledoc` explaining best-of-N selection
- [ ] 1.3.3.3 Implement `aggregate/2` to select max score
- [ ] 1.3.3.4 Add confidence based on score distribution
- [ ] 1.3.3.5 Handle ties with secondary criteria (token efficiency)
- [ ] 1.3.3.6 Return score metadata with selected candidate

### 1.3.4 Weighted Aggregator

Combine multiple selection strategies with weights.

- [ ] 1.3.4.1 Create `lib/jido_ai/accuracy/aggregators/weighted.ex`
- [ ] 1.3.4.2 Add `@moduledoc` explaining weighted combination
- [ ] 1.3.4.3 Implement `aggregate/3` with strategy weights
- [ ] 1.3.4.4 Support dynamic weight adjustment
- [ ] 1.3.4.5 Combine scores from multiple aggregators
- [ ] 1.3.4.6 Normalize weights to sum to 1.0

### 1.3.5 Unit Tests for Aggregators

- [ ] Test `MajorityVote.aggregate/2` selects majority answer
- [ ] Test `MajorityVote.aggregate/2` handles ties correctly
- [ ] Test `MajorityVote.aggregate/2` returns vote confidence
- [ ] Test `MajorityVote.extract_answer/1` parses various formats
- [ ] Test `MajorityVote` fuzzy matching works for similar answers
- [ ] Test `BestOfN.aggregate/2` selects highest scored
- [ ] Test `BestOfN.aggregate/2` handles equal scores
- [ ] Test `BestOfN` uses token efficiency for tie-breaking
- [ ] Test `Weighted.aggregate/3` combines strategies correctly
- [ ] Test `Weighted` normalizes weights properly
- [ ] Test edge case: empty candidate list
- [ ] Test edge case: single candidate
- [ ] Test vote distribution analysis

---

## 1.4 Self-Consistency Runner

Orchestrate the full self-consistency workflow.

### 1.4.1 Self-Consistency Module

Create the high-level runner for self-consistency.

- [ ] 1.4.1.1 Create `lib/jido_ai/accuracy/self_consistency.ex`
- [ ] 1.4.1.2 Add `@moduledoc` explaining self-consistency pattern
- [ ] 1.4.1.3 Define configuration schema with Zoi:
  - `:num_candidates` - Number of candidates (default: 5)
  - `:aggregator` - Aggregation strategy (default: :majority_vote)
  - `:temperature_range` - Temperature range for sampling
  - `:model` - Model to use
  - `:timeout` - Overall timeout
- [ ] 1.4.1.4 Implement `run/2` with prompt and options
- [ ] 1.4.1.5 Implement `run_with_reasoning/2` for CoT prompts
- [ ] 1.4.1.6 Add telemetry hooks for monitoring
- [ ] 1.4.1.7 Support streaming intermediate results
- [ ] 1.4.1.8 Implement `validate_opts/1` for configuration validation

### 1.4.2 Runner Operations

Implement the core runner operations.

- [ ] 1.4.2.1 Implement `generate_candidates/2` with configured generator
- [ ] 1.4.2.2 Implement `aggregate_candidates/2` with configured aggregator
- [ ] 1.4.2.3 Implement `calculate_confidence/2` from aggregation results
- [ ] 1.4.2.4 Implement `format_result/2` for output formatting
- [ ] 1.4.2.5 Add support for custom aggregators

### 1.4.3 Unit Tests for SelfConsistency

- [ ] Test `run/2` generates and aggregates candidates
- [ ] Test `run_with_reasoning/2` preserves reasoning traces
- [ ] Test telemetry events are emitted
- [ ] Test configuration validation via schema
- [ ] Test invalid aggregator returns error
- [ ] Test num_candidates=1 returns single result
- [ ] Test custom aggregator is used when specified
- [ ] Test streaming returns intermediate results
- [ ] Test confidence is calculated correctly
- [ ] Test timeout is enforced

---

## 1.5 Phase 1 Integration Tests

Comprehensive integration tests for self-consistency functionality.

### 1.5.1 End-to-End Self-Consistency Tests

- [ ] 1.5.1.1 Create `test/jido_ai/accuracy/self_consistency_test.exs`
- [ ] 1.5.1.2 Test: Generate 5 candidates for math problem
  - Prompt: "What is 15 * 23?"
  - Verify 5 candidates generated
  - Verify majority answer is correct (345)
- [ ] 1.5.1.3 Test: Multi-step reasoning with CoT
  - Prompt with chain-of-thought instructions
  - Verify reasoning traces preserved
  - Verify final answer extracted correctly
- [ ] 1.5.1.4 Test: Temperature variation produces diverse outputs
  - Generate candidates with wide temperature range
  - Measure diversity (should increase with range)
- [ ] 1.5.1.5 Test: Tie-breaking in majority vote
  - Craft prompt producing 2-2 tie
  - Verify deterministic tie-break

### 1.5.2 Performance and Cost Tests

- [ ] 1.5.2.1 Test: Token counting is accurate
  - Generate candidates
  - Compare counted tokens vs actual API usage
- [ ] 1.5.2.2 Test: Parallel generation completes faster
  - Compare sequential vs parallel generation time
  - Verify parallel is ~N times faster
- [ ] 1.5.2.3 Test: Cost tracking works correctly
  - Verify total_tokens matches sum of individual tokens
- [ ] 1.5.2.4 Test: Timeout is enforced
  - Set short timeout
  - Verify timeout error returned

### 1.5.3 Error Recovery Tests

- [ ] 1.5.3.1 Test: API failure during generation
  - Mock API error for one candidate
  - Verify remaining candidates still generated
- [ ] 1.5.3.2 Test: All candidates fail gracefully
  - Mock complete API failure
  - Verify error returned, not crash
- [ ] 1.5.3.3 Test: Invalid configuration
  - Test with invalid num_candidates
  - Test with invalid aggregator
  - Verify appropriate errors

---

## Phase 1 Success Criteria

1. **Candidate representation**: Struct with all required metadata fields
2. **GenerationResult**: Holds multiple candidates with aggregation metadata
3. **LLMGenerator**: Parallel generation of N candidates with varied parameters
4. **MajorityVote**: Self-consistency through majority voting
5. **BestOfN**: Score-based candidate selection
6. **SelfConsistency runner**: End-to-end orchestration of generation and aggregation
7. **Cost tracking**: Accurate token counting across all candidates
8. **Test coverage**: Minimum 90% for Phase 1 modules

---

## Phase 1 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/candidate.ex`
- `lib/jido_ai/accuracy/generation_result.ex`
- `lib/jido_ai/accuracy/generator.ex`
- `lib/jido_ai/accuracy/generators/llm_generator.ex`
- `lib/jido_ai/accuracy/aggregator.ex`
- `lib/jido_ai/accuracy/aggregators/majority_vote.ex`
- `lib/jido_ai/accuracy/aggregators/best_of_n.ex`
- `lib/jido_ai/accuracy/aggregators/weighted.ex`
- `lib/jido_ai/accuracy/self_consistency.ex`

**Test Files:**
- `test/jido_ai/accuracy/candidate_test.exs`
- `test/jido_ai/accuracy/generation_result_test.exs`
- `test/jido_ai/accuracy/generators/llm_generator_test.exs`
- `test/jido_ai/accuracy/aggregators/majority_vote_test.exs`
- `test/jido_ai/accuracy/aggregators/best_of_n_test.exs`
- `test/jido_ai/accuracy/aggregators/weighted_test.exs`
- `test/jido_ai/accuracy/self_consistency_test.exs`
