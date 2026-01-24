# Phase 4A.3: GEPA Reflector Module - Summary

**Branch**: `feature/phase4a-gepa-reflector`
**Date**: 2026-01-05
**Status**: COMPLETED

## Overview

Implemented the Reflector module for GEPA (Genetic-Pareto Prompt Evolution). The Reflector analyzes evaluation failures and proposes prompt mutations using LLM-based reflection. This is the "intelligence" behind GEPA's genetic evolution - it uses the LLM itself to examine failures and suggest improvements.

## Implementation Details

### Core Functions

| Function | Purpose |
|----------|---------|
| `reflect_on_failures/3` | Analyze why tasks failed, return natural language insights |
| `propose_mutations/3` | Generate new prompt templates based on reflection |
| `mutate_prompt/3` | Combined reflect + propose, returns PromptVariant children |
| `crossover/3` | Combine elements from two parent prompts |

### reflect_on_failures/3

- Takes: `variant`, `failing_results`, `opts` (runner required)
- Returns: `{:ok, reflection_text}` or `{:error, reason}`
- Samples up to 5 failures to prevent context overflow
- Builds detailed prompt with template, inputs, expected, actual outputs
- Requests 2-4 paragraphs of actionable analysis

### propose_mutations/3

- Takes: `variant`, `reflection`, `opts` (runner, mutation_count)
- Returns: `{:ok, [template_strings]}` or `{:error, reason}`
- Default: generates 3 mutations
- Parses LLM response using `---MUTATION N---` markers
- Fallback: paragraph-based parsing for unformatted responses

### mutate_prompt/3

- Takes: `variant`, `eval_result`, `opts`
- Returns: `{:ok, [PromptVariant]}` or `{:error, reason}`
- Filters eval_result.results to get failures
- Calls reflect_on_failures then propose_mutations
- Creates PromptVariant children with proper lineage

### crossover/3

- Takes: `variant1`, `variant2`, `opts` (runner, children_count)
- Returns: `{:ok, [PromptVariant]}` or `{:error, reason}`
- Combines strengths from two parent prompts
- Children have both parents in lineage
- Generation = max(parent_generations) + 1
- Metadata includes `mutation_type: :crossover`

## Prompt Design

### Reflection Prompt
```
You are analyzing a prompt that failed on some tasks...

## Current Prompt Template
[template]

## Failed Tasks (N of M failures)
[sampled failures with input, expected, output]

## Analysis Request
Analyze these failures and identify:
1. Common patterns in why the prompt failed
2. What the prompt is missing or doing wrong
3. Specific weaknesses in the prompt's instructions
```

### Mutation Prompt
```
Generate exactly N improved prompt templates...

Format your response as:
---MUTATION 1---
[improved template]

---MUTATION 2---
[improved template]
```

## Test Coverage

**28 tests passing** covering:

**reflect_on_failures (8 tests):**
- Basic reflection analysis
- No failures handling
- Multiple failures
- Failure sampling limit
- Error results
- Validation and error handling

**propose_mutations (4 tests):**
- Mutation generation
- mutation_count option
- Poorly formatted LLM responses
- Error handling

**mutate_prompt (5 tests):**
- Full mutation flow
- Child lineage
- Unique IDs
- Unevaluated children
- All tasks passing

**crossover (5 tests):**
- Parent combination
- Dual-parent lineage
- Generation calculation
- Metadata tagging
- children_count option

**Edge cases (6 tests):**
- Map templates
- Long outputs (truncation)
- Custom validators
- Unicode handling

## Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `lib/jido_ai/gepa/reflector.ex` | ~350 | Reflector module |
| `test/jido_ai/gepa/reflector_test.exs` | ~340 | Unit tests |

## Design Decisions

1. **Pluggable Runner**: Like Evaluator, accepts a runner function for LLM calls. This allows using a more capable model for reflection than the one being evaluated.

2. **Failure Sampling**: Limits to 5 failures to prevent context overflow. Failures are truncated at 500 chars for output, 300 chars for input.

3. **Structured Parsing**: Uses `---MUTATION N---` markers for reliable extraction. Falls back to paragraph parsing if markers aren't found.

4. **Crossover Metadata**: Children from crossover are tagged with `mutation_type: :crossover` for tracking.

## GEPA Test Summary

| Module | Tests |
|--------|-------|
| PromptVariant | 36 |
| Task | 30 |
| Evaluator | 22 |
| Reflector | 28 |
| **Total** | **116** |

## Next Steps

Continue with Phase 4A:
- **4A.4**: Selection module (Pareto-optimal selection)
- **4A.5**: Optimizer module (main optimization loop)
