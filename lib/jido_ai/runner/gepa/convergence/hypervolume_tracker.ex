defmodule Jido.AI.Runner.GEPA.Convergence.HypervolumeTracker do
  @moduledoc """
  Tracks Pareto frontier hypervolume to detect saturation.

  Monitors hypervolume growth over time and detects when the Pareto frontier
  has stopped expanding, indicating convergence. Uses multi-criteria approach
  combining absolute improvement, relative improvement, and average growth rate.

  ## Detection Strategy

  1. **Absolute Improvement**: Current HV - Previous HV
  2. **Relative Improvement**: (Current - Previous) / Previous
  3. **Average Growth Rate**: Mean improvement over window
  4. **Patience Mechanism**: Require N consecutive low-growth generations

  Saturation is declared when ALL criteria indicate minimal improvement for
  patience generations.

  ## Saturation Criteria

  A frontier is saturated when:
  - Absolute improvement < absolute_threshold (default: 0.001)
  - Relative improvement < relative_threshold (default: 0.01 = 1%)
  - Average improvement rate < average_threshold (default: 0.005)
  - Above conditions persist for patience generations (default: 5)

  ## Configuration

  - `:absolute_threshold` - Minimum absolute HV increase (default: 0.001)
  - `:relative_threshold` - Minimum relative HV increase (default: 0.01 = 1%)
  - `:average_threshold` - Minimum average improvement rate (default: 0.005)
  - `:window_size` - Generations for average rate calculation (default: 5)
  - `:patience` - Non-improving generations before saturation (default: 5)

  ## Example

      iex> tracker = HypervolumeTracker.new(absolute_threshold: 0.001, patience: 3)
      iex> tracker = HypervolumeTracker.update(tracker, 0.50)
      iex> tracker = HypervolumeTracker.update(tracker, 0.52)
      iex> tracker.saturated
      false
  """

  use TypedStruct

  typedstruct module: HypervolumeRecord do
    @moduledoc """
    Record of hypervolume for a single generation.

    ## Fields

    - `:generation` - Generation number
    - `:hypervolume` - Hypervolume indicator value
    - `:absolute_improvement` - Improvement from previous generation
    - `:relative_improvement` - Relative improvement from previous
    - `:timestamp` - When recorded
    """

    field(:generation, non_neg_integer(), enforce: true)
    field(:hypervolume, float(), enforce: true)
    field(:absolute_improvement, float() | nil)
    field(:relative_improvement, float() | nil)
    field(:timestamp, DateTime.t(), default: DateTime.utc_now())
  end

  typedstruct do
    field(:hypervolume_history, list(HypervolumeRecord.t()), default: [])
    field(:absolute_threshold, float(), default: 0.001)
    field(:relative_threshold, float(), default: 0.01)
    field(:average_threshold, float(), default: 0.005)
    field(:window_size, pos_integer(), default: 5)
    field(:patience, pos_integer(), default: 5)
    field(:patience_counter, non_neg_integer(), default: 0)
    field(:saturated, boolean(), default: false)
    field(:max_history, pos_integer(), default: 100)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates a new hypervolume tracker with given configuration.

  ## Options

  - `:absolute_threshold` - Minimum absolute improvement (default: 0.001)
  - `:relative_threshold` - Minimum relative improvement (default: 0.01)
  - `:average_threshold` - Minimum average rate (default: 0.005)
  - `:window_size` - Generations for averaging (default: 5)
  - `:patience` - Generations before saturation (default: 5)
  - `:max_history` - Maximum history to keep (default: 100)

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      %HypervolumeTracker{absolute_threshold: 0.001, patience: 5}

      iex> tracker = HypervolumeTracker.new(patience: 10, relative_threshold: 0.05)
      %HypervolumeTracker{patience: 10, relative_threshold: 0.05}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      absolute_threshold: Keyword.get(opts, :absolute_threshold, 0.001),
      relative_threshold: Keyword.get(opts, :relative_threshold, 0.01),
      average_threshold: Keyword.get(opts, :average_threshold, 0.005),
      window_size: Keyword.get(opts, :window_size, 5),
      patience: Keyword.get(opts, :patience, 5),
      max_history: Keyword.get(opts, :max_history, 100),
      config: Map.new(opts)
    }
  end

  @doc """
  Updates tracker with new hypervolume value and checks for saturation.

  Adds the new hypervolume record to history, calculates improvements,
  and evaluates whether the frontier has saturated.

  ## Parameters

  - `tracker` - Current tracker state
  - `hypervolume` - Hypervolume value for current generation (float or map)
  - `generation` - Optional generation number (extracted from map or auto-incremented)

  ## Returns

  Updated tracker with saturation status

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      iex> tracker = HypervolumeTracker.update(tracker, 0.50)
      iex> tracker.saturated
      false

      iex> tracker = HypervolumeTracker.update(tracker, %{hypervolume: 0.52, generation: 1})
      iex> hd(tracker.hypervolume_history).hypervolume
      0.52
  """
  @spec update(t(), float() | map(), non_neg_integer() | nil) :: t()
  def update(tracker, hypervolume, generation \\ nil)

  def update(%__MODULE__{} = tracker, hypervolume, generation) when is_float(hypervolume) do
    gen = generation || get_next_generation(tracker)
    record = create_record(tracker, gen, hypervolume)

    # Add to history and trim
    history = [record | tracker.hypervolume_history]
    history = Enum.take(history, tracker.max_history)

    tracker = %{tracker | hypervolume_history: history}

    # Check for saturation
    check_saturation(tracker)
  end

  def update(tracker, %{hypervolume: hv} = map, _generation) do
    gen = Map.get(map, :generation, get_next_generation(tracker))
    update(tracker, hv, gen)
  end

  @doc """
  Checks if hypervolume has saturated.

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      iex> HypervolumeTracker.saturated?(tracker)
      false
  """
  @spec saturated?(t()) :: boolean()
  def saturated?(%__MODULE__{} = tracker) do
    tracker.saturated
  end

  @doc """
  Returns the current hypervolume value.

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      iex> HypervolumeTracker.get_current_hypervolume(tracker)
      nil
  """
  @spec get_current_hypervolume(t()) :: float() | nil
  def get_current_hypervolume(%__MODULE__{hypervolume_history: []}) do
    nil
  end

  def get_current_hypervolume(%__MODULE__{hypervolume_history: [latest | _]}) do
    latest.hypervolume
  end

  @doc """
  Returns the most recent absolute improvement.

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      iex> HypervolumeTracker.get_recent_improvement(tracker)
      nil
  """
  @spec get_recent_improvement(t()) :: float() | nil
  def get_recent_improvement(%__MODULE__{hypervolume_history: []}) do
    nil
  end

  def get_recent_improvement(%__MODULE__{hypervolume_history: [latest | _]}) do
    latest.absolute_improvement
  end

  @doc """
  Returns the average improvement rate over the window.

  ## Examples

      iex> tracker = HypervolumeTracker.new()
      iex> HypervolumeTracker.get_average_improvement_rate(tracker)
      0.0
  """
  @spec get_average_improvement_rate(t()) :: float()
  def get_average_improvement_rate(%__MODULE__{} = tracker) do
    if length(tracker.hypervolume_history) < 2 do
      0.0
    else
      recent = Enum.take(tracker.hypervolume_history, tracker.window_size)

      improvements =
        recent
        |> Enum.map(& &1.absolute_improvement)
        |> Enum.reject(&is_nil/1)

      if Enum.empty?(improvements) do
        0.0
      else
        Enum.sum(improvements) / length(improvements)
      end
    end
  end

  @doc """
  Resets the hypervolume tracker, clearing history and counters.

  ## Examples

      iex> tracker = HypervolumeTracker.new() |> HypervolumeTracker.update(0.5)
      iex> tracker = HypervolumeTracker.reset(tracker)
      iex> tracker.hypervolume_history
      []
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = tracker) do
    %{tracker | hypervolume_history: [], patience_counter: 0, saturated: false}
  end

  # Private functions

  defp get_next_generation(%__MODULE__{hypervolume_history: []}) do
    1
  end

  defp get_next_generation(%__MODULE__{hypervolume_history: [latest | _]}) do
    latest.generation + 1
  end

  defp create_record(_tracker, generation, hypervolume) when is_float(hypervolume) do
    %HypervolumeRecord{
      generation: generation,
      hypervolume: hypervolume,
      absolute_improvement: nil,
      relative_improvement: nil
    }
  end

  defp check_saturation(tracker) do
    if length(tracker.hypervolume_history) < 2 do
      %{tracker | saturated: false}
    else
      [current, previous | _] = tracker.hypervolume_history

      # Calculate improvements
      abs_improvement = current.hypervolume - previous.hypervolume

      rel_improvement =
        if previous.hypervolume > 0 do
          abs_improvement / previous.hypervolume
        else
          0.0
        end

      # Update current record with improvements
      updated_current = %{
        current
        | absolute_improvement: abs_improvement,
          relative_improvement: rel_improvement
      }

      history = [updated_current | tl(tracker.hypervolume_history)]
      tracker = %{tracker | hypervolume_history: history}

      # Calculate average improvement rate
      avg_rate = get_average_improvement_rate(tracker)

      # Check all criteria
      is_improving =
        abs_improvement > tracker.absolute_threshold or
          rel_improvement > tracker.relative_threshold or
          avg_rate > tracker.average_threshold

      # Update patience counter
      tracker =
        if is_improving do
          %{tracker | patience_counter: 0}
        else
          %{tracker | patience_counter: tracker.patience_counter + 1}
        end

      # Declare saturation if patience exhausted
      saturated = tracker.patience_counter >= tracker.patience

      %{tracker | saturated: saturated}
    end
  end
end
