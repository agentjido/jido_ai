# Phase 4A.5: GEPA Optimizer Module

## Summary

Implement the Optimizer module for GEPA (Genetic-Pareto Prompt Evolution). The Optimizer is the main orchestration component that ties together all GEPA modules (PromptVariant, Task, Evaluator, Reflector, Selection) into a cohesive optimization loop.

## Planning Document

See: `notes/planning/architecture/phase-04A-gepa-strategy.md` (Section 4A.5)

## Problem Statement

We have all the building blocks for GEPA:
- PromptVariant: Represents prompt templates with metrics
- Task: Defines evaluation tasks
- Evaluator: Runs variants against tasks
- Reflector: Generates mutations from failures
- Selection: Chooses survivors using Pareto selection

Now we need the main optimization loop that:
1. Initializes a population from a seed template
2. Iterates through generations
3. Evaluates, selects, and mutates variants
4. Returns the best variants after optimization

## Technical Design

### Module Structure

```elixir
defmodule Jido.AI.GEPA.Optimizer do
  # Main entry point
  def optimize(seed_template, tasks, opts)

  # Generation execution
  def run_generation(variants, tasks, generation, opts)

  # Result extraction
  def best_variants(variants, opts)
end
```

### Optimization Flow

```
1. Create seed PromptVariant from template
2. Initialize population (seed + initial mutations)
3. For each generation:
   a. Evaluate all unevaluated variants
   b. Select survivors (Pareto selection)
   c. Generate mutations from survivors
   d. Emit telemetry events
4. Return best variants (Pareto front of final generation)
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `:generations` | 10 | Number of evolution cycles |
| `:population_size` | 8 | Target population per generation |
| `:mutation_count` | 3 | Mutations per survivor |
| `:runner` | required | Function for LLM calls |
| `:objectives` | accuracy↑, cost↓ | Selection objectives |
| `:crossover_rate` | 0.2 | Probability of crossover vs mutation |

### Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:jido, :ai, :gepa, :generation]` | best_accuracy, avg_accuracy, token_cost | generation, population_size |
| `[:jido, :ai, :gepa, :evaluation]` | accuracy, token_cost, latency_ms | variant_id, generation |
| `[:jido, :ai, :gepa, :mutation]` | mutation_count | parent_id, generation |
| `[:jido, :ai, :gepa, :complete]` | total_generations, total_evaluations | best_accuracy, best_variant_id |

## Implementation Plan

### Step 1: Create Optimizer Module Skeleton
- [x] Create `lib/jido_ai/gepa/optimizer.ex`
- [x] Define module structure and typespecs
- [x] Add @moduledoc with usage examples

### Step 2: Implement optimize/3
- [x] Validate options
- [x] Create seed variant
- [x] Initialize population
- [x] Run generation loop
- [x] Return best variants

### Step 3: Implement run_generation/4
- [x] Evaluate unevaluated variants
- [x] Select survivors
- [x] Generate mutations
- [x] Optional crossover
- [x] Return new population

### Step 4: Add Telemetry
- [x] Emit generation events
- [x] Emit evaluation events
- [x] Emit mutation events
- [x] Emit completion event

### Step 5: Add Unit Tests
- [x] Test optimization loop (6 tests)
- [x] Test generation progression (3 tests)
- [x] Test configuration options
- [x] Test telemetry emission (3 tests)
- [x] Test edge cases (6 tests)

## Current Status

**COMPLETED** - 2026-01-05

## Dependencies

- `Jido.AI.GEPA.PromptVariant`
- `Jido.AI.GEPA.Task`
- `Jido.AI.GEPA.Evaluator`
- `Jido.AI.GEPA.Reflector`
- `Jido.AI.GEPA.Selection`
