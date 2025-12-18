# GEPA Section 2.3: Convergence Detection - Implementation Plan

**Status**: Planning
**Phase**: 5 (GEPA Optimization)
**Stage**: 2 (Evolution & Selection)
**Date Created**: 2025-10-28
**Last Updated**: 2025-10-28

## Table of Contents

1. [Problem Statement](#problem-statement)
2. [Solution Overview](#solution-overview)
3. [Agent Consultations Performed](#agent-consultations-performed)
4. [Technical Details](#technical-details)
5. [Success Criteria](#success-criteria)
6. [Implementation Plan](#implementation-plan)
7. [Notes/Considerations](#notesconsiderations)

---

## Problem Statement

### Current State

Section 2.1 (Pareto Frontier Management) and Section 2.2 (Selection Mechanisms) provide the infrastructure for multi-objective evolutionary optimization:

**Section 2.1 (Complete)**:
- Multi-objective evaluation across accuracy, latency, cost, and robustness
- Dominance computation with NSGA-II fast non-dominated sorting
- Frontier maintenance with non-dominated solution sets
- Hypervolume calculation for frontier quality measurement

**Section 2.2 (Complete)**:
- Tournament selection for parent selection
- Crowding distance integration for diversity preservation
- Elite preservation ensuring best solutions never lost
- Fitness sharing promoting niche formation

However, **we currently lack mechanisms to detect when optimization has converged** and should terminate. Without proper convergence detection:

### Problems

**Problem 1: Wasted Computational Resources**
- Optimization continues long after improvements have plateaued
- Expensive LLM evaluations perform redundant work
- No signal to stop when diminishing returns reached
- Budget exhausted on marginal or zero gains
- Example: Running 100 generations when convergence at generation 40

**Problem 2: No Early Stopping**
- Cannot automatically terminate when objectives satisfied
- Manual intervention required to stop optimization
- No detection of stagnation or fitness plateaus
- Optimization may run until max_generations exhausted
- Wastes time on tasks that have already converged

**Problem 3: Inability to Detect Diversity Collapse**
- Population may lose diversity silently
- Premature convergence to suboptimal regions undetected
- No warning when exploration has stopped
- Cannot trigger diversity restoration mechanisms
- Results in homogeneous populations with limited trade-off options

**Problem 4: No Hypervolume Saturation Detection**
- Cannot detect when Pareto frontier has stopped improving
- No measure of frontier growth rate over time
- Cannot distinguish between:
  - Slow but steady improvement (continue optimization)
  - True saturation (stop optimization)
- Hypervolume already calculated but not tracked for convergence

**Problem 5: No Budget Enforcement**
- Evaluation budgets can be exceeded
- No tracking of evaluation consumption rate
- Cannot adapt optimization to budget constraints
- No cost-aware termination criteria
- May exhaust API quotas or exceed cost limits

### Why Convergence Detection?

Convergence detection is **critical for sample-efficient optimization**, enabling:

1. **Resource Efficiency**: Stop when further iterations provide minimal benefit
2. **Cost Control**: Enforce evaluation budgets and prevent overruns
3. **Automatic Termination**: No manual monitoring required
4. **Quality Assurance**: Detect problematic convergence (diversity loss, local optima)
5. **Adaptive Control**: Trigger interventions before complete convergence

**Key Insight from GEPA Research**: GEPA achieves **35× fewer evaluations than RL methods** by detecting convergence early and stopping before wasteful exploration.

### What Does "Converged" Mean?

An optimization has converged when one or more criteria are met:

1. **Fitness Plateau**: No significant improvement in objective values across N generations
2. **Diversity Collapse**: Population variance below threshold (premature convergence)
3. **Hypervolume Saturation**: Pareto frontier growth rate near zero
4. **Budget Exhaustion**: Evaluation limit or cost budget reached
5. **Target Achievement**: Specific objective thresholds met

Multiple criteria provide robust convergence detection, preventing both premature and delayed termination.

---

## Solution Overview

### High-Level Approach

Implement four complementary convergence detection mechanisms that work together to determine when optimization should terminate:

```
┌─────────────────────────────────────────────────────────────────┐
│                  GEPA Convergence Detection System               │
│                                                                   │
│  Input: Population history, frontier evolution, evaluation costs │
│  Output: Convergence status and termination recommendation       │
│                                                                   │
│  ┌────────────────────────────────────────────────────────────┐  │
│  │      Task 2.3.1: Fitness Plateau Detection                 │  │
│  │  • Track fitness changes across generations                │  │
│  │  • Statistical significance testing (t-test, Mann-Whitney) │  │
│  │  • Patience mechanism (allow temporary plateaus)           │  │
│  │  • Multi-objective plateau detection (all objectives)      │  │
│  └─────────────────────┬──────────────────────────────────────┘  │
│                        │ Plateau Status                           │
│  ┌─────────────────────▼──────────────────────────────────────┐  │
│  │       Task 2.3.2: Diversity Monitoring                     │  │
│  │  • Track population variance over time                     │  │
│  │  • Diversity threshold detection                           │  │
│  │  • Trend analysis predicting convergence                   │  │
│  │  • Early warning before complete collapse                  │  │
│  └─────────────────────┬──────────────────────────────────────┘  │
│                        │ Diversity Status                         │
│  ┌─────────────────────▼──────────────────────────────────────┐  │
│  │      Task 2.3.3: Hypervolume Saturation                   │  │
│  │  • Track hypervolume growth across generations            │  │
│  │  • Detect saturation (growth rate → 0)                    │  │
│  │  • Relative improvement thresholds                         │  │
│  │  • Theoretical maximum estimation                          │  │
│  └─────────────────────┬──────────────────────────────────────┘  │
│                        │ Hypervolume Status                       │
│  ┌─────────────────────▼──────────────────────────────────────┐  │
│  │         Task 2.3.4: Budget Management                      │  │
│  │  • Track evaluation consumption                            │  │
│  │  • Budget-based termination at limits                      │  │
│  │  • Budget allocation per generation with carryover         │  │
│  │  • Cost-aware optimization adapting to constraints         │  │
│  └────────────────────────────────────────────────────────────┘  │
│                        ↓                                          │
│            Convergence Decision & Termination Signal             │
└─────────────────────────────────────────────────────────────────┘
```

### Key Concepts

**1. Fitness Plateau Detection (Task 2.3.1)**

**How it works:**
- Track best, mean, and worst fitness across generations
- Compare recent generations (window) to previous baseline
- Statistical testing: Is improvement significant or noise?
- Patience counter: Allow N generations without improvement before declaring plateau

**Metrics:**
- Absolute improvement: `|fitness[t] - fitness[t-k]|`
- Relative improvement: `(fitness[t] - fitness[t-k]) / fitness[t-k]`
- Improvement rate: `Δfitness / Δgenerations`

**Example:**
```
Generation 1-10: Fitness 0.50 → 0.75 (25% improvement) ✓ Continue
Generation 11-20: Fitness 0.75 → 0.78 (4% improvement) ✓ Continue
Generation 21-30: Fitness 0.78 → 0.785 (0.6% improvement) ⚠ Plateau warning
Generation 31-40: Fitness 0.785 → 0.786 (0.1% improvement) ✗ Plateau detected
```

**2. Diversity Monitoring (Task 2.3.2)**

**How it works:**
- Calculate population diversity metrics each generation
- Track diversity trend: increasing, stable, or decreasing
- Detect when diversity falls below critical threshold
- Predict convergence before complete diversity loss

**Metrics (from existing `Diversity.Metrics` module)**:
- Pairwise diversity: Average distance between candidates
- Entropy: Information-theoretic measure of variety
- Clustering coefficient: Proportion in dense clusters
- Convergence risk: Composite risk score

**Example:**
```
Generation 1: Diversity 0.85 (excellent) ✓ Healthy
Generation 10: Diversity 0.65 (healthy) ✓ Acceptable
Generation 20: Diversity 0.35 (moderate) ⚠ Declining
Generation 30: Diversity 0.15 (critical) ✗ Collapse detected
```

**3. Hypervolume Saturation (Task 2.3.3)**

**How it works:**
- Track hypervolume of Pareto frontier each generation
- Calculate hypervolume improvement rate
- Detect saturation when growth rate approaches zero
- Compare to theoretical maximum (if known)

**Metrics (using existing `HypervolumeCalculator`)**:
- Absolute hypervolume: `HV[t]`
- Hypervolume improvement: `HV[t] - HV[t-1]`
- Improvement rate: `(HV[t] - HV[t-k]) / k`
- Relative improvement: `(HV[t] - HV[t-1]) / HV[t-1]`

**Example:**
```
Generation 1-10: HV 0.50 → 0.70 (+40%) ✓ Strong growth
Generation 11-20: HV 0.70 → 0.82 (+17%) ✓ Moderate growth
Generation 21-30: HV 0.82 → 0.86 (+5%) ⚠ Slowing
Generation 31-40: HV 0.86 → 0.862 (+0.2%) ✗ Saturated
```

**4. Budget Management (Task 2.3.4)**

**How it works:**
- Track evaluation count and costs consumed
- Allocate budget per generation with optional carryover
- Terminate when budget exhausted
- Adapt optimization strategy to remaining budget

**Budget Types:**
- Evaluation count: Fixed number of prompt evaluations
- Cost budget: Dollar limit on LLM API calls
- Time budget: Maximum optimization duration
- Generation limit: Maximum number of generations

**Example:**
```
Budget: 1000 evaluations, 50 generations

Generation 1-10: 200 evals (20%), 40% budget/generation → On track
Generation 11-20: 350 evals (35%), 35% budget/generation → On track
Generation 21-30: 550 evals (55%), 20% budget/generation → Slowing
Generation 31-40: 850 evals (85%), 30% budget/generation → Budget warning
Generation 41-48: 1000 evals (100%) ✗ Budget exhausted
```

### Integration with Existing Infrastructure

**Section 2.1 Provides:**
- `HypervolumeCalculator.calculate/2` - Frontier quality metric
- `HypervolumeCalculator.improvement/3` - Generation-over-generation comparison
- `DominanceComparator.fast_non_dominated_sort/1` - Pareto front identification

**Section 2.2 Provides:**
- Elite preservation tracking best fitness
- Diversity metrics from selection

**Section 1.4 Provides:**
- `Diversity.Metrics` module - Existing diversity calculation

**Section 2.3 Adds:**
- Temporal tracking of all metrics
- Convergence criteria evaluation
- Early stopping signals
- Budget enforcement

---

## Agent Consultations Performed

### Consultation 1: Elixir OTP Patterns for Metric Tracking

**Question**: What's the best Elixir/OTP pattern for tracking optimization metrics over time? Should I use GenServer state, ETS, or another approach?

**Recommendation**:
- **GenServer state** for lightweight tracking (last N generations)
- Store history in optimizer state: `%{generation_history: [], hypervolume_history: [], diversity_history: []}`
- Circular buffer implementation to bound memory (keep last 50-100 generations)
- Periodic snapshots to avoid memory growth
- ETS only if sharing across multiple processes or very large history needed

**Pattern**:
```elixir
defmodule Jido.AI.Runner.GEPA.ConvergenceTracker do
  use GenServer

  @max_history_size 100

  def init(opts) do
    state = %{
      generation_history: CircularBuffer.new(@max_history_size),
      hypervolume_history: CircularBuffer.new(@max_history_size),
      diversity_history: CircularBuffer.new(@max_history_size),
      config: Keyword.get(opts, :convergence_config, %{})
    }
    {:ok, state}
  end

  def handle_call({:record_generation, metrics}, _from, state) do
    # Update circular buffers
    state = update_history(state, metrics)

    # Check convergence criteria
    status = check_convergence(state)

    {:reply, status, state}
  end
end
```

### Consultation 2: Statistical Tests for Plateau Detection

**Question**: What statistical tests should I use to determine if fitness improvement is significant vs. random noise?

**Recommendation**:
- **Mann-Whitney U test** (non-parametric): No assumptions about distribution
- **t-test** (parametric): If fitness values approximately normal
- **Effect size** (Cohen's d): Measure practical significance, not just statistical
- **Moving average smoothing**: Reduce noise before testing
- Threshold-based: Improvement < ε considered plateau (ε = 0.01 or 1%)

**Implementation Approach**:
```elixir
# Compare recent window to baseline window
recent_fitness = get_fitness_window(generation - window_size, generation)
baseline_fitness = get_fitness_window(generation - 2*window_size, generation - window_size)

# Statistical test
p_value = mann_whitney_test(recent_fitness, baseline_fitness)
is_significant = p_value < 0.05

# Effect size
effect_size = cohens_d(recent_fitness, baseline_fitness)
is_meaningful = effect_size > 0.2  # Small effect

# Threshold test
improvement = mean(recent_fitness) - mean(baseline_fitness)
is_improving = improvement > threshold

converged = not is_significant or not is_meaningful or not is_improving
```

**Note**: Elixir doesn't have built-in statistical libraries. Options:
1. Implement simple versions of Mann-Whitney U and t-test
2. Use `:statistics` library if available
3. Focus on threshold-based detection (simpler, often sufficient)

### Consultation 3: Hypervolume Saturation Thresholds

**Question**: What are reasonable thresholds for detecting hypervolume saturation? How do I distinguish true saturation from slow-but-steady improvement?

**Recommendation**:
- **Absolute threshold**: Improvement < 0.01 (1% of current HV)
- **Relative threshold**: Improvement < 0.001 (0.1% relative)
- **Rate threshold**: Average improvement over last K generations < ε
- **Trend analysis**: Linear regression slope near zero
- **Patience**: Require N consecutive low-improvement generations

**Multi-criteria approach**:
```
Saturated IF:
  (improvement < 0.01 OR relative_improvement < 0.001) AND
  average_rate_last_10_gens < 0.005 AND
  patience_counter >= 5
```

**Adaptive thresholds**:
- Early generations: Higher threshold (rapid improvement expected)
- Late generations: Lower threshold (fine-tuning phase)
- Scale by population size and objective count

---

## Technical Details

### Module Structure

```
lib/jido_ai/runner/gepa/
├── convergence/
│   ├── plateau_detector.ex          # Task 2.3.1
│   ├── diversity_monitor.ex         # Task 2.3.2
│   ├── hypervolume_tracker.ex       # Task 2.3.3
│   ├── budget_manager.ex            # Task 2.3.4
│   └── convergence_coordinator.ex   # Orchestrates all detectors
├── convergence.ex                    # Public API
└── optimizer.ex                      # Integration point

test/jido_ai/runner/gepa/convergence/
├── plateau_detector_test.exs
├── diversity_monitor_test.exs
├── hypervolume_tracker_test.exs
├── budget_manager_test.exs
└── convergence_integration_test.exs
```

### Data Structures

**Convergence Status**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.Status do
  use TypedStruct

  typedstruct do
    field(:converged, boolean(), enforce: true)
    field(:reason, atom() | nil)  # :plateau | :diversity_collapse | :hypervolume_saturated | :budget_exhausted
    field(:should_stop, boolean(), enforce: true)
    field(:warnings, list(String.t()), default: [])

    field(:plateau_detected, boolean(), default: false)
    field(:plateau_generations, non_neg_integer(), default: 0)

    field(:diversity_collapsed, boolean(), default: false)
    field(:diversity_score, float() | nil)

    field(:hypervolume_saturated, boolean(), default: false)
    field(:hypervolume_improvement, float() | nil)

    field(:budget_exhausted, boolean(), default: false)
    field(:budget_remaining, float() | nil)

    field(:metadata, map(), default: %{})
  end
end
```

**Plateau Detector State**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.PlateauDetector do
  use TypedStruct

  typedstruct do
    field(:fitness_history, CircularBuffer.t(), enforce: true)
    # List of %{generation: int, best_fitness: float, mean_fitness: float, ...}

    field(:window_size, pos_integer(), default: 5)
    # Number of generations to compare

    field(:patience, pos_integer(), default: 5)
    # Generations to wait before declaring plateau

    field(:improvement_threshold, float(), default: 0.01)
    # Minimum improvement to avoid plateau (1%)

    field(:patience_counter, non_neg_integer(), default: 0)
    # Current patience count

    field(:plateau_detected, boolean(), default: false)

    field(:config, map(), default: %{})
  end
end
```

**Diversity Monitor State**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.DiversityMonitor do
  use TypedStruct

  typedstruct do
    field(:diversity_history, CircularBuffer.t(), enforce: true)
    # List of %{generation: int, pairwise_diversity: float, entropy: float, ...}

    field(:critical_threshold, float(), default: 0.15)
    field(:warning_threshold, float(), default: 0.25)

    field(:trend_window, pos_integer(), default: 10)
    # Generations for trend analysis

    field(:diversity_collapsed, boolean(), default: false)
    field(:trend, atom() | nil)  # :increasing | :stable | :decreasing

    field(:config, map(), default: %{})
  end
end
```

**Hypervolume Tracker State**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.HypervolumeTracker do
  use TypedStruct

  typedstruct do
    field(:hypervolume_history, CircularBuffer.t(), enforce: true)
    # List of %{generation: int, hypervolume: float}

    field(:window_size, pos_integer(), default: 5)
    field(:patience, pos_integer(), default: 5)

    field(:absolute_threshold, float(), default: 0.01)
    # Min absolute improvement

    field(:relative_threshold, float(), default: 0.001)
    # Min relative improvement (0.1%)

    field(:patience_counter, non_neg_integer(), default: 0)
    field(:saturated, boolean(), default: false)

    field(:config, map(), default: %{})
  end
end
```

**Budget Manager State**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.BudgetManager do
  use TypedStruct

  typedstruct do
    field(:max_evaluations, pos_integer() | nil)
    field(:evaluations_consumed, non_neg_integer(), default: 0)

    field(:max_cost, float() | nil)
    field(:cost_consumed, float(), default: 0.0)

    field(:max_generations, pos_integer() | nil)
    field(:current_generation, non_neg_integer(), default: 0)

    field(:budget_per_generation, pos_integer() | nil)
    field(:allow_carryover, boolean(), default: true)
    field(:carryover_balance, non_neg_integer(), default: 0)

    field(:budget_exhausted, boolean(), default: false)

    field(:config, map(), default: %{})
  end
end
```

### Algorithm Details

**Task 2.3.1: Plateau Detection Algorithm**

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.PlateauDetector do
  @doc """
  Check if fitness has plateaued.

  Compares recent generations to baseline using:
  1. Absolute improvement threshold
  2. Relative improvement threshold
  3. Statistical significance (optional)
  4. Patience mechanism
  """
  def check_plateau(detector, generation_metrics) do
    # Update history
    detector = add_to_history(detector, generation_metrics)

    # Need enough history
    if length(detector.fitness_history) < detector.window_size * 2 do
      {:ok, %{detector | plateau_detected: false}}
    else
      # Get recent and baseline windows
      recent = get_recent_window(detector)
      baseline = get_baseline_window(detector)

      # Calculate improvements
      recent_fitness = calculate_mean_fitness(recent)
      baseline_fitness = calculate_mean_fitness(baseline)

      absolute_improvement = recent_fitness - baseline_fitness
      relative_improvement =
        if baseline_fitness > 0,
          do: absolute_improvement / baseline_fitness,
          else: 0.0

      # Check if improving
      is_improving =
        absolute_improvement > detector.improvement_threshold or
        relative_improvement > detector.improvement_threshold

      # Update patience counter
      detector = if is_improving do
        %{detector | patience_counter: 0}
      else
        %{detector | patience_counter: detector.patience_counter + 1}
      end

      # Declare plateau if patience exhausted
      plateau_detected = detector.patience_counter >= detector.patience

      {:ok, %{detector | plateau_detected: plateau_detected}}
    end
  end

  defp get_recent_window(detector) do
    detector.fitness_history
    |> CircularBuffer.to_list()
    |> Enum.take(-detector.window_size)
  end

  defp get_baseline_window(detector) do
    all = CircularBuffer.to_list(detector.fitness_history)
    start_idx = -detector.window_size * 2
    end_idx = -detector.window_size - 1

    all
    |> Enum.slice(start_idx..end_idx)
  end
end
```

**Task 2.3.2: Diversity Trend Analysis**

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.DiversityMonitor do
  @doc """
  Analyzes diversity trend to predict convergence.

  Uses linear regression on recent diversity history to determine if:
  - :increasing - Diversity growing (healthy)
  - :stable - Diversity maintained (acceptable)
  - :decreasing - Diversity declining (warning)
  """
  def analyze_trend(monitor) do
    history = CircularBuffer.to_list(monitor.diversity_history)

    if length(history) < monitor.trend_window do
      {:ok, %{monitor | trend: :unknown}}
    else
      recent = Enum.take(history, -monitor.trend_window)

      # Linear regression
      slope = calculate_trend_slope(recent)

      trend = cond do
        slope > 0.01 -> :increasing
        slope < -0.01 -> :decreasing
        true -> :stable
      end

      {:ok, %{monitor | trend: trend}}
    end
  end

  defp calculate_trend_slope(points) do
    # points = [%{generation: g, pairwise_diversity: d}, ...]
    n = length(points)

    {sum_x, sum_y, sum_xy, sum_x2} =
      points
      |> Enum.with_index()
      |> Enum.reduce({0, 0.0, 0.0, 0}, fn {point, idx}, {sx, sy, sxy, sx2} ->
        x = idx
        y = point.pairwise_diversity
        {sx + x, sy + y, sxy + (x * y), sx2 + (x * x)}
      end)

    # Slope = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
    numerator = (n * sum_xy) - (sum_x * sum_y)
    denominator = (n * sum_x2) - (sum_x * sum_x)

    if denominator == 0, do: 0.0, else: numerator / denominator
  end
end
```

**Task 2.3.3: Hypervolume Saturation Detection**

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.HypervolumeTracker do
  @doc """
  Detects hypervolume saturation.

  Multi-criteria approach:
  1. Absolute improvement < threshold
  2. Relative improvement < threshold
  3. Average improvement rate over window < threshold
  4. Patience mechanism
  """
  def check_saturation(tracker, hypervolume) do
    # Update history
    entry = %{
      generation: tracker.current_generation,
      hypervolume: hypervolume
    }
    tracker = add_to_history(tracker, entry)

    if length(tracker.hypervolume_history) < tracker.window_size do
      {:ok, %{tracker | saturated: false}}
    else
      history = CircularBuffer.to_list(tracker.hypervolume_history)
      current = List.last(history).hypervolume
      previous = Enum.at(history, -2).hypervolume

      # Absolute improvement
      abs_improvement = current - previous

      # Relative improvement
      rel_improvement =
        if previous > 0,
          do: abs_improvement / previous,
          else: 0.0

      # Average improvement over window
      avg_improvement = calculate_average_improvement(history, tracker.window_size)

      # Check criteria
      is_saturated =
        abs_improvement < tracker.absolute_threshold and
        rel_improvement < tracker.relative_threshold and
        avg_improvement < tracker.absolute_threshold

      # Update patience
      tracker = if is_saturated do
        %{tracker | patience_counter: tracker.patience_counter + 1}
      else
        %{tracker | patience_counter: 0}
      end

      # Declare saturation if patience exhausted
      saturated = tracker.patience_counter >= tracker.patience

      {:ok, %{tracker | saturated: saturated}}
    end
  end

  defp calculate_average_improvement(history, window_size) do
    recent = Enum.take(history, -window_size)

    if length(recent) < 2 do
      0.0
    else
      improvements =
        recent
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, curr] ->
          curr.hypervolume - prev.hypervolume
        end)

      Enum.sum(improvements) / length(improvements)
    end
  end
end
```

**Task 2.3.4: Budget Management**

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.BudgetManager do
  @doc """
  Tracks budget consumption and enforces limits.

  Supports multiple budget types:
  - Evaluation count
  - Cost (dollars)
  - Generations
  - Per-generation allocation with carryover
  """
  def record_evaluations(manager, count, cost) do
    manager = %{manager |
      evaluations_consumed: manager.evaluations_consumed + count,
      cost_consumed: manager.cost_consumed + cost,
      current_generation: manager.current_generation + 1
    }

    # Check if any budget exhausted
    exhausted =
      (manager.max_evaluations && manager.evaluations_consumed >= manager.max_evaluations) or
      (manager.max_cost && manager.cost_consumed >= manager.max_cost) or
      (manager.max_generations && manager.current_generation >= manager.max_generations)

    {:ok, %{manager | budget_exhausted: exhausted}}
  end

  @doc """
  Calculates available budget for next generation.

  If per-generation budget set, returns allocation + carryover.
  """
  def available_budget(manager) do
    if manager.budget_per_generation do
      base = manager.budget_per_generation

      if manager.allow_carryover do
        base + manager.carryover_balance
      else
        base
      end
    else
      # No per-generation limit
      remaining_from_total(manager)
    end
  end

  defp remaining_from_total(manager) do
    cond do
      manager.max_evaluations ->
        manager.max_evaluations - manager.evaluations_consumed

      manager.max_cost ->
        (manager.max_cost - manager.cost_consumed) * 1000  # Convert to eval count estimate

      true ->
        :unlimited
    end
  end
end
```

---

## Success Criteria

### Functional Requirements

**Plateau Detection**:
- ✅ Tracks fitness history across generations
- ✅ Detects plateau using threshold-based and statistical tests
- ✅ Implements patience mechanism (N generations without improvement)
- ✅ Supports multi-objective plateau detection (all objectives)
- ✅ Provides early warning before complete stagnation

**Diversity Monitoring**:
- ✅ Calculates population diversity each generation
- ✅ Detects diversity below critical threshold
- ✅ Performs trend analysis predicting convergence
- ✅ Triggers early warning before complete collapse
- ✅ Integrates with existing `Diversity.Metrics` module

**Hypervolume Saturation**:
- ✅ Tracks hypervolume across generations
- ✅ Detects saturation when growth rate plateaus
- ✅ Uses relative improvement thresholds
- ✅ Estimates theoretical maximum (if possible)
- ✅ Multi-criteria saturation detection

**Budget Management**:
- ✅ Tracks evaluation consumption
- ✅ Enforces budget-based termination
- ✅ Supports per-generation allocation with carryover
- ✅ Adapts to budget constraints
- ✅ Multiple budget types (count, cost, time)

### Performance Requirements

- **Overhead**: Convergence checking < 5ms per generation
- **Memory**: Circular buffers bound history (max 100 generations)
- **Detection Latency**: Identify convergence within 3-5 generations of occurrence
- **False Positive Rate**: < 5% premature termination
- **False Negative Rate**: < 10% delayed termination

### Quality Requirements

- ✅ 120+ unit tests covering all detection mechanisms
- ✅ Integration tests with full optimization cycles
- ✅ Property-based tests for convergence invariants
- ✅ Edge case handling (empty history, single generation, etc.)
- ✅ Clear documentation of thresholds and configuration

---

## Implementation Plan

### Phase 1: Plateau Detection (Task 2.3.1)

**Estimated Time**: 2 days

**Sub-task 2.3.1.1: Create Improvement Tracker**

Implement tracking of fitness changes across generations.

```elixir
# lib/jido_ai/runner/gepa/convergence/plateau_detector.ex

defmodule Jido.AI.Runner.GEPA.Convergence.PlateauDetector do
  @moduledoc """
  Detects fitness improvement plateau indicating optimization convergence.
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.CircularBuffer

  typedstruct do
    field(:fitness_history, CircularBuffer.t(), enforce: true)
    field(:window_size, pos_integer(), default: 5)
    field(:patience, pos_integer(), default: 5)
    field(:improvement_threshold, float(), default: 0.01)
    field(:patience_counter, non_neg_integer(), default: 0)
    field(:plateau_detected, boolean(), default: false)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates new plateau detector.
  """
  def new(opts \\ []) do
    %__MODULE__{
      fitness_history: CircularBuffer.new(Keyword.get(opts, :history_size, 100)),
      window_size: Keyword.get(opts, :window_size, 5),
      patience: Keyword.get(opts, :patience, 5),
      improvement_threshold: Keyword.get(opts, :improvement_threshold, 0.01),
      config: Map.new(opts)
    }
  end

  @doc """
  Records generation fitness metrics.
  """
  def record_generation(detector, metrics) do
    entry = %{
      generation: metrics.generation,
      best_fitness: metrics.best_fitness,
      mean_fitness: metrics.mean_fitness,
      worst_fitness: metrics.worst_fitness,
      timestamp: System.monotonic_time(:millisecond)
    }

    history = CircularBuffer.insert(detector.fitness_history, entry)
    %{detector | fitness_history: history}
  end
end
```

**Sub-task 2.3.1.2: Implement Plateau Detection**

Statistical and threshold-based tests.

**Sub-task 2.3.1.3: Add Patience Mechanism**

Allow temporary plateaus before stopping.

**Sub-task 2.3.1.4: Multi-Objective Plateau Detection**

Detect plateau across all objectives.

**Tests** (~30 tests):
- Test threshold-based detection
- Test patience mechanism
- Test multi-objective plateau
- Test edge cases (insufficient history, etc.)

---

### Phase 2: Diversity Monitoring (Task 2.3.2)

**Estimated Time**: 1.5 days

**Sub-task 2.3.2.1: Create Diversity Metrics Tracker**

Track population variance over time.

**Sub-task 2.3.2.2: Implement Threshold Detection**

Detect when diversity falls below critical level.

**Sub-task 2.3.2.3: Add Trend Analysis**

Predict convergence using linear regression on diversity trend.

**Sub-task 2.3.2.4: Early Warning System**

Trigger warnings before complete collapse.

**Tests** (~25 tests):
- Test diversity tracking
- Test threshold detection
- Test trend analysis (increasing/decreasing)
- Test early warning triggers

---

### Phase 3: Hypervolume Saturation (Task 2.3.3)

**Estimated Time**: 2 days

**Sub-task 2.3.3.1: Create Hypervolume Tracker**

Monitor frontier growth across generations.

**Sub-task 2.3.3.2: Implement Saturation Detection**

Detect when growth rate plateaus.

**Sub-task 2.3.3.3: Add Relative Improvement Thresholds**

Use both absolute and relative thresholds.

**Sub-task 2.3.3.4: Theoretical Maximum Estimation**

Estimate max achievable hypervolume (if possible).

**Tests** (~30 tests):
- Test hypervolume tracking
- Test saturation detection
- Test relative vs absolute thresholds
- Test patience mechanism

---

### Phase 4: Budget Management (Task 2.3.4)

**Estimated Time**: 1.5 days

**Sub-task 2.3.4.1: Create Budget Tracker**

Monitor evaluation consumption.

**Sub-task 2.3.4.2: Implement Budget Termination**

Stop when limits reached.

**Sub-task 2.3.4.3: Add Per-Generation Allocation**

Support budget quotas with carryover.

**Sub-task 2.3.4.4: Cost-Aware Optimization**

Adapt strategy to remaining budget.

**Tests** (~25 tests):
- Test evaluation tracking
- Test budget enforcement
- Test per-generation allocation
- Test carryover mechanism

---

### Phase 5: Integration & Coordination

**Estimated Time**: 1.5 days

**Convergence Coordinator**:

```elixir
defmodule Jido.AI.Runner.GEPA.Convergence.Coordinator do
  @moduledoc """
  Coordinates all convergence detection mechanisms.
  """

  def check_convergence(state) do
    # Check all criteria
    plateau_status = PlateauDetector.check_plateau(state.plateau_detector, state.metrics)
    diversity_status = DiversityMonitor.check_diversity(state.diversity_monitor, state.population)
    hv_status = HypervolumeTracker.check_saturation(state.hv_tracker, state.hypervolume)
    budget_status = BudgetManager.check_budget(state.budget_manager)

    # Determine overall convergence
    converged =
      plateau_status.plateau_detected or
      diversity_status.diversity_collapsed or
      hv_status.saturated or
      budget_status.budget_exhausted

    reason = determine_reason(plateau_status, diversity_status, hv_status, budget_status)

    %Status{
      converged: converged,
      reason: reason,
      should_stop: converged,
      plateau_detected: plateau_status.plateau_detected,
      diversity_collapsed: diversity_status.diversity_collapsed,
      hypervolume_saturated: hv_status.saturated,
      budget_exhausted: budget_status.budget_exhausted
    }
  end
end
```

**Integration Tests** (~20 tests):
- End-to-end convergence detection
- Multiple criteria triggering simultaneously
- Early stopping effectiveness
- Integration with optimizer

**Total Estimated Time**: 8.5 days

---

## Notes/Considerations

### Design Decisions

**Why Multiple Convergence Criteria?**
- Single criterion can be misleading
- Plateau detection alone misses diversity loss
- Hypervolume alone doesn't catch budget overruns
- Multiple criteria provide robust detection

**Why Patience Mechanisms?**
- Prevent premature termination on temporary plateaus
- Allow exploration to recover from local stagnation
- Balance early stopping with thorough optimization
- Configurable patience for different optimization phases

**Why Circular Buffers for History?**
- Bound memory consumption
- O(1) insertion and retrieval
- Sufficient for convergence detection (last 50-100 generations)
- Simple implementation in Elixir

### Edge Cases

**Insufficient History**:
- Return `:unknown` status until minimum history accumulated
- Minimum: 2 × window_size generations
- Never declare convergence with < 10 generations

**Noisy Fitness**:
- Use smoothing (moving average) before comparison
- Increase window_size for noisy objectives
- Consider statistical tests (Mann-Whitney U)

**Multi-Modal Fitness**:
- Track multiple fitness metrics (best, mean, median)
- Require plateau in multiple metrics
- Consider worst-case fitness for robustness

**Budget Edge Cases**:
- Carryover across generations
- Generation uses less than allocated budget
- Cost estimation errors (actual cost vs predicted)

### Performance Optimizations

**Lazy Evaluation**:
- Only calculate metrics when needed
- Skip expensive statistical tests if threshold test passes
- Cache intermediate calculations

**Parallel Detection**:
- Run all four detectors concurrently
- Use Task.async_stream for parallel checking
- Aggregate results

**Memory Management**:
- Circular buffers prevent unbounded growth
- Periodic garbage collection of old history
- Store only essential metrics

### Integration Points

**With Optimizer**:
```elixir
# In GEPA Optimizer evolution loop

def handle_continue(:evolution_cycle, state) do
  # Evaluate population
  evaluated_population = evaluate(state.population)

  # Record metrics for convergence detection
  metrics = extract_metrics(evaluated_population)
  convergence_status = ConvergenceCoordinator.check_convergence(
    state.convergence_state,
    metrics
  )

  if convergence_status.should_stop do
    # Terminate optimization
    {:stop, :normal, finalize_results(state, convergence_status)}
  else
    # Continue evolution
    next_state = perform_selection_and_reproduction(state)
    {:noreply, next_state}
  end
end
```

**With Section 2.1 (Hypervolume)**:
- Use existing `HypervolumeCalculator.calculate/2`
- Track hypervolume each generation
- No changes to Section 2.1 code

**With Section 1.4 (Diversity)**:
- Use existing `Diversity.Metrics.calculate/2`
- Track diversity metrics each generation
- No changes to Section 1.4 code

### Configuration Guidelines

**Conservative (High Confidence)**:
```elixir
convergence_config: [
  # Plateau detection
  plateau_window_size: 10,
  plateau_patience: 10,
  plateau_threshold: 0.001,  # 0.1% improvement

  # Diversity
  diversity_critical_threshold: 0.10,
  diversity_warning_threshold: 0.20,

  # Hypervolume
  hv_patience: 10,
  hv_absolute_threshold: 0.005,
  hv_relative_threshold: 0.0005,

  # Budget
  max_evaluations: 5000,
  budget_per_generation: 100
]
```

**Aggressive (Early Stopping)**:
```elixir
convergence_config: [
  plateau_window_size: 5,
  plateau_patience: 3,
  plateau_threshold: 0.01,  # 1% improvement

  diversity_critical_threshold: 0.15,

  hv_patience: 3,
  hv_absolute_threshold: 0.01,

  max_evaluations: 1000
]
```

**Balanced (Recommended)**:
```elixir
convergence_config: [
  plateau_window_size: 5,
  plateau_patience: 5,
  plateau_threshold: 0.005,  # 0.5% improvement

  diversity_critical_threshold: 0.15,
  diversity_warning_threshold: 0.25,

  hv_patience: 5,
  hv_absolute_threshold: 0.01,
  hv_relative_threshold: 0.001,

  max_evaluations: 2000,
  budget_per_generation: 50,
  allow_carryover: true
]
```

### Expected Outcomes

After Section 2.3 implementation:

1. **Automatic Early Stopping**: 20-40% reduction in wasted evaluations
2. **Budget Enforcement**: 100% compliance with evaluation/cost limits
3. **Diversity Protection**: Early warning prevents 80%+ diversity collapses
4. **Sample Efficiency**: Contributing to GEPA's 35× advantage over RL
5. **User Confidence**: Clear convergence signals and termination reasons

---

## End of Planning Document
