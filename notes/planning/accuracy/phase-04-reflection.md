# Phase 4: Reflection and Self-Critique Loops

This phase implements iterative refinement through self-critique and reflection. Reflection loops enable models to improve their own responses by identifying flaws and revising, forming a key component of the accuracy improvement stack.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                   Reflection Loop                            │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐              │
│  │ Generate │───→│ Critique │───→│  Revise  │              │
│  └──────────┘    └──────────┘    └──────────┘              │
│                                           │                  │
│                                    ┌──────▼──────┐          │
│                                    │ Converged?  │──(no)────┤
│                                    └──────┬──────┘          │
│                                      (yes)                  │
│                                         │                    │
│                                    ┌────▼──────┐           │
│                                    │   Output   │           │
│                                    └───────────┘           │
│                                                               │
│  ┌────────────────────────────────────────────────────┐    │
│  │  Reflexion Memory (cross-episode learning)         │    │
│  └────────────────────────────────────────────────────┘    │
│                                                               │
└─────────────────────────────────────────────────────────────┘
```

## Components in This Phase

| Component | Purpose |
|-----------|---------|
| Critique behavior | Interface for critique generation |
| CritiqueResult | Struct holding critique feedback |
| LLMCritiquer | Uses LLM to identify issues |
| ToolCritiquer | Uses tool execution for critique |
| Revision behavior | Interface for revision implementations |
| LLMReviser | Uses LLM to revise based on critique |
| ReflectionLoop | Orchestrates generate-critique-revise cycle |
| ReflexionMemory | Stores and retrieves critique patterns |
| SelfRefine | Single-pass refinement strategy |

---

## 4.1 Critique Component

Generate critiques of candidate responses to identify areas for improvement.

### 4.1.1 Critique Behavior

Define the behavior for critique generation.

- [ ] 4.1.1.1 Create `lib/jido_ai/accuracy/critique.ex`
- [ ] 4.1.1.2 Add `@moduledoc` explaining critique concept
- [ ] 4.1.1.3 Define `@callback critique/2`:
  ```elixir
  @callback critique(
    candidate :: Jido.AI.Accuracy.Candidate.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.CritiqueResult.t()} | {:error, term()}
  ```
- [ ] 4.1.1.4 Document critique patterns

### 4.1.2 Critique Result

Define the result type for critique operations.

- [ ] 4.1.2.1 Create `lib/jido_ai/accuracy/critique_result.ex`
- [ ] 4.1.2.2 Define `defstruct` with fields:
  - `:issues` - List of identified issues
  - `:suggestions` - List of improvement suggestions
  - `:severity` - Overall severity score
  - `:feedback` - Natural language feedback
  - `:actionable` - Whether issues are actionable
  - `:metadata` - Additional metadata
- [ ] 4.1.2.3 Add `@moduledoc` with documentation
- [ ] 4.1.2.4 Implement `new/1` constructor
- [ ] 4.1.2.5 Implement `has_issues?/1`
- [ ] 4.1.2.6 Implement `should_refine?/1`
- [ ] 4.1.2.7 Implement `add_issue/2`
- [ ] 4.1.2.8 Implement `severity_level/1` returns :low, :medium, :high

### 4.1.3 LLM Critiquer

Use an LLM to critique candidates.

- [ ] 4.1.3.1 Create `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex`
- [ ] 4.1.3.2 Add `@moduledoc` explaining LLM-based critique
- [ ] 4.1.3.3 Define configuration schema:
  - `:model` - Model for critique (may differ from generation)
  - `:prompt_template` - Custom critique prompt
  - `:domain` - Optional domain for specialized critique
- [ ] 4.1.3.4 Implement `critique/2` with critique prompt
- [ ] 4.1.3.5 Add few-shot examples for critique format
- [ ] 4.1.3.6 Parse structured critique from response
- [ ] 4.1.3.7 Support domain-specific critique guidelines
- [ ] 4.1.3.8 Implement severity scoring

### 4.1.4 Tool-Based Critiquer

Use tools to verify and critique.

- [ ] 4.1.4.1 Create `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex`
- [ ] 4.1.4.2 Add `@moduledoc` explaining tool-based critique
- [ ] 4.1.4.3 Define configuration schema:
  - `:tools` - List of tools to run
  - `:severity_map` - Mapping from tool results to severity
- [ ] 4.1.4.4 Implement `critique/2` with tool calls
- [ ] 4.1.4.5 Run tests/linters for feedback
- [ ] 4.1.4.6 Convert tool output to critique format
- [ ] 4.1.4.7 Aggregate results from multiple tools

### 4.1.5 Unit Tests for Critique

- [ ] Test `CritiqueResult.new/1` creates valid result
- [ ] Test `LLMCritiquer.critique/2` identifies issues
- [ ] Test `ToolCritiquer.critique/2` runs tools
- [ ] Test `has_issues?/1` returns correct boolean
- [ ] Test `should_refine?/1` based on severity
- [ ] Test `severity_level/1` returns correct level
- [ ] Test critique parsing from LLM response
- [ ] Test tool output conversion to critique

---

## 4.2 Revision Component

Revise candidates based on critique feedback.

### 4.2.1 Revision Behavior

Define the behavior for revision implementations.

- [ ] 4.2.1.1 Create `lib/jido_ai/accuracy/revision.ex`
- [ ] 4.2.1.2 Add `@moduledoc` explaining revision concept
- [ ] 4.2.1.3 Define `@callback revise/3`:
  ```elixir
  @callback revise(
    candidate :: Jido.AI.Accuracy.Candidate.t(),
    critique :: Jido.AI.Accuracy.CritiqueResult.t(),
    context :: map()
  ) :: {:ok, Jido.AI.Accuracy.Candidate.t()} | {:error, term()}
  ```

### 4.2.2 LLM Reviser

Use an LLM to revise based on critique.

- [ ] 4.2.2.1 Create `lib/jido_ai/accuracy/revisers/llm_reviser.ex`
- [ ] 4.2.2.2 Add `@moduledoc` explaining LLM-based revision
- [ ] 4.2.2.3 Define configuration schema:
  - `:model` - Model for revision
  - `:prompt_template` - Custom revision prompt
  - `:preserve_correct` - Whether to preserve correct parts
- [ ] 4.2.2.4 Implement `revise/3` with revision prompt
- [ ] 4.2.2.5 Include critique in revision prompt
- [ ] 4.2.2.6 Preserve correct parts of original
- [ ] 4.2.2.7 Track what was changed
- [ ] 4.2.2.8 Implement `diff/2` to show changes

### 4.2.3 Targeted Revision

Implement targeted revision for specific issue types.

- [ ] 4.2.3.1 Create `lib/jido_ai/accuracy/revisers/targeted_reviser.ex`
- [ ] 4.2.3.2 Add `@moduledoc` explaining targeted revision
- [ ] 4.2.3.3 Implement `revise_code/3` for code-specific revision
- [ ] 4.2.3.4 Implement `revise_reasoning/3` for reasoning revision
- [ ] 4.2.3.5 Implement `revise_format/3` for format fixes

### 4.2.4 Unit Tests for Revision

- [ ] Test `LLMReviser.revise/3` improves candidate
- [ ] Test revision addresses critique issues
- [ ] Test revision doesn't introduce new errors
- [ ] Test `diff/2` shows correct changes
- [ ] Test targeted revision for code
- [ ] Test targeted revision for reasoning
- [ ] Test targeted revision for format

---

## 4.3 Reflection Loop

Orchestrate the generate-critique-revise loop.

### 4.3.1 Reflection Loop Module

Create the reflection loop orchestrator.

- [ ] 4.3.1.1 Create `lib/jido_ai/accuracy/reflection_loop.ex`
- [ ] 4.3.1.2 Add `@moduledoc` explaining reflection loop pattern
- [ ] 4.3.1.3 Define configuration schema:
  - `:max_iterations` - Maximum refinement iterations
  - `:critiquer` - Critiquer module to use
  - `:reviser` - Reviser module to use
  - `:convergence_threshold` - Score improvement threshold
- [ ] 4.3.1.4 Implement `run/3` with prompt and config
- [ ] 4.3.1.5 Implement `run_iteration/3` for single cycle
- [ ] 4.3.1.6 Check convergence criteria
- [ ] 4.3.1.7 Track iteration history
- [ ] 4.3.1.8 Support max iterations limit
- [ ] 4.3.1.9 Return best candidate across iterations

### 4.3.2 Convergence Detection

Implement convergence checking logic.

- [ ] 4.3.2.1 Implement `check_convergence/3`
- [ ] 4.3.2.2 Detect: No new issues found
- [ ] 4.3.2.3 Detect: Score plateau
- [ ] 4.3.2.4 Detect: Max iterations reached
- [ ] 4.3.2.5 Implement `has_converged?/2`

### 4.3.3 Reflexion Memory

Store and retrieve critique history for cross-episode learning.

- [ ] 4.3.3.1 Create `lib/jido_ai/accuracy/reflexion_memory.ex`
- [ ] 4.3.3.2 Add `@moduledoc` explaining reflexion pattern
- [ ] 4.3.3.3 Define configuration schema:
  - `:storage` - Storage backend (ETS, database)
  - `:max_entries` - Maximum stored critiques
  - `:similarity_threshold` - For retrieval matching
- [ ] 4.3.3.4 Implement `store/2` for critique storage
- [ ] 4.3.3.5 Implement `retrieve_similar/2`
- [ ] 4.3.3.6 Implement `format_for_prompt/1`
- [ ] 4.3.3.7 Implement `clear/1` for memory clearing
- [ ] 4.3.3.8 Implement similarity-based retrieval

### 4.3.4 Unit Tests for ReflectionLoop

- [ ] Test `run/3` executes multiple iterations
- [ ] Test convergence detection
- [ ] Test max iterations limit
- [ ] Test `ReflexionMemory` storage and retrieval
- [ ] Test cross-episode learning
- [ ] Test iteration history tracking
- [ ] Test best candidate selection

---

## 4.4 Self-Refine Strategy

Implement a simpler generate-feedback-refine loop.

### 4.4.1 SelfRefine Module

Create the single-pass refinement strategy.

- [ ] 4.4.1.1 Create `lib/jido_ai/accuracy/strategies/self_refine.ex`
- [ ] 4.4.1.2 Add `@moduledoc` explaining self-refine pattern
- [ ] 4.4.1.3 Define configuration schema:
  - `:model` - Model to use
  - `:feedback_prompt` - Template for feedback generation
- [ ] 4.4.1.4 Implement `run/2` with prompt
- [ ] 4.4.1.5 Generate initial response
- [ ] 4.4.1.6 Generate self-feedback
- [ ] 4.4.1.7 Refine based on feedback
- [ ] 4.4.1.8 Return refined response

### 4.4.2 Self-Refine Operations

Implement self-refine specific operations.

- [ ] 4.4.2.1 Implement `generate_feedback/2`
- [ ] 4.4.2.2 Implement `apply_feedback/3`
- [ ] 4.4.2.3 Implement `compare_original_refined/3`

### 4.4.3 Unit Tests for SelfRefine

- [ ] Test `run/2` improves initial response
- [ ] Test feedback generation
- [ ] Test refinement incorporates feedback
- [ ] Test comparison shows improvement

---

## 4.5 Phase 4 Integration Tests

Comprehensive integration tests for reflection functionality.

### 4.5.1 Reflection Loop Tests

- [ ] 4.5.1.1 Create `test/jido_ai/accuracy/reflection_test.exs`
- [ ] 4.5.1.2 Test: Reflection loop improves response over iterations
  - Start with flawed response
  - Run 3 iterations
  - Verify improvement each iteration
- [ ] 4.5.1.3 Test: Convergence detection works
  - Run until convergence
  - Verify stops when no improvement
- [ ] 4.5.1.4 Test: Reflexion memory improves subsequent runs
  - Run same task twice
  - Verify second run benefits from memory
- [ ] 4.5.1.5 Test: Self-refine improves single-pass
  - Compare initial vs refined
  - Verify refinement addresses issues

### 4.5.2 Domain-Specific Tests

- [ ] 4.5.2.1 Test: Code improvement through reflection
  - Start with buggy code
  - Run reflection loop
  - Verify bugs are fixed
- [ ] 4.5.2.2 Test: Writing improvement through reflection
  - Start with rough draft
  - Run reflection loop
  - Verify quality improves
- [ ] 4.5.2.3 Test: Math reasoning improvement
  - Start with incorrect math solution
  - Run reflection loop
  - Verify errors corrected

### 4.5.3 Performance Tests

- [ ] 4.5.3.1 Test: Reflection loop completes in reasonable time
  - Measure time for typical task
  - Verify < 30 seconds
- [ ] 4.5.3.2 Test: Memory lookup is efficient
  - Store many critiques
  - Measure retrieval time
  - Verify sub-second lookup

---

## Phase 4 Success Criteria

1. **Critique component**: Identifies issues accurately
2. **Revision component**: Addresses critique issues
3. **Reflection loop**: Iteratively improves responses
4. **Reflexion memory**: Stores and retrieves critique patterns
5. **Convergence**: Stops when improvement plateaus
6. **Self-refine**: Single-pass improvement strategy
7. **Test coverage**: Minimum 85% for Phase 4 modules

---

## Phase 4 Critical Files

**New Files:**
- `lib/jido_ai/accuracy/critique.ex`
- `lib/jido_ai/accuracy/critique_result.ex`
- `lib/jido_ai/accuracy/critiquers/llm_critiquer.ex`
- `lib/jido_ai/accuracy/critiquers/tool_critiquer.ex`
- `lib/jido_ai/accuracy/revision.ex`
- `lib/jido_ai/accuracy/revisers/llm_reviser.ex`
- `lib/jido_ai/accuracy/revisers/targeted_reviser.ex`
- `lib/jido_ai/accuracy/reflection_loop.ex`
- `lib/jido_ai/accuracy/reflexion_memory.ex`
- `lib/jido_ai/accuracy/strategies/self_refine.ex`

**Test Files:**
- `test/jido_ai/accuracy/critique_test.exs`
- `test/jido_ai/accuracy/critique_result_test.exs`
- `test/jido_ai/accuracy/critiquers/llm_critiquer_test.exs`
- `test/jido_ai/accuracy/critiquers/tool_critiquer_test.exs`
- `test/jido_ai/accuracy/revision_test.exs`
- `test/jido_ai/accuracy/revisers/llm_reviser_test.exs`
- `test/jido_ai/accuracy/revisers/targeted_reviser_test.exs`
- `test/jido_ai/accuracy/reflection_loop_test.exs`
- `test/jido_ai/accuracy/reflexion_memory_test.exs`
- `test/jido_ai/accuracy/strategies/self_refine_test.exs`
- `test/jido_ai/accuracy/reflection_test.exs`
