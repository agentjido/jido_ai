# Difficulty Estimation Guide

Difficulty estimation predicts how challenging a query is, enabling resource-appropriate processing.

## Overview

Difficulty estimation allows systems to:
- Allocate more compute to hard problems
- Use faster methods for easy problems
- Balance accuracy and cost

```mermaid
flowchart TD
    Query[Query] --> Estimate[Estimate Difficulty]

    Estimate --> Easy{Easy?}
    Estimate --> Medium{Medium?}
    Estimate --> Hard{Hard?}

    Easy --> Direct[Direct Generation<br/>Low cost]
    Medium --> Standard[Self-Consistency<br/>Medium cost]
    Hard -> Advanced[Full Pipeline<br/>High cost]

    style Direct fill:#e1ffe1
    style Standard fill:#fff3e1
    style Advanced fill:#ffe1e1
```

## When to Use Difficulty Estimation

| Scenario | Benefit |
|----------|---------|
| Variable difficulty queries | Optimize compute allocation |
| Cost-sensitive applications | Reduce average cost |
| SLA requirements | Ensure adequate resources |
| Fixed compute environments | Avoid over/under-provisioning |

## Heuristic Difficulty Estimator

Fast estimation using query characteristics.

```elixir
alias Jido.AI.Acciculty.Estimators.HeuristicEstimator

estimator = HeuristicEstimator.new()

{:ok, estimate} = HeuristicEstimator.estimate(estimator, """
  What is the square root of 144 multiplied by the sum of the first 10 prime numbers?
""")

# estimate.difficulty: :hard
# estimate.score: 0.8  # 0=easy, 1=hard
# estimate.reasoning: "Multiple operations, large numbers, primes knowledge"
```

### Heuristic Factors

| Factor | Indicates | Weight |
|--------|-----------|--------|
| Query length | Complex queries are longer | Medium |
| Number of clauses | Multi-part problems | High |
| Special vocabulary | Domain knowledge needed | Medium |
| Mathematical operations | Computation needed | High |
| Nested structures | Complex reasoning | High |

## LLM-Based Difficulty Estimator

Uses LLM to estimate difficulty.

```elixir
alias Jido.AI.Accuracy.Estimators.LLMDifficultyEstimator

estimator = LLMDifficultyEstimator.new!(%{
  model: :fast,
  classification: [:easy, :medium, :hard]
})

{:ok, estimate} = LLMDifficultyEstimator.estimate(estimator, """
  Solve: x^2 + 5x + 6 = 0
""")

# estimate.level: :medium
# estimate.confidence: 0.9
# estimate.reasoning: "Requires quadratic formula application"
```

### Difficulty Levels

```elixir
:easy    # Direct lookup, simple arithmetic
:medium   # Multi-step, domain knowledge
:hard     # Complex reasoning, creative synthesis
:expert   # Requires specialist knowledge
```

## Ensemble Difficulty Estimator

Combines multiple estimators for robust prediction.

```elixir
alias Jido.AI.Accuracy.Estimators.EnsembleEstimator

estimator = EnsembleEstimator.new!(%{
  estimators: [
    {HeuristicEstimator, []},
    {LLMDifficultyEstimator, [model: :fast]}
  ],
  aggregation: :weighted_average,
  weights: [0.3, 0.7]  # Trust LLM more
})

{:ok, estimate} = EnsembleEstimator.estimate(estimator, query)
```

## Using Difficulty for Resource Allocation

```elixir
alias Jido.AI.Accuracy.{DifficultyEstimator, SelfConsistency, AdaptiveSelfConsistency}

# Allocate resources based on difficulty
def allocate_compute(query) do
  {:ok, estimate} = DifficultyEstimator.estimate(
    HeuristicEstimator.new(),
    query
  )

  case estimate.difficulty do
    :easy ->
      # Direct generation
      ReqLLM.Generation.generate_text(:fast, messages)

    :medium ->
      # Standard self-consistency
      SelfConsistency.run(query, num_candidates: 5)

    :hard ->
      # Full adaptive pipeline
      AdaptiveSelfConsistency.run(query,
        min_candidates: 7,
        max_candidates: 20
      )
  end
end
```

## Compute Budgeting

Set compute budgets based on difficulty:

```elixir
alias Jido.AI.Accuracy.ComputeBudgeter

budgeter = ComputeBudgeter.new(%{
  tiers: %{
    easy: %{max_tokens: 512, temperature: 0.3},
    medium: %{max_tokens: 1024, temperature: 0.7},
    hard: %{max_tokens: 2048, temperature: 0.9}
  }
})

{:ok, budget} = ComputeBudgeter.assign(budgeter, query, estimator)
# budget.difficulty: :hard
# budget.max_tokens: 2048
# budget.temperature: 0.9
# budget.estimated_cost: calculated cost
```

## Adaptive Self-Consistency with Difficulty

Combine difficulty estimation with adaptive SC:

```elixir
# Configure adaptive SC based on difficulty
{:ok, difficulty} = DifficultyEstimator.estimate(estimator, query)

opts = case difficulty.level do
  :easy ->
    %{min_candidates: 3, max_candidates: 5, early_stop_threshold: 0.7}

  :medium ->
    %{min_candidates: 5, max_candidates: 10, early_stop_threshold: 0.8}

  :hard ->
    %{min_candidates: 7, max_candidates: 20, early_stop_threshold: 0.9}
end

{:ok, result} = AdaptiveSelfConsistency.run(query, opts)
```

## Best Practices

1. **Use heuristic for fast pre-screening** - Then LLM for uncertain cases
2. **Calibrate estimates** - Track prediction vs actual difficulty
3. **Update based on feedback** - Learn from actual processing results
4. **Consider domain knowledge** - Some domains are inherently harder
5. **Set conservative thresholds** - Better to over-allocate than under

## Next Steps

- [Adaptive Self-Consistency](./04_adaptive_self_consistency.md) - Difficulty-aware processing
- [Pipeline Guide](./12_pipeline.md) - Difficulty-based pipeline stages
