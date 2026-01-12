# Phase 2: Verifier System

This phase implements outcome and process verifiers that score candidate responses to guide selection. Verifiers are critical for identifying high-quality responses among multiple candidates, forming the foundation for verification-guided search and reflection loops.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Verification Pipeline                     │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Candidates ──→ Outcome Verifier ──→ Scores                 │
│                      │                                       │
│                      ├─ Process Verifier (step-level)       │
│                      │                                       │
│                      └─ Tool Verifier (execution)           │
│                                                               │
│                      ┌──────────────────┐                    │
│                      │ Verification     │                    │
│                      │ Runner           │                    │
│                      │ (orchestrates)   │                    │
│                      └──────────────────┘                    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| Verifier behavior | Interface for verification implementations |
| VerificationResult | Struct holding verification scores and metadata |
| LLMOutcomeVerifier | Uses LLM to score final answers |
| DeterministicVerifier | Uses ground truth or deterministic checks |
| PRM behavior | Interface for process reward models |
| LLMPrm | LLM-based step-level scoring |
| CodeExecutionVerifier | Verifies by executing code in sandbox |
| UnitTestVerifier | Verifies by running unit tests |
| StaticAnalysisVerifier | Verifies using linters/type checkers |
| VerificationRunner | Orchestrates multiple verifiers |

---

## 2.1 Verifier Behaviors and Types

Define the core verifier behavior and result types used across all verification components.

### 2.1.1 Verifier Behavior

Define the contract for verifying candidate responses.

- [ ] 2.1.1.1 Create `lib/jido_ai/accuracy/verifier.ex`
- [ ] 2.1.1.2 Add `@moduledoc` with behavior documentation
- [ ] 2.1.1.3 Define `@callback verify/2`:
  ```elixir
  @callback verify(
    candidate :: Jido.AI.Accuracy.Candidate.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.VerificationResult.t()} | {:error, term()}
  ```
- [ ] 2.1.1.4 Define `@callback verify_batch/2`:
  ```elixir
  @callback verify_batch(
    candidates :: [Jido.AI.Accuracy.Candidate.t()],
    context :: map()
  ) :: {:ok, [Jido.AI.Accuracy.VerificationResult.t()]} | {:error, term()}
  ```
- [ ] 2.1.1.5 Add optional `@callback supports_streaming?/0`
- [ ] 2.1.1.6 Document verification patterns in module docs

### 2.1.2 Verification Result

Define the result type for verification operations.

- [ ] 2.1.2.1 Create `lib/jido_ai/accuracy/verification_result.ex`
- [ ] 2.1.2.2 Define `defstruct` with fields:
  - `:candidate_id` - ID of verified candidate
  - `:score` - Numeric score (higher = better)
  - `:confidence` - Confidence in this score [0-1]
  - `:reasoning` - Explanation for the score
  - `:step_scores` - Map of step-level scores (for PRMs)
  - `:metadata` - Additional verification metadata
- [ ] 2.1.2.3 Add `@moduledoc` with documentation
- [ ] 2.1.2.4 Add `@type t()` definition
- [ ] 2.1.2.5 Implement `new/1` constructor
- [ ] 2.1.2.6 Implement `pass?/1` for threshold checking
- [ ] 2.1.2.7 Implement `merge_step_scores/2` for PRM aggregation
- [ ] 2.1.2.8 Implement `to_map/1` for serialization

### 2.1.3 Unit Tests for Verifier Types

- [ ] Test `VerificationResult.new/1` creates valid result
- [ ] Test `pass?/1` returns correct boolean for threshold
- [ ] Test `merge_step_scores/2` aggregates step scores
- [ ] Test `to_map/1` serializes correctly
- [ ] Test score field is numeric
- [ ] Test confidence is in [0, 1] range

---

## 2.2 Outcome Verifier

Implement verifiers that score final answers.

### 2.2.1 LLM Outcome Verifier

Use an LLM to score candidate responses.

- [ ] 2.2.1.1 Create `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex`
- [ ] 2.2.1.2 Add `@moduledoc` explaining LLM-based verification
- [ ] 2.2.1.3 Define configuration schema:
  - `:model` - Model for verification (may differ from generation)
  - `:prompt_template` - Custom evaluation prompt
  - `:score_range` - Range for output scores
- [ ] 2.2.1.4 Implement `init/1` for configuration
- [ ] 2.2.1.5 Implement `verify/2` with evaluation prompt
- [ ] 2.2.1.6 Add prompt template for scoring
- [ ] 2.2.1.7 Support few-shot examples in prompt
- [ ] 2.2.1.8 Extract numeric score from LLM response
- [ ] 2.2.1.9 Extract reasoning from response
- [ ] 2.2.1.10 Implement `verify_batch/2` for efficiency

