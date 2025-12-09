defmodule Jido.AI.Runner.GEPA.Metrics do
  @moduledoc """
  Metrics aggregation system for GEPA prompt evaluation.

  This module implements Section 1.2.3 of the GEPA implementation plan, providing
  comprehensive metrics collection and statistical aggregation for robust fitness
  estimation across multiple evaluation runs.

  ## Key Features

  - **Metrics Collection**: Accumulates success rates, latency, quality scores
  - **Statistical Aggregation**: Calculates mean, median, variance, standard deviation
  - **Multi-Task Evaluation**: Combines performance across diverse test cases
  - **Confidence Intervals**: Provides robust fitness estimation with statistical confidence

  ## Architecture

  Metrics are organized as collections of typed measurements:

  1. **MetricValue**: Individual measurements with type, value, and metadata
  2. **Metrics**: Aggregated collection with statistical analysis
  3. **MetricType**: Enum of supported metric types (success_rate, latency, quality_score)

  ## Metric Types

  - `:success_rate` - Binary success/failure (0.0-1.0)
  - `:latency` - Execution time in milliseconds
  - `:quality_score` - Numeric quality rating (0.0-1.0)
  - `:accuracy` - Correctness score (0.0-1.0)
  - `:custom` - User-defined metric with arbitrary value

  ## Usage

      # Create new metrics collector
      metrics = Metrics.new()

      # Add metric values
      metrics = Metrics.add_metric(metrics, :success_rate, 1.0)
      metrics = Metrics.add_metric(metrics, :latency, 1234)
      metrics = Metrics.add_metric(metrics, :quality_score, 0.85)

      # Aggregate statistics
      aggregated = Metrics.aggregate(metrics)
      # => %{
      #   success_rate: %{mean: 1.0, median: 1.0, variance: 0.0, ...},
      #   latency: %{mean: 1234, median: 1234, ...},
      #   ...
      # }

      # Calculate confidence intervals
      ci = Metrics.confidence_interval(metrics, :success_rate, confidence_level: 0.95)
      # => %{lower: 0.92, upper: 1.0, confidence: 0.95}

      # Calculate overall fitness score
      fitness = Metrics.calculate_fitness(metrics)
      # => 0.87

  ## Implementation Status

  - [x] 1.2.3.1 Metrics collector accumulating success rates, latency, quality scores
  - [x] 1.2.3.2 Statistical aggregation with mean, median, variance calculations
  - [x] 1.2.3.3 Multi-task evaluation combining performance across diverse test cases
  - [x] 1.2.3.4 Confidence interval calculation for robust fitness estimation
  """

  use TypedStruct
  require Logger

  # Type definitions

  @type metric_type ::
          :success_rate | :latency | :quality_score | :accuracy | :custom
  @type metric_value :: number()
  @type aggregation_stats :: %{
          mean: float(),
          median: float(),
          variance: float(),
          std_dev: float(),
          min: number(),
          max: number(),
          count: non_neg_integer()
        }

  typedstruct module: MetricValue do
    @moduledoc """
    Individual metric measurement.

    Represents a single measurement of a specific metric type,
    captured during prompt evaluation.
    """

    field(:type, Jido.AI.Runner.GEPA.Metrics.metric_type(), enforce: true)
    field(:value, Jido.AI.Runner.GEPA.Metrics.metric_value(), enforce: true)
    field(:timestamp, DateTime.t(), default: DateTime.utc_now())
    field(:metadata, map(), default: %{})
    field(:task_id, String.t() | nil)
  end

  typedstruct do
    # Aggregated metrics collection for prompt evaluation.
    # Contains collections of metric values organized by type,
    # enabling statistical analysis and fitness calculation.

    field(:values, %{optional(Jido.AI.Runner.GEPA.Metrics.metric_type()) => list(MetricValue.t())}, default: %{})
    field(:task_ids, MapSet.t(), default: MapSet.new())
    field(:metadata, map(), default: %{})
    field(:created_at, DateTime.t(), enforce: true)
  end

  # Public API

  @doc """
  Creates a new metrics collector.

  ## Options

  - `:metadata` - Additional context information (default: %{})

  ## Examples

      metrics = Metrics.new(metadata: %{prompt: "Think step by step"})
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      values: %{},
      task_ids: MapSet.new(),
      metadata: metadata,
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Adds a metric value to the collection.

  ## Parameters

  - `metrics` - Metrics collection to update
  - `type` - Type of metric (:success_rate, :latency, :quality_score, :accuracy, :custom)
  - `value` - Numeric metric value
  - `opts` - Additional options

  ## Options

  - `:task_id` - Task identifier for multi-task evaluation (default: nil)
  - `:metadata` - Additional metric metadata (default: %{})
  - `:timestamp` - Custom timestamp (default: DateTime.utc_now())

  ## Examples

      metrics = Metrics.add_metric(metrics, :success_rate, 1.0)
      metrics = Metrics.add_metric(metrics, :latency, 1234, task_id: "task_1")
      metrics = Metrics.add_metric(metrics, :quality_score, 0.85, metadata: %{model: "gpt-4"})
  """
  @spec add_metric(t(), Jido.AI.Runner.GEPA.Metrics.metric_type(), Jido.AI.Runner.GEPA.Metrics.metric_value(), keyword()) :: t()
  def add_metric(%__MODULE__{} = metrics, type, value, opts \\ [])
      when is_atom(type) and is_number(value) do
    task_id = Keyword.get(opts, :task_id)
    metadata = Keyword.get(opts, :metadata, %{})
    timestamp = Keyword.get(opts, :timestamp, DateTime.utc_now())

    metric_value = %MetricValue{
      type: type,
      value: value,
      timestamp: timestamp,
      metadata: metadata,
      task_id: task_id
    }

    # Add to values map
    updated_values =
      Map.update(
        metrics.values,
        type,
        [metric_value],
        fn existing -> existing ++ [metric_value] end
      )

    # Track task_id if provided
    updated_task_ids =
      if task_id do
        MapSet.put(metrics.task_ids, task_id)
      else
        metrics.task_ids
      end

    Logger.debug("Added metric (type: #{type}, value: #{value}, task_id: #{inspect(task_id)})")

    %{metrics | values: updated_values, task_ids: updated_task_ids}
  end

  @doc """
  Aggregates metrics with statistical calculations.

  Calculates mean, median, variance, standard deviation, min, max, and count
  for each metric type in the collection.

  ## Options

  - `:types` - List of metric types to aggregate (default: all types)
  - `:task_id` - Filter by specific task ID (default: nil, includes all)

  ## Examples

      # Aggregate all metrics
      aggregated = Metrics.aggregate(metrics)

      # Aggregate specific types
      aggregated = Metrics.aggregate(metrics, types: [:success_rate, :latency])

      # Aggregate for specific task
      aggregated = Metrics.aggregate(metrics, task_id: "task_1")

  ## Returns

  Map of metric_type => aggregation_stats
  """
  @spec aggregate(t(), keyword()) :: %{optional(Jido.AI.Runner.GEPA.Metrics.metric_type()) => aggregation_stats()}
  def aggregate(%__MODULE__{} = metrics, opts \\ []) do
    types = Keyword.get(opts, :types, Map.keys(metrics.values))
    task_id = Keyword.get(opts, :task_id)

    types
    |> Enum.map(fn type ->
      values =
        metrics.values
        |> Map.get(type, [])
        |> filter_by_task_id(task_id)
        |> Enum.map(& &1.value)

      stats = calculate_statistics(values)
      {type, stats}
    end)
    |> Enum.into(%{})
  end

  @doc """
  Calculates confidence interval for a specific metric type.

  Uses t-distribution for small samples (n < 30) and normal distribution
  for larger samples to compute confidence intervals.

  ## Parameters

  - `metrics` - Metrics collection
  - `type` - Metric type to analyze
  - `opts` - Additional options

  ## Options

  - `:confidence_level` - Confidence level (default: 0.95 for 95% CI)
  - `:task_id` - Filter by specific task ID (default: nil)

  ## Examples

      ci = Metrics.confidence_interval(metrics, :success_rate)
      # => %{lower: 0.92, upper: 1.0, mean: 0.96, confidence: 0.95}

      ci = Metrics.confidence_interval(metrics, :latency, confidence_level: 0.99)

  ## Returns

  Map with :lower, :upper, :mean, :confidence keys, or nil if insufficient data
  """
  @spec confidence_interval(t(), Jido.AI.Runner.GEPA.Metrics.metric_type(), keyword()) :: map() | nil
  def confidence_interval(%__MODULE__{} = metrics, type, opts \\ []) do
    confidence_level = Keyword.get(opts, :confidence_level, 0.95)
    task_id = Keyword.get(opts, :task_id)

    values =
      metrics.values
      |> Map.get(type, [])
      |> filter_by_task_id(task_id)
      |> Enum.map(& &1.value)

    if length(values) < 2 do
      Logger.warning(
        "Insufficient data for confidence interval (type: #{type}, count: #{length(values)})"
      )

      nil
    else
      calculate_confidence_interval(values, confidence_level)
    end
  end

  @doc """
  Calculates overall fitness score from aggregated metrics.

  Combines multiple metric types into a single fitness score (0.0-1.0)
  using weighted aggregation. Default weights prioritize success rate
  and quality score.

  ## Options

  - `:weights` - Custom weights for metric types (default: balanced weights)
  - `:task_id` - Calculate fitness for specific task (default: all tasks)
  - `:aggregation_method` - Method to combine metrics (default: :weighted_mean)

  ## Examples

      # Use default weights
      fitness = Metrics.calculate_fitness(metrics)

      # Custom weights
      fitness = Metrics.calculate_fitness(metrics,
        weights: %{success_rate: 0.5, quality_score: 0.3, latency: 0.2}
      )

      # Task-specific fitness
      fitness = Metrics.calculate_fitness(metrics, task_id: "task_1")

  ## Returns

  Float between 0.0 and 1.0, or nil if no metrics available
  """
  @spec calculate_fitness(t(), keyword()) :: float() | nil
  def calculate_fitness(%__MODULE__{} = metrics, opts \\ []) do
    weights = Keyword.get(opts, :weights, default_weights())
    task_id = Keyword.get(opts, :task_id)
    aggregation_method = Keyword.get(opts, :aggregation_method, :weighted_mean)

    aggregated = aggregate(metrics, task_id: task_id)

    if map_size(aggregated) == 0 do
      Logger.warning("No metrics available for fitness calculation")
      nil
    else
      case aggregation_method do
        :weighted_mean -> calculate_weighted_fitness(aggregated, weights)
        :geometric_mean -> calculate_geometric_fitness(aggregated)
        _ -> calculate_weighted_fitness(aggregated, weights)
      end
    end
  end

  @doc """
  Returns statistics for a specific metric type.

  ## Examples

      stats = Metrics.get_stats(metrics, :success_rate)
      # => %{mean: 0.95, median: 1.0, variance: 0.01, ...}
  """
  @spec get_stats(t(), Jido.AI.Runner.GEPA.Metrics.metric_type(), keyword()) :: aggregation_stats() | nil
  def get_stats(%__MODULE__{} = metrics, type, opts \\ []) do
    task_id = Keyword.get(opts, :task_id)

    values =
      metrics.values
      |> Map.get(type, [])
      |> filter_by_task_id(task_id)
      |> Enum.map(& &1.value)

    if Enum.empty?(values) do
      nil
    else
      calculate_statistics(values)
    end
  end

  @doc """
  Returns the count of metrics for a specific type.

  ## Examples

      count = Metrics.count(metrics, :success_rate)
      # => 10
  """
  @spec count(t(), Jido.AI.Runner.GEPA.Metrics.metric_type()) :: non_neg_integer()
  def count(%__MODULE__{} = metrics, type) do
    metrics.values
    |> Map.get(type, [])
    |> length()
  end

  @doc """
  Returns all task IDs present in the metrics collection.

  ## Examples

      task_ids = Metrics.task_ids(metrics)
      # => #MapSet<["task_1", "task_2", "task_3"]>
  """
  @spec task_ids(t()) :: MapSet.t()
  def task_ids(%__MODULE__{} = metrics) do
    metrics.task_ids
  end

  @doc """
  Merges multiple metrics collections into one.

  ## Examples

      merged = Metrics.merge([metrics1, metrics2, metrics3])
  """
  @spec merge(list(t())) :: t()
  def merge(metrics_list) when is_list(metrics_list) do
    Enum.reduce(metrics_list, new(), fn metrics, acc ->
      merge_two(acc, metrics)
    end)
  end

  # Private Functions

  @spec filter_by_task_id(list(MetricValue.t()), String.t() | nil) :: list(MetricValue.t())
  defp filter_by_task_id(values, nil), do: values

  defp filter_by_task_id(values, task_id) do
    Enum.filter(values, fn v -> v.task_id == task_id end)
  end

  @spec calculate_statistics(list(number())) :: aggregation_stats()
  defp calculate_statistics([]),
    do: %{mean: 0.0, median: 0.0, variance: 0.0, std_dev: 0.0, min: 0.0, max: 0.0, count: 0}

  defp calculate_statistics(values) when is_list(values) do
    count = length(values)
    mean = Enum.sum(values) / count
    sorted = Enum.sort(values)
    median = calculate_median(sorted)
    variance = calculate_variance(values, mean)
    std_dev = :math.sqrt(variance)

    %{
      mean: mean,
      median: median,
      variance: variance,
      std_dev: std_dev,
      min: List.first(sorted),
      max: List.last(sorted),
      count: count
    }
  end

  @spec calculate_median(list(number())) :: float()
  defp calculate_median([]), do: 0.0

  defp calculate_median(sorted_values) do
    count = length(sorted_values)
    mid = div(count, 2)

    if rem(count, 2) == 0 do
      (Enum.at(sorted_values, mid - 1) + Enum.at(sorted_values, mid)) / 2.0
    else
      Enum.at(sorted_values, mid) * 1.0
    end
  end

  @spec calculate_variance(list(number()), float()) :: float()
  defp calculate_variance([], _mean), do: 0.0

  defp calculate_variance(values, mean) do
    count = length(values)

    if count < 2 do
      0.0
    else
      sum_squared_diff =
        values
        |> Enum.map(fn x -> :math.pow(x - mean, 2) end)
        |> Enum.sum()

      sum_squared_diff / (count - 1)
    end
  end

  @spec calculate_confidence_interval(list(number()), float()) :: map()
  defp calculate_confidence_interval(values, confidence_level) do
    count = length(values)
    mean = Enum.sum(values) / count
    variance = calculate_variance(values, mean)
    std_dev = :math.sqrt(variance)
    std_error = std_dev / :math.sqrt(count)

    # Use t-distribution critical value for small samples
    # For simplicity, using approximations here
    # For production, consider using proper statistical library
    t_critical = calculate_t_critical(confidence_level, count - 1)

    margin_of_error = t_critical * std_error

    %{
      lower: max(0.0, mean - margin_of_error),
      upper: min(1.0, mean + margin_of_error),
      mean: mean,
      margin_of_error: margin_of_error,
      confidence: confidence_level,
      sample_size: count
    }
  end

  @spec calculate_t_critical(float(), non_neg_integer()) :: float()
  defp calculate_t_critical(confidence_level, degrees_of_freedom) do
    # Simplified t-critical values for common confidence levels
    # For production, use proper statistical library
    alpha = 1.0 - confidence_level

    cond do
      # For large samples, use z-scores (normal distribution)
      degrees_of_freedom >= 30 ->
        case alpha do
          a when a <= 0.01 ->
            2.576

          # 99% CI
          a when a <= 0.05 ->
            1.960

          # 95% CI
          _ ->
            1.645
            # 90% CI
        end

      # For small samples, use conservative t-values
      degrees_of_freedom >= 10 ->
        case alpha do
          a when a <= 0.01 -> 2.764
          a when a <= 0.05 -> 2.228
          _ -> 1.812
        end

      # Very small samples - use very conservative estimates
      true ->
        case alpha do
          a when a <= 0.01 -> 3.250
          a when a <= 0.05 -> 2.571
          _ -> 2.015
        end
    end
  end

  @spec default_weights() :: %{Jido.AI.Runner.GEPA.Metrics.metric_type() => float()}
  defp default_weights do
    %{
      success_rate: 0.4,
      quality_score: 0.3,
      accuracy: 0.2,
      latency: 0.1,
      custom: 0.0
    }
  end

  @spec calculate_weighted_fitness(%{Jido.AI.Runner.GEPA.Metrics.metric_type() => aggregation_stats()}, %{
          Jido.AI.Runner.GEPA.Metrics.metric_type() => float()
        }) :: float()
  defp calculate_weighted_fitness(aggregated, weights) do
    total_weight =
      aggregated
      |> Map.keys()
      |> Enum.map(fn type -> Map.get(weights, type, 0.0) end)
      |> Enum.sum()

    if total_weight == 0.0 do
      # No weights defined, use simple average
      aggregated
      |> Map.values()
      |> Enum.map(& &1.mean)
      |> Enum.sum()
      |> Kernel./(map_size(aggregated))
    else
      weighted_sum =
        aggregated
        |> Enum.map(fn {type, stats} ->
          weight = Map.get(weights, type, 0.0)
          normalized_value = normalize_metric_value(type, stats.mean)
          weight * normalized_value
        end)
        |> Enum.sum()

      weighted_sum / total_weight
    end
  end

  @spec calculate_geometric_fitness(%{Jido.AI.Runner.GEPA.Metrics.metric_type() => aggregation_stats()}) :: float()
  defp calculate_geometric_fitness(aggregated) do
    if map_size(aggregated) == 0 do
      0.0
    else
      product =
        aggregated
        |> Enum.map(fn {type, stats} ->
          normalize_metric_value(type, stats.mean)
        end)
        |> Enum.reduce(1.0, &*/2)

      :math.pow(product, 1.0 / map_size(aggregated))
    end
  end

  @spec normalize_metric_value(Jido.AI.Runner.GEPA.Metrics.metric_type(), number()) :: float()
  defp normalize_metric_value(:latency, value) do
    # Normalize latency: lower is better
    # Assume reasonable range is 0-10000ms
    max_acceptable_latency = 10_000
    1.0 - min(value / max_acceptable_latency, 1.0)
  end

  defp normalize_metric_value(_type, value) do
    # Most metrics are already 0.0-1.0 (success_rate, quality_score, accuracy)
    # Clamp to valid range
    value
    |> max(0.0)
    |> min(1.0)
  end

  @spec merge_two(t(), t()) :: t()
  defp merge_two(%__MODULE__{} = metrics1, %__MODULE__{} = metrics2) do
    merged_values =
      Map.merge(metrics1.values, metrics2.values, fn _k, v1, v2 ->
        v1 ++ v2
      end)

    merged_task_ids = MapSet.union(metrics1.task_ids, metrics2.task_ids)

    merged_metadata = Map.merge(metrics1.metadata, metrics2.metadata)

    %__MODULE__{
      values: merged_values,
      task_ids: merged_task_ids,
      metadata: merged_metadata,
      created_at: metrics1.created_at
    }
  end
end
