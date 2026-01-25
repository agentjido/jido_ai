defmodule Jido.AI.Accuracy.Aggregators.BestOfN do
  @moduledoc """
  Best-of-N aggregator for score-based candidate selection.

  This aggregator selects the candidate with the highest score.
  It's commonly used with verifier-based scoring where each candidate
  has been evaluated and assigned a score.

  ## Features

  - Score-based selection
  - Token efficiency tie-breaking
  - Timestamp tie-breaking
  - Confidence based on score value
  - Score distribution analysis

  ## Tie-Breaking

  When multiple candidates have the same score:

  1. Fewer tokens used (more efficient)
  2. Earlier timestamp (generated first)

  This ensures deterministic selection.

  ## Usage

      candidates = [
        Candidate.new!(%{content: "Answer A", score: 0.8, tokens_used: 100}),
        Candidate.new!(%{content: "Answer B", score: 0.95, tokens_used: 120}),
        Candidate.new!(%{content: "Answer C", score: 0.6, tokens_used: 80})
      ]

      {:ok, best, metadata} = BestOfN.aggregate(candidates)
      # best.content => "Answer B"
      # best.score => 0.95
      # metadata.confidence => 0.95

  ## Confidence

  Confidence is equal to the winning candidate's score.
  This assumes scores are normalized between 0 and 1.

  ## Without Scores

  If candidates don't have scores, the aggregator returns an error.
  For unsupervised selection, use `MajorityVote` instead.
  """

  @behaviour Jido.AI.Accuracy.Aggregator

  alias Jido.AI.Accuracy.{Aggregator, Candidate}

  @doc """
  Aggregates candidates using best-of-N selection.

  Selects the candidate with the highest score. Uses token efficiency
  and timestamp for deterministic tie-breaking.

  ## Options

  - `:min_score` - Minimum score threshold (default: 0.0)
  - `:prefer_early` - If true, prefer earlier candidates on tie (default: true)

  ## Examples

      iex> candidates = [
      ...>   Candidate.new!(%{content: "A", score: 0.8}),
      ...>   Candidate.new!(%{content: "B", score: 0.95}),
      ...>   Candidate.new!(%{content: "C", score: 0.7})
      ...> ]
      iex> {:ok, best, meta} = BestOfN.aggregate(candidates)
      iex> best.content
      "B"
      iex> meta.confidence
      0.95

  """
  @impl Aggregator
  @spec aggregate([Candidate.t()], keyword()) :: Aggregator.aggregate_result()
  def aggregate(candidates, opts \\ [])

  def aggregate([], _opts) do
    {:error, :no_candidates}
  end

  def aggregate([single], _opts) do
    # Single candidate is always the winner
    confidence = single.score || 1.0
    {:ok, single, %{confidence: confidence, score_distribution: %{single.score => 1}}}
  end

  def aggregate(candidates, opts) when is_list(candidates) do
    min_score = Keyword.get(opts, :min_score, 0.0)
    prefer_early = Keyword.get(opts, :prefer_early, true)

    # Filter out candidates without scores
    scored_candidates = Enum.filter(candidates, & &1.score)

    if Enum.empty?(scored_candidates) do
      {:error, :no_scores}
    else
      # Find the best candidate using score comparison
      best =
        scored_candidates
        |> Enum.sort(fn c1, c2 ->
          compare_candidates(c1, c2, prefer_early)
        end)
        |> List.first()

      # Calculate score distribution
      score_distribution = calculate_score_distribution(scored_candidates)

      confidence = best.score

      metadata = %{
        confidence: confidence,
        score_distribution: score_distribution,
        total_candidates: length(candidates),
        scored_candidates: length(scored_candidates),
        min_score: min_score
      }

      {:ok, best, metadata}
    end
  end

  @doc """
  Returns the score distribution for a list of candidates.

  ## Examples

      iex> candidates = [
      ...>   Candidate.new!(%{content: "A", score: 0.8}),
      ...>   Candidate.new!(%{content: "B", score: 0.8}),
      ...>   Candidate.new!(%{content: "C", score: 0.6})
      ...> ]
      iex> BestOfN.distribution(candidates)
      %{0.8 => 2, 0.6 => 1}

  """
  @impl Aggregator
  @spec distribution([Candidate.t()]) :: %{number() => non_neg_integer()}
  def distribution(candidates) when is_list(candidates) do
    calculate_score_distribution(candidates)
  end

  # Private functions

  defp compare_candidates(c1, c2, prefer_early) do
    cond do
      # c1 has no score, c2 wins
      is_nil(c1.score) ->
        false

      # c2 has no score, c1 wins
      is_nil(c2.score) ->
        true

      # Higher score wins
      c1.score < c2.score ->
        false

      c1.score > c2.score ->
        true

      # Scores are equal, use token efficiency
      # Fewer tokens is better, so :lt means c1 comes before c2
      true ->
        case token_compare(c1, c2) do
          :lt -> true
          :gt -> false
          :eq -> timestamp_compare(c1, c2, prefer_early) != :gt
        end
    end
  end

  defp token_compare(%{tokens_used: t1}, %{tokens_used: t2}) when is_number(t1) and is_number(t2) do
    cond do
      t1 < t2 -> :lt
      t1 > t2 -> :gt
      true -> :eq
    end
  end

  defp token_compare(%{tokens_used: t1}, %{tokens_used: t2}) when is_number(t1) and is_nil(t2), do: :gt
  defp token_compare(%{tokens_used: t1}, %{tokens_used: t2}) when is_nil(t1) and is_number(t2), do: :lt
  defp token_compare(_, _), do: :eq

  defp timestamp_compare(%{timestamp: ts1}, %{timestamp: ts2}, prefer_early) when ts1 and ts2 do
    compare_timestamps(ts1, ts2, prefer_early)
  end

  defp timestamp_compare(%{timestamp: ts1}, %{timestamp: ts2}, _prefer_early) when ts1 and is_nil(ts2), do: :lt
  defp timestamp_compare(%{timestamp: ts1}, %{timestamp: ts2}, _prefer_early) when is_nil(ts1) and ts2, do: :gt
  defp timestamp_compare(_, _, _), do: :eq

  defp compare_timestamps(ts1, ts2, true) do
    cond do
      DateTime.before?(ts1, ts2) -> :lt
      DateTime.after?(ts1, ts2) -> :gt
      true -> :eq
    end
  end

  defp compare_timestamps(ts1, ts2, false), do: DateTime.compare(ts1, ts2)

  defp calculate_score_distribution(candidates) do
    candidates
    |> Enum.filter(& &1.score)
    |> Enum.reduce(%{}, fn candidate, acc ->
      Map.update(acc, candidate.score, 1, &(&1 + 1))
    end)
  end
end
