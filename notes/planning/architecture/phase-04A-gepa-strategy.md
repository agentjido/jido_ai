# Phase 4A: GEPA (Genetic-Pareto Prompt Evolution) Strategy

## Overview

GEPA is an automated prompt optimizer that uses LLM-based reflection in a genetic search to iteratively improve prompts. Unlike CoT/ToT/GoT which are reasoning strategies, GEPA is a **meta-optimization framework** that evolves prompts for any strategy.

Key insight: GEPA outperformed RL-based prompt tuning (Group PPO) by ~10% on average while using 30-35× fewer trials.

## Design Principle

GEPA uses the model itself to:
1. **Evaluate** prompts on a task set
2. **Reflect** on failures in natural language
3. **Mutate** prompts based on reflection insights
4. **Select** using Pareto-optimal criteria (accuracy vs cost)

## Architecture

```
lib/jido_ai/
├── gepa/
│   ├── prompt_variant.ex      # Prompt variant struct with metrics
│   ├── evaluator.ex           # Runs tasks and collects metrics
│   ├── reflector.ex           # Analyzes failures, proposes mutations
│   ├── selection.ex           # Pareto selection logic
│   └── optimizer.ex           # Main optimization loop
└── strategies/
    └── gepa.ex                # Strategy adapter (if needed)

test/jido_ai/
└── gepa/
    ├── prompt_variant_test.exs
    ├── evaluator_test.exs
    ├── reflector_test.exs
    ├── selection_test.exs
    └── optimizer_test.exs
```

---

## 4A.1 PromptVariant Module

**Status**: COMPLETED (2026-01-05) - 36 tests passing

Represents a prompt template with its evaluation metrics.

### 4A.1.1 Struct Definition

- [x] Create `lib/jido_ai/gepa/prompt_variant.ex`
- [x] Define struct fields:
  - `id` - Unique identifier
  - `template` - Prompt template string or structured map
  - `generation` - Which generation this variant belongs to
  - `parents` - List of parent variant IDs (for lineage tracking)
  - `accuracy` - Evaluation accuracy score (0.0-1.0)
  - `token_cost` - Total tokens used during evaluation
  - `latency_ms` - Average latency per task (optional)
  - `metadata` - Additional notes/tags
- [x] Implement `new/1` and `new!/1` constructors
- [x] Implement `update_metrics/2` to update after evaluation
- [x] Implement `evaluated?/1` to check evaluation status
- [x] Implement `create_child/2` for creating mutated children
- [x] Implement `compare/3` for metric comparison

### 4A.1.2 Unit Tests

- [x] Test struct creation
- [x] Test metric updates
- [x] Test validation
- [x] Test child creation
- [x] Test comparison logic

---

## 4A.2 Evaluator Module

**Status**: COMPLETED (2026-01-05) - 52 tests passing (30 Task + 22 Evaluator)

Runs a prompt variant against a task set and collects metrics.

### 4A.2.1 Core Functions

- [x] Create `lib/jido_ai/gepa/evaluator.ex`
- [x] `evaluate_variant/3` - Evaluate variant on task set
  - Takes: variant, tasks, options (runner, parallel, timeout, runner_opts)
  - Returns: `%{accuracy: float, token_cost: int, latency_ms: int, results: [...]}`
- [x] `run_single_task/3` - Run one task with a variant
  - Pluggable runner function for LLM execution
  - Template rendering with `{{input}}` substitution
  - Captures: success?, output, tokens, latency_ms, error
- [x] Support configurable success criteria per task (expected string or validator function)

### 4A.2.2 Task Format

- [x] Create `lib/jido_ai/gepa/task.ex`
- [x] Define task struct:
  - `id` - Unique identifier (auto-generated with `task_` prefix)
  - `input` - The task input/prompt
  - `expected` - Expected output string (optional)
  - `validator` - Custom validation function (optional)
  - `metadata` - Task category, difficulty, etc.
- [x] `success?/2` - Check if output passes criteria (flexible matching)
- [x] `from_input/1`, `from_pairs/1` convenience functions

### 4A.2.3 Unit Tests

- [x] Test single task evaluation
- [x] Test batch evaluation (sequential and parallel)
- [x] Test metric aggregation
- [x] Test template rendering
- [x] Test error handling (timeouts, exceptions)
- [x] Test Task struct creation and validation

---

## 4A.3 Reflector Module

**Status**: COMPLETED (2026-01-05) - 28 tests passing

Analyzes failures and proposes prompt mutations using the LLM itself.

### 4A.3.1 Core Functions

- [x] Create `lib/jido_ai/gepa/reflector.ex`
- [x] `reflect_on_failures/3` - Analyze why tasks failed
  - Takes: variant, failing_results, opts (runner)
  - Returns: `{:ok, analysis_text}` explaining failure patterns
  - Samples up to 5 failures to prevent context overflow
- [x] `propose_mutations/3` - Generate new prompt variants
  - Takes: variant, reflection_analysis, opts (runner, mutation_count)
  - Returns: `{:ok, [template_strings]}`
  - Parses LLM response with `---MUTATION N---` markers
- [x] `mutate_prompt/3` - Combined reflect + propose
  - Takes: variant, eval_results, opts
  - Returns: `{:ok, [PromptVariant]}` with lineage
