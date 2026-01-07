# Jido.AI GEPA Guide

This guide covers GEPA (Genetic-Pareto Prompt Evolution), the prompt optimization system.

## Table of Contents

1. [Overview](#overview)
2. [Components](#components)
3. [Optimization Process](#optimization-process)
4. [Usage](#usage)
5. [Algorithms](#algorithms)

---

## Overview

GEPA (Genetic-Pareto Prompt Evolution) automatically optimizes prompts through evolutionary algorithms. It uses genetic operations (mutation, crossover) and Pareto-optimal selection to improve prompts across multiple objectives.

### Key Features

- **Multi-objective optimization**: Maximize accuracy, minimize cost
- **Genetic operations**: Mutation, crossover for prompt variation
- **Pareto selection**: Non-dominated sorting with crowding distance
- **Telemetry**: Full observability of optimization runs

### Objectives

| Objective | Goal | Metric |
|-----------|------|--------|
| **Accuracy** | Maximize correct outputs | Success rate on tasks |
| **Cost** | Minimize token usage | Input + output tokens |

---

## Components

### PromptVariant

**Module**: `Jido.AI.GEPA.PromptVariant`

Represents a single prompt template with version tracking and metrics.

```elixir
%PromptVariant{
  id: "variant_123",
  prompt: "You are a helpful assistant. {{task}}",
  version: 2,
  metrics: %{
    accuracy: 0.85,
    avg_tokens: 150,
    evaluations: 10
  },
  metadata: %{
    parent_id: "variant_000",
    generation: 2,
    mutation_type: :substitution
  }
}
```

**Fields**:

| Field | Type | Description |
|-------|------|-------------|
| `:id` | `String.t()` | Unique identifier |
| `:prompt` | `String.t()` | Template with `{{task}}` placeholder |
| `:version` | `pos_integer()` | Version number |
| `:metrics` | `map()` | Performance metrics |
| `:metadata` | `map()` | Provenance tracking |

**Key Functions**:

```elixir
# Create new variant
variant = PromptVariant.new("You are {{type}} assistant. {{task}}")

# Update metrics
updated = PromptVariant.update_metrics(variant, %{accuracy: 0.9})

# Compare for Pareto dominance
Pareto.dominates?(variant_a, variant_b)  # true if A dominates B
```

---

### Task

**Module**: `Jido.AI.GEPA.Task`

Represents an evaluation task with input and expected output.

```elixir
%Task{
  id: "task_123",
  input: "What is 2 + 2?",
  expected_output: "4",
  category: :math,
  difficulty: :easy
}
```

**Usage**:

```elixir
# Create task
task = Task.new("Calculate 2 + 2", "4", category: :math)

# Batch creation
tasks = Task.batch_from([
  {"Question 1", "Answer 1"},
  {"Question 2", "Answer 2"}
])

# Load from file
tasks = Task.from_file("test_cases.jsonl")
```

---

### Evaluator

**Module**: `Jido.AI.GEPA.Evaluator`

Evaluates prompt variants against tasks.

```elixir
# Evaluate single variant
{:ok, metrics} = Evaluator.evaluate(variant, tasks, model: model)

# Evaluate multiple variants
{:ok, results} = Evaluator.evaluate_batch([v1, v2, v3], tasks, model: model)

# Results format
[%{
  variant_id: "v1",
  accuracy: 0.8,
  avg_tokens: 150,
  total_cost: 0.002
}, ...]
```

**Metrics**:

| Metric | Description |
|--------|-------------|
| `:accuracy` | Success rate (0-1) |
| `:avg_tokens` | Average tokens per response |
| `:total_tokens` | Total tokens used |
| `:success_count` | Number of successful evaluations |
| `:evaluation_count` | Total evaluations |

---

### Reflector

**Module**: `Jido.AI.GEPA.Reflector`

Generates new prompt variants through mutation and crossover.

```elixir
# Mutate a variant
{:ok, mutated} = Reflector.mutate(variant,
  mutation_type: :substitution,
  rate: 0.3
)

# Crossover two variants
{:ok, child} = Reflector.crossover(parent1, parent2)

# Generate multiple mutations
mutations = Reflector.generate_mutations(variant, count: 5)

# Failure-based mutation
{:ok, improved} = Reflector.mutate_from_failure(variant,
  failed_task,
  error_reason
)
```

**Mutation Types**:

| Type | Description |
|------|-------------|
| `:substitution` | Replace prompt segment |
| `:insertion` | Add new instruction |
| `:deletion` | Remove segment |
| `:rephrasing` | Rewrite instruction |
| `:crossover` | Combine two prompts |

---

### Selection

**Module**: `Jido.AI.GEPA.Selection`

Selects best variants using Pareto-optimal sorting.

```elixir
# Get Pareto front
front = Selection.pareto_front(variants)
# => [variant1, variant2]  # Non-dominated variants

# NSGA-II with crowding distance
ranked = Selection.nsga_ii_sort(variants, population_size: 10)

# Select top N
selected = Selection.select_top(variants, count: 5)

# Tournament selection
winner = Selection.tournament(variants, tournament_size: 3)
```

**Pareto Dominance**:

A variant A dominates B if:
- A is better or equal in all objectives
- A is strictly better in at least one objective

```
High Accuracy ┃
    ┃    ┌─────────── B (90%, 1000 tokens)
    ┃    │
    ┃    │     ┌─────── A (85%, 500 tokens)  ← Pareto optimal
    ┃    │     │
    ┃    │     └─────── C (80%, 600 tokens)  ← Pareto optimal
    ┃    │
    ┃    └─────────── D (70%, 400 tokens)  ← Pareto optimal
    ┃
    └─────────────────────────────────────────────
                    Low Cost

Pareto front: {A, C, D}
B is dominated by D (higher accuracy AND lower cost)
```

---

### Optimizer

**Module**: `Jido.AI.GEPA.Optimizer`

Main optimization loop orchestrating evolution.

```elixir
# Run optimization
{:ok, result} = Optimizer.optimize(initial_prompt, tasks,
  model: model,
  generations: 10,
  population_size: 8
)

# Result format
%{
  best_variant: prompt_variant,
  all_variants: [v1, v2, ...],
  history: [%{generation: 0, best: v1}, ...],
  metrics: %{final_accuracy: 0.95, improvement: 0.15}
}
```

**Configuration**:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `:generations` | `pos_integer()` | `10` | Max generations |
| `:population_size` | `pos_integer()` | `8` | Variants per generation |
| `:mutation_rate` | `float()` | `0.3` | Mutation probability |
| `:crossover_rate` | `float()` | `0.7` | Crossover probability |
| `:elitism_count` | `pos_integer()` | `2` | Variants preserved as-is |

---

## Optimization Process

### Full Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    GEPA Optimization Loop                      │
│                                                                  │
│  Initial Prompt                                                   │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────┐     Evaluate     ┌─────────────┐               │
│  │ Evaluator   │ ────────────────▶│   Tasks     │               │
│  │             │                   │             │               │
│  └─────────────┘                   └─────────────┘               │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────┐     Select       ┌─────────────┐               │
│  │  Selection  │ ◀────────────────│  Metrics    │               │
│  │  (Pareto)   │                   │  (Acc+Cst)   │               │
│  └─────────────┘                   └─────────────┘               │
│       │                                                          │
│       ▼                                                          │
│  ┌─────────────┐     Mutate/     ┌─────────────┐               │
│  │ Reflector   │ ────────────────▶│  Next Gen   │               │
│  │             │     Crossover     │             │               │
│  └─────────────┘                   └─────────────┘               │
│       │                                                          │
│       └──────────────────────┬───────────────────────┐          │
│                              │                       │          │
│                              ▼                       ▼          │
│                        Max generations?       Good enough?   │
│                            │ Yes                    │ Yes      │
│                            ▼                        │          │
│                         Return                   Return      │
└─────────────────────────────────────────────────────────────────┘
```

### Step-by-Step

1. **Initialization**: Create initial population from seed prompt
2. **Evaluation**: Test each variant against tasks
3. **Selection**: Select Pareto-optimal variants
4. **Evolution**: Apply mutations and crossover
5. **Repeat**: Continue for specified generations
6. **Return**: Best variant found

---

## Usage

### Basic Optimization

```elixir
# Define tasks
tasks = [
  Task.new("What is 2 + 2?", "4"),
  Task.new("What is 3 + 3?", "6"),
  Task.new("What is 5 * 5?", "25")
]

# Run optimization
{:ok, result} = Jido.AI.GEPA.Optimizer.optimize(
  "You are a math assistant. {{task}}",
  tasks,
  model: "anthropic:claude-haiku-4-5",
  generations: 10,
  population_size: 8
)

# Get best prompt
best = result.best_variant
IO.puts("Best prompt: #{best.prompt}")
IO.puts("Accuracy: #{best.metrics.accuracy}")
```

### Advanced Configuration

```elixir
{:ok, result} = Optimizer.optimize(initial_prompt, tasks,
  model: model,
  generations: 20,
  population_size: 16,
  mutation_rate: 0.3,
  crossover_rate: 0.7,
  elitism_count: 2,
  # Custom selection
  selection_fn: &CustomSelection.custom_select/4,
  # Custom mutation
  mutation_fn: &CustomMutator.mutate/2
)
```

### With Telemetry

```elixir
# Attach handler
:telemetry.attach("gepa_monitor", [:jido, :ai, :gepa, :optimize, :complete], &handle/1, nil)

def handle(event, measurements, metadata) do
  IO.puts("Generation #{metadata.generation}: accuracy=#{metadata.accuracy}")
end
```

---

## Algorithms

### NSGA-II

Non-dominated Sorting Genetic Algorithm II used for Pareto selection:

1. **Fast Non-Dominated Sorting**: Rank by Pareto fronts
2. **Crowding Distance**: Preserve diversity within fronts
3. **Elitism**: Preserve best variants

### Mutation Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| **Substitution** | Replace text segment | "Helpful" → "Assistant" |
| **Insertion** | Add instruction | "Think step by step" |
| **Deletion** | Remove segment | Remove verbose instruction |
| **Rephrasing** | Rewrite instruction | "Calculate" → "Compute" |

### Crossover

```elixir
# Single-point crossover
parent1 = "You are {{adjective}}. {{task}}"
parent2 = "You are {{adjective}} assistant. {{task}}"

# Crossover at instruction boundary
child = "You are {{adjective}} assistant. {{task}}"
```

---

## Best Practices

### 1. Define Quality Tasks

```elixir
# ❌ Bad - too easy
tasks = [Task.new("1 + 1", "2")]

# ✅ Good - diverse difficulty
tasks = [
  Task.new("2 + 2", "4", difficulty: :easy),
  Task.new("25 * 4", "100", difficulty: :medium),
  Task.new("What is 15% of 200?", "30", difficulty: :hard)
]
```

### 2. Use Appropriate Metrics

```elixir
# For code generation: syntax correctness
%{
  syntax_valid: 0.9,
  tests_passing: 0.7
}

# For QA: factual correctness
%{
  factual_accuracy: 0.85,
  completeness: 0.9
}
```

### 3. Set Realistic Limits

```elixir
# Start small
generations: 5
population_size: 4

# Scale up for production
generations: 20
population_size: 16
```

---

## Telemetry Events

| Event | Measurements | Metadata |
|-------|--------------|----------|
| `[:jido, :ai, :gepa, :optimize, :start]` | `system_time` | `initial_prompt`, `task_count` |
| `[:jido, :ai, :gepa, :optimize, :generation]` | `duration` | `generation`, `best_accuracy` |
| `[:jido, :ai, :gepa, :optimize, :complete]` | `total_duration` | `final_accuracy`, `improvement` |
| `[:jido, :ai, :gepa, :evaluate, :complete]` | `duration` | `variant_id`, `metrics` |

---

## Related Guides

- [Architecture Overview](./01_architecture_overview.md) - System architecture
- [Strategies Guide](./02_strategies.md) - Strategy integration
