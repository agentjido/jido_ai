# Phase 4A.3: GEPA Reflector Module

## Summary

Implement the Reflector module for GEPA (Genetic-Pareto Prompt Evolution). The Reflector analyzes evaluation failures and proposes prompt mutations using LLM-based reflection. This is the core "intelligence" of GEPA that enables prompts to evolve based on failure analysis.

## Planning Document

See: `notes/planning/architecture/phase-04A-gepa-strategy.md` (Section 4A.3)

## Problem Statement

After evaluating a prompt variant against tasks, we need a way to:
1. Analyze why certain tasks failed
2. Generate insights about failure patterns
3. Propose concrete mutations to improve the prompt

The Reflector uses the LLM itself to perform this meta-cognitive task - examining its own failures and suggesting improvements.

## Technical Design

### Module Structure

```elixir
defmodule Jido.AI.GEPA.Reflector do
  # Core functions
  def reflect_on_failures(variant, failing_results, opts)
  def propose_mutations(variant, reflection, opts)
  def mutate_prompt(variant, eval_results, opts)

  # Crossover for combining prompts
  def crossover(variant1, variant2, opts)
end
```

### Function Signatures

1. **`reflect_on_failures/3`**
   - Input: `variant`, `failing_results` (list of failed task results), `opts` (runner for LLM)
   - Output: `{:ok, reflection_text}` or `{:error, reason}`
   - Purpose: Analyze failures and produce natural language insights

2. **`propose_mutations/3`**
   - Input: `variant`, `reflection_text`, `opts` (runner for LLM)
   - Output: `{:ok, [template_strings]}` or `{:error, reason}`
   - Purpose: Generate 2-3 concrete prompt mutations based on reflection

3. **`mutate_prompt/3`**
   - Input: `variant`, `eval_results`, `opts`
   - Output: `{:ok, [PromptVariant]}` or `{:error, reason}`
   - Purpose: Combined reflect + propose, returns new PromptVariant structs with lineage

4. **`crossover/3`**
   - Input: `variant1`, `variant2`, `opts`
   - Output: `{:ok, [PromptVariant]}` or `{:error, reason}`
   - Purpose: Combine elements from two parent prompts

### Reflection Prompt Design

The reflection prompt should include:
- Current prompt template
- Sample of failing cases (limited to ~5 for context window)
- Task inputs and expected outputs
- Actual outputs from the LLM
- Request for analysis of failure patterns

### Mutation Prompt Design

The mutation prompt should:
- Include the reflection analysis
- Request 2-3 specific mutations
- Ask for different mutation strategies (reword, restructure, add examples)
- Return mutations in a parseable format

### Runner Integration

Like the Evaluator, the Reflector accepts a `:runner` function for LLM calls:
```elixir
runner.(prompt, "", opts) -> {:ok, %{output: "...", tokens: N}}
```

This allows flexibility in which model/strategy is used for reflection.

## Implementation Plan

### Step 1: Create Reflector Module Skeleton
- [x] Create `lib/jido_ai/gepa/reflector.ex`
- [x] Define module structure and typespecs
- [x] Add @moduledoc with usage examples

### Step 2: Implement reflect_on_failures/3
- [x] Build reflection prompt with failure context
- [x] Call runner to get LLM analysis
- [x] Return reflection text

### Step 3: Implement propose_mutations/3
- [x] Build mutation prompt with reflection
- [x] Call runner to get mutation suggestions
- [x] Parse response to extract template strings

### Step 4: Implement mutate_prompt/3
- [x] Filter eval_results to get failures
- [x] Call reflect_on_failures
- [x] Call propose_mutations
- [x] Create PromptVariant children with lineage

### Step 5: Implement crossover/3
- [x] Design crossover prompt
- [x] Combine elements from two parents
- [x] Return hybrid variants

### Step 6: Add Unit Tests
- [x] Test reflection prompt construction
- [x] Test mutation parsing
- [x] Test full mutation flow with mock runner
- [x] Test edge cases (no failures, all failures)
- [x] Test crossover

## Current Status

**COMPLETED** - 2026-01-05

## Files Created

- `lib/jido_ai/gepa/reflector.ex` (~350 lines)
- `test/jido_ai/gepa/reflector_test.exs` (~340 lines)

## Test Results

28 tests passing covering:
- Reflection analysis (8 tests)
- Mutation proposal (4 tests)
- Full mutation flow (5 tests)
- Crossover (5 tests)
- Edge cases (6 tests)

## Dependencies

- `Jido.AI.GEPA.PromptVariant` - For creating child variants
- `Jido.AI.GEPA.Task` - For accessing task data
- Runner function for LLM calls
