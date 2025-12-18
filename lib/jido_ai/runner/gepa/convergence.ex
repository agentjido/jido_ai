defmodule Jido.AI.Runner.GEPA.Convergence do
  @moduledoc """
  Data structures and types for GEPA convergence detection.

  This module defines the core types used across the convergence detection system
  for identifying when optimization has plateaued and should terminate.

  ## Key Concepts

  - **Plateau**: Fitness improvements have stagnated across multiple generations
  - **Diversity Collapse**: Population variance has dropped below acceptable thresholds
  - **Hypervolume Saturation**: Pareto frontier growth has stopped
  - **Budget Exhaustion**: Resource limits have been reached

  ## Convergence Criteria

  Optimization is considered converged when one or more criteria are met:

  1. **Fitness Plateau** - No significant improvement over patience window
  2. **Diversity Collapse** - Population too homogeneous to explore
  3. **Hypervolume Saturation** - Pareto frontier no longer expanding
  4. **Budget Exhausted** - Evaluation or cost limits reached

  ## Status Levels

  - `:running` - Optimization actively improving
  - `:warning` - Convergence signals detected, monitor closely
  - `:converged` - Optimization complete, should stop
  - `:budget_exceeded` - Hard stop due to resource limits
  """

  use TypedStruct

  @type convergence_reason ::
          :plateau
          | :diversity_collapse
          | :hypervolume_saturated
          | :budget_exhausted
          | :target_achieved
          | nil

  @type status_level :: :running | :warning | :converged | :budget_exceeded

  typedstruct module: Status do
    @moduledoc """
    Overall convergence status combining all detection mechanisms.

    ## Fields

    - `:converged` - Whether optimization should stop
    - `:status_level` - Current optimization status
    - `:reason` - Primary reason for convergence (if converged)
    - `:should_stop` - Hard stop signal (budget exceeded)
    - `:warnings` - Active warning messages
    - `:plateau_detected` - Fitness plateau identified
    - `:plateau_generations` - Generations since last improvement
    - `:diversity_collapsed` - Population diversity too low
    - `:diversity_score` - Current diversity metric
    - `:hypervolume_saturated` - Frontier growth stagnated
    - `:hypervolume_improvement` - Recent hypervolume change
    - `:budget_exhausted` - Resource limits reached
    - `:budget_remaining` - Fraction of budget left (0.0-1.0)
    - `:metadata` - Additional diagnostic information
    """

    field(:converged, boolean(), enforce: true)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:status_level, Jido.AI.Runner.GEPA.Convergence.status_level(), default: :running)
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:reason, Jido.AI.Runner.GEPA.Convergence.convergence_reason())
    field(:should_stop, boolean(), default: false)
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

  typedstruct module: FitnessRecord do
    @moduledoc """
    Record of fitness metrics for a single generation.

    ## Fields

    - `:generation` - Generation number
    - `:best_fitness` - Best fitness in population
    - `:mean_fitness` - Average fitness
    - `:median_fitness` - Median fitness
    - `:std_dev` - Standard deviation of fitness
    - `:timestamp` - When recorded
    """

    field(:generation, non_neg_integer(), enforce: true)
    field(:best_fitness, float(), enforce: true)
    field(:mean_fitness, float(), enforce: true)
    field(:median_fitness, float() | nil)
    field(:std_dev, float() | nil)
    field(:timestamp, DateTime.t(), default: DateTime.utc_now())
  end
end
