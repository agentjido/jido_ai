# GEPA - Automatic Prompt Optimization

GEPA (Genetic-Pareto Prompt Evolution) automatically improves your prompts through evolutionary algorithms. Think of it as "training" your prompts to work better.

## What Problem Does GEPA Solve?

Writing effective prompts is hard. You might iterate many times:
- "Make it more specific"
- "Add examples"
- "Change the tone"

GEPA automates this process:
1. **Creates variations** of your prompt
2. **Tests them** on your tasks
3. **Keeps the best** performers
4. **Repeats** until satisfied

---

## Key Concepts

### Two Objectives

GEPA optimizes for two competing goals:

| Objective | Goal | Example |
|-----------|------|---------|
| **Accuracy** | Maximize correct answers | 95% success rate |
| **Cost** | Minimize tokens used | Fewer tokens = cheaper |

### Pareto Optimality

A prompt is "Pareto optimal" if you can't improve one objective without hurting the other:

```
High Accuracy
    │
    │     Prompt A (90%, 1000 tokens)  ❌ Dominated
    │
    │     Prompt B (85%, 500 tokens)   ✅ Pareto optimal
    │
    │     Prompt C (80%, 400 tokens)   ✅ Pareto optimal
    │
    └───────────────────────────────────────
                Low Cost
```

Prompt A is dominated because B has both higher accuracy AND lower cost.

---

## Basic Usage

### Step 1: Define Your Tasks

Create test cases with inputs and expected outputs:

```elixir
tasks = [
  Jido.AI.GEPA.Task.new(
    "What is 2 + 2?",
    "4",
    category: :math,
    difficulty: :easy
  ),
  Jido.AI.GEPA.Task.new(
    "What is 15% of 200?",
    "30",
    category: :math,
    difficulty: :medium
  ),
  Jido.AI.GEPA.Task.new(
    "If 3x + 7 = 22, what is x?",
    "5",
    category: :math,
    difficulty: :hard
  )
]
```

### Step 2: Create Initial Prompt

```elixir
initial_prompt = """
You are a math assistant. Solve the following problem:
{{task}}
"""
```

The `{{task}}` placeholder is replaced with each test case.

### Step 3: Run Optimization

```elixir
alias Jido.AI.GEPA.Optimizer

{:ok, result} = Optimizer.optimize(
  initial_prompt,
  tasks,
  model: "anthropic:claude-haiku-4-5",
  generations: 10,      # How many iterations
  population_size: 8    # How many variants per generation
)

# Get the best prompt
best_prompt = result.best_variant.prompt
IO.puts("Best prompt: #{best_prompt}")
IO.puts("Accuracy: #{result.best_variant.metrics.accuracy}")
```

### Step 4: Use the Optimized Prompt

```elixir
defmodule MyOptimizedAgent do
  use Jido.Agent,
    name: "optimized_agent",
    strategy: {
      Jido.AI.Strategies.ReAct,
      model: "anthropic:claude-haiku-4-5",
      system_prompt: best_prompt  # Use GEPA-optimized prompt
    }
end
```

---

## Configuration Options

```elixir
Optimizer.optimize(initial_prompt, tasks,
  # Required
  model: "anthropic:claude-haiku-4-5",

  # Evolution settings
  generations: 10,         # Default: 10 (how many iterations)
  population_size: 8,      # Default: 8 (variants per generation)
  mutation_rate: 0.3,      # Default: 0.3 (chance of mutation)
  crossover_rate: 0.7,     # Default: 0.7 (chance of crossover)
  elitism_count: 2,        # Default: 2 (best variants preserved)

  # Stopping criteria
  target_accuracy: 0.95,   # Stop when 95% accuracy reached
  max_cost: 1000,          # Stop when cost under threshold

  # Optional customization
  mutation_fn: &MyMutator.mutate/2,
  selection_fn: &MySelector.select/4
)
```

---

## How It Works

### The Evolution Process

```
Generation 0:
  Prompt A: "You are helpful. {{task}}"              → 70% accuracy, 500 tokens
  Prompt B: "Solve this: {{task}}"                  → 65% accuracy, 400 tokens
  Prompt C: "Calculate: {{task}}"                   → 75% accuracy, 450 tokens

Selection (keep best: A, C)
Mutation (create variations):
  Prompt A1: "You are a math expert. {{task}}"      → 80% accuracy, 520 tokens
  Prompt A2: "Please solve: {{task}}"               → 72% accuracy, 480 tokens
  Prompt C1: "Calculate carefully: {{task}}"        → 85% accuracy, 460 tokens

Generation 1:
  (best from before + new mutations)
  Evaluate → Select → Mutate → Repeat...

Final result: Best prompt found
```

### Mutation Operations

| Operation | Description | Example |
|-----------|-------------|---------|
| Substitution | Replace a word | "helpful" → "expert" |
| Insertion | Add instruction | "Think step by step" |
| Deletion | Remove segment | Remove "Please" |
| Rephrasing | Rewrite phrase | "Calculate" → "Compute" |
| Crossover | Combine prompts | Best parts of A + B |

---

## Creating Quality Tasks

Good tasks are crucial for effective optimization.

### Do's and Don'ts