### 2.2.2 Deterministic Verifier

Implement deterministic verification for specific domains.

- [ ] 2.2.2.1 Create `lib/jido_ai/accuracy/verifiers/deterministic_verifier.ex`
- [ ] 2.2.2.2 Add `@moduledoc` explaining deterministic verification
- [ ] 2.2.2.3 Define configuration schema:
  - `:ground_truth` - Known correct answer
  - `:comparison_type` - :exact, :numerical, :regex
  - `:tolerance` - Numerical tolerance for comparisons
- [ ] 2.2.2.4 Implement `verify/2` with answer comparison
- [ ] 2.2.2.5 Support exact match scoring
- [ ] 2.2.2.6 Support numerical comparison with tolerance
- [ ] 2.2.2.7 Support regex pattern matching
- [ ] 2.2.2.8 Implement `extract_answer/1` for parsing
- [ ] 2.2.2.9 Return binary score (1.0 or 0.0) for deterministic

### 2.2.3 Unit Tests for Outcome Verifiers

- [ ] Test `LLMOutcomeVerifier.verify/2` returns score
- [ ] Test `LLMOutcomeVerifier.verify/2` handles edge cases
- [ ] Test `LLMOutcomeVerifier.verify_batch/2` efficient batch processing
- [ ] Test `DeterministicVerifier.verify/2` with exact match
- [ ] Test `DeterministicVerifier.verify/2` with numerical tolerance
- [ ] Test `DeterministicVerifier.verify/2` with regex patterns
- [ ] Test `DeterministicVerifier` returns binary scores
- [ ] Test answer extraction works correctly

---

## 2.3 Process Reward Model

Implement step-level verification for reasoning traces.

### 2.3.1 PRM Behavior

Define behavior for process reward models.

- [ ] 2.3.1.1 Create `lib/jido_ai/accuracy/prm.ex`
- [ ] 2.3.1.2 Add `@moduledoc` explaining PRM concept
- [ ] 2.3.1.3 Define `@callback score_step/2`:
  ```elixir
  @callback score_step(
    step :: String.t(),
    context :: map()
  ) :: {:ok, number()} | {:error, term()}
  ```
- [ ] 2.3.1.4 Define `@callback score_trace/2`:
  ```elixir
  @callback score_trace(
    trace :: [String.t()],
    context :: map()
  ) :: {:ok, [number()]} | {:error, term()}
  ```
- [ ] 2.3.1.5 Document PRM usage patterns

### 2.3.2 LLM-Based PRM

Implement a PRM using LLM evaluation of reasoning steps.

- [ ] 2.3.2.1 Create `lib/jido_ai/accuracy/prms/llm_prm.ex`
- [ ] 2.3.2.2 Add `@moduledoc` explaining LLM-based PRM
- [ ] 2.3.2.3 Define configuration schema:
  - `:model` - Model for PRM scoring
  - `:prompt_template` - Step evaluation prompt
- [ ] 2.3.2.4 Implement `score_step/2` with evaluation prompt
- [ ] 2.3.2.5 Implement `score_trace/2` with batch scoring
- [ ] 2.3.2.6 Add step classification (correct/incorrect/neutral)
- [ ] 2.3.2.7 Support context from previous steps
- [ ] 2.3.2.8 Implement parallel step scoring

### 2.3.3 PRM Aggregation

Aggregate step scores into overall candidate scores.

- [ ] 2.3.3.1 Create `lib/jido_ai/accuracy/prm_aggregation.ex`
- [ ] 2.3.3.2 Add `@moduledoc` explaining aggregation strategies
- [ ] 2.3.3.3 Implement `sum_scores/1` for total score
- [ ] 2.3.3.4 Implement `product_scores/1` for probability-style
- [ ] 2.3.3.5 Implement `min_score/1` for bottleneck approach
- [ ] 2.3.3.6 Implement `weighted_average/2` for custom weights
- [ ] 2.3.3.7 Implement `aggregate/2` with strategy selection

### 2.3.4 Unit Tests for PRM

- [ ] Test `LLMPrm.score_step/2` returns numeric score
- [ ] Test `LLMPrm.score_trace/2` returns list of scores
- [ ] Test PRM aggregation strategies
- [ ] Test step classification (correct/incorrect/neutral)
- [ ] Test context propagation between steps
- [ ] Test parallel step scoring
- [ ] Test min_score identifies bottleneck errors

