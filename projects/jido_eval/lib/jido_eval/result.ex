defmodule Jido.Eval.Result do
  @moduledoc """
  Comprehensive evaluation result structure with aggregated statistics.

  Contains run-level summary, per-sample results, latency tracking,
  error analysis, and experimental metadata.

  ## Examples

      iex> result = %Jido.Eval.Result{
      ...>   run_id: "eval_001",
      ...>   sample_count: 100,
      ...>   completed_count: 95,
      ...>   pass_rate: 0.89
      ...> }
      iex> result.run_id
      "eval_001"
      
      iex> result = Jido.Eval.Result.aggregate_scores(result, [0.8, 0.9, 0.7])
      iex> result.summary_stats[:faithfulness][:mean]
      0.8
  """

  use TypedStruct

  typedstruct do
    @typedoc "Comprehensive evaluation result with statistics and metadata"

    # Run identification
    field(:run_id, String.t())
    field(:config, Jido.Eval.Config.t() | nil, default: nil)

    # Sample-level results
    field(:sample_results, [sample_result()], default: [])
    field(:sample_count, non_neg_integer(), default: 0)
    field(:completed_count, non_neg_integer(), default: 0)
    field(:error_count, non_neg_integer(), default: 0)

    # Aggregated statistics by metric
    field(:summary_stats, %{atom() => metric_stats()}, default: %{})
    field(:pass_rate, float() | nil, default: nil)

    # Performance metrics
    field(:latency, latency_stats(), default: %{})
    field(:start_time, DateTime.t() | nil, default: nil)
    field(:finish_time, DateTime.t() | nil, default: nil)
    field(:duration_ms, non_neg_integer() | nil, default: nil)

    # Error analysis
    field(:errors, [evaluation_error()], default: [])
    field(:error_categories, %{String.t() => non_neg_integer()}, default: %{})

    # Experimental tracking
    field(:by_tag, %{String.t() => tag_stats()}, default: %{})
    field(:metadata, %{String.t() => term()}, default: %{})
  end

  @typedoc "Per-sample evaluation result"
  @type sample_result :: %{
          sample_id: String.t() | nil,
          scores: %{atom() => float()},
          latency_ms: non_neg_integer() | nil,
          error: String.t() | nil,
          tags: %{String.t() => String.t()},
          metadata: %{String.t() => term()}
        }

  @typedoc "Statistical summary for a metric"
  @type metric_stats :: %{
          mean: float(),
          median: float(),
          std_dev: float(),
          min: float(),
          max: float(),
          p50: float(),
          p95: float(),
          p99: float(),
          count: non_neg_integer()
        }

  @typedoc "Latency performance statistics"
  @type latency_stats :: %{
          avg_ms: float(),
          median_ms: float(),
          p95_ms: float(),
          p99_ms: float(),
          max_ms: non_neg_integer(),
          min_ms: non_neg_integer()
        }

  @typedoc "Evaluation error with context"
  @type evaluation_error :: %{
          sample_id: String.t() | nil,
          metric: atom() | nil,
          error: String.t(),
          category: String.t(),
          timestamp: DateTime.t()
        }

  @typedoc "Statistics aggregated by tag"
  @type tag_stats :: %{
          sample_count: non_neg_integer(),
          avg_score: float() | nil,
          pass_rate: float() | nil,
          error_rate: float() | nil
        }

  @doc """
  Create a new result structure for a run.

  ## Parameters

  - `run_id` - Unique identifier for the evaluation run
  - `config` - Optional evaluation configuration

  ## Examples

      iex> result = Jido.Eval.Result.new("eval_001")
      iex> result.run_id
      "eval_001"
      
      iex> config = %Jido.Eval.Config{tags: %{"experiment" => "test"}}
      iex> result = Jido.Eval.Result.new("eval_002", config)
      iex> result.config.tags
      %{"experiment" => "test"}
  """
  def new(run_id, config \\ nil) do
    %__MODULE__{
      run_id: run_id,
      config: config,
      start_time: DateTime.utc_now()
    }
  end

  @doc """
  Add a sample result to the evaluation.

  Updates counters, aggregated statistics, and error tracking.

  ## Parameters

  - `result` - Current result structure
  - `sample_result` - Individual sample evaluation result

  ## Examples

      iex> result = Jido.Eval.Result.new("eval_001")
      iex> sample_result = %{sample_id: "s1", scores: %{faithfulness: 0.8}, latency_ms: 1200, error: nil, tags: %{}, metadata: %{}}
      iex> updated = Jido.Eval.Result.add_sample_result(result, sample_result)
      iex> updated.completed_count
      1
  """
  @spec add_sample_result(t(), sample_result()) :: t()
  def add_sample_result(result, sample_result) do
    updated_results = [sample_result | result.sample_results]

    updated_result = %{
      result
      | sample_results: updated_results,
        sample_count: result.sample_count + 1
    }

    cond do
      sample_result.error != nil ->
        error = %{
          sample_id: sample_result.sample_id,
          metric: nil,
          error: sample_result.error,
          category: categorize_error(sample_result.error),
          timestamp: DateTime.utc_now()
        }

        %{updated_result | error_count: result.error_count + 1, errors: [error | result.errors]}

      true ->
        %{updated_result | completed_count: result.completed_count + 1}
    end
    |> update_tag_stats(sample_result)
  end

  @doc """
  Finalize the evaluation result with aggregated statistics.

  Calculates summary statistics, latency metrics, pass rates,
  and error categorization.

  ## Parameters

  - `result` - Result structure to finalize
  - `opts` - Optional finalization settings

  ## Examples

      iex> result = %Jido.Eval.Result{run_id: "eval_001", start_time: ~U[2024-01-01 00:00:00Z]}
      iex> finalized = Jido.Eval.Result.finalize(result)
      iex> finalized.finish_time != nil
      true
  """
  @spec finalize(t(), keyword()) :: t()
  def finalize(result, _opts \\ []) do
    finish_time = DateTime.utc_now()

    duration_ms =
      if result.start_time do
        DateTime.diff(finish_time, result.start_time, :millisecond)
      else
        nil
      end

    result
    |> Map.put(:finish_time, finish_time)
    |> Map.put(:duration_ms, duration_ms)
    |> calculate_summary_stats()
    |> calculate_latency_stats()
    |> calculate_pass_rate()
    |> categorize_errors()
    |> finalize_tag_stats()
  end

  # Private implementation functions

  defp calculate_summary_stats(result) do
    summary_stats =
      result.sample_results
      |> Enum.reject(fn sample -> sample.error != nil end)
      |> Enum.reduce(%{}, fn sample, acc ->
        Enum.reduce(sample.scores, acc, fn {metric, score}, metric_acc ->
          scores = Map.get(metric_acc, metric, [])
          Map.put(metric_acc, metric, [score | scores])
        end)
      end)
      |> Enum.into(%{}, fn {metric, scores} ->
        {metric, calculate_metric_stats(scores)}
      end)

    %{result | summary_stats: summary_stats}
  end

  defp calculate_metric_stats([]),
    do: %{
      mean: 0.0,
      median: 0.0,
      std_dev: 0.0,
      min: 0.0,
      max: 0.0,
      p50: 0.0,
      p95: 0.0,
      p99: 0.0,
      count: 0
    }

  defp calculate_metric_stats(scores) do
    sorted_scores = Enum.sort(scores)
    count = length(scores)
    mean = Enum.sum(scores) / count

    variance =
      scores
      |> Enum.map(fn score -> :math.pow(score - mean, 2) end)
      |> Enum.sum()
      |> Kernel./(count)

    std_dev = :math.sqrt(variance)

    %{
      mean: mean,
      median: percentile(sorted_scores, 50),
      std_dev: std_dev,
      min: List.first(sorted_scores),
      max: List.last(sorted_scores),
      p50: percentile(sorted_scores, 50),
      p95: percentile(sorted_scores, 95),
      p99: percentile(sorted_scores, 99),
      count: count
    }
  end

  defp calculate_latency_stats(result) do
    latencies =
      result.sample_results
      |> Enum.filter(fn sample -> sample.latency_ms != nil end)
      |> Enum.map(fn sample -> sample.latency_ms end)

    latency_stats =
      case latencies do
        [] ->
          %{}

        _ ->
          sorted = Enum.sort(latencies)
          avg = Enum.sum(latencies) / length(latencies)

          %{
            avg_ms: avg,
            median_ms: percentile(sorted, 50),
            p95_ms: percentile(sorted, 95),
            p99_ms: percentile(sorted, 99),
            max_ms: List.last(sorted),
            min_ms: List.first(sorted)
          }
      end

    %{result | latency: latency_stats}
  end

  defp calculate_pass_rate(result) do
    completed_samples = Enum.filter(result.sample_results, fn sample -> sample.error == nil end)

    # Only calculate pass rate if we have samples with actual scores
    samples_with_scores =
      Enum.filter(completed_samples, fn sample ->
        map_size(sample.scores) > 0
      end)

    pass_rate =
      case samples_with_scores do
        [] ->
          nil

        samples ->
          # Calculate overall pass rate based on metric thresholds
          # For simplicity, we'll use 0.5 as threshold for all metrics
          passing_samples =
            Enum.count(samples, fn sample ->
              scores = Map.values(sample.scores)
              Enum.all?(scores, fn score -> score >= 0.5 end)
            end)

          passing_samples / length(samples)
      end

    %{result | pass_rate: pass_rate}
  end

  defp categorize_errors(result) do
    error_categories =
      result.errors
      |> Enum.group_by(fn error -> error.category end)
      |> Enum.into(%{}, fn {category, errors} -> {category, length(errors)} end)

    %{result | error_categories: error_categories}
  end

  defp finalize_tag_stats(result) do
    by_tag =
      result.by_tag
      |> Enum.into(%{}, fn {tag_value, stats} ->
        completed = stats[:completed] || 0
        total = stats[:total] || 0
        scores = stats[:scores] || []

        tag_stats = %{
          sample_count: total,
          avg_score: if(scores == [], do: nil, else: Enum.sum(scores) / length(scores)),
          pass_rate: if(total == 0, do: nil, else: completed / total),
          error_rate: if(total == 0, do: nil, else: (total - completed) / total)
        }

        {tag_value, tag_stats}
      end)

    %{result | by_tag: by_tag}
  end

  defp update_tag_stats(result, sample_result) do
    by_tag =
      sample_result.tags
      |> Enum.reduce(result.by_tag, fn {tag_key, tag_value}, acc ->
        key = "#{tag_key}:#{tag_value}"
        current = Map.get(acc, key, %{total: 0, completed: 0, scores: []})

        updated = %{
          total: current[:total] + 1,
          completed: current[:completed] + if(sample_result.error == nil, do: 1, else: 0),
          scores:
            case sample_result.error do
              nil ->
                new_scores = sample_result.scores |> Map.values()
                (current[:scores] || []) ++ new_scores

              _ ->
                current[:scores] || []
            end
        }

        Map.put(acc, key, updated)
      end)

    %{result | by_tag: by_tag}
  end

  defp categorize_error(error_string) when is_binary(error_string) do
    cond do
      String.contains?(error_string, "timeout") -> "timeout"
      String.contains?(error_string, "llm_error") -> "llm_error"
      String.contains?(error_string, "missing_field") -> "validation"
      String.contains?(error_string, "invalid_sample") -> "validation"
      true -> "unknown"
    end
  end

  defp categorize_error(_), do: "unknown"

  defp percentile([], _), do: 0.0
  defp percentile([single], _), do: single

  defp percentile(sorted_list, percentile) when percentile >= 0 and percentile <= 100 do
    count = length(sorted_list)
    index = percentile / 100 * (count - 1)

    lower_index = trunc(index)
    upper_index = min(lower_index + 1, count - 1)

    if lower_index == upper_index do
      Enum.at(sorted_list, lower_index)
    else
      lower_value = Enum.at(sorted_list, lower_index)
      upper_value = Enum.at(sorted_list, upper_index)
      weight = index - lower_index

      lower_value + weight * (upper_value - lower_value)
    end
  end
end