- [x] `crossover/3` - Combine elements from two parent prompts
  - Takes: variant1, variant2, opts (runner, children_count)
  - Returns: `{:ok, [PromptVariant]}` with both parents in lineage

### 4A.3.2 Reflection Prompt Design

- [x] Build reflection prompt that includes:
  - Current prompt template (string or map format)
  - Sample of failing cases (limited to 5)
  - Task inputs, expected outputs, actual outputs
  - Request for actionable analysis (2-4 paragraphs)
- [x] Parse LLM response to extract mutations
  - Primary: `---MUTATION N---` marker parsing
  - Fallback: Paragraph-based parsing for unformatted responses

### 4A.3.3 Mutation Strategies

- [x] **Textual mutations**: Clarification prompts request clearer instructions
- [x] **Structural mutations**: Restructuring prompts reorganize format
- [x] **Crossover**: `crossover/3` combines strengths from two parents

### 4A.3.4 Unit Tests

- [x] Test reflection prompt construction
- [x] Test mutation parsing (formatted and fallback)
- [x] Test edge cases (no failures, all failures, errors)
- [x] Test crossover with lineage tracking
- [x] Test unicode and long content handling

---

## 4A.4 Selection Module

Implements Pareto-optimal selection for multi-objective optimization.

### 4A.4.1 Core Functions

- [ ] Create `lib/jido_ai/gepa/selection.ex`
- [ ] `pareto_front/2` - Find non-dominated solutions
  - Takes: variants, objectives (e.g., [:accuracy, :token_cost])
  - Returns: List of Pareto-optimal variants
- [ ] `dominates?/3` - Check if one variant dominates another
  - Handles maximization (accuracy) vs minimization (cost)
- [ ] `select_survivors/3` - Select variants for next generation
  - Uses Pareto front + optional diversity bonus

### 4A.4.2 Objectives Configuration

- [ ] Support configurable objectives:
  - `{:accuracy, :maximize}`
  - `{:token_cost, :minimize}`
  - `{:latency_ms, :minimize}`
- [ ] Allow weighted combination for final selection

### 4A.4.3 Unit Tests

- [ ] Test Pareto front calculation
- [ ] Test domination logic
- [ ] Test with various objective combinations

---

## 4A.5 Optimizer Module

Main optimization loop orchestrating the GEPA process.

### 4A.5.1 Core Functions

- [ ] Create `lib/jido_ai/gepa/optimizer.ex`
- [ ] `optimize/3` - Main entry point
  - Takes: seed_template, tasks, options
  - Options: generations, population_size, strategy, model
  - Returns: Best variant(s) after optimization
- [ ] `run_generation/4` - Execute one generation
  - Evaluate all variants
  - Compute Pareto front
  - Generate mutations from survivors

### 4A.5.2 Configuration Options

- [ ] `generations` - Number of evolution cycles (default: 10)
- [ ] `population_size` - Variants per generation (default: 8)
- [ ] `mutation_count` - New variants per survivor (default: 3)
- [ ] `strategy` - Which reasoning strategy to use (default: :react)
- [ ] `model` - Which model to use for evaluation and reflection

### 4A.5.3 Telemetry

- [ ] Emit telemetry events:
  - `[:jido, :ai, :gepa, :generation]` - Per-generation stats
  - `[:jido, :ai, :gepa, :evaluation]` - Per-variant evaluation
  - `[:jido, :ai, :gepa, :mutation]` - Mutation events
  - `[:jido, :ai, :gepa, :complete]` - Optimization complete

### 4A.5.4 Unit Tests

- [ ] Test optimization loop
- [ ] Test generation progression
- [ ] Test convergence behavior

---

## 4A.6 Integration

### 4A.6.1 Strategy Integration (Optional)

- [ ] Create `lib/jido_ai/strategies/gepa.ex` if needed
- [ ] Or expose as standalone optimizer module

### 4A.6.2 Persistence

- [ ] Define how to persist best prompts
- [ ] Support loading evolved prompts into strategies
- [ ] Version tracking for prompt evolution

---

## 4A.7 Unit Tests Summary

- [ ] `test/jido_ai/gepa/prompt_variant_test.exs`
- [ ] `test/jido_ai/gepa/evaluator_test.exs`
- [ ] `test/jido_ai/gepa/reflector_test.exs`
- [ ] `test/jido_ai/gepa/selection_test.exs`
- [ ] `test/jido_ai/gepa/optimizer_test.exs`

---

## Success Criteria

1. **PromptVariant**: Clean struct with metrics tracking
2. **Evaluator**: Can evaluate prompts against task sets
3. **Reflector**: LLM-based failure analysis and mutation
4. **Selection**: Correct Pareto-optimal selection
5. **Optimizer**: Full loop running for N generations
6. **Test Coverage**: Minimum 80% for all GEPA modules

---

## Dependencies

- Phase 1: ReqLLM integration for LLM calls
- Phase 4: Existing strategies (ReAct, CoT, etc.) as evaluation targets

## References

- [GEPA Paper](https://arxiv.org/abs/2507.19457)
- [Dria GEPA Docs](https://docs.dria.co/docs/gepa/overview)
- Local research: `notes/research/running-gepa-locally.md`