---

## 2.4 Tool-Based Verifier

Implement verification through tool execution (compilation, tests).

### 2.4.1 Code Execution Verifier

Verify code by executing it.

- [ ] 2.4.1.1 Create `lib/jido_ai/accuracy/verifiers/code_execution_verifier.ex`
- [ ] 2.4.1.2 Add `@moduledoc` explaining execution-based verification
- [ ] 2.4.1.3 Define configuration schema:
  - `:timeout` - Execution timeout
  - `:sandbox` - Sandbox configuration
- [ ] 2.4.1.4 Implement `verify/2` with sandboxed execution
- [ ] 2.4.1.5 Support timeout limits
- [ ] 2.4.1.6 Capture stdout/stderr for feedback
- [ ] 2.4.1.7 Return score based on execution success
- [ ] 2.4.1.8 Parse error messages for feedback

### 2.4.2 Unit Test Verifier

Verify code by running unit tests.

- [ ] 2.4.2.1 Create `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex`
- [ ] 2.4.2.2 Add `@moduledoc` explaining test-based verification
- [ ] 2.4.2.3 Define configuration schema:
  - `:test_command` - Command to run tests
  - `:test_pattern` - Pattern for test selection
- [ ] 2.4.2.4 Implement `verify/2` with test execution
- [ ] 2.4.2.5 Parse test results for pass/fail
- [ ] 2.4.2.6 Return score based on test pass rate
- [ ] 2.4.2.7 Include specific failure information

### 2.4.3 Static Analysis Verifier

Verify code using static analysis tools.

- [ ] 2.4.3.1 Create `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex`
- [ ] 2.4.3.2 Add `@moduledoc` explaining static analysis verification
- [ ] 2.4.3.3 Define configuration schema:
  - `:tools` - List of analysis tools
  - `:severity_weights` - Weights for issue severity
- [ ] 2.4.3.4 Implement `verify/2` with analysis tools
- [ ] 2.4.3.5 Parse tool output for issues
- [ ] 2.4.3.6 Score based on issue severity
- [ ] 2.4.3.7 Support multiple analysis tools
- [ ] 2.4.3.8 Aggregate scores across tools

### 2.4.4 Unit Tests for Tool Verifiers

- [ ] Test `CodeExecutionVerifier.verify/2` executes safely
- [ ] Test `CodeExecutionVerifier.verify/2` times out correctly
- [ ] Test `UnitTestVerifier.verify/2` parses results
- [ ] Test `UnitTestVerifier.verify/2` calculates pass rate
- [ ] Test `StaticAnalysisVerifier.verify/2` scores issues
- [ ] Test error handling for tool failures
- [ ] Test sandbox prevents malicious execution

---

## 2.5 Verification Runner

Orchestrate verification across multiple verifiers.

### 2.5.1 Verification Runner Module

Create the runner that coordinates multiple verifiers.

- [ ] 2.5.1.1 Create `lib/jido_ai/accuracy/verification_runner.ex`
- [ ] 2.5.1.2 Add `@moduledoc` explaining orchestration
- [ ] 2.5.1.3 Define configuration schema:
  - `:verifiers` - List of verifiers to run
  - `:weights` - Weights for combining scores
  - `:parallel` - Whether to run in parallel
- [ ] 2.5.1.4 Implement `run/3` with candidates and verifiers
- [ ] 2.5.1.5 Implement `run_parallel/3` for concurrent verification
- [ ] 2.5.1.6 Add verifier priority/fallback logic
- [ ] 2.5.1.7 Aggregate scores from multiple verifiers
- [ ] 2.5.1.8 Implement weighted score combination

### 2.5.2 Runner Operations

Implement core runner operations.

- [ ] 2.5.2.1 Implement `verify_candidate/3` for single candidate
- [ ] 2.5.2.2 Implement `verify_all_candidates/3` for batch
- [ ] 2.5.2.3 Implement `aggregate_scores/2` for combination
- [ ] 2.5.2.4 Implement `handle_verifier_error/3` for error handling
- [ ] 2.5.2.5 Add telemetry emission

### 2.5.3 Unit Tests for VerificationRunner

- [ ] Test `run/3` applies all verifiers
- [ ] Test `run_parallel/3` executes concurrently
- [ ] Test score aggregation from multiple sources
- [ ] Test fallback when verifier fails
- [ ] Test empty verifier list handling
- [ ] Test weighted score combination
- [ ] Test telemetry events emitted

---

## 2.6 Phase 2 Integration Tests

Comprehensive integration tests for the verification system.

