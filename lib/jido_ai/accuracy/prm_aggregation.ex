defmodule Jido.AI.Accuracy.PrmAggregation do
  @moduledoc """
  Aggregation strategies for combining step scores from Process Reward Models.

  When a PRM evaluates a reasoning trace, it produces individual scores
  for each step. This module provides strategies to combine those step
  scores into an overall candidate score.

  ## Strategies

  - `:sum` - Sum of all step scores (default)
  - `:product` - Product of normalized scores (probability-style)
  - `:min` - Minimum score (bottleneck approach)
  - `:max` - Maximum score (best-step approach)
  - `:average` - Arithmetic mean of scores
  - `:weighted_average` - Custom weights per step

  ## Usage

      # Sum aggregation (default)
      {:ok, step_scores} = prm.score_trace(trace, context, opts)
      aggregated = PrmAggregation.aggregate(step_scores, :sum)

      # Product aggregation (any bad step kills the score)
      aggregated = PrmAggregation.aggregate(step_scores, :product)

      # Min aggregation (weakest step determines quality)
      aggregated = PrmAggregation.aggregate(step_scores, :min)

      # Weighted average (custom importance per step)
      weights = [0.2, 0.3, 0.5]  # Later steps more important
      aggregated = PrmAggregation.weighted_average(step_scores, weights)

  ## Strategy Comparison

  | Strategy | Use Case | Behavior |
  |----------|----------|----------|
  | `:sum` | Overall quality | Total score across all steps |
  | `:product` | All-or-nothing | Any zero/negative score brings total to zero |
  | `:min` | Bottleneck detection | Weakest step determines quality |
  | `:max` | Best-step | At least one good step |
  | `:average` | Balanced | Average quality across steps |
  | `:weighted_average` | Custom importance | Weight by step position/importance |

  ## Normalization

  Before aggregation, scores can be normalized to a standard range:

      normalized = PrmAggregation.normalize_scores(step_scores, {0.0, 1.0})
      aggregated = PrmAggregation.aggregate(normalized, :sum)

  ## Examples

      # Sum: Total quality
      PrmAggregation.sum_scores([0.8, 0.9, 0.7])
      # => 2.4

      # Product: All steps must be good
      PrmAggregation.product_scores([0.8, 0.9, 0.7])
      # => 0.504

      # Min: Bottleneck detection
      PrmAggregation.min_score([0.8, 0.9, 0.7])
      # => 0.7

      # Weighted average: Later steps more important
      PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.2, 0.3, 0.5])
      # => 0.77

  """

  @type strategy ::
          :sum
          | :product
          | :min
          | :max
          | :average
          | :weighted_average
  @type scores :: [number()]
  @type weights :: [number()]

  @doc """
  Aggregates step scores using the specified strategy.

  ## Parameters

  - `scores` - List of step scores from a PRM
  - `strategy` - Aggregation strategy to use
  - `opts` - Strategy-specific options (e.g., `:weights` for weighted_average)

  ## Returns

  Aggregated score (numeric value)

  ## Examples

      iex> PrmAggregation.aggregate([0.8, 0.9, 0.7], :sum)
      2.4

      iex> PrmAggregation.aggregate([0.8, 0.9, 0.7], :min)
      0.7

      iex> PrmAggregation.aggregate([0.8, 0.9, 0.7], :product)
      0.504

      iex> PrmAggregation.aggregate([0.8, 0.9, 0.7], :weighted_average, weights: [0.2, 0.3, 0.5])
      0.77

  """
  @spec aggregate(scores(), strategy(), keyword()) :: number()
  def aggregate(scores, strategy, opts \\ [])

  def aggregate(scores, :sum, _opts) do
    sum_scores(scores)
  end

  def aggregate(scores, :product, _opts) do
    product_scores(scores)
  end

  def aggregate(scores, :min, _opts) do
    min_score(scores)
  end

  def aggregate(scores, :max, _opts) do
    max_score(scores)
  end

  def aggregate(scores, :average, _opts) do
    average_score(scores)
  end

  def aggregate(scores, :weighted_average, opts) do
    weights = Keyword.get(opts, :weights)
    weighted_average(scores, weights)
  end

  def aggregate(_scores, strategy, _opts) do
    raise ArgumentError, "Unknown aggregation strategy: #{inspect(strategy)}"
  end

  @doc """
  Computes the sum of all step scores.

  This strategy gives the total quality across all steps.
  Higher scores indicate more total "correctness" in the reasoning.

  ## Examples

      iex> PrmAggregation.sum_scores([0.8, 0.9, 0.7])
      2.4

      iex> PrmAggregation.sum_scores([])
      0

  """
  @spec sum_scores(scores()) :: number()
  def sum_scores(scores) when is_list(scores) do
    Enum.sum(scores)
  end

  @doc """
  Computes the product of all step scores.

  This strategy is probability-style: any step with a very low score
  will significantly reduce the overall quality. Useful when all steps
  must be correct for the answer to be valid.

  Scores are assumed to be in the [0, 1] range. For other ranges,
  normalize first using `normalize_scores/2`.

  ## Examples

      iex> PrmAggregation.product_scores([0.8, 0.9, 0.7])
      0.504

      iex> PrmAggregation.product_scores([0.8, 0.0, 0.7])
      0.0

      iex> PrmAggregation.product_scores([])
      1

  """
  @spec product_scores(scores()) :: number()
  def product_scores([]), do: 1

  def product_scores(scores) when is_list(scores) do
    Enum.reduce(scores, 1, fn score, acc -> acc * score end)
  end

  @doc """
  Returns the minimum step score.

  This bottleneck approach means the weakest step determines the overall
  quality. Useful for detecting critical errors in reasoning.

  ## Examples

      iex> PrmAggregation.min_score([0.8, 0.9, 0.7])
      0.7

      iex> PrmAggregation.min_score([0.8, 0.3, 0.9])
      0.3

  """
  @spec min_score(scores()) :: number() | nil
  def min_score([]), do: nil

  def min_score(scores) when is_list(scores) do
    Enum.min(scores)
  end

  @doc """
  Returns the maximum step score.

  This best-step approach means at least one good step is enough.
  Less commonly used but can be useful for some scenarios.

  ## Examples

      iex> PrmAggregation.max_score([0.8, 0.9, 0.7])
      0.9

      iex> PrmAggregation.max_score([0.2, 0.3, 0.9])
      0.9

  """
  @spec max_score(scores()) :: number() | nil
  def max_score([]), do: nil

  def max_score(scores) when is_list(scores) do
    Enum.max(scores)
  end

  @doc """
  Computes the arithmetic mean of step scores.

  This provides a balanced view of overall quality.

  ## Examples

      iex> PrmAggregation.average_score([0.8, 0.9, 0.7])
      0.8

      iex> PrmAggregation.average_score([1.0, 0.0, 1.0])
      0.6666666666666666

  """
  @spec average_score(scores()) :: number() | nil
  def average_score([]), do: nil

  def average_score(scores) when is_list(scores) do
    Enum.sum(scores) / length(scores)
  end

  @doc """
  Computes a weighted average of step scores.

  Weights allow giving more importance to certain steps.
  Common patterns:
  - Later steps more important (e.g., [0.2, 0.3, 0.5])
  - Earlier steps more important (e.g., [0.5, 0.3, 0.2])
  - Uniform weights (same as average)

  ## Parameters

  - `scores` - List of step scores
  - `weights` - List of weights (must sum to 1.0, same length as scores)

  ## Examples

      iex> PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.2, 0.3, 0.5])
      0.77

      iex> PrmAggregation.weighted_average([0.8, 0.9, 0.7], [0.5, 0.3, 0.2])
      0.83

  """
  @spec weighted_average(scores(), weights()) :: number() | nil
  def weighted_average([], _weights), do: nil

  def weighted_average(scores, weights) when is_list(scores) and is_list(weights) do
    if length(scores) != length(weights) do
      raise ArgumentError,
            "Scores and weights must have the same length: got #{length(scores)} and #{length(weights)}"
    end

    weight_sum = Enum.sum(weights)

    if abs(weight_sum - 1.0) > 0.001 do
      raise ArgumentError,
            "Weights must sum to 1.0, got #{weight_sum}. Use normalize_weights/1 to normalize."
    end

    Enum.zip(scores, weights)
    |> Enum.map(fn {score, weight} -> score * weight end)
    |> Enum.sum()
  end

  @doc """
  Normalizes a list of weights to sum to 1.0.

  ## Examples

      iex> PrmAggregation.normalize_weights([2, 3, 5])
      [0.2, 0.3, 0.5]

      iex> PrmAggregation.normalize_weights([1, 1, 1])
      [0.3333333333333333, 0.3333333333333333, 0.3333333333333333]

  """
  @spec normalize_weights([number()]) :: [number()]
  def normalize_weights([]), do: []

  def normalize_weights(weights) when is_list(weights) do
    sum = Enum.sum(weights)
    if sum == 0, do: [0.0], else: Enum.map(weights, fn w -> w / sum end)
  end

  @doc """
  Normalizes scores to a standard range.

  Useful before aggregation when scores may come from different
  PRMs with different ranges.

  ## Parameters

  - `scores` - List of scores to normalize
  - `range` - Target range as {min, max}

  ## Examples

      iex> PrmAggregation.normalize_scores([5, 8, 10], {0.0, 1.0})
      [0.5, 0.8, 1.0]

      iex> PrmAggregation.normalize_scores([-1, 0, 1], {0.0, 1.0})
      [0.0, 0.5, 1.0]

  """
  @spec normalize_scores(scores(), {number(), number()}) :: [number()]
  def normalize_scores([], _range), do: []

  def normalize_scores(scores, {min_target, max_target}) when is_list(scores) do
    {min_source, max_source} = find_min_max(scores)
    range_source = max_source - min_source
    range_target = max_target - min_target

    if range_source == 0 do
      # All scores are the same
      List.duplicate(midpoint({min_target, max_target}), length(scores))
    else
      Enum.map(scores, fn score ->
        normalized = (score - min_source) / range_source
        normalized * range_target + min_target
      end)
    end
  end

  @doc """
  Applies softmax normalization to scores.

  Converts scores to probabilities that sum to 1.0.
  Useful for attention-like weighting.

  ## Examples

      iex> PrmAggregation.softmax([1.0, 2.0, 3.0])
      [0.09003057917038508, 0.24472847774992302, 0.6652409430796919]

  """
  @spec softmax(scores()) :: [number()]
  def softmax([]), do: []

  def softmax(scores) when is_list(scores) do
    # Subtract max for numerical stability
    max = Enum.max(scores)

    exps = Enum.map(scores, fn s -> :math.exp(s - max) end)
    sum = Enum.sum(exps)

    Enum.map(exps, fn e -> e / sum end)
  end

  # Private helper functions

  defp find_min_max(scores) do
    {Enum.min(scores), Enum.max(scores)}
  end

  defp midpoint({min, max}), do: (min + max) / 2
end
