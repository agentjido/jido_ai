defmodule Jido.AI.Runner.GEPA.Convergence.Detector do
  @moduledoc """
  Coordinates all convergence detection mechanisms for robust optimization termination.

  Integrates multiple convergence criteria to provide comprehensive detection:
  - Fitness plateau detection (no improvement in best/mean fitness)
  - Diversity monitoring (population variance collapse)
  - Hypervolume saturation (Pareto frontier growth stagnation)
  - Budget management (resource exhaustion)

  Uses multi-criteria approach where convergence is declared when ANY criterion
  triggers, providing robust early stopping while avoiding premature termination.

  ## Detection Strategy

  1. **Parallel Checking**: All four detectors run independently each generation
  2. **Individual Thresholds**: Each detector has its own configurable criteria
  3. **Patience Mechanisms**: Require sustained condition before declaring convergence
  4. **OR Logic**: Convergence when ANY detector triggers (fitness OR diversity OR hypervolume OR budget)

  ## Configuration

  Configuration options for each detector can be passed as keyword lists:
  - `:plateau_opts` - Options for PlateauDetector
  - `:diversity_opts` - Options for DiversityMonitor
  - `:hypervolume_opts` - Options for HypervolumeTracker
  - `:budget_opts` - Options for BudgetManager

  ## Example

      iex> detector = Detector.new(
      ...>   plateau_opts: [patience: 5],
      ...>   diversity_opts: [critical_threshold: 0.15],
      ...>   hypervolume_opts: [patience: 3],
      ...>   budget_opts: [max_evaluations: 1000]
      ...> )
      iex> detector = Detector.update(detector, metrics)
      iex> status = Detector.get_status(detector)
      iex> status.converged
      false
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Convergence.{
    BudgetManager,
    DiversityMonitor,
    HypervolumeTracker,
    PlateauDetector,
    Status
  }

  typedstruct do
    field(:plateau_detector, PlateauDetector.t(), enforce: true)
    field(:diversity_monitor, DiversityMonitor.t(), enforce: true)
    field(:hypervolume_tracker, HypervolumeTracker.t(), enforce: true)
    field(:budget_manager, BudgetManager.t(), enforce: true)
    field(:current_generation, non_neg_integer(), default: 0)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates a new convergence detector with given configuration.

  ## Options

  - `:plateau_opts` - Keyword list for PlateauDetector.new/1
  - `:diversity_opts` - Keyword list for DiversityMonitor.new/1
  - `:hypervolume_opts` - Keyword list for HypervolumeTracker.new/1
  - `:budget_opts` - Keyword list for BudgetManager.new/1

  ## Examples

      iex> detector = Detector.new()
      %Detector{}

      iex> detector = Detector.new(
      ...>   plateau_opts: [patience: 10],
      ...>   budget_opts: [max_evaluations: 500]
      ...> )
      %Detector{}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      plateau_detector: PlateauDetector.new(Keyword.get(opts, :plateau_opts, [])),
      diversity_monitor: DiversityMonitor.new(Keyword.get(opts, :diversity_opts, [])),
      hypervolume_tracker: HypervolumeTracker.new(Keyword.get(opts, :hypervolume_opts, [])),
      budget_manager: BudgetManager.new(Keyword.get(opts, :budget_opts, [])),
      config: Map.new(opts)
    }
  end

  @doc """
  Updates all detectors with metrics from the current generation.

  ## Parameters

  - `detector` - Current detector state
  - `metrics` - Map containing metrics for the generation:
    - `:fitness_record` - For PlateauDetector (FitnessRecord or map)
    - `:diversity_metrics` - For DiversityMonitor (DiversityMetrics or map)
    - `:hypervolume` - For HypervolumeTracker (float or map)
    - `:consumption` - For BudgetManager (keyword list)

  ## Returns

  Updated detector with all components updated

  ## Examples

      iex> detector = Detector.new()
      iex> metrics = %{
      ...>   fitness_record: %{generation: 1, best_fitness: 0.8, mean_fitness: 0.7},
      ...>   diversity_metrics: %{generation: 1, pairwise_diversity: 0.65, diversity_level: :healthy},
      ...>   hypervolume: 0.75,
      ...>   consumption: [evaluations: 50, cost: 1.25]
      ...> }
      iex> detector = Detector.update(detector, metrics)
      %Detector{}
  """
  @spec update(t(), map()) :: t()
  def update(%__MODULE__{} = detector, metrics) do
    # Update each component independently
    plateau_detector =
      if Map.has_key?(metrics, :fitness_record) do
        PlateauDetector.update(detector.plateau_detector, metrics.fitness_record)
      else
        detector.plateau_detector
      end

    diversity_monitor =
      if Map.has_key?(metrics, :diversity_metrics) do
        DiversityMonitor.update(detector.diversity_monitor, metrics.diversity_metrics)
      else
        detector.diversity_monitor
      end

    hypervolume_tracker =
      if Map.has_key?(metrics, :hypervolume) do
        HypervolumeTracker.update(detector.hypervolume_tracker, metrics.hypervolume)
      else
        detector.hypervolume_tracker
      end

    budget_manager =
      if Map.has_key?(metrics, :consumption) do
        BudgetManager.record_consumption(detector.budget_manager, metrics.consumption)
      else
        detector.budget_manager
      end

    # Increment generation
    generation =
      max(
        detector.current_generation + 1,
        Map.get(metrics, :generation, detector.current_generation + 1)
      )

    %{
      detector
      | plateau_detector: plateau_detector,
        diversity_monitor: diversity_monitor,
        hypervolume_tracker: hypervolume_tracker,
        budget_manager: budget_manager,
        current_generation: generation
    }
  end

  @doc """
  Returns the current convergence status.

  Aggregates statuses from all four detectors and determines overall convergence.

  ## Examples

      iex> detector = Detector.new()
      iex> status = Detector.get_status(detector)
      iex> status.converged
      false
  """
  @spec get_status(t()) :: Status.t()
  def get_status(%__MODULE__{} = detector) do
    # Get individual statuses
    plateau_detected = PlateauDetector.plateau_detected?(detector.plateau_detector)
    diversity_collapsed = DiversityMonitor.diversity_collapsed?(detector.diversity_monitor)
    hypervolume_saturated = HypervolumeTracker.saturated?(detector.hypervolume_tracker)
    budget_exhausted = BudgetManager.budget_exhausted?(detector.budget_manager)

    # Determine overall convergence (ANY criterion triggers)
    converged =
      plateau_detected or
        diversity_collapsed or
        hypervolume_saturated or
        budget_exhausted

    # Determine primary reason (priority: budget > plateau > diversity > hypervolume)
    reason =
      cond do
        budget_exhausted -> :budget_exhausted
        plateau_detected -> :fitness_plateau
        diversity_collapsed -> :diversity_collapse
        hypervolume_saturated -> :hypervolume_saturation
        true -> nil
      end

    # Determine status level
    status_level =
      cond do
        converged -> :converged
        plateau_detected or diversity_collapsed or hypervolume_saturated -> :warning
        true -> :running
      end

    # Collect warnings
    warnings = collect_warnings(detector)

    # Get detailed metrics
    plateau_generations = detector.plateau_detector.patience_counter
    diversity_score = DiversityMonitor.get_current_diversity(detector.diversity_monitor)

    hypervolume_improvement =
      HypervolumeTracker.get_recent_improvement(detector.hypervolume_tracker)

    budget_remaining = BudgetManager.remaining_evaluations(detector.budget_manager)

    %Status{
      converged: converged,
      status_level: status_level,
      reason: reason,
      should_stop: converged,
      warnings: warnings,
      plateau_detected: plateau_detected,
      plateau_generations: plateau_generations,
      diversity_collapsed: diversity_collapsed,
      diversity_score: diversity_score,
      hypervolume_saturated: hypervolume_saturated,
      hypervolume_improvement: hypervolume_improvement,
      budget_exhausted: budget_exhausted,
      budget_remaining: budget_remaining,
      metadata: %{
        generation: detector.current_generation,
        plateau_patience: detector.plateau_detector.patience_counter,
        diversity_trend: DiversityMonitor.get_trend(detector.diversity_monitor)
      }
    }
  end

  @doc """
  Checks if convergence has been detected.

  ## Examples

      iex> detector = Detector.new()
      iex> Detector.converged?(detector)
      false
  """
  @spec converged?(t()) :: boolean()
  def converged?(%__MODULE__{} = detector) do
    get_status(detector).converged
  end

  @doc """
  Resets all detectors, clearing history and counters.

  ## Examples

      iex> detector = Detector.new()
      iex> detector = Detector.update(detector, metrics)
      iex> detector = Detector.reset(detector)
      iex> detector.current_generation
      0
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = detector) do
    %{
      detector
      | plateau_detector: PlateauDetector.reset(detector.plateau_detector),
        diversity_monitor: DiversityMonitor.reset(detector.diversity_monitor),
        hypervolume_tracker: HypervolumeTracker.reset(detector.hypervolume_tracker),
        budget_manager: BudgetManager.reset(detector.budget_manager),
        current_generation: 0
    }
  end

  # Private functions

  defp collect_warnings(detector) do
    warnings = []

    # Check for early warnings before full convergence
    warnings =
      if DiversityMonitor.in_warning_zone?(detector.diversity_monitor) do
        ["Diversity below warning threshold" | warnings]
      else
        warnings
      end

    warnings =
      if detector.plateau_detector.patience_counter > 0 and
           not PlateauDetector.plateau_detected?(detector.plateau_detector) do
        patience_ratio =
          detector.plateau_detector.patience_counter / detector.plateau_detector.patience

        if patience_ratio >= 0.5 do
          [
            "Approaching fitness plateau (#{detector.plateau_detector.patience_counter}/#{detector.plateau_detector.patience})"
            | warnings
          ]
        else
          warnings
        end
      else
        warnings
      end

    warnings =
      if detector.hypervolume_tracker.patience_counter > 0 and
           not HypervolumeTracker.saturated?(detector.hypervolume_tracker) do
        patience_ratio =
          detector.hypervolume_tracker.patience_counter / detector.hypervolume_tracker.patience

        if patience_ratio >= 0.5 do
          [
            "Approaching hypervolume saturation (#{detector.hypervolume_tracker.patience_counter}/#{detector.hypervolume_tracker.patience})"
            | warnings
          ]
        else
          warnings
        end
      else
        warnings
      end

    warnings =
      case BudgetManager.remaining_evaluations(detector.budget_manager) do
        :unlimited ->
          warnings

        remaining when is_integer(remaining) ->
          max_evals = detector.budget_manager.max_evaluations

          if max_evals > 0 do
            usage_ratio = 1.0 - remaining / max_evals

            if usage_ratio >= 0.8 do
              ["Budget 80% consumed (#{remaining} evaluations remaining)" | warnings]
            else
              warnings
            end
          else
            warnings
          end

        _ ->
          warnings
      end

    Enum.reverse(warnings)
  end
end