### 2.6.1 End-to-End Verification Tests

- [ ] 2.6.1.1 Create `test/jido_ai/accuracy/verification_test.exs`
- [ ] 2.6.1.2 Test: LLM outcome verifier scores candidates
  - Generate 5 candidates
  - Verify with LLM outcome verifier
  - Check scores are in valid range
  - Verify best candidate has highest score
- [ ] 2.6.1.3 Test: PRM evaluates reasoning steps
  - Create candidate with reasoning trace
  - Score each step with PRM
  - Verify aggregate score matches expectation
- [ ] 2.6.1.4 Test: Code execution verifier
  - Generate code candidates
  - Execute in sandbox
  - Verify correct code passes
  - Verify incorrect code fails
- [ ] 2.6.1.5 Test: Combined verifiers
  - Run outcome + PRM + tool verifiers
  - Verify scores are combined
  - Check weightings are applied

### 2.6.2 Accuracy Validation Tests

- [ ] 2.6.2.1 Test: Verifier improves accuracy on math
  - Baseline: no verifier accuracy
  - With verifier: improved accuracy
- [ ] 2.6.2.2 Test: PRM catches reasoning errors
  - Create candidate with error mid-trace
  - Verify PRM scores step as incorrect
  - Check aggregate score is low
- [ ] 2.6.2.3 Test: Deterministic verifier exact match
  - Test with known ground truth
  - Verify exact match returns 1.0
  - Verify mismatch returns 0.0

### 2.6.3 Performance Tests

- [ ] 2.6.3.1 Test: Verification latency is acceptable
  - Measure single candidate verification time
  - Verify < 2 seconds per candidate
- [ ] 2.6.3.2 Test: Parallel verification scales
  - Compare sequential vs parallel
  - Verify near-linear speedup
- [ ] 2.6.3.3 Test: Batch verification efficiency
  - Compare single vs batch API calls
  - Verify batch is more efficient

### 2.6.4 Error Handling Tests

- [ ] 2.6.4.1 Test: Verifier failure is handled gracefully
  - Mock verifier failure
  - Verify remaining verifiers run
  - Check error is propagated correctly
- [ ] 2.6.4.2 Test: Invalid candidate handled
  - Pass candidate with missing fields
  - Verify appropriate error returned

---

## Phase 2 Success Criteria

1. **Verifier behavior**: Clean interface for verification implementations
2. **Outcome verifier**: Scores candidates using LLM evaluation
3. **Deterministic verifier**: Ground truth comparison for known answers
4. **PRM**: Step-level scoring for reasoning traces
5. **Tool verifiers**: Code execution, test, and static analysis verification
6. **Verification runner**: Orchestrates multiple verifiers with aggregation
7. **Accuracy improvement**: Verified candidates outperform baseline
8. **Test coverage**: Minimum 85% for Phase 2 modules

---

## Phase 2 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/verifier.ex`
- `lib/jido_ai/accuracy/verification_result.ex`
- `lib/jido_ai/accuracy/verifiers/llm_outcome_verifier.ex`
- `lib/jido_ai/accuracy/verifiers/deterministic_verifier.ex`
- `lib/jido_ai/accuracy/verifiers/code_execution_verifier.ex`
- `lib/jido_ai/accuracy/verifiers/unit_test_verifier.ex`
- `lib/jido_ai/accuracy/verifiers/static_analysis_verifier.ex`
- `lib/jido_ai/accuracy/prm.ex`
- `lib/jido_ai/accuracy/prms/llm_prm.ex`
- `lib/jido_ai/accuracy/prm_aggregation.ex`
- `lib/jido_ai/accuracy/verification_runner.ex`

**Test Files:**
- `test/jido_ai/accuracy/verifier_test.exs`
- `test/jido_ai/accuracy/verification_result_test.exs`
- `test/jido_ai/accuracy/verifiers/llm_outcome_verifier_test.exs`
- `test/jido_ai/accuracy/verifiers/deterministic_verifier_test.exs`
- `test/jido_ai/accuracy/verifiers/code_execution_verifier_test.exs`
- `test/jido_ai/accuracy/verifiers/unit_test_verifier_test.exs`
- `test/jido_ai/accuracy/verifiers/static_analysis_verifier_test.exs`
- `test/jido_ai/accuracy/prm_test.exs`
- `test/jido_ai/accuracy/prms/llm_prm_test.exs`
- `test/jido_ai/accuracy/prm_aggregation_test.exs`
- `test/jido_ai/accuracy/verification_runner_test.exs`
- `test/jido_ai/accuracy/verification_test.exs`