```elixir
# ❌ Bad - Too easy, no variation
tasks = [
  Task.new("1 + 1", "2")
]

# ✅ Good - Diverse difficulty
tasks = [
  Task.new("2 + 2", "4", difficulty: :easy),
  Task.new("25 * 4", "100", difficulty: :medium),
  Task.new("What is 15% of 200?", "30", difficulty: :hard),
  Task.new("If x + 5 = 12, what is x?", "7", difficulty: :medium)
]

# ❌ Bad - All same type
tasks = [
  Task.new("2 + 2", "4"),
  Task.new("3 + 3", "6"),
  Task.new("4 + 4", "8")
]

# ✅ Good - Mixed types
tasks = [
  Task.new("Add: 2 + 2", "4", category: :arithmetic),
  Task.new("Capital of France?", "Paris", category: :geography),
  Task.new("Define 'photosynthesis'", "...", category: :science)
]
```

### Loading Tasks from Files

```elixir
# From JSONL file (one JSON object per line)
# tasks.jsonl:
# {"input": "What is 2 + 2?", "output": "4", "category": "math"}
# {"input": "Capital of France?", "output": "Paris", "category": "geo"}

tasks = Jido.AI.GEPA.Task.from_file("tasks.jsonl")
```

---

## Practical Example

### Optimizing a Code Review Prompt

```elixir
# Initial prompt
initial = """
Review this code for bugs and style issues:
{{task}}
"""

# Test cases
code_tasks = [
  Task.new(
    ~s(def add(a, b), a + b end),
    "No issues found. Function is correct.",
    category: :code_review
  ),
  Task.new(
    ~s(divide(a, b), do: a / b end),
    "Issue: No division by zero protection.",
    category: :code_review
  ),
  Task.new(
    ~s(if true do: 1 else: 2 end),
    "Style: Use cond for multiple conditions.",
    category: :code_review
  )
]

# Run optimization
{:ok, result} = Optimizer.optimize(
  initial,
  code_tasks,
  model: "anthropic:claude-sonnet-4-20250514",
  generations: 15,
  population_size: 10
)

# Result might be:
# optimized_prompt = """
# You are a code reviewer. Check for:
# 1. Runtime errors (null, divide by zero, etc.)
# 2. Style issues (unnecessary complexity)
# 3. Security vulnerabilities
#
# Code to review:
# {{task}}
#
# Provide concise feedback.
# """
```

---

## Monitoring Progress

### With Telemetry

```elixir
# Attach a handler to watch optimization
:telemetry.attach(
  "gepa_monitor",
  [:jido, :ai, :gepa, :optimize, :generation],
  &handle_generation/4,
  nil
)

defp handle_generation(event, measurements, metadata, _config) do
  IO.puts("""
  Generation #{metadata.generation}:
    Best accuracy: #{metadata.best_accuracy}
    Avg tokens: #{metadata.avg_tokens}
  """)
end
```

### Check Results

```elixir
{:ok, result} = Optimizer.optimize(...)

# Full history
result.history
# => [
#   %{generation: 0, best_accuracy: 0.70, best_prompt: "..."},
#   %{generation: 1, best_accuracy: 0.75, best_prompt: "..."},
#   ...
# ]

# All variants tried
result.all_variants
# => [variant1, variant2, ...]

# Metrics
result.metrics
# => %{
#   final_accuracy: 0.92,
#   improvement: 0.22,
#   generations: 10,
#   total_evaluations: 80
# }
```

---

## Best Practices

### 1. Start Small

```elixir
# Development: Fast feedback
generations: 5
population_size: 4

# Production: Thorough search
generations: 20
population_size: 16
```

### 2. Use Representative Tasks

```elixir
# Tasks should match your real use cases
tasks = real_user_queries ++ edge_cases
```

### 3. Balance Objectives

```elixir
# Want accuracy over cost?
target_accuracy: 0.95

# Want low cost over accuracy?
max_cost: 500

# Want both balanced?
# Let Pareto selection find the trade-offs
```

### 4. Iterate

```elixir
# First pass: Find good baseline
{:ok, result1} = Optimizer.optimize(initial, tasks,
  generations: 5
)

# Second pass: Refine the best
{:ok, result2} = Optimizer.optimize(
  result1.best_variant.prompt,
  tasks,
  generations: 10
)
```

---

## Advanced: Custom Mutation

```elixir
defmodule MyMutator do
  def mutate(variant, options) do
    rate = options[:rate] || 0.3

    # Custom mutation logic
    new_prompt =
      variant.prompt
      |> add_examples()
      |> simplify_language()

    {:ok, %PromptVariant{variant | prompt: new_prompt}}
  end

  defp add_examples(prompt) do
    # Add relevant examples to prompt
    prompt <> "\n\nExample: ..."
  end

  defp simplify_language(prompt) do
    # Simplify wordy instructions
    String.replace(prompt, "please", "")
  end
end

# Use custom mutator
Optimizer.optimize(initial, tasks,
  mutation_fn: &MyMutator.mutate/2
)
```

---

## Tips for Success

| Situation | Recommendation |
|-----------|---------------|
| First time optimizing | Start with `generations: 5, population_size: 4` |
| High accuracy needed | Increase `generations`, use capable model |
| Budget constrained | Set `max_cost`, use cheaper model for optimization |
| Slow optimization | Use `anthropic:claude-haiku-4-5` for search, validate with `sonnet` |
| Poor results | Check task quality, ensure they're representative |

---

## Next Steps

- [Strategies Guide](./03_strategies.md) - Use optimized prompts in strategies
- [Getting Started](./01_getting_started.md) - New to Jido.AI?
- [Examples](./06_examples.md) - See GEPA in action
