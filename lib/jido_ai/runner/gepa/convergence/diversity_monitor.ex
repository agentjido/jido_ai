defmodule Jido.AI.Runner.GEPA.Convergence.DiversityMonitor do
  @moduledoc """
  Monitors population diversity to detect convergence through variance loss.

  Tracks diversity metrics over time and analyzes trends to predict convergence
  before complete diversity collapse occurs. Provides early warnings when diversity
  is declining, allowing intervention before premature convergence.

  ## Detection Strategy

  1. **Diversity Tracking**: Record diversity metrics each generation
  2. **Threshold Detection**: Identify when diversity falls below critical levels
  3. **Trend Analysis**: Use linear regression to detect declining diversity
  4. **Early Warning**: Alert before complete convergence occurs

  ## Diversity Levels

  - `:excellent` - High diversity (> 0.70), healthy exploration
  - `:healthy` - Good diversity (> 0.50), normal operations
  - `:moderate` - Acceptable diversity (> 0.30), monitor
  - `:low` - Low diversity (> 0.15), diversity promotion needed
  - `:critical` - Very low diversity (≤ 0.15), immediate intervention required

  ## Trend Analysis

  Uses linear regression on recent diversity history to determine trend:
  - `:increasing` - Diversity growing (slope > 0.01)
  - `:stable` - Diversity maintained (-0.01 ≤ slope ≤ 0.01)
  - `:decreasing` - Diversity declining (slope < -0.01)

  ## Configuration

  - `:critical_threshold` - Diversity below this triggers convergence (default: 0.15)
  - `:warning_threshold` - Diversity below this triggers warning (default: 0.30)
  - `:trend_window` - Generations for trend analysis (default: 5)
  - `:patience` - Generations below threshold before declaring collapse (default: 3)

  ## Example

      iex> monitor = DiversityMonitor.new(critical_threshold: 0.15, patience: 3)
      iex> metrics = %DiversityMetrics{pairwise_diversity: 0.65, diversity_level: :healthy}
      iex> monitor = DiversityMonitor.update(monitor, metrics)
      iex> monitor.diversity_collapsed
      false
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Diversity.DiversityMetrics

  @type trend :: :increasing | :stable | :decreasing | :unknown

  typedstruct module: DiversityRecord do
    @moduledoc """
    Record of diversity metrics for a single generation.

    ## Fields

    - `:generation` - Generation number
    - `:pairwise_diversity` - Average distance between prompts
    - `:diversity_level` - Categorical diversity level
    - `:convergence_risk` - Estimated convergence risk (0.0-1.0)
    - `:timestamp` - When recorded
    """

    field(:generation, non_neg_integer(), enforce: true)
    field(:pairwise_diversity, float(), enforce: true)
    field(:diversity_level, atom(), enforce: true)
    field(:convergence_risk, float(), default: 0.0)
    field(:timestamp, DateTime.t(), default: DateTime.utc_now())
  end

  typedstruct do
    field(:diversity_history, list(DiversityRecord.t()), default: [])
    field(:critical_threshold, float(), default: 0.15)
    field(:warning_threshold, float(), default: 0.30)
    field(:trend_window, pos_integer(), default: 5)
    field(:patience, pos_integer(), default: 3)
    field(:patience_counter, non_neg_integer(), default: 0)
    field(:diversity_collapsed, boolean(), default: false)
    field(:trend, trend(), default: :unknown)
    field(:max_history, pos_integer(), default: 100)
    field(:config, map(), default: %{})
  end

  @doc """
  Creates a new diversity monitor with given configuration.

  ## Options

  - `:critical_threshold` - Diversity triggering collapse detection (default: 0.15)
  - `:warning_threshold` - Diversity triggering warnings (default: 0.30)
  - `:trend_window` - Generations for trend analysis (default: 5)
  - `:patience` - Generations below threshold before collapse (default: 3)
  - `:max_history` - Maximum history to keep (default: 100)

  ## Examples

      iex> monitor = DiversityMonitor.new()
      %DiversityMonitor{critical_threshold: 0.15, patience: 3}

      iex> monitor = DiversityMonitor.new(critical_threshold: 0.20, patience: 5)
      %DiversityMonitor{critical_threshold: 0.20, patience: 5}
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      critical_threshold: Keyword.get(opts, :critical_threshold, 0.15),
      warning_threshold: Keyword.get(opts, :warning_threshold, 0.30),
      trend_window: Keyword.get(opts, :trend_window, 5),
      patience: Keyword.get(opts, :patience, 3),
      max_history: Keyword.get(opts, :max_history, 100),
      config: Map.new(opts)
    }
  end

  @doc """
  Updates monitor with new diversity metrics and checks for collapse.

  Adds the new diversity record to history, analyzes the trend, and evaluates
  whether diversity has collapsed below acceptable levels.

  ## Parameters

  - `monitor` - Current monitor state
  - `diversity_metrics` - Diversity metrics for the generation (DiversityMetrics or map)

  ## Returns

  Updated monitor with collapse status and trend analysis

  ## Examples

      iex> monitor = DiversityMonitor.new()
      iex> metrics = %{generation: 1, pairwise_diversity: 0.65, diversity_level: :healthy}
      iex> monitor = DiversityMonitor.update(monitor, metrics)
      iex> monitor.diversity_collapsed
      false
  """
  @spec update(t(), DiversityMetrics.t() | map()) :: t()
  def update(%__MODULE__{} = monitor, diversity_metrics) when is_map(diversity_metrics) do
    # Convert to DiversityRecord
    record = create_record(diversity_metrics)

    # Add to history and trim if needed
    history = [record | monitor.diversity_history]
    history = Enum.take(history, monitor.max_history)

    monitor = %{monitor | diversity_history: history}

    # Analyze trend
    monitor = analyze_trend(monitor)

    # Check for collapse
    check_collapse(monitor)
  end

  @doc """
  Checks if diversity has collapsed below critical threshold.

  ## Examples

      iex> monitor = DiversityMonitor.new()
      iex> DiversityMonitor.diversity_collapsed?(monitor)
      false
  """
  @spec diversity_collapsed?(t()) :: boolean()
  def diversity_collapsed?(%__MODULE__{} = monitor) do
    monitor.diversity_collapsed
  end

  @doc """
  Returns the current diversity trend.

  ## Examples

      iex> monitor = DiversityMonitor.new()
      iex> DiversityMonitor.get_trend(monitor)
      :unknown
  """
  @spec get_trend(t()) :: trend()
  def get_trend(%__MODULE__{} = monitor) do
    monitor.trend
  end

  @doc """
  Returns the most recent diversity value.

  ## Examples

      iex> monitor = DiversityMonitor.new()
      iex> DiversityMonitor.get_current_diversity(monitor)
      nil
  """
  @spec get_current_diversity(t()) :: float() | nil
  def get_current_diversity(%__MODULE__{diversity_history: []}) do
    nil
  end

  def get_current_diversity(%__MODULE__{diversity_history: [latest | _]}) do
    latest.pairwise_diversity
  end

  @doc """
  Checks if diversity is in warning zone.

  Returns true if diversity is below warning threshold but above critical threshold.

  ## Examples

      iex> monitor = DiversityMonitor.new()
      iex> DiversityMonitor.in_warning_zone?(monitor)
      false
  """
  @spec in_warning_zone?(t()) :: boolean()
  def in_warning_zone?(%__MODULE__{} = monitor) do
    case get_current_diversity(monitor) do
      nil ->
        false

      diversity ->
        diversity < monitor.warning_threshold and diversity >= monitor.critical_threshold
    end
  end

  @doc """
  Resets the diversity monitor, clearing history and counters.

  ## Examples

      iex> monitor = DiversityMonitor.new() |> DiversityMonitor.update(...)
      iex> monitor = DiversityMonitor.reset(monitor)
      iex> monitor.diversity_history
      []
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = monitor) do
    %{
      monitor
      | diversity_history: [],
        patience_counter: 0,
        diversity_collapsed: false,
        trend: :unknown
    }
  end

  # Private functions

  defp create_record(%DiversityRecord{} = record), do: record

  defp create_record(%DiversityMetrics{} = metrics) do
    %DiversityRecord{
      generation: Map.get(metrics.metadata, :generation, 0),
      pairwise_diversity: metrics.pairwise_diversity,
      diversity_level: metrics.diversity_level,
      convergence_risk: metrics.convergence_risk
    }
  end

  defp create_record(map) when is_map(map) do
    %DiversityRecord{
      generation: Map.get(map, :generation, 0),
      pairwise_diversity: Map.get(map, :pairwise_diversity, 0.0),
      diversity_level: Map.get(map, :diversity_level, :unknown),
      convergence_risk: Map.get(map, :convergence_risk, 0.0)
    }
  end

  defp check_collapse(monitor) do
    current_diversity = get_current_diversity(monitor)

    if current_diversity == nil do
      monitor
    else
      # Check if below critical threshold
      below_threshold = current_diversity < monitor.critical_threshold

      # Update patience counter
      monitor =
        if below_threshold do
          %{monitor | patience_counter: monitor.patience_counter + 1}
        else
          %{monitor | patience_counter: 0}
        end

      # Declare collapse if patience exhausted
      collapsed = monitor.patience_counter >= monitor.patience

      %{monitor | diversity_collapsed: collapsed}
    end
  end

  defp analyze_trend(monitor) do
    if length(monitor.diversity_history) < monitor.trend_window do
      %{monitor | trend: :unknown}
    else
      recent = Enum.take(monitor.diversity_history, monitor.trend_window)
      slope = calculate_trend_slope(recent)

      trend =
        cond do
          slope > 0.01 -> :increasing
          slope < -0.01 -> :decreasing
          true -> :stable
        end

      %{monitor | trend: trend}
    end
  end

  defp calculate_trend_slope(points) do
    # Linear regression: y = mx + b, we want m (slope)
    n = length(points)

    if n < 2 do
      0.0
    else
      {sum_x, sum_y, sum_xy, sum_x2} =
        points
        |> Enum.reverse()
        |> Enum.with_index()
        |> Enum.reduce({0, 0.0, 0.0, 0}, fn {point, idx}, {sx, sy, sxy, sx2} ->
          x = idx
          y = point.pairwise_diversity
          {sx + x, sy + y, sxy + x * y, sx2 + x * x}
        end)

      # Slope = (n*Σxy - Σx*Σy) / (n*Σx² - (Σx)²)
      numerator = n * sum_xy - sum_x * sum_y
      denominator = n * sum_x2 - sum_x * sum_x

      if denominator == 0 do
        0.0
      else
        numerator / denominator
      end
    end
  end
end
