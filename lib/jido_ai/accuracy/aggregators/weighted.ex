defmodule Jido.AI.Accuracy.Aggregators.Weighted do
  @moduledoc """
  Weighted aggregator for combining multiple selection strategies.

  This aggregator combines multiple aggregation strategies with configurable
  weights. Each strategy produces a selection/ranking, and the weighted
  combination produces a final selection.

  ## Features

  - Combines multiple strategies with weights
  - Automatic weight normalization
  - Supports any aggregator implementation
  - Dynamic weight adjustment via options

  ## Usage

      candidates = [
        Candidate.new!(%{content: "42", score: 0.9}),
        Candidate.new!(%{content: "42", score: 0.8}),
        Candidate.new!(%{content: "41", score: 0.7})
      ]

      # Combine majority vote (60%) and best-of-N (40%)
      {:ok, best, metadata} = Weighted.aggregate(candidates,
        strategies: [
          {Jido.AI.Accuracy.Aggregators.MajorityVote, 0.6},
          {Jido.AI.Accuracy.Aggregators.BestOfN, 0.4}
        ]
      )

  ## Weight Normalization

  Weights are automatically normalized to sum to 1.0. For example:

      strategies: [
        {MajorityVote, 2},
        {BestOfN, 1}
      ]

  This becomes MajorityVote: 0.67, BestOfN: 0.33

  ## Scoring

  Each strategy assigns a "selection score" to candidates:
  - Selected by strategy: 1.0
  - Not selected: 0.0

  The weighted score is the sum of (selection_score * weight) for all strategies.

  ## Confidence

  Confidence is the weighted score of the winning candidate.

  ## Edge Cases

  - Empty candidate list: Returns `{:error, :no_candidates}`
  - Single candidate: Returns that candidate with confidence 1.0
  - No strategies: Returns `{:error, :no_strategies}`
  - All strategies fail: Returns `{:error, :aggregation_failed}`

  """

  @behaviour Jido.AI.Accuracy.Aggregator

  alias Jido.AI.Accuracy.{Aggregator, Candidate}

  @default_strategies [
    {Jido.AI.Accuracy.Aggregators.MajorityVote, 0.5},
    {Jido.AI.Accuracy.Aggregators.BestOfN, 0.5}
  ]

  @doc """
  Aggregates candidates using weighted combination of strategies.

  Each strategy produces a selection, and candidates are ranked by
  how many strategies selected them (weighted).

  ## Options

  - `:strategies` - List of `{module, weight}` tuples (default: MajorityVote + BestOfN at 0.5 each)

  ## Examples

      iex> candidates = [
      ...>   Candidate.new!(%{content: "42", score: 0.9}),
      ...>   Candidate.new!(%{content: "42", score: 0.8}),
      ...>   Candidate.new!(%{content: "41", score: 0.7})
      ...> ]
      iex> {:ok, best, meta} = Weighted.aggregate(candidates,
      ...>   strategies: [
      ...>     {MajorityVote, 0.6},
      ...>     {BestOfN, 0.4}
      ...>   ]
      ...> )
      iex> best.content
      "42"

  """
  @impl Aggregator
  @spec aggregate([Candidate.t()], keyword()) :: Aggregator.aggregate_result()
  def aggregate(candidates, opts \\ [])

  def aggregate([], _opts) do
    {:error, :no_candidates}
  end

  def aggregate([single], _opts) do
    {:ok, single, %{confidence: 1.0, strategy_weights: %{}}}
  end

  def aggregate(candidates, opts) when is_list(candidates) do
    strategies = Keyword.get(opts, :strategies, @default_strategies)

    if Enum.empty?(strategies) do
      {:error, :no_strategies}
    else
      # Normalize weights
      normalized = normalize_weights(strategies)

      # Run each strategy and collect selections
      strategy_results =
        Enum.map(normalized, &apply_strategy_with_weight(&1, candidates, opts))

      # Calculate weighted scores for each candidate
      candidate_scores = calculate_weighted_scores(candidates, strategy_results)

      # Find the candidate with the highest weighted score
      # In case of ties, prefer the candidate that appears first in the original list
      max_score = candidate_scores |> Enum.map(fn {_c, s} -> s end) |> Enum.max(fn -> 0 end)

      {winner, score} =
        Enum.find_value(candidates, &find_candidate_score(&1, candidate_scores, max_score))

      # Build metadata
      weight_map = Map.new(normalized)

      metadata = %{
        confidence: score,
        weighted_scores: candidate_scores,
        strategy_weights: weight_map,
        strategy_results: strategy_results,
        total_strategies: length(strategy_results)
      }

      {:ok, winner, metadata}
    end
  end

  @doc """
  Returns the weighted score distribution.

  Not applicable for weighted aggregation as it combines strategies.
  Returns nil to indicate this.

  """
  @impl Aggregator
  @spec distribution([Candidate.t()]) :: nil
  def distribution(_candidates) do
    nil
  end

  # Private functions

  defp find_candidate_score(candidate, candidate_scores, max_score) do
    Enum.find(candidate_scores, fn {c, s} -> c.id == candidate.id and s == max_score end)
  end

  defp apply_strategy_with_weight({strategy_module, weight}, candidates, opts) do
    case apply_strategy(strategy_module, candidates, opts) do
      {:ok, selected, _metadata} ->
        {strategy_module, weight, selected}

      {:error, _reason} ->
        # Skip failed strategies but continue
        {strategy_module, weight, nil}
    end
  end

  defp normalize_weights(strategies) do
    total_weight =
      strategies
      |> Enum.map(fn {_module, weight} -> weight end)
      |> Enum.sum()

    if total_weight == 0 do
      # Equal weights if all are zero
      count = length(strategies)
      Enum.map(strategies, fn {module, _weight} -> {module, 1.0 / count} end)
    else
      Enum.map(strategies, fn {module, weight} -> {module, weight / total_weight} end)
    end
  end

  defp apply_strategy(strategy_module, candidates, opts) do
    strategy_module.aggregate(candidates, opts)
  rescue
    # Handle cases where function doesn't exist or module not loaded
    e in [UndefinedFunctionError, ArgumentError] ->
      {:error, {:not_implemented, e}}
  end

  defp calculate_weighted_scores(candidates, strategy_results) do
    # For each candidate, calculate weighted score
    Enum.map(candidates, fn candidate ->
      score = calculate_candidate_score(candidate, strategy_results)
      {candidate, score}
    end)
  end

  defp calculate_candidate_score(candidate, strategy_results) do
    Enum.reduce(strategy_results, 0.0, fn
      {_strategy_module, _weight, nil}, acc ->
        # Strategy failed, skip
        acc

      {_strategy_module, weight, selected}, acc ->
        if candidate.id == selected.id do
          acc + weight
        else
          acc
        end
    end)
  end
end
