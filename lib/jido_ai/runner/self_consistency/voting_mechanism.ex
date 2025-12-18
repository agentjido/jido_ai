defmodule Jido.AI.Runner.SelfConsistency.VotingMechanism do
  @moduledoc """
  Voting and consensus mechanisms for self-consistency CoT.

  Implements multiple voting strategies to select the most reliable answer
  from multiple reasoning paths:

  ## Voting Strategies

  - **Majority Voting**: Select answer with highest frequency
  - **Confidence-Weighted**: Weight votes by path confidence scores
  - **Quality-Weighted**: Weight votes by path quality scores
  - **Hybrid**: Combine multiple weighting factors

  ## Tie-Breaking

  When multiple answers have equal votes, tie-breaking strategies:
  - Highest average confidence
  - Highest average quality
  - First occurrence
  - Random selection

  ## Research

  Self-consistency with majority voting shows +17.9% accuracy improvement
  on GSM8K benchmark. Confidence weighting can further improve reliability
  on tasks with varying reasoning quality.
  """

  require Logger

  alias Jido.AI.Runner.SelfConsistency.AnswerExtractor

  @type reasoning_path :: %{
          reasoning: String.t(),
          answer: term(),
          confidence: float(),
          quality_score: float()
        }

  @type vote_result :: %{
          answer: term(),
          confidence: float(),
          consensus: float(),
          paths: list(reasoning_path()),
          votes: map(),
          metadata: map()
        }

  @default_tie_breaker :highest_confidence
  @default_strategy :majority

  @doc """
  Performs voting to select the most reliable answer.

  ## Parameters

  - `paths` - List of reasoning paths with answers
  - `opts` - Options:
    - `:strategy` - Voting strategy (:majority, :confidence_weighted, :quality_weighted, :hybrid)
    - `:tie_breaker` - Tie-breaking strategy (:highest_confidence, :highest_quality, :first, :random)
    - `:semantic_equivalence` - Group semantically equivalent answers (default: true)
    - `:domain` - Domain for semantic equivalence checking

  ## Returns

  - `{:ok, result}` - Voting result with selected answer
  - `{:error, reason}` - Voting failed

  ## Examples

      paths = [
        %{answer: 42, confidence: 0.8, quality_score: 0.9},
        %{answer: 42, confidence: 0.7, quality_score: 0.8},
        %{answer: 43, confidence: 0.6, quality_score: 0.7}
      ]

      {:ok, result} = VotingMechanism.vote(paths)
      # => {:ok, %{answer: 42, confidence: 0.75, consensus: 0.67, ...}}
  """
  @spec vote(list(reasoning_path()), keyword()) :: {:ok, vote_result()} | {:error, term()}
  def vote(paths, opts \\ []) do
    if Enum.empty?(paths) do
      {:error, :no_paths_to_vote}
    else
      strategy = Keyword.get(opts, :strategy, @default_strategy)
      tie_breaker = Keyword.get(opts, :tie_breaker, @default_tie_breaker)
      semantic_eq = Keyword.get(opts, :semantic_equivalence, true)
      domain = Keyword.get(opts, :domain, :general)

      # Group paths by answer (with semantic equivalence if enabled)
      grouped = group_by_answer(paths, semantic_eq, domain)

      # Perform voting based on strategy
      case perform_voting(grouped, strategy, tie_breaker) do
        {:ok, winner_answer, winner_paths} ->
          {:ok, build_result(winner_answer, winner_paths, paths, grouped)}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  @doc """
  Calculates the consensus level (agreement) among paths.

  Returns a value from 0.0 to 1.0 indicating the proportion of paths
  that agree with the selected answer.

  ## Parameters

  - `paths` - All reasoning paths
  - `selected_answer` - The selected answer
  - `opts` - Options:
    - `:semantic_equivalence` - Consider semantic equivalence (default: true)
    - `:domain` - Domain for equivalence checking

  ## Returns

  Float from 0.0 to 1.0

  ## Examples

      consensus = VotingMechanism.calculate_consensus(paths, 42)
      # => 0.67 (if 2 out of 3 paths agree on 42)
  """
  @spec calculate_consensus(list(reasoning_path()), term(), keyword()) :: float()
  def calculate_consensus(paths, selected_answer, opts \\ []) do
    if Enum.empty?(paths) do
      0.0
    else
      semantic_eq = Keyword.get(opts, :semantic_equivalence, true)
      domain = Keyword.get(opts, :domain, :general)

      agreeing_count =
        Enum.count(paths, fn path ->
          if semantic_eq do
            AnswerExtractor.equivalent?(path.answer, selected_answer, domain: domain)
          else
            path.answer == selected_answer
          end
        end)

      agreeing_count / length(paths)
    end
  end

  # Private functions

  defp group_by_answer(paths, semantic_eq, domain) do
    if semantic_eq do
      # Group semantically equivalent answers together
      group_semantically(paths, domain)
    else
      # Group by exact equality
      Enum.group_by(paths, & &1.answer)
    end
  end

  defp group_semantically(paths, domain) do
    # Build groups by checking semantic equivalence
    Enum.reduce(paths, %{}, fn path, groups ->
      # Find existing group with equivalent answer
      case find_equivalent_group(path.answer, groups, domain) do
        nil ->
          # No equivalent group, create new one
          Map.put(groups, path.answer, [path])

        {key, _existing_paths} ->
          # Add to existing group
          Map.update!(groups, key, fn existing -> [path | existing] end)
      end
    end)
  end

  defp find_equivalent_group(answer, groups, domain) do
    Enum.find(groups, fn {key, _paths} ->
      AnswerExtractor.equivalent?(answer, key, domain: domain)
    end)
  end

  defp perform_voting(grouped, strategy, tie_breaker) do
    case strategy do
      :majority ->
        majority_vote(grouped, tie_breaker)

      :confidence_weighted ->
        confidence_weighted_vote(grouped, tie_breaker)

      :quality_weighted ->
        quality_weighted_vote(grouped, tie_breaker)

      :hybrid ->
        hybrid_vote(grouped, tie_breaker)

      _ ->
        {:error, {:unknown_strategy, strategy}}
    end
  end

  defp majority_vote([], _tie_breaker) do
    {:error, :no_paths}
  end

  defp majority_vote(grouped, tie_breaker) do
    # Count votes for each answer
    vote_counts =
      Enum.map(grouped, fn {answer, paths} ->
        {answer, length(paths), paths}
      end)

    # Find maximum vote count
    max_votes = vote_counts |> Enum.map(fn {_, count, _} -> count end) |> Enum.max()

    # Get all answers with max votes (for tie-breaking)
    winners = Enum.filter(vote_counts, fn {_, count, _} -> count == max_votes end)

    case winners do
      [{answer, _count, paths}] ->
        {:ok, answer, paths}

      multiple_winners ->
        # Tie-breaking needed
        break_tie(multiple_winners, tie_breaker)
    end
  end

  defp confidence_weighted_vote([], _tie_breaker) do
    {:error, :no_paths}
  end

  defp confidence_weighted_vote(grouped, tie_breaker) do
    # Sum confidence scores for each answer
    weighted_votes =
      Enum.map(grouped, fn {answer, paths} ->
        total_confidence = Enum.reduce(paths, 0.0, fn path, acc -> acc + path.confidence end)
        {answer, total_confidence, paths}
      end)

    # Find maximum weighted vote
    max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()

    # Get all answers with max weight (within small epsilon for floating point)
    winners =
      Enum.filter(weighted_votes, fn {_, weight, _} ->
        abs(weight - max_weight) < 0.0001
      end)

    case winners do
      [{answer, _weight, paths}] ->
        {:ok, answer, paths}

      multiple_winners ->
        break_tie(multiple_winners, tie_breaker)
    end
  end

  defp quality_weighted_vote([], _tie_breaker) do
    {:error, :no_paths}
  end

  defp quality_weighted_vote(grouped, tie_breaker) do
    # Sum quality scores for each answer
    weighted_votes =
      Enum.map(grouped, fn {answer, paths} ->
        total_quality =
          Enum.reduce(paths, 0.0, fn path, acc -> acc + (path.quality_score || 0.0) end)

        {answer, total_quality, paths}
      end)

    # Find maximum weighted vote
    max_weight = weighted_votes |> Enum.map(fn {_, weight, _} -> weight end) |> Enum.max()

    # Get all answers with max weight
    winners =
      Enum.filter(weighted_votes, fn {_, weight, _} ->
        abs(weight - max_weight) < 0.0001
      end)

    case winners do
      [{answer, _weight, paths}] ->
        {:ok, answer, paths}

      multiple_winners ->
        break_tie(multiple_winners, tie_breaker)
    end
  end

  defp hybrid_vote([], _tie_breaker) do
    {:error, :no_paths}
  end

  defp hybrid_vote(grouped, tie_breaker) do
    # Combine multiple factors: count, confidence, quality
    weighted_votes =
      Enum.map(grouped, fn {answer, paths} ->
        count = length(paths)
        avg_confidence = Enum.reduce(paths, 0.0, fn p, acc -> acc + p.confidence end) / count

        avg_quality =
          Enum.reduce(paths, 0.0, fn p, acc -> acc + (p.quality_score || 0.0) end) / count

        # Weighted combination: 40% count, 30% confidence, 30% quality
        score = count * 0.4 + avg_confidence * count * 0.3 + avg_quality * count * 0.3

        {answer, score, paths}
      end)

    # Find maximum score
    max_score = weighted_votes |> Enum.map(fn {_, score, _} -> score end) |> Enum.max()

    # Get all answers with max score
    winners =
      Enum.filter(weighted_votes, fn {_, score, _} ->
        abs(score - max_score) < 0.0001
      end)

    case winners do
      [{answer, _score, paths}] ->
        {:ok, answer, paths}

      multiple_winners ->
        break_tie(multiple_winners, tie_breaker)
    end
  end

  defp break_tie(candidates, strategy) do
    case strategy do
      :highest_confidence ->
        break_tie_by_confidence(candidates)

      :highest_quality ->
        break_tie_by_quality(candidates)

      :first ->
        # Take first candidate
        case candidates do
          [{answer, _score, paths} | _] -> {:ok, answer, paths}
          [] -> {:error, :no_candidates}
        end

      :random ->
        # Random selection
        case Enum.random(candidates) do
          {answer, _score, paths} -> {:ok, answer, paths}
        end

      _ ->
        {:error, {:unknown_tie_breaker, strategy}}
    end
  end

  defp break_tie_by_confidence(candidates) do
    {answer, _score, paths} =
      Enum.max_by(candidates, fn {_answer, _score, paths} ->
        avg_confidence =
          Enum.reduce(paths, 0.0, fn p, acc -> acc + p.confidence end) / length(paths)

        avg_confidence
      end)

    {:ok, answer, paths}
  end

  defp break_tie_by_quality(candidates) do
    {answer, _score, paths} =
      Enum.max_by(candidates, fn {_answer, _score, paths} ->
        avg_quality =
          Enum.reduce(paths, 0.0, fn p, acc -> acc + (p.quality_score || 0.0) end) / length(paths)

        avg_quality
      end)

    {:ok, answer, paths}
  end

  defp build_result(winner_answer, winner_paths, all_paths, grouped) do
    # Calculate metrics
    avg_confidence =
      if Enum.empty?(winner_paths) do
        0.0
      else
        Enum.reduce(winner_paths, 0.0, fn p, acc -> acc + p.confidence end) / length(winner_paths)
      end

    consensus = length(winner_paths) / length(all_paths)

    # Build vote count map
    votes =
      Enum.into(grouped, %{}, fn {answer, paths} ->
        {answer, length(paths)}
      end)

    # Metadata
    metadata = %{
      total_paths: length(all_paths),
      unique_answers: map_size(grouped),
      winning_paths: length(winner_paths),
      vote_distribution: votes
    }

    %{
      answer: winner_answer,
      confidence: avg_confidence,
      consensus: consensus,
      paths: winner_paths,
      votes: votes,
      metadata: metadata
    }
  end
end
