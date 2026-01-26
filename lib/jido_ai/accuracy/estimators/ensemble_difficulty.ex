defmodule Jido.AI.Accuracy.EnsembleDifficulty do
  @moduledoc """
  Ensemble difficulty estimator that combines multiple estimators.

  This estimator runs multiple difficulty estimators and combines their
  predictions using various strategies to improve accuracy and reliability.

  ## Combination Strategies

  - `:weighted_average` - Weighted average of scores with confidence weighting
  - `:majority_vote` - Majority vote on difficulty levels
  - `:max_confidence` - Use the estimate with highest confidence
  - `:average` - Simple average of all scores

  ## Usage

      # Create with default settings
      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{})},
          {LLMDifficulty, LLMDifficulty.new!(%{})}
        ]
      })

      # Create with custom weights
      ensemble = EnsembleDifficulty.new!(%{
        estimators: [
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{})},
          {LLMDifficulty, LLMDifficulty.new!(%{})}
        ],
        weights: [0.3, 0.7],  # 30% heuristic, 70% LLM
        combination: :weighted_average
      })

      # Estimate difficulty
      {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, query, %{})

  ## Features

  - Parallel execution of estimators
  - Configurable combination strategies
  - Fallback estimator for failures
  - Timeout protection per estimator
  - Confidence-weighted aggregation

  ## Combination Behavior

  ### Weighted Average

  Calculates weighted average of scores, where weights represent
  confidence in each estimator. Final confidence is the average
  of confidences weighted by estimator weights.

      score = w1*s1 + w2*s2 + ... + wn*sn
      confidence = w1*c1 + w2*c2 + ... + wn*cn

  ### Majority Vote

  Each estimator votes for a difficulty level. The level with
  the most votes wins. Confidence is based on vote agreement.

      agreement = max_votes / total_votes
      confidence = agreement

  ### Max Confidence

  Returns the estimate with the highest confidence score.

  ### Average

  Simple arithmetic mean of all scores and confidences.

  """

  @behaviour Jido.AI.Accuracy.DifficultyEstimator

  alias Jido.AI.Accuracy.DifficultyEstimate

  @type combination :: :weighted_average | :majority_vote | :max_confidence | :average
  @type estimator_pair :: {module(), struct()}

  @type t :: %__MODULE__{
          estimators: [estimator_pair()],
          weights: [float()] | nil,
          combination: combination(),
          fallback: module() | nil,
          timeout: pos_integer()
        }

  @default_timeout 10_000
  @default_combination :weighted_average

  defstruct [
    :estimators,
    :weights,
    fallback: nil,
    timeout: @default_timeout,
    combination: @default_combination
  ]

  @doc """
  Creates a new ensemble difficulty estimator.

  ## Parameters

  - `attrs` - Map with estimator attributes:
    - `:estimators` - List of {module, struct} tuples (required)
    - `:weights` - Optional weights for each estimator (sum to 1.0)
    - `:combination` - Combination strategy (default: :weighted_average)
    - `:fallback` - Fallback estimator module if all fail (optional)
    - `:timeout` - Per-estimator timeout in ms (default: 10_000)

  ## Returns

  `{:ok, ensemble}` on success, `{:error, reason}` on validation failure.

  ## Examples

      {:ok, ensemble} = EnsembleDifficulty.new(%{
        estimators: [
          {HeuristicDifficulty, HeuristicDifficulty.new!(%{})}
        ]
      })

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    estimators = Map.get(attrs, :estimators)
    weights = Map.get(attrs, :weights)
    combination = Map.get(attrs, :combination, @default_combination)
    fallback = Map.get(attrs, :fallback)
    timeout = Map.get(attrs, :timeout, @default_timeout)

    with :ok <- validate_estimators(estimators),
         :ok <- validate_weights(weights, length(estimators || [])),
         :ok <- validate_combination(combination),
         :ok <- validate_timeout(timeout) do
      ensemble = %__MODULE__{
        estimators: estimators,
        weights: weights,
        combination: combination,
        fallback: fallback,
        timeout: timeout
      }

      {:ok, ensemble}
    end
  end

  @doc """
  Creates a new ensemble, raising on error.

  ## Examples

      ensemble = EnsembleDifficulty.new!(%{
        estimators: [{HeuristicDifficulty, heuristic}]
      })

  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, ensemble} -> ensemble
      {:error, reason} -> raise ArgumentError, "Invalid EnsembleDifficulty: #{format_error(reason)}"
    end
  end

  @doc """
  Estimates difficulty for a query using all estimators.

  Runs all estimators in parallel and combines their results
  based on the configured combination strategy.

  ## Parameters

  - `ensemble` - The ensemble estimator
  - `query` - The query string to estimate
  - `context` - Additional context

  ## Returns

  `{:ok, estimate}` on success, `{:error, reason}` on failure.

  ## Examples

      {:ok, estimate} = EnsembleDifficulty.estimate(ensemble, "What is 2+2?", %{})

  """
  @impl true
  @spec estimate(t(), String.t(), map()) :: {:ok, DifficultyEstimate.t()} | {:error, term()}
  def estimate(%__MODULE__{} = ensemble, query, context) do
    # Validate query first
    if is_binary(query) do
      # Run all estimators in parallel
      results = run_estimators(ensemble, query, context)

      case results do
        {:ok, estimates} when is_list(estimates) and (is_list(estimates) and estimates != []) ->
          combine_results(ensemble, estimates)

        {:ok, []} ->
          # All estimators failed, try fallback
          try_fallback(ensemble, query, context)

        {:error, :invalid_query} ->
          {:error, :invalid_query}
      end
    else
      {:error, :invalid_query}
    end
  end

  @doc """
  Estimates difficulty for multiple queries.

  Runs all estimators in parallel for each query.

  ## Parameters

  - `ensemble` - The ensemble estimator
  - `queries` - List of query strings
  - `context` - Additional context

  ## Returns

  `{:ok, estimates}` on success, `{:error, reason}` on failure.

  """
  @impl true
  @spec estimate_batch(t(), [String.t()], map()) :: {:ok, [DifficultyEstimate.t()]} | {:error, term()}
  def estimate_batch(%__MODULE__{} = ensemble, queries, context) when is_list(queries) do
    # Process queries and stop on first error
    case do_estimate_batch(ensemble, queries, context, []) do
      {:ok, results} -> {:ok, Enum.reverse(results)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_estimate_batch(_ensemble, [], _context, acc), do: {:ok, acc}

  defp do_estimate_batch(ensemble, [query | rest], context, acc) do
    case estimate(ensemble, query, context) do
      {:ok, estimate} ->
        do_estimate_batch(ensemble, rest, context, [estimate | acc])

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private functions

  # Run all estimators in parallel with timeout
  defp run_estimators(%__MODULE__{estimators: estimators, timeout: timeout}, query, context) do
    tasks =
      Enum.map(estimators, fn {module, estimator_struct} ->
        Task.async(fn ->
          module.estimate(estimator_struct, query, context)
        end)
      end)

    # Wait for all tasks with timeout
    results =
      Enum.map(tasks, fn task ->
        case Task.yield(task, timeout) do
          {:ok, result} -> result
          {:exit, _} -> {:error, :estimator_crashed}
          nil -> {:error, :timeout}
        end
      end)

    # Filter out errors and return successful estimates
    successful =
      Enum.filter(results, fn
        {:ok, _estimate} -> true
        _ -> false
      end)

    handle_estimator_results(results, successful)
  end

  defp handle_estimator_results(results, successful) do
    if successful == [] do
      handle_all_failed_results(results)
    else
      {:ok, Enum.map(successful, fn {:ok, estimate} -> estimate end)}
    end
  end

  defp handle_all_failed_results(results) do
    if all_invalid_query?(results) do
      {:error, :invalid_query}
    else
      {:ok, []}
    end
  end

  defp all_invalid_query?(results) do
    Enum.all?(results, fn
      {:error, :invalid_query} -> true
      _ -> false
    end)
  end

  # Combine estimates based on combination strategy
  defp combine_results(%__MODULE__{combination: combination, weights: weights}, estimates) do
    case combination do
      :weighted_average -> combine_weighted_average(estimates, weights)
      :majority_vote -> combine_majority_vote(estimates)
      :max_confidence -> combine_max_confidence(estimates)
      :average -> combine_average(estimates)
    end
  end

  # Weighted average combination
  defp combine_weighted_average(estimates, weights) do
    num = length(estimates)
    weights = weights || List.duplicate(1.0 / num, num)

    # Normalize weights if needed
    weights =
      if Enum.sum(weights) == 1.0 do
        weights
      else
        total = Enum.sum(weights)
        Enum.map(weights, &(&1 / total))
      end

    # Calculate weighted score and confidence
    {weighted_score, weighted_confidence} =
      Enum.zip(estimates, weights)
      |> Enum.reduce({0.0, 0.0}, fn {%DifficultyEstimate{score: score, confidence: conf}, weight},
                                    {acc_score, acc_conf} ->
        {acc_score + score * weight, acc_conf + conf * weight}
      end)

    # Combine reasoning from all estimates
    reasoning = build_ensemble_reasoning(estimates, weights)

    # Combine features
    features = combine_features(estimates, weights)

    # Determine level from weighted score
    level = DifficultyEstimate.to_level(weighted_score)

    estimate = %DifficultyEstimate{
      level: level,
      score: weighted_score,
      confidence: weighted_confidence,
      reasoning: reasoning,
      features: features,
      metadata: %{
        ensemble: true,
        combination: :weighted_average,
        num_estimators: num,
        individual_scores: Enum.map(estimates, & &1.score),
        individual_confidences: Enum.map(estimates, & &1.confidence)
      }
    }

    {:ok, estimate}
  end

  # Majority vote combination
  defp combine_majority_vote(estimates) do
    # Count votes for each level
    votes =
      Enum.reduce(estimates, %{easy: 0, medium: 0, hard: 0}, fn estimate, acc ->
        Map.update!(acc, estimate.level, &(&1 + 1))
      end)

    # Find winner
    {winning_level, vote_count} =
      Enum.max_by(votes, fn {_level, count} -> count end)

    agreement = vote_count / length(estimates)
    confidence = agreement

    # Average score of estimates with winning level
    winning_estimates = Enum.filter(estimates, &(&1.level == winning_level))
    avg_score = Enum.map(winning_estimates, & &1.score) |> avg()

    reasoning = build_majority_reasoning(winning_level, vote_count, length(estimates))

    features = %{
      vote_distribution: votes,
      agreement: agreement
    }

    estimate = %DifficultyEstimate{
      level: winning_level,
      score: avg_score,
      confidence: confidence,
      reasoning: reasoning,
      features: features,
      metadata: %{
        ensemble: true,
        combination: :majority_vote,
        num_estimators: length(estimates),
        vote_distribution: votes,
        agreement: agreement
      }
    }

    {:ok, estimate}
  end

  # Max confidence combination
  defp combine_max_confidence(estimates) do
    # Find estimate with highest confidence
    best_estimate = Enum.max_by(estimates, & &1.confidence)

    reasoning =
      """
      Selected estimate with highest confidence (#{Float.round(best_estimate.confidence * 100, 1)}%).
      #{best_estimate.reasoning || ""}
      """
      |> String.trim()

    estimate = %{
      best_estimate
      | reasoning: reasoning,
        metadata: Map.put(best_estimate.metadata || %{}, :ensemble, true)
    }

    {:ok, estimate}
  end

  # Simple average combination
  defp combine_average(estimates) do
    num = length(estimates)

    avg_score = Enum.map(estimates, & &1.score) |> avg()
    avg_confidence = Enum.map(estimates, & &1.confidence) |> avg()

    reasoning = "Average of #{num} difficulty estimates."

    estimate = %DifficultyEstimate{
      level: DifficultyEstimate.to_level(avg_score),
      score: avg_score,
      confidence: avg_confidence,
      reasoning: reasoning,
      features: %{
        num_estimators: num,
        score_range: [Enum.min_by(estimates, & &1.score).score, Enum.max_by(estimates, & &1.score).score]
      },
      metadata: %{
        ensemble: true,
        combination: :average,
        num_estimators: num
      }
    }

    {:ok, estimate}
  end

  # Try fallback estimator
  defp try_fallback(%__MODULE__{fallback: nil}, _query, _context), do: {:error, :all_estimators_failed}

  defp try_fallback(%__MODULE__{fallback: fallback}, query, context) do
    case fallback.estimate(fallback, query, context) do
      {:ok, estimate} ->
        # Add note that fallback was used
        estimate = %{estimate | metadata: Map.put(estimate.metadata || %{}, :ensemble_fallback, true)}
        {:ok, estimate}

      {:error, _reason} ->
        {:error, :all_estimators_failed}
    end
  end

  # Build reasoning for weighted average
  defp build_ensemble_reasoning(estimates, weights) do
    contributions =
      Enum.zip(estimates, weights)
      |> Enum.map_join(", ", fn {%DifficultyEstimate{level: level, confidence: conf}, weight} ->
        "#{level} (#{Float.round(conf * 100, 1)}%, weight: #{Float.round(weight, 2)})"
      end)

    "Ensemble of #{length(estimates)} estimators: #{contributions}"
  end

  # Build reasoning for majority vote
  defp build_majority_reasoning(level, vote_count, total) do
    percentage = Float.round(vote_count / total * 100, 1)
    "Majority vote: #{level} (#{vote_count}/#{total} = #{percentage}%)"
  end

  # Combine features from multiple estimates
  defp combine_features(estimates, weights) do
    # Merge all feature maps with weights
    Enum.reduce(Enum.zip(estimates, weights), %{}, fn {%DifficultyEstimate{features: features}, weight}, acc ->
      merge_weighted_features(acc, features, weight)
    end)
  end

  defp merge_weighted_features(acc, features, weight) do
    Map.merge(acc, features, fn _k, v1, v2 ->
      weight_feature_value(v1, v2, weight)
    end)
  end

  defp weight_feature_value(v1, v2, weight) when is_number(v1) and is_number(v2) do
    v1 * weight + v2 * weight
  end

  defp weight_feature_value(v1, _, _weight), do: v1

  # Calculate average of a list
  defp avg([]), do: 0.0
  defp avg(list), do: Enum.sum(list) / length(list)

  # Validation functions

  defp validate_estimators(nil), do: {:error, :estimators_required}
  defp validate_estimators([]), do: {:error, :estimators_required}

  defp validate_estimators(estimators) when is_list(estimators) do
    if Enum.all?(estimators, fn
         {module, struct} when is_atom(module) and is_struct(struct) -> true
         _ -> false
       end) do
      :ok
    else
      {:error, :invalid_estimators}
    end
  end

  defp validate_estimators(_), do: {:error, :invalid_estimators}

  defp validate_weights(nil, _num_estimators), do: :ok

  defp validate_weights(weights, num_estimators) when is_list(weights) do
    cond do
      length(weights) != num_estimators ->
        {:error, :weights_length_mismatch}

      not Enum.all?(weights, &is_number/1) ->
        {:error, :invalid_weights}

      true ->
        :ok
    end
  end

  defp validate_weights(_, _), do: {:error, :invalid_weights}

  defp validate_combination(combination)
       when combination in [:weighted_average, :majority_vote, :max_confidence, :average],
       do: :ok

  defp validate_combination(_), do: {:error, :invalid_combination}

  defp validate_timeout(timeout) when is_integer(timeout) and timeout > 0, do: :ok
  defp validate_timeout(_), do: {:error, :invalid_timeout}

  defp format_error(atom) when is_atom(atom), do: atom
end
