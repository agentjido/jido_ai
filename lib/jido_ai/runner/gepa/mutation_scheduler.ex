defmodule Jido.AI.Runner.GEPA.MutationScheduler do
  @moduledoc """
  Adaptive mutation rate scheduling for GEPA optimization.

  The mutation scheduler controls mutation intensity based on optimization progress,
  balancing exploration (high mutation) and exploitation (low mutation) dynamically.
  Unlike static mutation rates, this scheduler adapts based on:

  - **Fitness improvement rates** - How quickly the population is improving
  - **Diversity metrics** - Current population diversity levels
  - **Generation progress** - Where we are in the optimization cycle
  - **Manual overrides** - User-specified mutation rates when needed

  ## Key Concepts

  - **Exploration**: High mutation rates to search new solution space regions
  - **Exploitation**: Low mutation rates to refine existing good solutions
  - **Adaptive Control**: Automatically switching between exploration/exploitation
  - **Progress Tracking**: Historical fitness trends inform scheduling decisions

  ## Scheduling Strategies

  - `:adaptive` - Automatically adjust based on progress (default)
  - `:linear_decay` - Linearly decrease mutation rate over generations
  - `:exponential_decay` - Exponentially decrease mutation rate
  - `:constant` - Fixed mutation rate throughout
  - `:manual` - User-specified rate with no adaptation

  ## Example

      # Initialize scheduler
      scheduler = MutationScheduler.new(strategy: :adaptive, base_rate: 0.2)

      # Update with fitness data and get current rate
      {:ok, rate, scheduler} = MutationScheduler.next_rate(
        scheduler,
        current_generation: 5,
        best_fitness: 0.85,
        avg_fitness: 0.75,
        diversity_metrics: diversity_metrics
      )

      # Manual override when needed
      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.3)
  """

  use TypedStruct
  require Logger

  @type strategy :: :adaptive | :linear_decay | :exponential_decay | :constant | :manual

  typedstruct module: SchedulerState do
    @moduledoc """
    State maintained by the mutation scheduler.

    ## Fields

    - `:strategy` - Current scheduling strategy
    - `:base_rate` - Base mutation rate (default: 0.15)
    - `:min_rate` - Minimum allowed mutation rate (default: 0.05)
    - `:max_rate` - Maximum allowed mutation rate (default: 0.5)
    - `:current_rate` - Current computed mutation rate
    - `:manual_rate` - User-specified override rate (nil = no override)
    - `:fitness_history` - Recent fitness values for trend analysis
    - `:improvement_threshold` - Fitness improvement to consider progress (default: 0.01)
    - `:stagnation_generations` - Generations without improvement before boosting exploration
    - `:metadata` - Additional scheduler state
    """

    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    field(:strategy, Jido.AI.Runner.GEPA.MutationScheduler.strategy(), default: :adaptive)
    field(:base_rate, float(), default: 0.15)
    field(:min_rate, float(), default: 0.05)
    field(:max_rate, float(), default: 0.5)
    field(:current_rate, float(), default: 0.15)
    field(:manual_rate, float() | nil, default: nil)
    field(:fitness_history, list({non_neg_integer(), float()}), default: [])
    field(:improvement_threshold, float(), default: 0.01)
    field(:stagnation_generations, non_neg_integer(), default: 0)
    field(:metadata, map(), default: %{})
  end

  @doc """
  Creates a new mutation scheduler with the specified configuration.

  ## Options

  - `:strategy` - Scheduling strategy (default: :adaptive)
  - `:base_rate` - Base mutation rate (default: 0.15)
  - `:min_rate` - Minimum mutation rate (default: 0.05)
  - `:max_rate` - Maximum mutation rate (default: 0.5)
  - `:improvement_threshold` - Fitness delta to consider improvement (default: 0.01)

  ## Examples

      scheduler = MutationScheduler.new()
      scheduler = MutationScheduler.new(strategy: :linear_decay, base_rate: 0.2)
  """
  @spec new(keyword()) :: SchedulerState.t()
  def new(opts \\ []) do
    %SchedulerState{
      strategy: Keyword.get(opts, :strategy, :adaptive),
      base_rate: Keyword.get(opts, :base_rate, 0.15),
      min_rate: Keyword.get(opts, :min_rate, 0.05),
      max_rate: Keyword.get(opts, :max_rate, 0.5),
      current_rate: Keyword.get(opts, :base_rate, 0.15),
      improvement_threshold: Keyword.get(opts, :improvement_threshold, 0.01),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  Computes the next mutation rate based on optimization progress.

  ## Parameters

  - `scheduler` - Current SchedulerState
  - `opts` - Context for rate computation:
    - `:current_generation` - Current generation number
    - `:max_generations` - Total generations planned
    - `:best_fitness` - Current best fitness in population
    - `:avg_fitness` - Current average fitness
    - `:diversity_metrics` - Optional DiversityMetrics for consideration

  ## Returns

  `{:ok, rate, updated_scheduler}` - New mutation rate and updated scheduler state

  ## Examples

      {:ok, rate, scheduler} = MutationScheduler.next_rate(
        scheduler,
        current_generation: 10,
        max_generations: 50,
        best_fitness: 0.85,
        avg_fitness: 0.75
      )
  """
  @spec next_rate(SchedulerState.t(), keyword()) :: {:ok, float(), SchedulerState.t()}
  def next_rate(%SchedulerState{} = scheduler, opts) do
    # If manual override is set, use it
    if scheduler.manual_rate do
      {:ok, scheduler.manual_rate, scheduler}
    else
      current_gen = Keyword.fetch!(opts, :current_generation)
      max_gen = Keyword.get(opts, :max_generations, 100)
      best_fitness = Keyword.fetch!(opts, :best_fitness)
      _avg_fitness = Keyword.get(opts, :avg_fitness, best_fitness)
      diversity_metrics = Keyword.get(opts, :diversity_metrics)

      # Update fitness history
      scheduler = update_fitness_history(scheduler, current_gen, best_fitness)

      # Compute rate based on strategy
      rate =
        case scheduler.strategy do
          :adaptive ->
            adaptive_rate(scheduler, current_gen, max_gen, diversity_metrics)

          :linear_decay ->
            linear_decay_rate(scheduler, current_gen, max_gen)

          :exponential_decay ->
            exponential_decay_rate(scheduler, current_gen, max_gen)

          :constant ->
            scheduler.base_rate

          :manual ->
            scheduler.manual_rate || scheduler.base_rate
        end

      # Clamp to min/max bounds
      rate = Float.round(clamp(rate, scheduler.min_rate, scheduler.max_rate), 3)

      # Update scheduler state
      scheduler = %{scheduler | current_rate: rate}

      {:ok, rate, scheduler}
    end
  end

  @doc """
  Sets a manual mutation rate override.

  When set, the scheduler will always return this rate regardless of
  optimization progress, until the override is cleared.

  ## Parameters

  - `scheduler` - Current SchedulerState
  - `rate` - Manual rate to set (must be between min_rate and max_rate)

  ## Returns

  Updated SchedulerState with manual rate set

  ## Examples

      scheduler = MutationScheduler.set_manual_rate(scheduler, 0.3)
      scheduler = MutationScheduler.set_manual_rate(scheduler, nil)  # Clear override
  """
  @spec set_manual_rate(SchedulerState.t(), float() | nil) :: SchedulerState.t()
  def set_manual_rate(%SchedulerState{} = scheduler, nil) do
    %{scheduler | manual_rate: nil, strategy: :adaptive}
  end

  def set_manual_rate(%SchedulerState{} = scheduler, rate) when is_float(rate) do
    clamped_rate = clamp(rate, scheduler.min_rate, scheduler.max_rate)

    if abs(clamped_rate - rate) > 0.001 do
      Logger.warning(
        "Manual rate #{rate} clamped to bounds [#{scheduler.min_rate}, #{scheduler.max_rate}] = #{clamped_rate}"
      )
    end

    %{scheduler | manual_rate: clamped_rate, strategy: :manual}
  end

  @doc """
  Gets the current mutation rate without updating scheduler state.

  ## Examples

      rate = MutationScheduler.current_rate(scheduler)
  """
  @spec current_rate(SchedulerState.t()) :: float()
  def current_rate(%SchedulerState{manual_rate: manual_rate, current_rate: current_rate}) do
    manual_rate || current_rate
  end

  @doc """
  Resets the scheduler to initial state while preserving configuration.

  Clears fitness history and stagnation tracking but keeps strategy and rate bounds.

  ## Examples

      scheduler = MutationScheduler.reset(scheduler)
  """
  @spec reset(SchedulerState.t()) :: SchedulerState.t()
  def reset(%SchedulerState{} = scheduler) do
    %{
      scheduler
      | current_rate: scheduler.base_rate,
        fitness_history: [],
        stagnation_generations: 0,
        manual_rate: nil
    }
  end

  # Private Functions

  defp update_fitness_history(scheduler, generation, fitness) do
    # Keep last 10 generations for trend analysis
    history = [{generation, fitness} | scheduler.fitness_history] |> Enum.take(10)

    # Check for stagnation
    stagnation_gens =
      if stagnating?(history, scheduler.improvement_threshold) do
        scheduler.stagnation_generations + 1
      else
        0
      end

    %{scheduler | fitness_history: history, stagnation_generations: stagnation_gens}
  end

  defp stagnating?(history, _threshold) when length(history) < 3, do: false

  defp stagnating?(history, threshold) do
    # Check if recent generations show little improvement
    recent = Enum.take(history, 5)
    fitness_values = Enum.map(recent, fn {_gen, fit} -> fit end)
    max_fit = Enum.max(fitness_values)
    min_fit = Enum.min(fitness_values)

    max_fit - min_fit < threshold
  end

  defp adaptive_rate(scheduler, current_gen, max_gen, diversity_metrics) do
    # Base rate starts high and decreases as we progress
    progress_ratio = current_gen / max(max_gen, 1)
    progress_factor = 1.0 - progress_ratio * 0.5

    # Stagnation factor - increase mutation if stagnating
    stagnation_factor =
      cond do
        scheduler.stagnation_generations >= 5 -> 2.0
        scheduler.stagnation_generations >= 3 -> 1.5
        true -> 1.0
      end

    # Diversity factor - increase mutation if low diversity
    diversity_factor =
      if diversity_metrics do
        case diversity_metrics.diversity_level do
          :critical -> 2.0
          :low -> 1.5
          :moderate -> 1.0
          :healthy -> 0.8
          :excellent -> 0.6
        end
      else
        1.0
      end

    # Improvement trend factor
    improvement_factor = improvement_trend_factor(scheduler.fitness_history)

    # Combine all factors
    scheduler.base_rate * progress_factor * stagnation_factor * diversity_factor *
      improvement_factor
  end

  defp improvement_trend_factor(history) when length(history) < 3, do: 1.0

  defp improvement_trend_factor(history) do
    # Calculate rate of improvement
    recent = Enum.take(history, 5)
    fitness_values = Enum.map(recent, fn {_gen, fit} -> fit end) |> Enum.reverse()

    if length(fitness_values) >= 2 do
      improvements =
        fitness_values
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [a, b] -> b - a end)

      avg_improvement = Enum.sum(improvements) / length(improvements)

      cond do
        # Rapid improvement - reduce exploration
        avg_improvement > 0.05 -> 0.7
        # Moderate improvement - maintain
        avg_improvement > 0.01 -> 1.0
        # Slow improvement - increase exploration
        avg_improvement > 0.0 -> 1.3
        # No improvement - boost exploration
        true -> 1.6
      end
    else
      1.0
    end
  end

  defp linear_decay_rate(scheduler, current_gen, max_gen) do
    progress = current_gen / max(max_gen, 1)
    scheduler.max_rate - (scheduler.max_rate - scheduler.min_rate) * progress
  end

  defp exponential_decay_rate(scheduler, current_gen, max_gen) do
    progress = current_gen / max(max_gen, 1)
    decay_rate = 3.0

    scheduler.min_rate +
      (scheduler.max_rate - scheduler.min_rate) * :math.exp(-decay_rate * progress)
  end

  defp clamp(value, min_val, max_val) do
    value
    |> max(min_val)
    |> min(max_val)
  end
end
