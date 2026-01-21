# GEPA Section 2.1: Pareto Frontier Management - Implementation Plan

**Status**: In Progress - Phase 1 Complete ✅
**Phase**: 5 (GEPA Optimization)
**Stage**: 2 (Evolution & Selection)
**Date Started**: 2025-10-27
**Last Updated**: 2025-10-27

## Implementation Status

✅ **Phase 1: Multi-Objective Evaluation (Task 2.1.1) - COMPLETE**
- Extended Candidate struct with multi-objective fields
- Implemented MultiObjectiveEvaluator module (473 lines)
- Created comprehensive test suite (42 tests, 100% passing)
- All 2216 project tests passing

✅ **Phase 2: Dominance Computation (Task 2.1.2) - COMPLETE**
- Implemented DominanceComparator module (507 lines)
- Pareto dominance checking with compare/3 and dominates?/3
- NSGA-II fast non-dominated sorting algorithm
- Crowding distance calculation for diversity preservation
- Epsilon-dominance for noisy objective handling
- Created comprehensive test suite (47 tests, 100% passing)
- All 2263 project tests passing

⏳ **Phase 3: Frontier Maintenance (Task 2.1.3) - PENDING**

⏳ **Phase 4: Hypervolume Calculation (Task 2.1.4) - PENDING**

