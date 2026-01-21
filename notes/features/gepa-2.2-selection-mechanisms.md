# GEPA Section 2.2: Selection Mechanisms - Implementation Plan

**Status**: Planning
**Phase**: 5 (GEPA Optimization)
**Stage**: 2 (Evolution & Selection)
**Date Created**: 2025-10-27
**Last Updated**: 2025-10-27

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Technical Background](#technical-background)
4. [Architecture](#architecture)
5. [Implementation Plan](#implementation-plan)
6. [Testing Strategy](#testing-strategy)
7. [Success Criteria](#success-criteria)
8. [Integration Notes](#integration-notes)
9. [References](#references)

---

## Problem Statement

### Current State

Section 2.1 (Pareto Frontier Management) provides the infrastructure for multi-objective optimization:
- **Multi-Objective Evaluation** (Task 2.1.1): Measures accuracy, latency, cost, and robustness
- **Dominance Computation** (Task 2.1.2): Implements Pareto dominance, NSGA-II sorting, and **crowding distance calculation**
- **Frontier Maintenance** (Task 2.1.3): Manages the set of non-dominated solutions
- **Hypervolume Calculation** (Task 2.1.4): Quantifies frontier quality

However, we currently lack mechanisms to **select which candidates propagate to the next generation**. Without proper selection:

### Problems

**Problem 1: No Reproductive Selection**
- We can identify Pareto-optimal solutions but can't choose parents for reproduction
- Cannot balance fitness pressure (choosing high-performers) with diversity (exploring solution space)
- No mechanism to prevent premature convergence to local optima
- Missing the core evolutionary mechanism: differential reproduction based on fitness

**Problem 2: Elite Loss Risk**
- Without explicit elitism, best solutions may be lost during reproduction
- Pareto-optimal candidates could be replaced by inferior offspring
- No guarantee of monotonic improvement across generations
- Risk of regression in optimization quality

**Problem 3: Insufficient Diversity Pressure**
- Even with crowding distance calculated, no mechanism uses it for selection
- Population may cluster around a few solutions, losing diversity
- Cannot maintain spread along the Pareto frontier
- May miss important regions of the objective space

**Problem 4: No Niche Protection**
- Similar solutions compete equally, leading to redundant selection
- Cannot protect novel solutions in less-explored regions
- No mechanism to promote variety in the population
- Convergence to homogeneous population

### Why Selection Mechanisms?

Selection mechanisms are the **driving force of evolution**, determining which genetic material (prompts) propagates. They must balance:

1. **Selection Pressure**: Favor high-quality solutions (fitness-based)
2. **Diversity Maintenance**: Preserve solution variety (diversity-based)
3. **Elite Preservation**: Never lose best solutions (elitism)
4. **Niche Protection**: Reward novelty and spread (fitness sharing)

Together, these mechanisms ensure:
- **Convergence**: Improving average population quality over generations
- **Exploration**: Discovering diverse regions of the solution space
- **Efficiency**: Sample-efficient search guided by both quality and novelty
- **Robustness**: Maintaining multiple high-quality solutions with different trade-offs

---

## Solution Overview

### High-Level Approach

Implement four complementary selection mechanisms that work together to achieve balanced evolution:

```
┌─────────────────────────────────────────────────────────────────┐
│                     GEPA Selection System                        │
│                                                                  │
│  Input: Population with Pareto ranks and crowding distances    │
│  Output: Selected candidates for next generation               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Task 2.2.1: Tournament Selection                   │ │
│  │  • K-way competitions between random candidates           │ │
│  │  • Winner selected by: Pareto rank → Crowding distance    │ │
│  │  • Adaptive tournament size based on diversity            │ │
│  │  • Primary parent selection mechanism                      │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │    Task 2.2.2: Crowding Distance Integration               │ │
│  │  • Use existing crowding distance from Section 2.1.2      │ │
│  │  • Tie-breaking in tournament selection                   │ │
│  │  • Diversity-aware survivor selection                      │ │
│  │  • Boundary solution protection (infinite distance)        │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Task 2.2.3: Elite Preservation                     │ │
│  │  • Preserve top K solutions unconditionally                │ │
│  │  • Pareto Front 1 automatically selected                   │ │
│  │  • Diversity-preserving elitism (high crowding distance)   │ │
│  │  • Configurable elite ratio (default: 10-20%)             │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │         Task 2.2.4: Fitness Sharing                        │ │
│  │  • Penalize solutions in crowded objective regions         │ │
│  │  • Niche radius calculation based on population spread     │ │
│  │  • Adaptive sharing adjusting to diversity                 │ │
│  │  • Objective-specific sharing for targeted diversity       │ │
│  └────────────────────────────────────────────────────────────┘ │
│                              ↓                                   │
│             Next Generation Population (diverse + elite)        │
└─────────────────────────────────────────────────────────────────┘
```

### Key Mechanisms

**1. Tournament Selection (Task 2.2.1)**

**How it works:**
- Randomly sample K candidates from population
- Compare them using:
  1. **Primary**: Pareto rank (lower is better: Front 1 > Front 2 > ...)
  2. **Tie-breaker**: Crowding distance (higher is better: more isolated)
- Winner selected as parent for reproduction
- Repeat for each offspring needed

**Why tournaments?**
- Computationally efficient: O(K) per selection
- Naturally maintains diversity: localized competition
- Tunable selection pressure: larger K = stronger pressure
- Parallelize easily across multiple processes

**2. Crowding Distance Integration (Task 2.2.2)**

**Note**: Crowding distance is **already implemented** in Section 2.1.2 (`DominanceComparator.crowding_distance/2`). This task integrates it into selection, not reimplementing it.

**How it works:**
- Use existing `DominanceComparator.crowding_distance/2` function
- Apply in tournament tie-breaking: same rank → prefer higher distance
- Survivor selection: when trimming population, keep high-distance candidates
- Boundary protection: infinite distance ensures extreme solutions survive

**Why crowding distance?**
- Maintains spread along Pareto frontier
- Prevents clustering around a few solutions
- Preserves boundary solutions (extreme objective values)
- Density-based diversity metric (simple, effective)

**3. Elite Preservation (Task 2.2.3)**

**How it works:**
- Identify top K candidates by:
  1. All Pareto Front 1 members (non-dominated)
  2. If Front 1 < K, fill with Front 2, prioritizing high crowding distance
- Copy elites directly to next generation (no mutation)
- Remaining population filled by selected parents + offspring
- Configurable elite ratio (default: 10-20% of population)

**Why elitism?**
- **Monotonic improvement**: Never lose best solutions found
- **Convergence guarantee**: Best fitness can only improve or stay same
- **Safety net**: Protects Pareto frontier from mutation damage
- **Efficiency**: Preserves hard-won discoveries

**4. Fitness Sharing (Task 2.2.4)**

**How it works:**
- Calculate shared fitness: `f_shared(i) = f_raw(i) / niche_count(i)`
- Niche count: How many similar solutions exist
- Similarity: Distance in objective space < niche radius
- Penalizes crowded solutions, rewards isolated ones

**Why fitness sharing?**
- **Niche protection**: Rewards exploring empty regions
- **Diversity incentive**: Being unique increases effective fitness
- **Overcrowding prevention**: Multiple similar solutions share fitness
- **Speciation**: Stable subpopulations in different niches

---

## Technical Background

### NSGA-II Selection Strategy

Our implementation follows **NSGA-II** (Non-dominated Sorting Genetic Algorithm II), the gold standard for multi-objective optimization:

**NSGA-II Selection Process:**
1. **Non-dominated sorting**: Classify population into Pareto fronts
2. **Crowding distance**: Calculate density within each front
3. **Tournament selection**: Parents chosen via (rank, distance) comparison
4. **Elitism**: Combine parents + offspring, select best N by (rank, distance)

**NSGA-II Crowded-Comparison Operator:**
```
candidate_a < candidate_b if:
  (rank_a < rank_b) OR
  (rank_a == rank_b AND distance_a > distance_b)
```
This is exactly what we implement in tournament selection.

### Diversity Mechanisms

**Why diversity matters in GEPA:**
- **Multi-objective**: Need spread across trade-off frontier
- **Prompt space**: Multiple semantic approaches to same task
- **Generalization**: Diverse prompts more robust to variations
- **Sample efficiency**: Avoid redundant evaluations of similar prompts

**How we maintain diversity:**
1. **Crowding distance**: Spatial spread in objective space
2. **Fitness sharing**: Penalize similarity
3. **Tournament localization**: Random sampling limits competition
4. **Elite diversity**: Preserve diverse high-performers

### Integration with Section 2.1

**Existing Infrastructure (from Section 2.1.2):**

```elixir
# Already implemented in DominanceComparator
DominanceComparator.compare(candidate_a, candidate_b)
# => :dominates | :dominated_by | :non_dominated

DominanceComparator.fast_non_dominated_sort(population)
# => %{1 => [front_1_candidates], 2 => [front_2_candidates], ...}

DominanceComparator.crowding_distance(front_candidates)
# => %{"candidate_id" => distance, ...}
```

**What Section 2.2 adds:**

```elixir
# New selection operations
TournamentSelector.select(population, tournament_size: 3)
# => selected_candidate (for reproduction)

EliteSelector.select_elites(population, elite_ratio: 0.15)
# => elite_candidates (preserved to next generation)

FitnessSharing.calculate_shared_fitness(population, niche_radius: 0.1)
# => population_with_shared_fitness

SurvivorSelector.select_survivors(combined_population, target_size: 100)
# => next_generation_population
```

---

## Architecture

### File Structure

```
lib/jido_ai/runner/gepa/
├── selection/
│   ├── tournament_selector.ex          # Task 2.2.1
│   ├── crowding_distance_selector.ex   # Task 2.2.2 (integration wrapper)
│   ├── elite_selector.ex               # Task 2.2.3
│   └── fitness_sharing.ex              # Task 2.2.4
├── pareto/
│   └── dominance_comparator.ex         # Already exists (Section 2.1.2)
│                                       # crowding_distance/2 implemented here
└── population/
    └── candidate.ex                    # Already exists (Section 2.1.1)
                                        # Has pareto_rank, crowding_distance fields

test/jido_ai/runner/gepa/
├── selection/
│   ├── tournament_selector_test.exs
│   ├── crowding_distance_selector_test.exs
│   ├── elite_selector_test.exs
│   └── fitness_sharing_test.exs
└── integration/
    └── selection_integration_test.exs  # Full selection cycle
```

### Module Dependencies

```
Tournament Selector
  ├── Uses: DominanceComparator (for rank comparison)
  ├── Uses: Candidate.pareto_rank
  └── Uses: Candidate.crowding_distance

Crowding Distance Selector
  ├── Wraps: DominanceComparator.crowding_distance/2
  └── Used by: Tournament, Elite, Survivor selection

Elite Selector
  ├── Uses: DominanceComparator.fast_non_dominated_sort/1
  ├── Uses: DominanceComparator.crowding_distance/2
  └── Uses: Candidate.pareto_rank

Fitness Sharing
  ├── Uses: Candidate.normalized_objectives (distance calculation)
  └── Modifies: Candidate.fitness (shared fitness)
```

### Data Flow

```
Input: Population (from evaluation)
  │
  ├─> Non-dominated sorting (existing: DominanceComparator)
  │     └─> Assigns pareto_rank to each candidate
  │
  ├─> Crowding distance (existing: DominanceComparator)
  │     └─> Assigns crowding_distance to each candidate
  │
  ├─> Fitness sharing (new: Task 2.2.4)
  │     └─> Calculates shared_fitness for each candidate
  │
  ├─> Elite selection (new: Task 2.2.3)
  │     └─> Selects top K candidates (Front 1 + diverse)
  │
  └─> Tournament selection (new: Task 2.2.1)
        └─> Selects parents for reproduction (N times)

Output: Selected candidates for next generation
```

---

## Implementation Plan

### Task 2.2.1: Tournament Selection

**Objective**: Implement tournament selection as the primary parent selection mechanism.

#### 2.2.1.1: Create Tournament Selector Conducting K-Way Competitions

**File**: `lib/jido_ai/runner/gepa/selection/tournament_selector.ex`

**Implementation**:

```elixir
defmodule Jido.AI.Runner.GEPA.Selection.TournamentSelector do
  @moduledoc """
  Tournament selection for GEPA multi-objective optimization.

  Selects parents for reproduction through localized competitions
  where K randomly-chosen candidates compete, and the winner is
  determined by Pareto rank (primary) and crowding distance (tie-breaker).

  ## NSGA-II Crowded-Comparison Operator

  Candidate A wins over B if:
  - A has better (lower) Pareto rank, OR
  - A has same rank but higher crowding distance (more isolated)

  ## Tournament Size Effects

  - Small K (2-3): Weak selection pressure, high diversity
  - Medium K (4-7): Balanced pressure and diversity
  - Large K (8+): Strong pressure, risk of premature convergence

  ## Usage

      # Select a single parent
      parent = TournamentSelector.select_one(population, tournament_size: 3)

      # Select N parents for reproduction
      parents = TournamentSelector.select_many(population, count: 50, tournament_size: 3)
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  @type selection_result :: {:ok, Candidate.t()} | {:error, term()}

  @doc """
  Selects one candidate via tournament selection.

  ## Arguments

  - `population` - List of candidates with pareto_rank and crowding_distance
  - `opts` - Options:
    - `:tournament_size` - Number of competitors (default: 3)

  ## Returns

  - `{:ok, candidate}` - Winner of tournament
  - `{:error, reason}` - Selection failed
  """
  @spec select_one(list(Candidate.t()), keyword()) :: selection_result()
  def select_one(population, opts \\ [])

  @doc """
  Selects N candidates via repeated tournaments.

  ## Arguments

  - `population` - List of candidates
  - `opts` - Options:
    - `:count` - Number of candidates to select (required)
    - `:tournament_size` - Competitors per tournament (default: 3)
    - `:replacement` - Allow same candidate multiple times (default: true)
  """
  @spec select_many(list(Candidate.t()), keyword()) ::
    {:ok, list(Candidate.t())} | {:error, term()}
  def select_many(population, opts)

  # Private: Conduct single tournament
  defp conduct_tournament(population, tournament_size)

  # Private: Compare two candidates (NSGA-II crowded-comparison)
  defp crowded_compare(candidate_a, candidate_b)
end
```

**Key Functions**:
- `select_one/2`: Single tournament selection
- `select_many/2`: Repeated tournaments for batch selection
- `conduct_tournament/2`: Sample K candidates, return winner
- `crowded_compare/2`: NSGA-II comparison operator

**Tests**: `test/jido_ai/runner/gepa/selection/tournament_selector_test.exs`
- Test tournament with various sizes (2, 3, 5, 7)
- Test selection pressure (larger tournaments favor better ranks)
- Test tie-breaking by crowding distance
- Test batch selection (select_many)
- Test with/without replacement
- Test edge cases (empty population, K > population size)

#### 2.2.1.2: Implement Fitness-Based Tournament Using Pareto Ranking

**Implementation** (in `tournament_selector.ex`):

```elixir
defp crowded_compare(a, b) do
  cond do
    # Primary: Better (lower) Pareto rank wins
    a.pareto_rank < b.pareto_rank -> :better
    a.pareto_rank > b.pareto_rank -> :worse

    # Tie-breaker: Higher crowding distance wins (more isolated)
    # Handle infinity correctly
    true -> compare_crowding_distance(a.crowding_distance, b.crowding_distance)
  end
end

defp compare_crowding_distance(:infinity, :infinity), do: :equal
defp compare_crowding_distance(:infinity, _), do: :better
defp compare_crowding_distance(_, :infinity), do: :worse
defp compare_crowding_distance(a_dist, b_dist) when a_dist > b_dist, do: :better
defp compare_crowding_distance(a_dist, b_dist) when a_dist < b_dist, do: :worse
defp compare_crowding_distance(_, _), do: :equal
```

**Tests**:
- Test rank-based selection (Front 1 beats Front 2)
- Test same-rank tie-breaking (higher distance wins)
- Test boundary solutions (infinite distance always wins tie)
- Test with missing ranks/distances (graceful degradation)

#### 2.2.1.3: Add Diversity-Aware Tournament Favoring Spread-Out Solutions

**Implementation**:

Already handled by crowding distance tie-breaking. When candidates have the same rank, higher crowding distance (more isolated) wins the tournament. This naturally favors spread-out solutions.

**Additional enhancement** (optional): Diversity-biased tournament

```elixir
@doc """
Selects candidate with diversity bias.

When `diversity_bias: true`, crowding distance weighs equally with rank
instead of being a tie-breaker. Useful when diversity is critical.
"""
def select_one(population, opts) do
  diversity_bias = Keyword.get(opts, :diversity_bias, false)

  if diversity_bias do
    diversity_biased_selection(population, opts)
  else
    standard_tournament_selection(population, opts)
  end
end

defp diversity_biased_compare(a, b) do
  # Normalize rank and distance to [0, 1], then combine
  # Score = 0.5 * (1 - normalized_rank) + 0.5 * normalized_distance
  score_a = calculate_combined_score(a)
  score_b = calculate_combined_score(b)

  cond do
    score_a > score_b -> :better
    score_a < score_b -> :worse
    true -> :equal
  end
end
```

**Tests**:
- Test standard tournament (rank > distance)
- Test diversity-biased tournament (rank ~ distance)
- Compare selection pressure between modes

#### 2.2.1.4: Support Adaptive Tournament Size Based on Population Diversity

**Implementation**:

```elixir
@doc """
Calculates adaptive tournament size based on population diversity.

Low diversity → Smaller tournaments → Weaker pressure → More exploration
High diversity → Larger tournaments → Stronger pressure → Faster convergence

## Arguments

- `population` - List of candidates
- `opts` - Options:
  - `:min_tournament_size` - Minimum size (default: 2)
  - `:max_tournament_size` - Maximum size (default: 7)
  - `:diversity_metric` - :crowding | :fitness_variance (default: :crowding)
"""
@spec adaptive_tournament_size(list(Candidate.t()), keyword()) :: pos_integer()
def adaptive_tournament_size(population, opts \\ [])

defp adaptive_tournament_size(population, opts) do
  min_size = Keyword.get(opts, :min_tournament_size, 2)
  max_size = Keyword.get(opts, :max_tournament_size, 7)

  # Calculate diversity metric
  diversity = calculate_population_diversity(population, opts)

  # Map diversity [0, 1] to tournament size [min, max]
  # Low diversity (0) → min_size (weak pressure)
  # High diversity (1) → max_size (strong pressure)
  size = min_size + (max_size - min_size) * diversity
  round(size)
end

defp calculate_population_diversity(population, opts) do
  metric = Keyword.get(opts, :diversity_metric, :crowding)

  case metric do
    :crowding ->
      # Average crowding distance (excluding infinity)
      # Normalize to [0, 1]
      average_crowding_distance(population)

    :fitness_variance ->
      # Coefficient of variation in fitness
      fitness_diversity(population)
  end
end
```

**Tests**:
- Test adaptive sizing with various diversity levels
- Test min/max bounds respected
- Test different diversity metrics produce sensible sizes
- Test integration with select_one/select_many

---

### Task 2.2.2: Crowding Distance Integration

**Objective**: Integrate existing crowding distance calculations into selection mechanisms.

**IMPORTANT**: This task does NOT reimplement crowding distance. It wraps and applies the existing `DominanceComparator.crowding_distance/2` function for selection purposes.

#### 2.2.2.1: Create Crowding Distance Calculator Integration Wrapper

**File**: `lib/jido_ai/runner/gepa/selection/crowding_distance_selector.ex`

**Implementation**:

```elixir
defmodule Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelector do
  @moduledoc """
  Integration wrapper for crowding distance in selection operations.

  This module provides convenience functions for using crowding distance
  (calculated by DominanceComparator) in various selection contexts:
  - Survivor selection (trim population while preserving diversity)
  - Elite selection (choose diverse elites)
  - Tournament tie-breaking (already handled by TournamentSelector)

  ## Note

  Crowding distance calculation is implemented in:
  `Jido.AI.Runner.GEPA.Pareto.DominanceComparator.crowding_distance/2`

  This module focuses on APPLYING that metric for selection.
  """

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate

  @doc """
  Updates population with crowding distances.

  Calculates crowding distance for each Pareto front separately,
  then assigns distances to candidate.crowding_distance field.

  ## Arguments

  - `population` - List of candidates with pareto_rank assigned
  - `opts` - Options (passed to DominanceComparator.crowding_distance/2)

  ## Returns

  - `{:ok, population}` - Population with crowding_distance assigned
  """
  @spec assign_crowding_distances(list(Candidate.t()), keyword()) ::
    {:ok, list(Candidate.t())}
  def assign_crowding_distances(population, opts \\ [])

  @doc """
  Selects candidates prioritizing higher crowding distance.

  Used for survivor selection when trimming population.
  Within each front, keeps candidates with highest crowding distance.

  ## Arguments

  - `population` - Candidates with pareto_rank and crowding_distance
  - `opts` - Options:
    - `:count` - Number of survivors to select (required)

  ## Returns

  - `{:ok, survivors}` - Selected candidates
  """
  @spec select_by_crowding_distance(list(Candidate.t()), keyword()) ::
    {:ok, list(Candidate.t())} | {:error, term()}
  def select_by_crowding_distance(population, opts)
end
```

**Key Functions**:
- `assign_crowding_distances/2`: Wrapper around `DominanceComparator.crowding_distance/2`
- `select_by_crowding_distance/2`: Survivor selection using distance

**Implementation Details**:

```elixir
def assign_crowding_distances(population, opts) do
  # Group by Pareto front
  fronts = Enum.group_by(population, & &1.pareto_rank)

  # Calculate crowding distance for each front separately
  population_with_distances =
    Enum.flat_map(fronts, fn {_rank, front_candidates} ->
      # Call existing DominanceComparator function
      distances = DominanceComparator.crowding_distance(front_candidates, opts)

      # Assign to candidate struct
      Enum.map(front_candidates, fn candidate ->
        distance = Map.get(distances, candidate.id, 0.0)
        %{candidate | crowding_distance: distance}
      end)
    end)

  {:ok, population_with_distances}
end

def select_by_crowding_distance(population, opts) do
  count = Keyword.fetch!(opts, :count)

  # Sort by (rank ASC, distance DESC)
  survivors =
    population
    |> Enum.sort_by(
      fn c -> {c.pareto_rank, negate_distance(c.crowding_distance)} end,
      :asc
    )
    |> Enum.take(count)

  {:ok, survivors}
end

# Helper: Handle infinity in sorting
defp negate_distance(:infinity), do: -999999999
defp negate_distance(dist), do: -dist
```

**Tests**: `test/jido_ai/runner/gepa/selection/crowding_distance_selector_test.exs`
- Test assign_crowding_distances calls DominanceComparator correctly
- Test select_by_crowding_distance preserves boundary solutions (infinity)
- Test select_by_crowding_distance respects Pareto rank priority
- Test integration with existing crowding distance calculations

#### 2.2.2.2: Implement Distance-Based Diversity Preservation in Selection

**Implementation**:

Already handled by `select_by_crowding_distance/2` above. This function is the primary distance-based diversity preservation mechanism.

**Additional**: Environmental selection (NSGA-II style)

```elixir
@doc """
Environmental selection: Combines parents and offspring, selects best N.

This is the NSGA-II survivor selection strategy:
1. Sort by Pareto rank (fronts)
2. Add fronts in order until next front would exceed N
3. From the cutoff front, select by crowding distance

## Arguments

- `combined_population` - Parents + offspring
- `target_size` - Desired population size

## Returns

- `{:ok, survivors}` - Selected population for next generation
"""
@spec environmental_selection(list(Candidate.t()), pos_integer()) ::
  {:ok, list(Candidate.t())}
def environmental_selection(combined_population, target_size)
```

**Tests**:
- Test environmental selection with various front distributions
- Test cutoff front trimming uses crowding distance
- Test boundary solutions preserved when trimming
- Test target size respected exactly

#### 2.2.2.3: Add Boundary Solution Protection Ensuring Extreme Objectives Represented

**Implementation**:

Already handled by existing crowding distance calculation!

From `DominanceComparator.crowding_distance/2`:
```elixir
# Boundary solutions (extreme values in any objective) receive infinite distance
```

This means boundary solutions:
- Always win tournament tie-breaks (infinite > any finite distance)
- Always survive environmental selection (infinite distance sorts first)
- Never trimmed from population (highest priority)

**Enhancement**: Explicit boundary detection helper

```elixir
@doc """
Identifies boundary solutions with extreme objective values.

A candidate is a boundary solution if it has the minimum or maximum
value in ANY objective across the population.

## Returns

List of candidate IDs that are boundary solutions.
"""
@spec identify_boundary_solutions(list(Candidate.t())) :: list(String.t())
def identify_boundary_solutions(population)

defp identify_boundary_solutions(population) do
  # Get all objectives from first candidate
  objectives =
    population
    |> List.first()
    |> Map.get(:normalized_objectives, %{})
    |> Map.keys()

  # For each objective, find min and max candidates
  boundary_ids =
    Enum.flat_map(objectives, fn obj ->
      candidates_by_obj = Enum.sort_by(population, & &1.normalized_objectives[obj])
      min_candidate = List.first(candidates_by_obj)
      max_candidate = List.last(candidates_by_obj)

      [min_candidate.id, max_candidate.id]
    end)
    |> Enum.uniq()

  boundary_ids
end
```

**Tests**:
- Test boundary detection identifies min/max for each objective
- Test boundary solutions have infinite crowding distance
- Test boundary solutions never eliminated in selection
- Test with 2, 3, 4 objectives

#### 2.2.2.4: Support Normalization Preventing Objective Scale Bias

**Implementation**:

Already handled! From Section 2.1.1 (Multi-Objective Evaluation):
- Raw objectives stored in `candidate.objectives`
- **Normalized objectives** stored in `candidate.normalized_objectives`
- Normalization to [0, 1] with min-max scaling

Crowding distance operates on `normalized_objectives`, so scale bias already prevented.

**Verification test**:

```elixir
test "crowding distance uses normalized objectives, preventing scale bias" do
  # Create candidates with vastly different objective scales
  # Accuracy: [0.85, 0.90, 0.95] (scale: 0.10)
  # Latency: [100ms, 500ms, 1000ms] (scale: 900ms)

  # Without normalization, latency would dominate crowding distance
  # With normalization, both objectives contribute equally

  population = create_multi_scale_population()
  {:ok, pop_with_distances} = CrowdingDistanceSelector.assign_crowding_distances(population)

  # Verify distances reflect spread in BOTH objectives, not just large-scale one
  assert_balanced_crowding_contribution(pop_with_distances)
end
```

**Tests**:
- Test crowding distance with vastly different objective scales
- Test normalized vs. raw objectives produce different (correct) distances
- Test all objectives contribute to distance calculation

---

### Task 2.2.3: Elite Preservation

**Objective**: Implement elitism ensuring best solutions survive across generations.

#### 2.2.3.1: Create Elite Selector Preserving Top K Solutions

**File**: `lib/jido_ai/runner/gepa/selection/elite_selector.ex`

**Implementation**:

```elixir
defmodule Jido.AI.Runner.GEPA.Selection.EliteSelector do
  @moduledoc """
  Elite preservation for GEPA multi-objective optimization.

  Ensures that the best solutions found are never lost during evolution.
  Elite selection prioritizes:
  1. Pareto rank (Front 1 > Front 2 > ...)
  2. Crowding distance (diverse > clustered)

  ## Elitism Benefits

  - **Monotonic improvement**: Best fitness never decreases
  - **Convergence guarantee**: Optimization cannot regress
  - **Safety net**: Protects discoveries from mutation damage
  - **Efficiency**: Preserves expensive evaluations

  ## Elite Ratio Guidelines

  - Too low (<5%): Risk losing good solutions to mutation
  - Balanced (10-20%): Standard recommendation
  - Too high (>30%): Reduced exploration, slower improvement

  ## Usage

      # Select elites for next generation
      {:ok, elites} = EliteSelector.select_elites(population, elite_ratio: 0.15)

      # Get all Pareto-optimal solutions
      {:ok, pareto_optimal} = EliteSelector.select_pareto_front_1(population)
  """

  alias Jido.AI.Runner.GEPA.Pareto.DominanceComparator
  alias Jido.AI.Runner.GEPA.Population.Candidate
  alias Jido.AI.Runner.GEPA.Selection.CrowdingDistanceSelector

  @default_elite_ratio 0.15  # 15% of population

  @doc """
  Selects elite candidates for preservation.

  ## Arguments

  - `population` - List of candidates with pareto_rank and crowding_distance
  - `opts` - Options:
    - `:elite_ratio` - Fraction of population to preserve (default: 0.15)
    - `:elite_count` - Absolute count to preserve (overrides ratio)
    - `:min_elites` - Minimum number to preserve (default: 1)

  ## Returns

  - `{:ok, elites}` - List of elite candidates
  """
  @spec select_elites(list(Candidate.t()), keyword()) ::
    {:ok, list(Candidate.t())} | {:error, term()}
  def select_elites(population, opts \\ [])

  @doc """
  Selects all Pareto Front 1 (non-dominated) solutions.

  ## Returns

  - `{:ok, front_1}` - List of non-dominated candidates
  """
  @spec select_pareto_front_1(list(Candidate.t())) :: {:ok, list(Candidate.t())}
  def select_pareto_front_1(population)

  # Private helpers
  defp calculate_elite_count(population_size, opts)
  defp select_by_rank_and_distance(population, count)
end
```

**Key Functions**:
- `select_elites/2`: Main elite selection function
- `select_pareto_front_1/1`: Get all non-dominated solutions
- `calculate_elite_count/2`: Compute how many elites to preserve
- `select_by_rank_and_distance/2`: Pick top K by (rank, distance)

**Implementation Details**:

```elixir
def select_elites(population, opts) do
  elite_count = calculate_elite_count(length(population), opts)

  # Ensure pareto_rank and crowding_distance are assigned
  population_with_metrics = ensure_selection_metrics(population)

  # Select top elite_count by (rank ASC, distance DESC)
  elites = select_by_rank_and_distance(population_with_metrics, elite_count)

  {:ok, elites}
end

defp calculate_elite_count(population_size, opts) do
  cond do
    Keyword.has_key?(opts, :elite_count) ->
      Keyword.get(opts, :elite_count)

    Keyword.has_key?(opts, :elite_ratio) ->
      ratio = Keyword.get(opts, :elite_ratio)
      max(1, round(population_size * ratio))

    true ->
      max(1, round(population_size * @default_elite_ratio))
  end
end

defp select_by_rank_and_distance(population, count) do
  population
  |> Enum.sort_by(
    fn c -> {c.pareto_rank, negate_distance(c.crowding_distance)} end,
    :asc
  )
  |> Enum.take(count)
end

def select_pareto_front_1(population) do
  # Perform non-dominated sorting if needed
  fronts = DominanceComparator.fast_non_dominated_sort(population)
  front_1 = Map.get(fronts, 1, [])

  {:ok, front_1}
end
```

**Tests**: `test/jido_ai/runner/gepa/selection/elite_selector_test.exs`
- Test elite selection with various ratios (0.05, 0.15, 0.30)
- Test elite_count overrides elite_ratio
- Test min_elites constraint
- Test all Front 1 included when elite_count >= |Front 1|
- Test diversity when selecting from multiple fronts
- Test edge cases (empty population, elite_count > population)

#### 2.2.3.2: Implement Pareto-Based Elitism Maintaining Frontier

**Implementation**:

Already handled by `select_pareto_front_1/1` above. This function ensures all non-dominated solutions are identified and prioritized.

**Enhancement**: Frontier-preserving elitism strategy

```elixir
@doc """
Selects elites with frontier preservation guarantee.

Ensures all Pareto Front 1 members are preserved, then fills
remaining elite slots with Front 2 (prioritizing high crowding distance).

This strategy guarantees the Pareto frontier never degrades.

## Arguments

- `population` - Candidates with metrics
- `opts` - Options:
  - `:elite_count` - Total elites to select

## Returns

- `{:ok, elites}` - All Front 1 + diverse Front 2/3/... up to elite_count
"""
@spec select_elites_preserve_frontier(list(Candidate.t()), keyword()) ::
  {:ok, list(Candidate.t())}
def select_elites_preserve_frontier(population, opts)

defp select_elites_preserve_frontier(population, opts) do
  elite_count = Keyword.fetch!(opts, :elite_count)

  # Get all fronts
  fronts = DominanceComparator.fast_non_dominated_sort(population)

  # Always include all of Front 1
  front_1 = Map.get(fronts, 1, [])

  if length(front_1) >= elite_count do
    # Front 1 fills or exceeds elite quota
    # Trim Front 1 by crowding distance if needed
    elites = select_diverse_subset(front_1, elite_count)
    {:ok, elites}
  else
    # Include all Front 1, fill remaining from Front 2+
    remaining = elite_count - length(front_1)
    lower_fronts = get_lower_fronts(fronts, starting_from: 2)

    additional_elites =
      lower_fronts
      |> select_by_rank_and_distance(remaining)

    {:ok, front_1 ++ additional_elites}
  end
end
```

**Tests**:
- Test all Front 1 always included (even if > elite_count)
- Test Front 2 filling uses crowding distance
- Test frontier never degrades across generations
- Test with various front size distributions

#### 2.2.3.3: Add Diversity-Preserving Elitism Preventing Duplicate Elites

**Implementation**:

```elixir
@doc """
Selects diverse elites, avoiding duplicates.

When multiple candidates have identical objectives, selects only one
to preserve elite diversity. Prioritizes by:
1. Pareto rank
2. Crowding distance
3. Earlier generation (older = more validated)

## Arguments

- `population` - Candidates
- `opts` - Options:
  - `:elite_count` - Number to select
  - `:similarity_threshold` - Objective distance threshold (default: 0.01)

## Returns

- `{:ok, diverse_elites}` - Elites with no near-duplicates
"""
@spec select_diverse_elites(list(Candidate.t()), keyword()) ::
  {:ok, list(Candidate.t())}
def select_diverse_elites(population, opts)

defp select_diverse_elites(population, opts) do
  elite_count = Keyword.fetch!(opts, :elite_count)
  similarity_threshold = Keyword.get(opts, :similarity_threshold, 0.01)

  # Sort by (rank, distance, generation)
  sorted =
    population
    |> Enum.sort_by(fn c ->
      {c.pareto_rank, negate_distance(c.crowding_distance), c.generation}
    end, :asc)

  # Greedily select elites, skipping similar ones
  selected =
    Enum.reduce(sorted, [], fn candidate, acc ->
      if length(acc) >= elite_count do
        acc  # Quota filled
      else
        # Check if candidate is too similar to any already selected
        if is_diverse?(candidate, acc, similarity_threshold) do
          [candidate | acc]
        else
          acc  # Skip duplicate
        end
      end
    end)
    |> Enum.reverse()

  {:ok, selected}
end

defp is_diverse?(candidate, selected_elites, threshold) do
  Enum.all?(selected_elites, fn elite ->
    objective_distance(candidate, elite) > threshold
  end)
end

defp objective_distance(candidate_a, candidate_b) do
  # Euclidean distance in normalized objective space
  objectives = Map.keys(candidate_a.normalized_objectives)

  squared_diffs =
    Enum.map(objectives, fn obj ->
      a_val = candidate_a.normalized_objectives[obj]
      b_val = candidate_b.normalized_objectives[obj]
      (a_val - b_val) ** 2
    end)

  :math.sqrt(Enum.sum(squared_diffs))
end
```

**Tests**:
- Test duplicate detection in objective space
- Test similarity threshold tuning (strict vs. relaxed)
- Test diverse elite selection vs. standard (fewer duplicates)
- Test with identical candidates (different IDs, same objectives)

#### 2.2.3.4: Support Configurable Elite Ratio Balancing Preservation and Exploration

**Implementation**:

Already handled by `calculate_elite_count/2` function above, which supports:
- `:elite_ratio` - Fraction-based (0.0 to 1.0)
- `:elite_count` - Absolute count
- `:min_elites` - Floor constraint

**Enhancement**: Adaptive elite ratio

```elixir
@doc """
Calculates adaptive elite ratio based on optimization progress.

Early generations: Low elite ratio (more exploration)
Late generations: High elite ratio (preserve good solutions)

## Arguments

- `population` - Current population
- `opts` - Options:
  - `:current_generation` - Current generation number
  - `:max_generations` - Total generations planned
  - `:min_ratio` - Minimum elite ratio (default: 0.05)
  - `:max_ratio` - Maximum elite ratio (default: 0.30)

## Returns

Adaptive elite ratio in [min_ratio, max_ratio]
"""
@spec adaptive_elite_ratio(list(Candidate.t()), keyword()) :: float()
def adaptive_elite_ratio(population, opts)

defp adaptive_elite_ratio(_population, opts) do
  current_gen = Keyword.fetch!(opts, :current_generation)
  max_gen = Keyword.fetch!(opts, :max_generations)
  min_ratio = Keyword.get(opts, :min_ratio, 0.05)
  max_ratio = Keyword.get(opts, :max_ratio, 0.30)

  # Progress: 0.0 (start) to 1.0 (end)
  progress = current_gen / max_gen

  # Linearly increase elite ratio with progress
  ratio = min_ratio + (max_ratio - min_ratio) * progress

  ratio
end
```

**Tests**:
- Test various elite ratios (5%, 15%, 30%)
- Test adaptive ratio increases with generation
- Test min/max ratio bounds respected
- Test exploration/exploitation balance (low ratio early, high ratio late)

---

### Task 2.2.4: Fitness Sharing

**Objective**: Implement fitness sharing to penalize similar solutions and promote diversity.

#### 2.2.4.1: Create Fitness Sharing Mechanism Penalizing Similar Solutions

**File**: `lib/jido_ai/runner/gepa/selection/fitness_sharing.ex`

**Implementation**:

```elixir
defmodule Jido.AI.Runner.GEPA.Selection.FitnessSharing do
  @moduledoc """
  Fitness sharing for GEPA multi-objective optimization.

  Fitness sharing penalizes solutions in crowded regions of objective space,
  promoting diversity and niche formation. Each candidate's fitness is divided
  by its "niche count" - the number of similar solutions nearby.

  ## Mechanism

  Shared fitness: f_shared(i) = f_raw(i) / niche_count(i)

  Niche count: Sum of sharing function over all other solutions

  Sharing function: sh(distance) =
    - 1 - (distance / niche_radius)^α   if distance < niche_radius
    - 0                                  otherwise

  Where:
  - distance: Euclidean distance in normalized objective space
  - niche_radius: Similarity threshold
  - α: Sharing slope (typically 1 or 2)

  ## Effects

  - Crowded solutions: High niche count → low shared fitness → less likely selected
  - Isolated solutions: Low niche count → high shared fitness → more likely selected
  - Promotes speciation: Stable subpopulations in different niches

  ## Usage

      # Apply fitness sharing to population
      {:ok, shared_pop} = FitnessSharing.apply_sharing(population, niche_radius: 0.1)

      # Calculate niche count for a candidate
      count = FitnessSharing.niche_count(candidate, population, niche_radius: 0.1)
  """

  alias Jido.AI.Runner.GEPA.Population.Candidate

  @default_niche_radius 0.1
  @default_sharing_alpha 1.0

  @doc """
  Applies fitness sharing to population.

  Calculates niche counts and shared fitness for all candidates.
  Updates candidate.fitness to shared_fitness for selection.

  ## Arguments

  - `population` - Candidates with normalized_objectives and fitness
  - `opts` - Options:
    - `:niche_radius` - Similarity threshold (default: 0.1)
    - `:sharing_alpha` - Sharing slope (default: 1.0)
    - `:preserve_raw_fitness` - Store original fitness in metadata (default: true)

  ## Returns

  - `{:ok, population}` - Candidates with shared fitness
  """
  @spec apply_sharing(list(Candidate.t()), keyword()) :: {:ok, list(Candidate.t())}
  def apply_sharing(population, opts \\ [])

  @doc """
  Calculates niche count for a candidate.

  Sums sharing function over all other candidates in population.

  ## Returns

  Float >= 1.0 (at minimum, candidate shares niche with itself = 1.0)
  """
  @spec niche_count(Candidate.t(), list(Candidate.t()), keyword()) :: float()
  def niche_count(candidate, population, opts \\ [])

  # Private helpers
  defp sharing_function(distance, niche_radius, alpha)
  defp objective_distance(candidate_a, candidate_b)
end
```

**Key Functions**:
- `apply_sharing/2`: Main function applying fitness sharing
- `niche_count/3`: Calculate similarity-based niche count
- `sharing_function/3`: Triangular sharing function
- `objective_distance/2`: Euclidean distance in objective space

**Implementation Details**:

```elixir
def apply_sharing(population, opts) do
  niche_radius = Keyword.get(opts, :niche_radius, @default_niche_radius)
  sharing_alpha = Keyword.get(opts, :sharing_alpha, @default_sharing_alpha)
  preserve_raw = Keyword.get(opts, :preserve_raw_fitness, true)

  shared_population =
    Enum.map(population, fn candidate ->
      # Calculate niche count
      nc = niche_count(candidate, population,
        niche_radius: niche_radius, sharing_alpha: sharing_alpha)

      # Calculate shared fitness
      raw_fitness = candidate.fitness || 0.0
      shared_fitness = raw_fitness / nc

      # Update candidate
      metadata =
        if preserve_raw do
          Map.put(candidate.metadata, :raw_fitness, raw_fitness)
          |> Map.put(:niche_count, nc)
        else
          candidate.metadata
        end

      %{candidate | fitness: shared_fitness, metadata: metadata}
    end)

  {:ok, shared_population}
end

def niche_count(candidate, population, opts) do
  niche_radius = Keyword.get(opts, :niche_radius, @default_niche_radius)
  sharing_alpha = Keyword.get(opts, :sharing_alpha, @default_sharing_alpha)

  population
  |> Enum.map(fn other ->
    distance = objective_distance(candidate, other)
    sharing_function(distance, niche_radius, sharing_alpha)
  end)
  |> Enum.sum()
end

defp sharing_function(distance, niche_radius, alpha) do
  if distance < niche_radius do
    1.0 - :math.pow(distance / niche_radius, alpha)
  else
    0.0
  end
end

defp objective_distance(candidate_a, candidate_b) do
  objectives = Map.keys(candidate_a.normalized_objectives)

  squared_diffs =
    Enum.map(objectives, fn obj ->
      a_val = candidate_a.normalized_objectives[obj]
      b_val = candidate_b.normalized_objectives[obj]
      (a_val - b_val) ** 2
    end)

  :math.sqrt(Enum.sum(squared_diffs))
end
```

**Tests**: `test/jido_ai/runner/gepa/selection/fitness_sharing_test.exs`
- Test sharing reduces fitness of clustered solutions
- Test isolated solutions maintain high fitness
- Test niche count calculation (self = 1.0 minimum)
- Test sharing function (linear, quadratic)
- Test raw fitness preservation in metadata

#### 2.2.4.2: Implement Niche Radius Calculation Controlling Sharing Intensity

**Implementation**:

```elixir
@doc """
Calculates appropriate niche radius for population.

Niche radius controls sharing intensity:
- Small radius: Only very similar solutions share fitness (weak diversity pressure)
- Large radius: Many solutions share fitness (strong diversity pressure)

## Strategies

- `:fixed` - Use provided radius
- `:population_based` - Based on population size (larger pop = smaller radius)
- `:objective_range` - Fraction of objective space diagonal (default: 0.1)
- `:adaptive` - Based on population diversity

## Arguments

- `population` - Current population
- `opts` - Options:
  - `:strategy` - Calculation strategy (default: :objective_range)
  - `:radius` - For :fixed strategy
  - `:fraction` - For :objective_range strategy (default: 0.1)

## Returns

Calculated niche radius (float > 0)
"""
@spec calculate_niche_radius(list(Candidate.t()), keyword()) :: float()
def calculate_niche_radius(population, opts \\ [])

defp calculate_niche_radius(population, opts) do
  strategy = Keyword.get(opts, :strategy, :objective_range)

  case strategy do
    :fixed ->
      Keyword.get(opts, :radius, @default_niche_radius)

    :population_based ->
      # Larger populations need smaller radius to maintain niches
      # radius = base_radius / sqrt(population_size)
      base = Keyword.get(opts, :base_radius, 0.3)
      base / :math.sqrt(length(population))

    :objective_range ->
      # Fraction of objective space diagonal
      fraction = Keyword.get(opts, :fraction, 0.1)
      objective_space_diagonal(population) * fraction

    :adaptive ->
      # Based on current diversity (low diversity → larger radius)
      adaptive_niche_radius(population, opts)
  end
end

defp objective_space_diagonal(population) do
  # Calculate diagonal of bounding box in normalized objective space
  objectives =
    population
    |> List.first()
    |> Map.get(:normalized_objectives, %{})
    |> Map.keys()

  # For normalized objectives in [0, 1], diagonal = sqrt(num_objectives)
  :math.sqrt(length(objectives))
end

defp adaptive_niche_radius(population, opts) do
  # Calculate average pairwise distance
  avg_distance = average_pairwise_distance(population)

  # Adjust radius based on diversity
  # High avg_distance → good diversity → small radius (maintain)
  # Low avg_distance → poor diversity → large radius (spread out)
  target_diversity = Keyword.get(opts, :target_diversity, 0.3)

  if avg_distance < target_diversity do
    # Low diversity: increase radius to spread population
    avg_distance * 1.5
  else
    # Good diversity: moderate radius to maintain
    avg_distance * 0.5
  end
end
```

**Tests**:
- Test fixed radius strategy
- Test population-based scaling (larger pop → smaller radius)
- Test objective-range strategy (fraction of space diagonal)
- Test adaptive strategy responds to diversity
- Test reasonable radius values (not too small/large)

#### 2.2.4.3: Add Adaptive Sharing Adjusting to Population Diversity

**Implementation**:

Already covered by `adaptive_niche_radius/2` above, which adjusts radius based on population diversity.

**Additional enhancement**: Dynamic sharing activation

```elixir
@doc """
Conditionally applies fitness sharing based on diversity state.

Only applies sharing when diversity is below threshold, to avoid
unnecessary computation when population is already diverse.

## Arguments

- `population` - Current population
- `opts` - Options:
  - `:diversity_threshold` - Apply sharing if diversity < this (default: 0.3)
  - `:diversity_metric` - :crowding | :pairwise_distance (default: :crowding)

## Returns

- `{:ok, population}` - With sharing applied if needed
- `{:ok, population, :skipped}` - Sharing skipped (already diverse)
"""
@spec adaptive_apply_sharing(list(Candidate.t()), keyword()) ::
  {:ok, list(Candidate.t())} | {:ok, list(Candidate.t()), :skipped}
def adaptive_apply_sharing(population, opts)

defp adaptive_apply_sharing(population, opts) do
  threshold = Keyword.get(opts, :diversity_threshold, 0.3)
  current_diversity = calculate_diversity(population, opts)

  if current_diversity < threshold do
    # Low diversity: apply sharing
    apply_sharing(population, opts)
  else
    # Already diverse: skip sharing
    {:ok, population, :skipped}
  end
end
```

**Tests**:
- Test sharing applied when diversity low
- Test sharing skipped when diversity high
- Test threshold tuning
- Test integration with adaptive radius

#### 2.2.4.4: Support Objective-Specific Sharing for Targeted Diversity

**Implementation**:

```elixir
@doc """
Applies fitness sharing on specific objectives only.

Useful when diversity is needed in some objectives but not others.
For example, maintain cost diversity but allow convergence in accuracy.

## Arguments

- `population` - Current population
- `opts` - Options:
  - `:sharing_objectives` - List of objectives to use for distance (required)
  - `:niche_radius` - Similarity threshold

## Returns

- `{:ok, population}` - With objective-specific sharing applied

## Example

    # Only maintain diversity in cost and latency, allow accuracy convergence
    FitnessSharing.apply_sharing(population,
      sharing_objectives: [:cost, :latency],
      niche_radius: 0.1
    )
"""
@spec apply_objective_specific_sharing(list(Candidate.t()), keyword()) ::
  {:ok, list(Candidate.t())}
def apply_objective_specific_sharing(population, opts)

defp objective_distance_subset(candidate_a, candidate_b, objectives) do
  # Calculate distance using only specified objectives
  squared_diffs =
    Enum.map(objectives, fn obj ->
      a_val = candidate_a.normalized_objectives[obj]
      b_val = candidate_b.normalized_objectives[obj]
      (a_val - b_val) ** 2
    end)

  :math.sqrt(Enum.sum(squared_diffs))
end
```

**Tests**:
- Test objective-specific distance calculation
- Test sharing on subset of objectives
- Test diversity increases in targeted objectives only
- Test with different objective combinations

---

## Testing Strategy

### Unit Tests by Task

**Task 2.2.1: Tournament Selection**
- File: `test/jido_ai/runner/gepa/selection/tournament_selector_test.exs`
- Coverage: ~40 tests
- Focus: Selection correctness, pressure tuning, diversity awareness

**Task 2.2.2: Crowding Distance Integration**
- File: `test/jido_ai/runner/gepa/selection/crowding_distance_selector_test.exs`
- Coverage: ~25 tests
- Focus: Integration with DominanceComparator, boundary protection

**Task 2.2.3: Elite Preservation**
- File: `test/jido_ai/runner/gepa/selection/elite_selector_test.exs`
- Coverage: ~30 tests
- Focus: Elite ratios, frontier preservation, diversity

**Task 2.2.4: Fitness Sharing**
- File: `test/jido_ai/runner/gepa/selection/fitness_sharing_test.exs`
- Coverage: ~35 tests
- Focus: Niche formation, radius calculation, adaptive sharing

### Integration Tests

**File**: `test/jido_ai/runner/gepa/integration/selection_integration_test.exs`

**Test scenarios**:

1. **Full Selection Cycle**
   - Evaluate population → rank + crowding → select elites + tournament → next gen
   - Verify population quality improves
   - Verify diversity maintained

2. **Multi-Objective Trade-off Discovery**
   - Population with accuracy/cost trade-offs
   - Selection maintains both high-accuracy and low-cost solutions
   - Pareto frontier preserved

3. **Diversity Maintenance Over Generations**
   - Run 50 generations
   - Track crowding distance over time
   - Verify diversity doesn't collapse

4. **Elite Preservation Correctness**
   - Track best solutions across generations
   - Verify best fitness never decreases
   - Verify Pareto Front 1 always preserved

5. **Fitness Sharing Effect**
   - Population with clusters
   - Fitness sharing applied
   - Verify clusters disperse over generations

### Performance Tests

**Benchmarks** (in `test/jido_ai/runner/gepa/selection/performance_test.exs`):

- Tournament selection: < 1ms for population of 100
- Crowding distance assignment: < 5ms for population of 100
- Elite selection: < 2ms for population of 100
- Fitness sharing: < 10ms for population of 100
- Full selection cycle: < 20ms for population of 100

### Property-Based Tests

Using StreamData:

```elixir
property "tournament selection pressure increases with tournament size" do
  check all population <- population_generator(size: 100),
            small_k <- integer(2..3),
            large_k <- integer(6..8) do

    # Run many tournaments, measure average rank
    small_k_avg_rank = average_selected_rank(population, small_k, runs: 100)
    large_k_avg_rank = average_selected_rank(population, large_k, runs: 100)

    # Larger tournaments should select better (lower) ranks on average
    assert large_k_avg_rank <= small_k_avg_rank
  end
end

property "elite preservation ensures monotonic improvement" do
  check all initial_pop <- population_generator() do
    generations =
      1..10
      |> Enum.reduce([initial_pop], fn _gen, [prev_pop | _] = acc ->
        next_pop = evolve_with_elitism(prev_pop)
        [next_pop | acc]
      end)
      |> Enum.reverse()

    # Best fitness should never decrease
    best_fitnesses = Enum.map(generations, &get_best_fitness/1)

    assert monotonically_non_decreasing?(best_fitnesses)
  end
end
```

---

## Success Criteria

### Functional Requirements

**Selection Mechanisms**:
- ✅ Tournament selection implemented with configurable size
- ✅ Crowding distance integrated from Section 2.1.2
- ✅ Elite preservation with configurable ratio
- ✅ Fitness sharing with adaptive radius

**Selection Correctness**:
- ✅ Tournament favors better Pareto ranks
- ✅ Ties broken by crowding distance (higher wins)
- ✅ Boundary solutions always preserved (infinite distance)
- ✅ Elites include all Front 1 members

**Diversity Maintenance**:
- ✅ Crowding distance promotes spread
- ✅ Fitness sharing penalizes clustering
- ✅ Population diversity doesn't collapse over 50+ generations
- ✅ Multiple niches maintained simultaneously

**Elite Preservation**:
- ✅ Best fitness never decreases across generations
- ✅ Pareto Front 1 always preserved
- ✅ Elite ratio configurable (5-30%)
- ✅ Diverse elites selected (high crowding distance)

### Performance Requirements

- ✅ Tournament selection: O(K) per parent, < 1ms for K=3, N=100
- ✅ Elite selection: O(N log N), < 2ms for N=100
- ✅ Fitness sharing: O(N²), < 10ms for N=100
- ✅ Full selection cycle: < 20ms for population of 100

### Quality Requirements

- ✅ 130+ unit tests (40+25+30+35)
- ✅ 5+ integration tests covering full selection cycle
- ✅ Property-based tests for selection pressure and monotonicity
- ✅ All tests passing (100% pass rate)
- ✅ Code coverage > 95% for selection modules

### Documentation Requirements

- ✅ Module documentation for all selection components
- ✅ Function documentation with examples
- ✅ Algorithm explanations (NSGA-II, fitness sharing)
- ✅ Configuration guidelines (tournament size, elite ratio, niche radius)
- ✅ Integration guide with Section 2.1

---

## Integration Notes

### Dependencies on Section 2.1

**Required from Section 2.1.1 (Multi-Objective Evaluation)**:
- `Candidate.objectives` - Raw objective values
- `Candidate.normalized_objectives` - Normalized to [0, 1]
- Multi-objective evaluation infrastructure

**Required from Section 2.1.2 (Dominance Computation)**:
- `DominanceComparator.compare/3` - Pareto dominance checking
- `DominanceComparator.fast_non_dominated_sort/1` - NSGA-II sorting
- `DominanceComparator.crowding_distance/2` - **Already implemented!**
- `Candidate.pareto_rank` - Front number (1, 2, 3, ...)
- `Candidate.crowding_distance` - Density metric

**Note**: Task 2.2.2 does NOT reimplement crowding distance. It integrates the existing implementation from Section 2.1.2.

### Integration with GEPA Optimizer

Selection mechanisms plug into the evolution cycle:

```elixir
# In GEPA Optimizer evolution loop

# 1. Evaluate population (Section 1.2)
evaluated_population = Evaluator.evaluate(population, tasks)

# 2. Assign Pareto ranks (Section 2.1.2)
fronts = DominanceComparator.fast_non_dominated_sort(evaluated_population)
population_with_ranks = assign_ranks_from_fronts(fronts)

# 3. Assign crowding distances (Section 2.1.2)
population_with_metrics = assign_crowding_distances(population_with_ranks)

# 4. Select elites (Section 2.2.3 - NEW)
{:ok, elites} = EliteSelector.select_elites(population_with_metrics, elite_ratio: 0.15)

# 5. Select parents via tournament (Section 2.2.1 - NEW)
{:ok, parents} = TournamentSelector.select_many(
  population_with_metrics,
  count: population_size - length(elites),
  tournament_size: 3
)

# 6. Reproduce (mutation/crossover) - Section 1.4
offspring = Reproducer.reproduce(parents)

# 7. Combine and select survivors (Section 2.2.2 - NEW)
combined = elites ++ offspring
{:ok, next_generation} = CrowdingDistanceSelector.environmental_selection(
  combined,
  population_size
)

# 8. Optional: Apply fitness sharing (Section 2.2.4 - NEW)
{:ok, next_generation_shared} = FitnessSharing.apply_sharing(
  next_generation,
  niche_radius: 0.1
)
```

### Configuration

**Selection configuration** (in GEPA Optimizer opts):

```elixir
selection_config = [
  # Tournament selection
  tournament_size: 3,              # 2-7 recommended
  adaptive_tournament: true,       # Adjust size based on diversity

  # Elite preservation
  elite_ratio: 0.15,               # 10-20% recommended
  elite_strategy: :frontier_preserving,  # Guarantee Front 1 survival

  # Fitness sharing
  enable_fitness_sharing: true,
  niche_radius: :adaptive,         # :adaptive | :fixed | float
  sharing_objectives: :all,        # :all | [:cost, :latency]

  # Diversity
  diversity_threshold: 0.3,        # Trigger diversity mechanisms if below
  boundary_protection: true        # Always preserve extreme solutions
]
```

### Migration Path

**For existing GEPA Stage 1 code**:

1. Section 2.1 already implemented (complete)
2. Add Section 2.2 modules (new code, no breaking changes)
3. Update Optimizer to use new selection mechanisms
4. Existing Stage 1 tests continue to pass
5. New Stage 2 tests validate multi-objective selection

**Backward compatibility**:
- Single-objective mode still supported (use fitness instead of pareto_rank)
- Stage 1 selection (simple fitness-based) can coexist with Stage 2
- Gradual migration: enable features incrementally

---

## References

### Academic Papers

1. **NSGA-II**: Deb et al. (2002) - "A Fast and Elitist Multiobjective Genetic Algorithm: NSGA-II"
   - Non-dominated sorting algorithm
   - Crowding distance for diversity
   - Tournament selection with crowded-comparison

2. **Fitness Sharing**: Goldberg & Richardson (1987) - "Genetic Algorithms with Sharing for Multimodal Function Optimization"
   - Niche formation and speciation
   - Sharing function design
   - Diversity maintenance

3. **Multi-Objective Optimization**: Coello Coello et al. (2007) - "Evolutionary Algorithms for Solving Multi-Objective Problems"
   - Survey of selection mechanisms
   - Diversity preservation techniques
   - Elite preservation strategies

### Implementation References

**Existing GEPA Code** (Section 2.1):
- `/lib/jido_ai/runner/gepa/pareto/dominance_comparator.ex` - Crowding distance implementation
- `/lib/jido_ai/runner/gepa/pareto/multi_objective_evaluator.ex` - Objective evaluation
- `/lib/jido_ai/runner/gepa/population/candidate.ex` - Multi-objective fields

**GEPA Paper**:
- Zhou et al. (2024) - "GEPA: Genetic Evolution Prompt Optimization"
- Sample-efficient prompt optimization
- LLM-guided reflection and mutation

### Elixir/OTP References

- GenServer patterns for stateful selection
- Enum/Stream for efficient population operations
- Property-based testing with StreamData

---

## Implementation Phases

### Phase 1: Tournament Selection (Task 2.2.1)
**Estimated effort**: 2 days
- Implement TournamentSelector module
- NSGA-II crowded-comparison operator
- Adaptive tournament sizing
- Unit tests (~40 tests)

### Phase 2: Crowding Distance Integration (Task 2.2.2)
**Estimated effort**: 1 day
- Implement CrowdingDistanceSelector wrapper
- Environmental selection
- Boundary protection verification
- Unit tests (~25 tests)

### Phase 3: Elite Preservation (Task 2.2.3)
**Estimated effort**: 1.5 days
- Implement EliteSelector module
- Frontier-preserving elitism
- Diverse elite selection
- Unit tests (~30 tests)

### Phase 4: Fitness Sharing (Task 2.2.4)
**Estimated effort**: 2 days
- Implement FitnessSharing module
- Adaptive niche radius calculation
- Objective-specific sharing
- Unit tests (~35 tests)

### Phase 5: Integration & Testing
**Estimated effort**: 1.5 days
- Integration tests (5+ scenarios)
- Performance benchmarks
- Property-based tests
- Documentation updates

**Total estimated effort**: 8 days

---

## Next Steps

After completing Section 2.2:

1. **Section 2.3: Convergence Detection**
   - Fitness plateau detection
   - Diversity monitoring
   - Hypervolume saturation
   - Early stopping

2. **Section 2.4: Integration Testing (Stage 2)**
   - Multi-objective optimization end-to-end
   - Performance benchmarks
   - Comparison with Stage 1 (single-objective)

3. **Stage 3: Advanced Optimization**
   - Novelty search
   - Historical learning
   - Adaptive mutation
   - Multi-task optimization

---

## Notes

### Design Decisions

**Why NSGA-II over other multi-objective algorithms?**
- Industry standard (10,000+ citations)
- Proven effective across domains
- Computationally efficient: O(MN²)
- Crowding distance simple yet effective
- Well-suited to GEPA's prompt optimization domain

**Why fitness sharing in addition to crowding distance?**
- Complementary diversity mechanisms
- Crowding distance: spatial diversity in objective space
- Fitness sharing: niche protection and speciation
- Together provide robust diversity maintenance

**Why configurable elite ratio vs. fixed?**
- Different optimization phases need different preservation
- Early: Low elitism (explore)
- Late: High elitism (converge)
- Different tasks have different optimal ratios

### Edge Cases

**Empty populations**:
- All selection functions return `{:error, :empty_population}`

**Missing metrics** (no pareto_rank or crowding_distance):
- Tournament falls back to raw fitness comparison
- Elite selection triggers ranking/distance calculation

**All candidates identical**:
- Crowding distance = 0 for all (except boundaries)
- Tournament selection becomes random
- Fitness sharing heavily penalizes (niche_count = N)

**Very small populations** (N < 5):
- Tournament size capped at N-1
- Elite count capped at N/2
- Fitness sharing uses larger niche radius

### Performance Optimizations

**Tournament selection**:
- Use random sampling without sorting entire population: O(K) vs O(N log N)
- Parallelize tournaments for batch selection

**Crowding distance**:
- Already calculated in Section 2.1.2, just apply in selection
- Cache distances, recalculate only when population changes

**Fitness sharing**:
- Most expensive: O(N²) distance calculations
- Optimize: spatial indexing (KD-tree) for large populations
- Early termination: stop summing when clearly outside niche radius

**Elite selection**:
- Front 1 typically small (10-30), cheap to preserve
- Partial sorting: only sort enough to get top K

---

**End of Planning Document**
