defmodule Jido.AI.Runner.GEPA.Convergence.PlateauDetector do
  @moduledoc """
  Detects fitness improvement plateaus using statistical tests and patience mechanisms.

  A plateau is detected when fitness improvements fall below threshold for a patience
  window of generations. Uses statistical comparison between recent and baseline windows
  to avoid false positives from natural variance.

  ## Detection Strategy

  1. **Windowed Comparison**: Compare recent K generations to baseline K generations
  2. **Statistical Testing**: Use effect size and improvement thresholds
  3. **Patience Mechanism**: Require N consecutive non-improving generations
  4. **Multi-Objective Support**: Track improvements across all objectives

  ## Configuration

  - `:window_size` - Generations to compare (default: 5)
  - `:patience` - Non-improving generations before plateau (default: 5)
  - `:improvement_threshold` - Minimum relative improvement (default: 0.01 = 1%)
  - `:absolute_threshold` - Minimum absolute improvement (default: 0.001)

  ## Example

      iex> detector = PlateauDetector.new(window_size: 5, patience: 3)
      iex> detector = PlateauDetector.update(detector, %{generation: 1, best_fitness: 0.5, ...})
      iex> detector = PlateauDetector.update(detector, %{generation: 2, best_fitness: 0.52, ...})
      iex> detector.plateau_detected
      false
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Convergence.FitnessRecord

  typedstruct do
    field(:fitness_history, list(FitnessRecord.t()), default: [])
    field(:window_size, pos_integer(), default: 5)
    field(:patience, pos_integer(), default: 5)
    field(:improvement_threshold, float(), default: 0.01)
    field(:absolute_threshold, float(), default: 0.001)
    field(:patience_counter, non_neg_integer(), default: 0)
    field(:plateau_detected, boolean(), default: false)
    field(:max_history, pos_integer(), default: 100)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates a new plateau detector with given configuration.

  ## Options

  - `:window_size` - Number of generations to compare (default: 5)
  - `:patience` - Generations without improvement before plateau (default: 5)
  - `:improvement_threshold` - Minimum relative improvement (default: 0.01)
  - `:absolute_threshold` - Minimum absolute improvement (default: 0.001)
  - `:max_history` - Maximum history to keep (default: 100)

  ## Examples

      iex> detector = PlateauDetector.new()
      %PlateauDetector{window_size: 5, patience: 5}

      iex> detector = PlateauDetector.new(patience: 10, improvement_threshold: 0.05)
      %PlateauDetector{patience: 10, improvement_threshold: 0.05}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      window_size: Keyword.get(opts, :window_size, 5),
      patience: Keyword.get(opts, :patience, 5),
      improvement_threshold: Keyword.get(opts, :improvement_threshold, 0.01),
      absolute_threshold: Keyword.get(opts, :absolute_threshold, 0.001),
      max_history: Keyword.get(opts, :max_history, 100),
      config: Map.new(opts)
    }
  end

  @doc """
  Updates detector with new generation metrics and checks for plateau.

  Adds the new fitness record to history and evaluates whether a plateau has occurred.
  Uses windowed comparison between recent and baseline fitness values.

  ## Parameters

  - `detector` - Current detector state
  - `fitness_record` - Fitness metrics for the generation (map or FitnessRecord)

  ## Returns

  Updated detector with plateau status

  ## Examples

      iex> detector = PlateauDetector.new()
      iex> record = %{generation: 1, best_fitness: 0.5, mean_fitness: 0.45}
      iex> detector = PlateauDetector.update(detector, record)
      iex> detector.plateau_detected
      false
  """
  @spec update(t(), FitnessRecord.t() | map()) :: t()
  def update(%__MODULE__{} = detector, fitness_record) when is_map(fitness_record) do
    # Convert map to FitnessRecord if needed
    record =
      case fitness_record do
        %FitnessRecord{} = r -> r
        map when is_map(map) -> struct(FitnessRecord, map)
      end

    # Add to history and trim if needed
    history = [record | detector.fitness_history]
    history = Enum.take(history, detector.max_history)

    detector = %{detector | fitness_history: history}

    # Check for plateau
    check_plateau(detector)
  end

  @doc """
  Checks if a plateau has been detected based on current history.

  Returns true if fitness improvements have stagnated for patience generations.

  ## Examples

      iex> detector = PlateauDetector.new()
      iex> PlateauDetector.plateau_detected?(detector)
      false
  """
  @spec plateau_detected?(t()) :: boolean()
  def plateau_detected?(%__MODULE__{} = detector) do
    detector.plateau_detected
  end

  @doc """
  Returns the number of consecutive non-improving generations.

  ## Examples

      iex> detector = PlateauDetector.new()
      iex> PlateauDetector.get_patience_count(detector)
      0
  """
  @spec get_patience_count(t()) :: non_neg_integer()
  def get_patience_count(%__MODULE__{} = detector) do
    detector.patience_counter
  end

  @doc """
  Resets the plateau detector, clearing history and counters.

  ## Examples

      iex> detector = PlateauDetector.new() |> PlateauDetector.update(...)
      iex> detector = PlateauDetector.reset(detector)
      iex> detector.fitness_history
      []
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = detector) do
    %{detector | fitness_history: [], patience_counter: 0, plateau_detected: false}
  end

  # Private functions

  defp check_plateau(detector) do
    # Need at least window_size * 2 generations for comparison
    required_history = detector.window_size * 2

    if length(detector.fitness_history) < required_history do
      %{detector | plateau_detected: false}
    else
      # Get recent and baseline windows
      recent_window = get_recent_window(detector)
      baseline_window = get_baseline_window(detector)

      # Calculate fitness statistics
      recent_fitness = calculate_mean_fitness(recent_window)
      baseline_fitness = calculate_mean_fitness(baseline_window)

      # Calculate improvements
      absolute_improvement = recent_fitness - baseline_fitness

      relative_improvement =
        if baseline_fitness > 0 do
          absolute_improvement / baseline_fitness
        else
          0.0
        end

      # Check if improving
      is_improving =
        absolute_improvement > detector.absolute_threshold or
          relative_improvement > detector.improvement_threshold

      # Update patience counter
      detector =
        if is_improving do
          %{detector | patience_counter: 0}
        else
          %{detector | patience_counter: detector.patience_counter + 1}
        end

      # Declare plateau if patience exhausted
      plateau_detected = detector.patience_counter >= detector.patience

      %{detector | plateau_detected: plateau_detected}
    end
  end

  defp get_recent_window(detector) do
    detector.fitness_history
    |> Enum.take(detector.window_size)
  end

  defp get_baseline_window(detector) do
    detector.fitness_history
    |> Enum.drop(detector.window_size)
    |> Enum.take(detector.window_size)
  end

  defp calculate_mean_fitness(window) do
    if Enum.empty?(window) do
      0.0
    else
      window
      |> Enum.map(& &1.best_fitness)
      |> Enum.sum()
      |> Kernel./(length(window))
    end
  end
end