⏳ **Phase 5: Integration & Testing - PENDING**

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Technical Background](#technical-background)
4. [Architecture](#architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Success Criteria](#success-criteria)
8. [References](#references)

---

## Problem Statement

### Current State

Stage 1 of GEPA (Sections 1.1-1.5) implements basic evolutionary prompt optimization with:
- Single-objective fitness optimization (typically accuracy)
- Simple fitness-based selection with elitism
- Population management maintaining prompt candidates
- 660 passing tests validating core functionality

However, this single-objective approach has significant limitations:

**Problem 1: Single Objective Myopia**
- Optimizes only for one metric (e.g., accuracy)
- Ignores other critical objectives: cost, latency, robustness
- Cannot discover trade-offs between competing objectives
- Forces users to manually balance objectives through weighted sums

**Problem 2: Lack of Solution Diversity**
- Converges to a single "best" prompt
- Loses alternative solutions that may be better for different deployment scenarios
- Cannot provide options for different operational constraints
- Limited exploration of the solution space

**Problem 3: Deployment Inflexibility**
- Single optimized prompt may not suit all deployment contexts
- Cannot choose between high-accuracy/high-cost vs. moderate-accuracy/low-cost
- No visibility into objective trade-offs during optimization
- Expensive reoptimization required for different constraints

### Why Pareto Frontier Management?

Pareto frontier management solves these problems by maintaining a set of **non-dominated solutions** where:

- **Non-dominated**: A solution A dominates B if A is better or equal in all objectives and strictly better in at least one
- **Pareto frontier**: The set of all non-dominated solutions represents optimal trade-offs
- **Multi-objective**: Simultaneously optimizes accuracy, latency, cost, and robustness

**Benefits:**
1. **Deployment Flexibility**: Choose from multiple optimal prompts based on deployment constraints
2. **Trade-off Visibility**: See what you give up when improving one objective
3. **Better Exploration**: Maintains diversity through multiple objectives
4. **Sample Efficiency**: Guide search toward promising regions of objective space

**Example Trade-offs:**
- **High-accuracy prompt**: 95% accuracy, 3s latency, $0.05/query, 80% robustness
- **Low-cost prompt**: 88% accuracy, 1.5s latency, $0.01/query, 75% robustness
- **Fast prompt**: 90% accuracy, 0.8s latency, $0.03/query, 70% robustness
- **Robust prompt**: 92% accuracy, 2.5s latency, $0.04/query, 95% robustness

All four prompts are Pareto-optimal: improving any objective requires sacrificing another.

---

## Solution Overview

### High-Level Approach

Implement Pareto frontier management through four integrated subsystems:

```
┌─────────────────────────────────────────────────────────────┐
│                    GEPA Optimizer                            │
│  ┌────────────────────────────────────────────────────────┐ │
│  │           Multi-Objective Evaluation (2.1.1)           │ │
│  │  Measures: Accuracy | Latency | Cost | Robustness     │ │
│  └─────────────────────┬──────────────────────────────────┘ │
│                        │ Fitness Vectors                     │
│  ┌─────────────────────▼──────────────────────────────────┐ │
│  │      Dominance Relationship Computation (2.1.2)        │ │
│  │  Pareto dominance | Non-dominated sorting | Fronts    │ │
│  └─────────────────────┬──────────────────────────────────┘ │
│                        │ Dominance Rankings                  │
│  ┌─────────────────────▼──────────────────────────────────┐ │
│  │            Frontier Maintenance (2.1.3)                │ │
│  │  Add solutions | Remove dominated | Archive best      │ │
│  └─────────────────────┬──────────────────────────────────┘ │
│                        │ Pareto Set                          │
│  ┌─────────────────────▼──────────────────────────────────┐ │
│  │          Hypervolume Calculation (2.1.4)               │ │
│  │  Measure frontier quality | Track progress | Optimize  │ │
│  └────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

### Key Concepts

**1. Pareto Dominance**

Solution A dominates solution B if:
- A is better or equal to B in ALL objectives
- A is strictly better than B in AT LEAST ONE objective

```elixir
# Example: Does A dominate B?
a = %{accuracy: 0.90, latency: 1.5, cost: 0.02, robustness: 0.85}
b = %{accuracy: 0.88, latency: 1.8, cost: 0.03, robustness: 0.82}

# A >= B in all objectives: YES (0.90>=0.88, 1.5<=1.8, 0.02<=0.03, 0.85>=0.82)
# A > B in at least one: YES (accuracy, latency, cost, robustness ALL better)
# Result: A dominates B
```

**2. Non-Dominated Sorting (NSGA-II Algorithm)**

Classifies population into fronts:
- **Front 1**: Non-dominated by any solution (Pareto optimal)
- **Front 2**: Dominated only by Front 1
- **Front 3**: Dominated only by Fronts 1 and 2
- ...and so on

```
Objective Space Visualization:

Accuracy ↑
  1.0  │     ● (Front 1) - Pareto optimal
       │   ●   ● (Front 1)
  0.9  │ ●       ● (Front 1)
       │   ◆ (Front 2)
  0.8  │     ◆   ◆ (Front 2)
       │       ◆ (Front 2)
  0.7  │   ■ (Front 3)
       └──────────────────────→ Cost
         Low            High
```

**3. Hypervolume Indicator**

Measures the volume of objective space dominated by the Pareto frontier:
- **Higher hypervolume** = Better frontier (more coverage, better solutions)
- **Monotonic**: Adding non-dominated solutions increases hypervolume
- **Reference point dependent**: Needs a baseline for comparison

```
Hypervolume = Area between Pareto frontier and reference point

Accuracy ↑
  1.0  │  A─────B        Shaded area = Hypervolume
       │  │█████│        Better frontiers = Larger area
  0.9  │  │█████│C
       │  │█████││       Reference point: (0.5 acc, 0.1 cost)
  0.8  │  │█████││       Hypervolume guides optimization
       │  └─────┘│       toward better frontiers
  0.7  │         └D
       │          ▼ (reference)
       └──────────────────────→ Cost
```

**4. Crowding Distance**

Measures solution density along the Pareto frontier:
- **Higher distance** = More isolated, preserves diversity
- **Used in selection**: Prefer solutions with higher crowding distance
- **Boundary protection**: Solutions at extremes get infinite distance

---

## Technical Background

### Multi-Objective Optimization Theory

**Pareto Optimality**: A solution is Pareto optimal if no other solution can improve one objective without worsening another.

**NSGA-II Algorithm** (Deb et al., 2002):
1. Fast non-dominated sorting: Classify population into fronts (O(MN²))
2. Crowding distance assignment: Measure solution density (O(MN log N))
3. Selection: Prefer better fronts, then higher crowding distance
4. Genetic operators: Crossover and mutation produce offspring
5. Environmental selection: Keep best N solutions for next generation

**Hypervolume Indicator** (Zitzler & Thiele, 1999):
- Most popular quality indicator for multi-objective optimization
- Measures dominated region of objective space
- Weakly Pareto compliant: Maximizing hypervolume leads to Pareto optimal sets
- Computationally expensive: O(N^(M-1)) for M objectives, N solutions

### Existing GEPA Infrastructure

**Population Management** (`lib/jido_ai/runner/gepa/population.ex`):
- Population struct with candidates map and statistics
- Add/remove/replace candidate operations
- Fitness tracking (currently single float value)
- Already has 660 tests passing

**Optimizer Agent** (`lib/jido_ai/runner/gepa/optimizer.ex`):
- GenServer managing optimization loop
- Evaluation, reflection, mutation, selection phases
- Currently uses simple fitness-based selection

**Evaluation System** (Section 1.2):
- Parallel prompt evaluation
- Trajectory collection
- Metrics aggregation (currently single success rate)

**Mutation Operators** (Section 1.4):
- Targeted mutations based on LLM feedback
- Crossover, diversity enforcement
- Adaptive mutation rates

### Challenges

**1. Multi-Objective Fitness Evaluation**
- Need to measure multiple objectives per candidate
- Objectives have different scales (accuracy: 0-1, latency: 0-10s, cost: $0-0.1)
- Some objectives minimize (cost, latency), others maximize (accuracy, robustness)
- Must normalize objectives for fair comparison

**2. Dominance Computation Efficiency**
- Comparing all pairs is O(N²) for N candidates
- With M objectives, each comparison is O(M)
- Total: O(MN²) per generation
- Need efficient algorithms (NSGA-II fast non-dominated sort)

**3. Frontier Size Management**
- Unlimited frontiers grow without bound
- Need diversity-preserving trimming (crowding distance)
- Archive management for historical best
- Balance between diversity and quality

**4. Hypervolume Calculation Cost**
- Exact calculation is O(N^(M-1)) - exponential in objectives
- For 4 objectives, 100 solutions: ~1M operations
- Need incremental updates or approximation algorithms
- Reference point selection affects results

**5. Integration with Existing Selection**
- Current selection uses single fitness value
- Need to integrate Pareto ranking with existing elitism
- Maintain backward compatibility
- Support mixed single/multi-objective modes

---

## Architecture

### Module Structure

```
lib/jido_ai/runner/gepa/
├── pareto/
│   ├── multi_objective_evaluator.ex    # Task 2.1.1
│   ├── dominance_comparator.ex         # Task 2.1.2
│   ├── frontier_manager.ex             # Task 2.1.3
│   └── hypervolume_calculator.ex       # Task 2.1.4
├── population.ex                        # Extend for multi-objective
└── optimizer.ex                         # Integrate Pareto selection

test/jido_ai/runner/gepa/pareto/
├── multi_objective_evaluator_test.exs
├── dominance_comparator_test.exs
├── frontier_manager_test.exs
└── hypervolume_calculator_test.exs
```

### Data Structures

**Multi-Objective Fitness** (extends existing Candidate):

```elixir
defmodule Jido.AI.Runner.GEPA.Population.Candidate do
  use TypedStruct

  # Existing fields
  field(:id, String.t(), enforce: true)
  field(:prompt, String.t(), enforce: true)
  field(:fitness, float() | nil)  # Keep for backward compatibility
  field(:generation, non_neg_integer(), enforce: true)
  field(:parent_ids, list(String.t()), default: [])
  field(:metadata, map(), default: %{})
  field(:created_at, integer(), enforce: true)
  field(:evaluated_at, integer() | nil)

  # NEW: Multi-objective fields
  field(:objectives, map() | nil, default: nil)
  # Example: %{accuracy: 0.90, latency: 1.5, cost: 0.02, robustness: 0.85}

  field(:normalized_objectives, map() | nil, default: nil)
  # Normalized to [0, 1] for fair comparison

  field(:pareto_rank, integer() | nil, default: nil)
  # Front number: 1 = Pareto optimal, 2 = second front, etc.

  field(:crowding_distance, float() | nil, default: nil)
  # Density measure for diversity preservation

  field(:dominated_by, list(String.t()), default: [])
  # IDs of solutions that dominate this one

  field(:dominates, list(String.t()), default: [])
  # IDs of solutions this one dominates
end
```

**Pareto Frontier**:

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.Frontier do
  use TypedStruct

  field(:solutions, list(Candidate.t()), default: [])
  # Non-dominated solutions on the frontier

  field(:fronts, map(), default: %{})
  # Front number -> list of candidate IDs
  # Example: %{1 => ["cand_1", "cand_2"], 2 => ["cand_3"]}

  field(:hypervolume, float(), default: 0.0)
  # Current hypervolume of the frontier

  field(:reference_point, map(), enforce: true)
  # Reference point for hypervolume calculation
  # Example: %{accuracy: 0.0, latency: 10.0, cost: 0.1, robustness: 0.0}

  field(:objectives, list(atom()), enforce: true)
  # List of objective names: [:accuracy, :latency, :cost, :robustness]

  field(:objective_directions, map(), enforce: true)
  # :maximize or :minimize for each objective
  # Example: %{accuracy: :maximize, latency: :minimize, cost: :minimize, robustness: :maximize}

  field(:archive, list(Candidate.t()), default: [])
  # Historical best solutions (for later warm-start)

  field(:generation, non_neg_integer(), default: 0)
  field(:created_at, integer(), enforce: true)
  field(:updated_at, integer(), enforce: true)
end
```

### Algorithm Details

**Task 2.1.1: Multi-Objective Evaluation**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator do
  @moduledoc """
  Evaluates prompt candidates across multiple objectives.
  """

  @type objectives :: %{
    accuracy: float(),
    latency: float(),
    cost: float(),
    robustness: float()
  }

  @type evaluation_result :: %{
    candidate_id: String.t(),
    objectives: objectives(),
    normalized_objectives: objectives()
  }

  @doc """
  Evaluate a candidate across all objectives.

  ## Objectives

  - **Accuracy**: Success rate on task (0.0 to 1.0, maximize)
  - **Latency**: Average execution time in seconds (minimize)
  - **Cost**: Token cost per execution in dollars (minimize)
  - **Robustness**: Performance variance across diverse inputs (0.0 to 1.0, maximize)
  """
  @spec evaluate(Candidate.t(), keyword()) :: {:ok, objectives()} | {:error, term()}
  def evaluate(candidate, opts \\ [])

  @doc """
  Normalize objectives to [0, 1] range for comparison.

  Uses min-max normalization with population statistics.
  Inverts minimize objectives so higher is always better.
  """
  @spec normalize(objectives(), keyword()) :: objectives()
  def normalize(objectives, opts \\ [])

  @doc """
  Calculate weighted aggregate fitness for backward compatibility.

  Returns single fitness value = weighted sum of normalized objectives.
  Default weights: accuracy=0.5, latency=0.2, cost=0.2, robustness=0.1
  """
  @spec aggregate_fitness(objectives(), keyword()) :: float()
  def aggregate_fitness(objectives, opts \\ [])
end
```

**Task 2.1.2: Dominance Computation**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @moduledoc """
  Computes dominance relationships and non-dominated sorting.

  Implements NSGA-II fast non-dominated sorting algorithm.
  """

  @type dominance_result :: :dominates | :dominated_by | :non_dominated

  @doc """
  Check if solution A dominates solution B.

  A dominates B if:
  1. A >= B in all objectives
  2. A > B in at least one objective
  """
  @spec dominates?(Candidate.t(), Candidate.t()) :: boolean()
  def dominates?(a, b)

  @doc """
  Fast non-dominated sorting (NSGA-II algorithm).

  Classifies population into fronts:
  - Front 1: Non-dominated solutions (Pareto optimal)
  - Front 2: Dominated only by Front 1
  - Front k: Dominated only by Fronts 1..k-1

  Returns: Map of front_number -> list of candidate IDs
  Complexity: O(MN²) where M = objectives, N = population size
  """
  @spec fast_non_dominated_sort(list(Candidate.t())) :: map()
  def fast_non_dominated_sort(candidates)

  @doc """
  Calculate crowding distance for candidates in a front.

  Measures solution density along the Pareto frontier.
  Boundary solutions (extreme values) get infinite distance.

  Returns: Map of candidate_id -> crowding_distance
  Complexity: O(MN log N) where M = objectives, N = front size
  """
  @spec crowding_distance(list(Candidate.t())) :: map()
  def crowding_distance(candidates)

  @doc """
  Epsilon-dominance check for approximate comparisons.

  Useful when objectives are noisy or measurement is imprecise.
  A epsilon-dominates B if A >= B - epsilon in all objectives.
  """
  @spec epsilon_dominates?(Candidate.t(), Candidate.t(), float()) :: boolean()
  def epsilon_dominates?(a, b, epsilon \\ 0.01)
end
```

**Task 2.1.3: Frontier Maintenance**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  @moduledoc """
  Manages the Pareto frontier: adding, removing, and archiving solutions.
  """

  @doc """
  Create a new Pareto frontier.

  ## Options

  - `:objectives` - List of objective names (required)
  - `:objective_directions` - Map of objective -> :maximize/:minimize (required)
  - `:reference_point` - Reference for hypervolume calculation (required)
  - `:max_size` - Maximum frontier size, triggers trimming (default: 100)
  - `:archive_size` - Maximum archive size (default: 500)
  """
  @spec new(keyword()) :: {:ok, Frontier.t()} | {:error, term()}
  def new(opts)

  @doc """
  Add a solution to the frontier.

  - Checks if solution is dominated by existing frontier
  - Removes solutions dominated by new solution
  - Updates hypervolume
  - Triggers trimming if frontier exceeds max size
  """
  @spec add_solution(Frontier.t(), Candidate.t()) :: {:ok, Frontier.t()} | {:error, term()}
  def add_solution(frontier, candidate)

  @doc """
  Remove a solution from the frontier.

  Updates dominance relationships and recalculates hypervolume.
  """
  @spec remove_solution(Frontier.t(), String.t()) :: {:ok, Frontier.t()} | {:error, term()}
  def remove_solution(frontier, candidate_id)

  @doc """
  Trim frontier to max size using diversity-preserving selection.

  Keeps solutions with highest crowding distance to maintain spread.
  Never removes boundary solutions (extreme objective values).
  """
  @spec trim(Frontier.t(), keyword()) :: {:ok, Frontier.t()}
  def trim(frontier, opts \\ [])

  @doc """
  Archive a solution for historical preservation.

  Archives maintain best solutions seen across all generations
  for warm-starting future optimizations.
  """
  @spec archive_solution(Frontier.t(), Candidate.t()) :: {:ok, Frontier.t()}
  def archive_solution(frontier, candidate)

  @doc """
  Get all non-dominated solutions (Front 1).
  """
  @spec get_pareto_optimal(Frontier.t()) :: list(Candidate.t())
  def get_pareto_optimal(frontier)

  @doc """
  Get solutions by Pareto rank (front number).
  """
  @spec get_front(Frontier.t(), integer()) :: list(Candidate.t())
  def get_front(frontier, rank)
end
```

**Task 2.1.4: Hypervolume Calculation**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  @moduledoc """
  Calculates hypervolume indicator for Pareto frontier quality assessment.

  Uses WFG algorithm (While et al., 2006) for efficient computation.
  """

  @doc """
  Calculate hypervolume of a set of solutions.

  Hypervolume = volume of objective space dominated by solutions
  relative to a reference point.

  ## Reference Point

  Reference point should be dominated by all solutions:
  - For maximize objectives: use minimum possible value (e.g., 0.0)
  - For minimize objectives: use maximum possible value (e.g., 10.0)

  ## Algorithm

  Uses WFG algorithm with complexity O(N log N) for 2-3 objectives,
  O(N^(M-2) log N) for M objectives.
  """
  @spec calculate(list(Candidate.t()), map(), keyword()) :: {:ok, float()} | {:error, term()}
  def calculate(solutions, reference_point, opts \\ [])

  @doc """
  Calculate hypervolume contribution of each solution.

  Contribution = hypervolume lost if solution is removed from frontier.
  Solutions with higher contribution are more valuable.
  Used for trimming decisions.
  """
  @spec contribution(list(Candidate.t()), map(), keyword()) :: map()
  def contribution(solutions, reference_point, opts \\ [])

  @doc """
  Select reference point automatically from population statistics.

  Uses nadir point (worst value in each objective) with margin.
  """
  @spec auto_reference_point(list(Candidate.t()), keyword()) :: map()
  def auto_reference_point(candidates, opts \\ [])

  @doc """
  Calculate hypervolume improvement over previous generation.

  Returns: {:ok, improvement_ratio, new_hypervolume}
  """
  @spec improvement(Frontier.t(), Frontier.t()) :: {:ok, float(), float()}
  def improvement(current_frontier, previous_frontier)
end
```

### Integration with Optimizer

**Modified Optimizer Selection Phase**:

```elixir
defmodule Jido.AI.Runner.GEPA.Optimizer do
  # ... existing code ...

  # Phase 4: Selection (MODIFIED for Pareto)
  @doc false
  @spec perform_selection(State.t(), list(map())) :: Population.t()
  defp perform_selection(%State{} = state, offspring) do
    # Combine current population and offspring
    all_candidates = Population.get_all(state.population) ++ offspring

    # Perform multi-objective evaluation
    candidates_with_objectives = Enum.map(all_candidates, fn candidate ->
      {:ok, objectives} = MultiObjectiveEvaluator.evaluate(candidate)
      normalized = MultiObjectiveEvaluator.normalize(objectives)
      %{candidate |
        objectives: objectives,
        normalized_objectives: normalized,
        fitness: MultiObjectiveEvaluator.aggregate_fitness(normalized)
      }
    end)

    # Fast non-dominated sorting
    fronts = DominanceComparator.fast_non_dominated_sort(candidates_with_objectives)

    # Calculate crowding distance for each front
    candidates_with_crowding = Enum.flat_map(fronts, fn {_rank, front_ids} ->
      front_candidates = Enum.filter(candidates_with_objectives, &(&1.id in front_ids))
      distances = DominanceComparator.crowding_distance(front_candidates)
      Enum.map(front_candidates, fn c ->
        %{c | pareto_rank: Map.get(fronts, c.id),
              crowding_distance: Map.get(distances, c.id)}
      end)
    end)

    # Select best N solutions using Pareto ranking + crowding distance
    selected = select_by_pareto_ranking(
      candidates_with_crowding,
      state.config.population_size
    )

    # Create new population
    {:ok, next_population} = Population.new(
      size: state.config.population_size,
      generation: state.generation + 1
    )

    # Add selected candidates
    Enum.reduce(selected, next_population, fn candidate, pop ->
      case Population.add_candidate(pop, Map.from_struct(candidate)) do
        {:ok, updated_pop} -> updated_pop
        {:error, _} -> pop
      end
    end)
  end

  defp select_by_pareto_ranking(candidates, target_size) do
    # Sort by Pareto rank (front number), then crowding distance
    candidates
    |> Enum.sort_by(fn c ->
      {c.pareto_rank || 999, -(c.crowding_distance || 0.0)}
    end)
    |> Enum.take(target_size)
  end
end
```

---

## Implementation Plan

### Phase 1: Multi-Objective Evaluation (Task 2.1.1)

**Estimated Time**: 3-4 days

**Step 1.1: Define Objective Measurement Functions**

Create objective-specific measurement logic:

```elixir
# lib/jido_ai/runner/gepa/pareto/multi_objective_evaluator.ex

defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator do
  alias Jido.AI.Runner.GEPA.Population.Candidate

  @objectives [:accuracy, :latency, :cost, :robustness]

  # Measure accuracy: success rate on evaluation tasks
  defp measure_accuracy(trajectory_results) do
    successes = Enum.count(trajectory_results, & &1.success)
    successes / max(length(trajectory_results), 1)
  end

  # Measure latency: average execution time
  defp measure_latency(trajectory_results) do
    durations = Enum.map(trajectory_results, & &1.duration_ms)
    Enum.sum(durations) / max(length(durations), 1) / 1000.0  # Convert to seconds
  end

  # Measure cost: token usage converted to dollars
  defp measure_cost(trajectory_results, model_pricing) do
    total_tokens = Enum.reduce(trajectory_results, 0, fn result, acc ->
      acc + result.prompt_tokens + result.completion_tokens
    end)
    total_tokens * model_pricing.cost_per_1k_tokens / 1000.0
  end

  # Measure robustness: inverse of performance variance
  defp measure_robustness(trajectory_results) do
    scores = Enum.map(trajectory_results, & &1.quality_score)
    mean = Enum.sum(scores) / length(scores)
    variance = Enum.reduce(scores, 0.0, fn score, acc ->
      acc + :math.pow(score - mean, 2)
    end) / length(scores)

    # Convert variance to robustness score (0-1, higher is better)
    max(0.0, 1.0 - :math.sqrt(variance))
  end
end
```

**Step 1.2: Implement Objective Normalization**

Normalize objectives to [0, 1] for fair comparison:

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator do
  # Min-max normalization
  defp normalize_objectives(objectives, population_stats) do
    Enum.map(@objectives, fn obj ->
      value = Map.get(objectives, obj)
      min_val = Map.get(population_stats, :"#{obj}_min", 0.0)
      max_val = Map.get(population_stats, :"#{obj}_max", 1.0)

      # Normalize to [0, 1]
      normalized = if max_val > min_val do
        (value - min_val) / (max_val - min_val)
      else
        0.5  # All values are the same
      end

      # Invert if minimization objective
      normalized = if obj in [:latency, :cost] do
        1.0 - normalized
      else
        normalized
      end

      {obj, Float.round(normalized, 4)}
    end)
    |> Map.new()
  end

  # Calculate population statistics for normalization
  def calculate_population_stats(candidates) do
    # Extract all objective values
    all_objectives = Enum.map(candidates, & &1.objectives)

    # Calculate min/max for each objective
    Enum.flat_map(@objectives, fn obj ->
      values = Enum.map(all_objectives, &Map.get(&1, obj, 0.0))
      [
        {:"#{obj}_min", Enum.min(values, fn -> 0.0 end)},
        {:"#{obj}_max", Enum.max(values, fn -> 1.0 end)}
      ]
    end)
    |> Map.new()
  end
end
```

**Step 1.3: Implement Weighted Aggregate Fitness**

For backward compatibility with single-objective code:

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.MultiObjectiveEvaluator do
  @default_weights %{
    accuracy: 0.5,
    latency: 0.2,
    cost: 0.2,
    robustness: 0.1
  }

  def aggregate_fitness(normalized_objectives, opts \\ []) do
    weights = Keyword.get(opts, :weights, @default_weights)

    Enum.reduce(@objectives, 0.0, fn obj, acc ->
      obj_value = Map.get(normalized_objectives, obj, 0.0)
      weight = Map.get(weights, obj, 0.0)
      acc + (obj_value * weight)
    end)
    |> Float.round(4)
  end
end
```

**Step 1.4: Write Tests**

Test suite covering:
- Objective measurement accuracy
- Normalization correctness (min-max, inversion)
- Edge cases (empty results, identical values)
- Aggregate fitness calculation
- Custom objective definitions

**Deliverables:**
- `lib/jido_ai/runner/gepa/pareto/multi_objective_evaluator.ex` (~250 lines)
- `test/jido_ai/runner/gepa/pareto/multi_objective_evaluator_test.exs` (~400 lines, 30 tests)

---

### Phase 2: Dominance Computation (Task 2.1.2)

**Estimated Time**: 4-5 days

**Step 2.1: Implement Pareto Dominance Check**

```elixir
# lib/jido_ai/runner/gepa/pareto/dominance_comparator.ex

defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @doc """
  Check if solution A dominates solution B.

  Returns: :dominates | :dominated_by | :non_dominated
  """
  def compare(a, b, objective_directions) do
    objectives = Map.keys(objective_directions)

    # Check each objective
    comparisons = Enum.map(objectives, fn obj ->
      a_val = get_in(a.normalized_objectives, [obj])
      b_val = get_in(b.normalized_objectives, [obj])

      cond do
        a_val > b_val -> :better
        a_val < b_val -> :worse
        true -> :equal
      end
    end)

    # A dominates B if all >= and at least one >
    all_better_or_equal = Enum.all?(comparisons, &(&1 in [:better, :equal]))
    at_least_one_better = Enum.any?(comparisons, &(&1 == :better))

    # B dominates A if all <= and at least one <
    all_worse_or_equal = Enum.all?(comparisons, &(&1 in [:worse, :equal]))
    at_least_one_worse = Enum.any?(comparisons, &(&1 == :worse))

    cond do
      all_better_or_equal and at_least_one_better -> :dominates
      all_worse_or_equal and at_least_one_worse -> :dominated_by
      true -> :non_dominated
    end
  end

  def dominates?(a, b, objective_directions) do
    compare(a, b, objective_directions) == :dominates
  end
end
```

**Step 2.2: Implement Fast Non-Dominated Sorting (NSGA-II)**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @doc """
  Fast non-dominated sorting algorithm from NSGA-II.

  Complexity: O(MN²) where M = objectives, N = population size
  """
  def fast_non_dominated_sort(candidates, objective_directions) do
    # Initialize dominance relationships
    initial_state = Enum.reduce(candidates, %{}, fn candidate, acc ->
      Map.put(acc, candidate.id, %{
        candidate: candidate,
        dominated_by: [],    # Solutions that dominate this one
        dominates: [],       # Solutions this one dominates
        domination_count: 0  # Number of solutions that dominate this one
      })
    end)

    # Calculate dominance relationships (O(N²))
    state_with_dominance = calculate_dominance_relationships(
      candidates,
      initial_state,
      objective_directions
    )

    # Classify into fronts
    classify_into_fronts(state_with_dominance)
  end

  defp calculate_dominance_relationships(candidates, state, objective_directions) do
    # Compare each pair of candidates
    for a <- candidates,
        b <- candidates,
        a.id != b.id,
        reduce: state do
      acc ->
        case compare(a, b, objective_directions) do
          :dominates ->
            # A dominates B
            acc
            |> update_in([a.id, :dominates], &[b.id | &1])
            |> update_in([b.id, :dominated_by], &[a.id | &1])
            |> update_in([b.id, :domination_count], &(&1 + 1))

          _ ->
            acc
        end
    end
  end

  defp classify_into_fronts(state) do
    # Front 1: candidates with domination_count = 0 (non-dominated)
    front_1_ids = state
    |> Enum.filter(fn {_id, info} -> info.domination_count == 0 end)
    |> Enum.map(fn {id, _info} -> id end)

    # Recursively build remaining fronts
    classify_remaining_fronts(state, front_1_ids, %{1 => front_1_ids}, 1)
  end

  defp classify_remaining_fronts(state, current_front, fronts, front_num) do
    if Enum.empty?(current_front) do
      fronts
    else
      # Find next front: solutions dominated only by current and previous fronts
      next_front = find_next_front(state, current_front)

      if Enum.empty?(next_front) do
        fronts
      else
        new_fronts = Map.put(fronts, front_num + 1, next_front)
        classify_remaining_fronts(state, next_front, new_fronts, front_num + 1)
      end
    end
  end

  defp find_next_front(state, current_front) do
    # For each solution in current front, reduce domination count
    # of solutions it dominates
    updated_counts = Enum.reduce(current_front, %{}, fn id, acc ->
      dominated_ids = get_in(state, [id, :dominates])

      Enum.reduce(dominated_ids, acc, fn dominated_id, acc2 ->
        current_count = Map.get(acc2, dominated_id,
                                 get_in(state, [dominated_id, :domination_count]))
        Map.put(acc2, dominated_id, current_count - 1)
      end)
    end)

    # Solutions with count = 0 after reduction form next front
    Enum.filter(updated_counts, fn {_id, count} -> count == 0 end)
    |> Enum.map(fn {id, _count} -> id end)
  end
end
```

**Step 2.3: Implement Crowding Distance**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @doc """
  Calculate crowding distance for candidates in a front.

  Crowding distance measures solution density along the Pareto frontier.
  Boundary solutions get infinite distance.

  Complexity: O(MN log N) where M = objectives, N = front size
  """
  def crowding_distance(candidates, objectives) do
    if length(candidates) <= 2 do
      # Boundary condition: all get infinite distance
      Enum.map(candidates, fn c -> {c.id, :infinity} end) |> Map.new()
    else
      # Initialize distances to 0
      initial_distances = Enum.map(candidates, fn c -> {c.id, 0.0} end) |> Map.new()

      # Calculate distance contribution for each objective
      Enum.reduce(objectives, initial_distances, fn objective, distances ->
        add_objective_crowding(candidates, objective, distances)
      end)
    end
  end

  defp add_objective_crowding(candidates, objective, distances) do
    # Sort candidates by objective value
    sorted = Enum.sort_by(candidates, fn c ->
      get_in(c.normalized_objectives, [objective])
    end)

    # Boundary solutions get infinite distance
    first = List.first(sorted)
    last = List.last(sorted)

    distances = distances
    |> Map.put(first.id, :infinity)
    |> Map.put(last.id, :infinity)

    # Calculate range for normalization
    min_val = get_in(first.normalized_objectives, [objective])
    max_val = get_in(last.normalized_objectives, [objective])
    range = max_val - min_val

    # Skip if all values are the same
    if range == 0 do
      distances
    else
      # Calculate cuboid distance for interior solutions
      sorted
      |> Enum.drop(1)  # Skip first (boundary)
      |> Enum.drop(-1) # Skip last (boundary)
      |> Enum.with_index(1)  # Track position
      |> Enum.reduce(distances, fn {candidate, idx}, acc ->
        prev = Enum.at(sorted, idx - 1)
        next = Enum.at(sorted, idx + 1)

        prev_val = get_in(prev.normalized_objectives, [objective])
        next_val = get_in(next.normalized_objectives, [objective])

        # Distance = (next - prev) / range
        contribution = (next_val - prev_val) / range

        current_distance = Map.get(acc, candidate.id, 0.0)
        Map.put(acc, candidate.id, current_distance + contribution)
      end)
    end
  end
end
```

**Step 2.4: Implement Epsilon-Dominance**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.DominanceComparator do
  @doc """
  Check epsilon-dominance for noisy objective measurements.

  A epsilon-dominates B if A >= B - epsilon in all objectives.
  """
  def epsilon_dominates?(a, b, objective_directions, epsilon \\ 0.01) do
    objectives = Map.keys(objective_directions)

    Enum.all?(objectives, fn obj ->
      a_val = get_in(a.normalized_objectives, [obj])
      b_val = get_in(b.normalized_objectives, [obj])

      # A must be better or within epsilon of B
      a_val >= (b_val - epsilon)
    end) and
    Enum.any?(objectives, fn obj ->
      a_val = get_in(a.normalized_objectives, [obj])
      b_val = get_in(b.normalized_objectives, [obj])

      # And strictly better in at least one objective
      a_val > (b_val + epsilon)
    end)
  end
end
```

**Step 2.5: Write Tests**

Comprehensive test coverage:
- Pairwise dominance checks (all combinations)
- Fast non-dominated sorting correctness
- Crowding distance calculation
- Boundary solution handling (infinite distance)
- Epsilon-dominance with various epsilon values
- Edge cases (identical solutions, single front)

**Deliverables:**
- `lib/jido_ai/runner/gepa/pareto/dominance_comparator.ex` (~350 lines)
- `test/jido_ai/runner/gepa/pareto/dominance_comparator_test.exs` (~500 lines, 40 tests)

---

### Phase 3: Frontier Maintenance (Task 2.1.3)

**Estimated Time**: 3-4 days

**Step 3.1: Implement Frontier Creation**

```elixir
# lib/jido_ai/runner/gepa/pareto/frontier_manager.ex

defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  alias Jido.AI.Runner.GEPA.Pareto.Frontier
  alias Jido.AI.Runner.GEPA.Population.Candidate

  def new(opts) do
    objectives = Keyword.fetch!(opts, :objectives)
    objective_directions = Keyword.fetch!(opts, :objective_directions)
    reference_point = Keyword.fetch!(opts, :reference_point)

    # Validate inputs
    with :ok <- validate_objectives(objectives, objective_directions),
         :ok <- validate_reference_point(reference_point, objectives) do

      now = System.monotonic_time(:millisecond)

      frontier = %Frontier{
        solutions: [],
        fronts: %{},
        hypervolume: 0.0,
        reference_point: reference_point,
        objectives: objectives,
        objective_directions: objective_directions,
        archive: [],
        generation: 0,
        created_at: now,
        updated_at: now
      }

      {:ok, frontier}
    end
  end

  defp validate_objectives(objectives, directions) do
    if Enum.all?(objectives, fn obj -> Map.has_key?(directions, obj) end) do
      :ok
    else
      {:error, :missing_objective_direction}
    end
  end

  defp validate_reference_point(reference, objectives) do
    if Enum.all?(objectives, fn obj -> Map.has_key?(reference, obj) end) do
      :ok
    else
      {:error, :missing_reference_value}
    end
  end
end
```

**Step 3.2: Implement Add Solution**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  alias Jido.AI.Runner.GEPA.Pareto.{DominanceComparator, HypervolumeCalculator}

  def add_solution(frontier, candidate) do
    # Check if candidate is dominated by any existing solution
    dominated_by = Enum.filter(frontier.solutions, fn existing ->
      DominanceComparator.dominates?(existing, candidate, frontier.objective_directions)
    end)

    if length(dominated_by) > 0 do
      # Candidate is dominated, don't add
      {:ok, frontier}
    else
      # Remove solutions dominated by candidate
      solutions_to_keep = Enum.reject(frontier.solutions, fn existing ->
        DominanceComparator.dominates?(candidate, existing, frontier.objective_directions)
      end)

      # Add candidate
      new_solutions = [candidate | solutions_to_keep]

      # Recalculate hypervolume
      {:ok, new_hypervolume} = HypervolumeCalculator.calculate(
        new_solutions,
        frontier.reference_point,
        objectives: frontier.objectives
      )

      # Update frontier
      updated_frontier = %{frontier |
        solutions: new_solutions,
        hypervolume: new_hypervolume,
        updated_at: System.monotonic_time(:millisecond)
      }

      # Check if trimming needed
      max_size = Application.get_env(:jido_ai, :pareto_max_frontier_size, 100)

      if length(new_solutions) > max_size do
        trim(updated_frontier)
      else
        {:ok, updated_frontier}
      end
    end
  end
end
```

**Step 3.3: Implement Diversity-Preserving Trimming**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  def trim(frontier, opts \\ []) do
    max_size = Keyword.get(opts, :max_size, 100)

    if length(frontier.solutions) <= max_size do
      {:ok, frontier}
    else
      # Calculate crowding distance
      distances = DominanceComparator.crowding_distance(
        frontier.solutions,
        frontier.objectives
      )

      # Sort by crowding distance (keep highest)
      # Never remove boundary solutions (infinite distance)
      sorted_solutions = Enum.sort_by(frontier.solutions, fn solution ->
        case Map.get(distances, solution.id) do
          :infinity -> {0, :infinity}  # Keep boundaries first
          dist -> {1, -dist}           # Then by decreasing distance
        end
      end)

      # Keep top max_size solutions
      trimmed_solutions = Enum.take(sorted_solutions, max_size)

      # Recalculate hypervolume
      {:ok, new_hypervolume} = HypervolumeCalculator.calculate(
        trimmed_solutions,
        frontier.reference_point,
        objectives: frontier.objectives
      )

      {:ok, %{frontier |
        solutions: trimmed_solutions,
        hypervolume: new_hypervolume,
        updated_at: System.monotonic_time(:millisecond)
      }}
    end
  end
end
```

**Step 3.4: Implement Archive Management**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.FrontierManager do
  def archive_solution(frontier, candidate) do
    # Add to archive if not already present
    if Enum.any?(frontier.archive, fn c -> c.id == candidate.id end) do
      {:ok, frontier}
    else
      new_archive = [candidate | frontier.archive]

      # Trim archive if too large
      max_archive_size = Application.get_env(:jido_ai, :pareto_max_archive_size, 500)
      trimmed_archive = if length(new_archive) > max_archive_size do
        # Keep best solutions by aggregate fitness
        new_archive
        |> Enum.sort_by(& &1.fitness, :desc)
        |> Enum.take(max_archive_size)
      else
        new_archive
      end

      {:ok, %{frontier | archive: trimmed_archive}}
    end
  end

  def get_pareto_optimal(frontier) do
    frontier.solutions
  end

  def get_front(frontier, rank) do
    front_ids = Map.get(frontier.fronts, rank, [])
    Enum.filter(frontier.solutions, fn c -> c.id in front_ids end)
  end
end
```

**Step 3.5: Write Tests**

Test coverage:
- Frontier creation and validation
- Adding dominated solutions (rejected)
- Adding dominating solutions (removes dominated)
- Trimming with diversity preservation
- Archive management and size limits
- Boundary solution protection
- Edge cases (empty frontier, single solution)

**Deliverables:**
- `lib/jido_ai/runner/gepa/pareto/frontier_manager.ex` (~300 lines)
- `test/jido_ai/runner/gepa/pareto/frontier_manager_test.exs` (~450 lines, 35 tests)

---

### Phase 4: Hypervolume Calculation (Task 2.1.4)

**Estimated Time**: 4-5 days

**Step 4.1: Implement Basic Hypervolume Algorithm**

For 2-3 objectives, use simple geometric calculation:

```elixir
# lib/jido_ai/runner/gepa/pareto/hypervolume_calculator.ex

defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  @doc """
  Calculate hypervolume for 2 objectives (simple case).

  Sort solutions by first objective, calculate rectangular areas.
  """
  def calculate_2d(solutions, reference_point, objectives) do
    [obj1, obj2] = objectives

    # Sort by first objective (descending)
    sorted = Enum.sort_by(solutions, fn s ->
      -get_in(s.normalized_objectives, [obj1])
    end)

    # Calculate area of each rectangle
    {hypervolume, _} = Enum.reduce(sorted, {0.0, reference_point[obj1]}, fn solution, {hv, prev_x} ->
      x = get_in(solution.normalized_objectives, [obj1])
      y = get_in(solution.normalized_objectives, [obj2])
      ref_y = reference_point[obj2]

      # Rectangle area: (x - prev_x) * (y - ref_y)
      area = max(0.0, (prev_x - x) * max(0.0, y - ref_y))

      {hv + area, x}
    end)

    {:ok, Float.round(hypervolume, 6)}
  end
end
```

**Step 4.2: Implement WFG Algorithm for 3+ Objectives**

While-Fonseca-Gomes (WFG) algorithm for efficient multi-dimensional hypervolume:

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  @doc """
  Calculate hypervolume using WFG algorithm.

  Complexity: O(N log N) for 2-3 objectives, O(N^(M-2) log N) for M objectives
  """
  def calculate(solutions, reference_point, opts \\ []) do
    objectives = Keyword.fetch!(opts, :objectives)

    case length(objectives) do
      2 -> calculate_2d(solutions, reference_point, objectives)
      3 -> calculate_3d_wfg(solutions, reference_point, objectives)
      _ -> calculate_nd_wfg(solutions, reference_point, objectives)
    end
  end

  defp calculate_3d_wfg(solutions, reference_point, objectives) do
    # Implement 3D WFG algorithm
    # Recursively slices objective space
    # See: While, Bradstreet, Barone (2006)

    # Transform to minimization problem (WFG standard)
    transformed = transform_to_minimization(solutions, reference_point, objectives)

    # Calculate using recursive slicing
    hypervolume = wfg_recursive(transformed, reference_point, objectives, 0)

    {:ok, Float.round(hypervolume, 6)}
  end

  defp wfg_recursive([], _reference, _objectives, _depth), do: 0.0

  defp wfg_recursive([solution | rest], reference, objectives, depth) do
    if depth >= length(objectives) - 1 do
      # Base case: calculate 1D hypervolume
      [last_obj] = Enum.drop(objectives, depth)
      sol_val = get_in(solution.normalized_objectives, [last_obj])
      ref_val = reference[last_obj]
      max(0.0, ref_val - sol_val)
    else
      # Recursive case: slice and recurse
      current_obj = Enum.at(objectives, depth)
      sol_val = get_in(solution.normalized_objectives, [current_obj])
      ref_val = reference[current_obj]

      # Limited hypervolume contribution
      limited_hv = (ref_val - sol_val) * wfg_recursive(
        rest,
        Map.put(reference, current_obj, sol_val),
        objectives,
        depth + 1
      )

      # Continue with remaining solutions
      remaining_hv = wfg_recursive(rest, reference, objectives, depth)

      limited_hv + remaining_hv
    end
  end
end
```

**Step 4.3: Implement Hypervolume Contribution**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  def contribution(solutions, reference_point, opts \\ []) do
    objectives = Keyword.fetch!(opts, :objectives)

    # Calculate total hypervolume
    {:ok, total_hv} = calculate(solutions, reference_point, objectives: objectives)

    # Calculate hypervolume without each solution
    Enum.map(solutions, fn solution ->
      remaining = Enum.reject(solutions, fn s -> s.id == solution.id end)
      {:ok, hv_without} = calculate(remaining, reference_point, objectives: objectives)

      # Contribution = total - without
      contribution = max(0.0, total_hv - hv_without)

      {solution.id, contribution}
    end)
    |> Map.new()
  end
end
```

**Step 4.4: Implement Auto Reference Point Selection**

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.HypervolumeCalculator do
  def auto_reference_point(candidates, opts \\ []) do
    objectives = Keyword.fetch!(opts, :objectives)
    objective_directions = Keyword.fetch!(opts, :objective_directions)
    margin = Keyword.get(opts, :margin, 0.1)

    # Find nadir point (worst value in each objective)
    Enum.map(objectives, fn obj ->
      values = Enum.map(candidates, fn c ->
        get_in(c.normalized_objectives, [obj])
      end)

      # For maximization: use minimum - margin
      # For minimization: use maximum + margin (inverted in normalized space)
      direction = Map.get(objective_directions, obj)
      reference_value = case direction do
        :maximize ->
          min_val = Enum.min(values, fn -> 0.0 end)
          max(0.0, min_val - margin)

        :minimize ->
          # In normalized space, minimize becomes maximize after inversion
          min_val = Enum.min(values, fn -> 0.0 end)
          max(0.0, min_val - margin)
      end

      {obj, reference_value}
    end)
    |> Map.new()
  end
end
```

**Step 4.5: Write Tests**

Comprehensive testing:
- 2D hypervolume calculation accuracy
- 3D WFG algorithm correctness
- Contribution calculation
- Auto reference point selection
- Edge cases (empty set, single solution, dominated solutions)
- Performance benchmarks (time complexity)

**Deliverables:**
- `lib/jido_ai/runner/gepa/pareto/hypervolume_calculator.ex` (~400 lines)
- `test/jido_ai/runner/gepa/pareto/hypervolume_calculator_test.exs` (~450 lines, 35 tests)

---

### Phase 5: Integration & Testing (Sections 2.1 Unit Tests)

**Estimated Time**: 2-3 days

**Step 5.1: Update Candidate Struct**

Extend `Population.Candidate` with multi-objective fields:

```elixir
# lib/jido_ai/runner/gepa/population.ex

defmodule Jido.AI.Runner.GEPA.Population.Candidate do
  use TypedStruct

  # Existing fields...

  # NEW: Multi-objective fields
  field(:objectives, map() | nil, default: nil)
  field(:normalized_objectives, map() | nil, default: nil)
  field(:pareto_rank, integer() | nil, default: nil)
  field(:crowding_distance, float() | nil, default: nil)
  field(:dominated_by, list(String.t()), default: [])
  field(:dominates, list(String.t()), default: [])
end
```

**Step 5.2: Integrate with Optimizer**

Modify optimizer selection phase to use Pareto ranking:

```elixir
# lib/jido_ai/runner/gepa/optimizer.ex

defmodule Jido.AI.Runner.GEPA.Optimizer do
  alias Jido.AI.Runner.GEPA.Pareto.{
    MultiObjectiveEvaluator,
    DominanceComparator,
    FrontierManager,
    HypervolumeCalculator
  }

  # Add to Config struct
  field(:multi_objective, boolean(), default: true)
  field(:objectives, list(atom()), default: [:accuracy, :latency, :cost, :robustness])
  field(:objective_directions, map(), default: %{
    accuracy: :maximize,
    latency: :minimize,
    cost: :minimize,
    robustness: :maximize
  })

  # Modify selection phase
  defp perform_selection(%State{config: %{multi_objective: true}} = state, offspring) do
    # Use Pareto selection (implemented in Phase 3)
    perform_pareto_selection(state, offspring)
  end

  defp perform_selection(state, offspring) do
    # Fallback to simple fitness-based selection
    perform_fitness_selection(state, offspring)
  end
end
```

**Step 5.3: Integration Tests**

End-to-end tests for full Pareto workflow:

```elixir
# test/jido_ai/runner/gepa/pareto/integration_test.exs

defmodule Jido.AI.Runner.GEPA.Pareto.IntegrationTest do
  use ExUnit.Case

  alias Jido.AI.Runner.GEPA.{Optimizer, Population}
  alias Jido.AI.Runner.GEPA.Pareto.{
    MultiObjectiveEvaluator,
    DominanceComparator,
    FrontierManager,
    HypervolumeCalculator
  }

  describe "Multi-objective optimization workflow" do
    test "evaluates population across multiple objectives" do
      # Setup population with diverse prompts
      # Evaluate with multi-objective evaluator
      # Verify all objectives measured
    end

    test "performs non-dominated sorting correctly" do
      # Create population with known dominance relationships
      # Run sorting
      # Verify fronts match expected structure
    end

    test "maintains Pareto frontier across generations" do
      # Run optimization for multiple generations
      # Verify frontier only contains non-dominated solutions
      # Check hypervolume increases over time
    end

    test "preserves diversity through crowding distance" do
      # Run optimization
      # Measure solution spread
      # Verify boundary solutions maintained
    end

    test "discovers trade-offs between objectives" do
      # Run optimization
      # Verify frontier contains diverse trade-off solutions
      # Check accuracy-cost, accuracy-latency, etc. trade-offs
    end
  end
end
```

**Step 5.4: Performance Benchmarks**

Benchmark computational overhead:

```elixir
# test/jido_ai/runner/gepa/pareto/performance_test.exs

defmodule Jido.AI.Runner.GEPA.Pareto.PerformanceTest do
  use ExUnit.Case

  @tag :benchmark
  test "non-dominated sorting scales O(MN²)" do
    # Benchmark with varying population sizes
    # Verify time complexity
  end

  @tag :benchmark
  test "hypervolume calculation efficiency" do
    # Benchmark 2D, 3D, 4D hypervolume
    # Compare against theoretical complexity
  end
end
```

**Deliverables:**
- Updated `population.ex` with multi-objective fields (~50 lines added)
- Updated `optimizer.ex` with Pareto integration (~100 lines added)
- `test/jido_ai/runner/gepa/pareto/integration_test.exs` (~300 lines, 20 tests)
- `test/jido_ai/runner/gepa/pareto/performance_test.exs` (~200 lines, 10 tests)

---

## Testing Strategy

### Unit Tests by Module

**2.1.1 Multi-Objective Evaluator** (~30 tests):
- Objective measurement accuracy (8 tests)
- Normalization correctness (8 tests)
- Aggregate fitness calculation (5 tests)
- Edge cases (5 tests)
- Custom objectives (4 tests)

**2.1.2 Dominance Comparator** (~40 tests):
- Pairwise dominance (10 tests)
- Fast non-dominated sorting (10 tests)
- Crowding distance (10 tests)
- Epsilon-dominance (5 tests)
- Edge cases (5 tests)

**2.1.3 Frontier Manager** (~35 tests):
- Frontier creation (5 tests)
- Add/remove solutions (10 tests)
- Trimming (8 tests)
- Archive management (7 tests)
- Edge cases (5 tests)

**2.1.4 Hypervolume Calculator** (~35 tests):
- 2D hypervolume (8 tests)
- 3D WFG algorithm (8 tests)
- Contribution calculation (8 tests)
- Auto reference point (6 tests)
- Edge cases (5 tests)

**Integration Tests** (~20 tests):
- End-to-end Pareto workflow (5 tests)
- Multi-generation optimization (5 tests)
- Trade-off discovery (5 tests)
- Performance verification (5 tests)

**Total: ~160 tests**

### Test Data

Create realistic test populations:

```elixir
defmodule Jido.AI.Runner.GEPA.ParetoTestFixtures do
  def create_test_population do
    [
      # High accuracy, high cost
      create_candidate("cand_1", %{
        accuracy: 0.95, latency: 3.0, cost: 0.05, robustness: 0.80
      }),

      # Balanced
      create_candidate("cand_2", %{
        accuracy: 0.88, latency: 1.5, cost: 0.02, robustness: 0.85
      }),

      # Fast, low cost
      create_candidate("cand_3", %{
        accuracy: 0.80, latency: 0.8, cost: 0.01, robustness: 0.70
      }),

      # Robust
      create_candidate("cand_4", %{
        accuracy: 0.90, latency: 2.5, cost: 0.04, robustness: 0.95
      }),

      # Dominated (should be filtered)
      create_candidate("cand_5", %{
        accuracy: 0.75, latency: 2.0, cost: 0.03, robustness: 0.75
      })
    ]
  end

  defp create_candidate(id, objectives) do
    %Candidate{
      id: id,
      prompt: "Test prompt #{id}",
      objectives: objectives,
      normalized_objectives: normalize_simple(objectives),
      fitness: 0.0,
      generation: 0,
      parent_ids: [],
      metadata: %{},
      created_at: System.monotonic_time(:millisecond)
    }
  end

  defp normalize_simple(objectives) do
    # Simple normalization for testing
    %{
      accuracy: objectives.accuracy,
      latency: 1.0 - (objectives.latency / 10.0),
      cost: 1.0 - (objectives.cost / 0.1),
      robustness: objectives.robustness
    }
  end
end
```

### Property-Based Testing

Use StreamData for property tests:

```elixir
defmodule Jido.AI.Runner.GEPA.Pareto.PropertyTest do
  use ExUnit.Case
  use ExUnitProperties

  property "dominance relation is transitive" do
    check all(
      population <- population_generator(),
      max_runs: 100
    ) do
      # If A dominates B and B dominates C, then A dominates C
      verify_transitivity(population)
    end
  end

  property "Pareto frontier contains only non-dominated solutions" do
    check all(
      population <- population_generator(),
      max_runs: 100
    ) do
      fronts = DominanceComparator.fast_non_dominated_sort(population)
      front_1 = Map.get(fronts, 1, [])

      # No solution in front 1 should dominate another
      for a <- front_1, b <- front_1, a != b do
        refute DominanceComparator.dominates?(a, b)
      end
    end
  end

  property "hypervolume increases with better solutions" do
    check all(
      population <- population_generator(),
      better_solution <- better_solution_generator(population),
      max_runs: 50
    ) do
      {:ok, hv1} = HypervolumeCalculator.calculate(population, reference)
      {:ok, hv2} = HypervolumeCalculator.calculate([better_solution | population], reference)

      assert hv2 >= hv1
    end
  end
end
```

---

## Success Criteria

### Functional Requirements

1. **Multi-Objective Evaluation**
   - [ ] Measures accuracy, latency, cost, robustness for all candidates
   - [ ] Normalizes objectives to [0, 1] range
   - [ ] Supports custom objective definitions
   - [ ] Calculates aggregate fitness for backward compatibility

2. **Dominance Computation**
   - [ ] Correctly identifies Pareto dominance relationships
   - [ ] Classifies population into fronts (NSGA-II)
   - [ ] Calculates crowding distance for diversity
   - [ ] Supports epsilon-dominance for noisy objectives

3. **Frontier Maintenance**
   - [ ] Maintains non-dominated solution set
   - [ ] Removes dominated solutions efficiently
   - [ ] Trims frontier using diversity-preserving selection
   - [ ] Archives historical best solutions

4. **Hypervolume Calculation**
   - [ ] Accurately calculates hypervolume for 2-4 objectives
   - [ ] Computes solution contributions for selection
   - [ ] Auto-selects reference points
   - [ ] Tracks hypervolume improvement across generations

### Performance Requirements

1. **Computational Efficiency**
   - Non-dominated sorting: O(MN²) for M objectives, N candidates
   - Crowding distance: O(MN log N) per front
   - Hypervolume: O(N log N) for 2-3 objectives
   - Total overhead: < 20% increase over single-objective selection

2. **Scalability**
   - Supports populations up to 500 candidates
   - Handles 4+ objectives (accuracy, latency, cost, robustness, ...)
   - Maintains frontiers up to 100 solutions
   - Archives up to 500 historical solutions

3. **Accuracy**
   - Hypervolume calculation error: < 1%
   - Normalization precision: 4 decimal places
   - Dominance checking: 100% correctness

### Quality Requirements

1. **Test Coverage**
   - [ ] ~160 comprehensive unit tests
   - [ ] 20+ integration tests
   - [ ] Property-based tests for key invariants
   - [ ] Performance benchmarks

2. **Documentation**
   - [ ] Module documentation with examples
   - [ ] Algorithm explanations (NSGA-II, WFG)
   - [ ] Usage guide for multi-objective optimization
   - [ ] Trade-off interpretation guide

3. **Maintainability**
   - [ ] Clean separation of concerns (4 focused modules)
   - [ ] Consistent error handling
   - [ ] Comprehensive logging
   - [ ] Type specifications for all public functions

### Expected Outcomes

After Section 2.1 implementation:

1. **Optimization Improvements**
   - Discover 4-6 diverse Pareto-optimal prompts per optimization
   - Enable deployment flexibility (accuracy vs. cost vs. latency trade-offs)
   - Maintain solution diversity (crowding distance > 0.1 on average)

2. **User Benefits**
   - Choose prompts based on deployment constraints
   - Visualize objective trade-offs
   - Understand what you sacrifice when optimizing one objective

3. **Foundation for Stage 2**
   - Section 2.2: Selection mechanisms (tournament, fitness sharing)
   - Section 2.3: Convergence detection (hypervolume saturation)
   - Section 2.4: Integration tests for full Stage 2

---

## References

### Research Papers

1. **NSGA-II Algorithm**
   - Deb, K., Pratap, A., Agarwal, S., & Meyarivan, T. (2002). A fast and elitist multiobjective genetic algorithm: NSGA-II. IEEE Transactions on Evolutionary Computation, 6(2), 182-197.
   - https://ieeexplore.ieee.org/document/996017

2. **Hypervolume Indicator**
   - Zitzler, E., & Thiele, L. (1999). Multiobjective evolutionary algorithms: a comparative case study and the strength Pareto approach. IEEE Transactions on Evolutionary Computation, 3(4), 257-271.
   - While, L., Bradstreet, L., & Barone, L. (2006). A fast way of calculating exact hypervolumes. IEEE Transactions on Evolutionary Computation, 10(1), 29-38.

3. **GEPA (Genetic-Pareto Prompt Optimization)**
   - Agrawal et al. (2024). GEPA: Reflective Prompt Evolution Can Outperform Reinforcement Learning. arXiv:2507.19457
   - https://arxiv.org/abs/2507.19457

### Code Examples

1. **NSGA-II Implementation**
   - Python: https://github.com/haris989/NSGA-II
   - Java: https://github.com/jMetal/jMetal (NSGA-II in jmetal-algorithm)

2. **Hypervolume Calculation**
   - WFG Algorithm: https://github.com/wfg/hypervolume
   - Python: https://github.com/PyMOO/pymoo/blob/main/pymoo/indicators/hv.py

### Existing Jido Infrastructure

1. **Population Management**: `lib/jido_ai/runner/gepa/population.ex`
2. **Optimizer Agent**: `lib/jido_ai/runner/gepa/optimizer.ex`
3. **Evaluation System**: Section 1.2 (trajectory collection, metrics)
4. **Mutation Operators**: Section 1.4 (targeted mutations, diversity)

---

## Conclusion

Section 2.1 implements comprehensive Pareto frontier management enabling GEPA to optimize prompts across multiple objectives simultaneously. By maintaining a diverse set of non-dominated solutions rather than converging to a single best prompt, we provide deployment flexibility and discover meaningful trade-offs between accuracy, latency, cost, and robustness.

The implementation follows proven multi-objective optimization algorithms (NSGA-II, WFG hypervolume) adapted to GEPA's prompt optimization context. With ~160 comprehensive tests and integration with existing GEPA infrastructure, Section 2.1 provides a solid foundation for Stage 2's evolution and selection mechanisms.

**Estimated Total Implementation Time**: 16-21 days
- Phase 1 (Multi-Objective Evaluation): 3-4 days
- Phase 2 (Dominance Computation): 4-5 days
- Phase 3 (Frontier Maintenance): 3-4 days
- Phase 4 (Hypervolume Calculation): 4-5 days
- Phase 5 (Integration & Testing): 2-3 days

**Next Steps After Section 2.1:**
- Section 2.2: Selection Mechanisms (tournament, fitness sharing)
- Section 2.3: Convergence Detection
- Section 2.4: Integration Tests for Stage 2
