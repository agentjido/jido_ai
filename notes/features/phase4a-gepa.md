# Phase 4A: GEPA Implementation

## Summary

Implement GEPA (Genetic-Pareto Prompt Evolution) - an automated prompt optimizer that uses LLM-based reflection and genetic search to evolve better prompts.

## Planning Document

See: `notes/planning/architecture/phase-04A-gepa-strategy.md`

## Work Progress

### 4A.1 PromptVariant Module ✅ COMPLETE
- [x] Create struct with metrics (id, template, generation, parents, accuracy, token_cost, latency_ms, metadata)
- [x] Add constructors (`new/1`, `new!/1`) with validation
- [x] Add `update_metrics/2` for post-evaluation updates
- [x] Add `evaluated?/1` to check if variant has been evaluated
- [x] Add `create_child/2` for creating mutated children with lineage
- [x] Add `compare/3` for metric comparison
- [x] Add unit tests (36 tests passing)

**Files created:**
- `lib/jido_ai/gepa/prompt_variant.ex`
- `test/jido_ai/gepa/prompt_variant_test.exs`

### 4A.2 Evaluator Module
- [ ] Create evaluator for running tasks
- [ ] Define task format
- [ ] Add unit tests

### 4A.3 Reflector Module
- [ ] Create failure analysis
- [ ] Create mutation proposals
- [ ] Add unit tests

### 4A.4 Selection Module
- [ ] Implement Pareto selection
- [ ] Add unit tests

### 4A.5 Optimizer Module
- [ ] Create main optimization loop
- [ ] Add telemetry
- [ ] Add unit tests

## Current Status

**IN PROGRESS** - 2026-01-05

## Notes

Based on research in `notes/research/running-gepa-locally.md`
