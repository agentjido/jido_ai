defmodule Jido.AI.Accuracy.Estimators.EnsembleConfidence do
  @moduledoc """
  Ensemble confidence estimator that combines multiple estimation methods.

  This estimator runs multiple confidence estimators and combines their
  results using a specified combination method. This provides more robust
  confidence estimates by leveraging different approaches.

  ## Configuration

  - `:estimators` - List of `{module, config}` tuples for each estimator
  - `:weights` - Weights for each estimator (for weighted mean)
  - `:combination_method` - How to combine estimates:
    - `:weighted_mean` - Weighted average of scores (default)
    - `:mean` - Simple average of scores
    - `:voting` - Majority vote on confidence level

  ## Usage

      # Create ensemble with multiple estimators
      estimator = EnsembleConfidence.new!(%{
        estimators: [
          {AttentionConfidence, [aggregation: :product]},
          {MyCustomEstimator, [param: value]}
        ],
        weights: [0.7, 0.3],
        combination_method: :weighted_mean
      })

      # Estimate confidence
      {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{})

  ## Combination Methods

  ### Weighted Mean

  Takes a weighted average of all estimator scores:

      score = sum(weight_i * score_i) / sum(weights)

  ### Mean

  Takes a simple average of all estimator scores:

      score = mean(scores)

  ### Voting

  Each estimator votes on confidence level (:high, :medium, :low).
  The majority vote determines the final score as the midpoint of that level.

  ## Disagreement Analysis

  Use `disagreement_score/2` to measure how much estimators disagree:

      {estimate, disagreement} = EnsembleConfidence.estimate_with_disagreement(
        estimator,
        candidate,
        %{}
      )

      score = EnsembleConfidence.disagreement_score(estimate, 0.5)
      # => 0.15  # 15% disagreement

  Higher disagreement scores indicate less consensus among estimators,
  which may indicate the response is ambiguous or uncertain.

  ## Handling Failures

  If any estimator fails, it is excluded from the ensemble. If all
  estimators fail, the ensemble returns an error.

  """

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate, ConfidenceEstimator, Helpers}

  import Helpers, only: [get_attr: 2, get_attr: 3]

  @type t :: %__MODULE__{
          estimators: [{module(), keyword()}],
          weights: [float()] | nil,
          combination_method: :weighted_mean | :mean | :voting
        }

  @behaviour ConfidenceEstimator

  defstruct [
    estimators: [],
    weights: nil,
    combination_method: :weighted_mean
  ]

  @doc """
  Creates a new EnsembleConfidence estimator from the given attributes.

  ## Options

  - `:estimators` - List of `{module, config}` tuples (required)
  - `:weights` - Weights for each estimator (optional)
  - `:combination_method` - Combination method (default: `:weighted_mean`)

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    estimators = get_attr(attrs, :estimators, [])
    weights = get_attr(attrs, :weights)
    combination_method = get_attr(attrs, :combination_method, :weighted_mean)

    with :ok <- validate_estimators(estimators),
         :ok <- validate_weights(weights, length(estimators)),
         :ok <- validate_combination_method(combination_method) do
      estimator = %__MODULE__{
        estimators: estimators,
        weights: weights,
        combination_method: combination_method
      }

      {:ok, estimator}
    end
  end

  @doc """
  Creates a new EnsembleConfidence estimator, raising on error.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, estimator} -> estimator
      {:error, reason} -> raise ArgumentError, "Invalid EnsembleConfidence: #{inspect(reason)}"
    end
  end

  @impl true
  @doc """
  Estimates confidence using multiple estimators.

  ## Context Options

  - `:combination_method` - Override default combination method
  - `:weights` - Override default weights

  """
  @spec estimate(t(), Candidate.t(), map()) :: {:ok, ConfidenceEstimate.t()} | {:error, term()}
  def estimate(%__MODULE__{} = estimator, %Candidate{} = candidate, context) do
    combination_method = Map.get(context, :combination_method, estimator.combination_method)
    weights = Map.get(context, :weights, estimator.weights)

    with {:ok, estimates} <- run_estimators(estimator.estimators, candidate, context),
         {:ok, combined} <- combine_estimates(estimates, combination_method, weights) do
      reasoning = generate_ensemble_reasoning(estimates, combined, combination_method)

      estimate = ConfidenceEstimate.new!(%{
        score: combined.score,
        calibration: nil,
        method: :ensemble,
        reasoning: reasoning,
        token_level_confidence: nil,
        metadata: %{
          combination_method: combination_method,
          estimator_count: length(estimates),
          individual_scores: Enum.map(estimates, & &1.score),
          individual_methods: Enum.map(estimates, & &1.method),
          disagreement: calculate_disagreement(estimates)
        }
      })

      {:ok, estimate}
    end
  end

  @impl true
  @doc """
  Estimates confidence for multiple candidates.

  """
  @spec estimate_batch(t(), [Candidate.t()], map()) :: {:ok, [ConfidenceEstimate.t()]} | {:error, term()}
  def estimate_batch(%__MODULE__{} = estimator, candidates, context) when is_list(candidates) do
    results = Enum.map(candidates, fn candidate ->
      estimate(estimator, candidate, context)
    end)

    errors = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)

    if Enum.empty?(errors) do
      {:ok, Enum.map(results, fn {:ok, e} -> e end)}
    else
      {:error, :batch_estimation_failed}
    end
  end

  @doc """
  Calculates the disagreement score among estimators.

  Returns a value between 0.0 (full agreement) and 1.0 (maximum disagreement).

  ## Parameters

  - `estimates` - List of confidence estimates from individual estimators
  - `baseline` - Baseline score for comparison (optional, defaults to mean)

  ## Examples

      estimates = [
        ConfidenceEstimate.new!(%{score: 0.8, method: :method1}),
        ConfidenceEstimate.new!(%{score: 0.6, method: :method2}),
        ConfidenceEstimate.new!(%{score: 0.9, method: :method3})
      ]

      EnsembleConfidence.disagreement_score(estimates)
      # => 0.15  # Standard deviation relative to mean

  """
  @spec disagreement_score([ConfidenceEstimate.t()], float() | nil) :: float()
  def disagreement_score(estimates, baseline \\ nil) when is_list(estimates) do
    scores = Enum.map(estimates, & &1.score)

    baseline_score =
      if is_number(baseline) do
        baseline
      else
        Enum.sum(scores) / length(scores)
      end

    # Calculate mean absolute deviation from baseline
    deviations =
      Enum.map(scores, fn score ->
        abs(score - baseline_score)
      end)

    mean_deviation = Enum.sum(deviations) / length(deviations)

    # Normalize to [0, 1] range (max possible deviation is 0.5 from 0.5 baseline)
    min(mean_deviation * 2, 1.0)
  end

  @doc """
  Estimates confidence and returns the disagreement score.

  ## Returns

  `{{:ok, estimate}, disagreement}` or `{{:error, reason}, nil}`

  """
  @spec estimate_with_disagreement(t(), Candidate.t(), map()) ::
          {{:ok, ConfidenceEstimate.t()}, float()} | {{:error, term()}, nil}
  def estimate_with_disagreement(%__MODULE__{} = estimator, %Candidate{} = candidate, context) do
    combination_method = Map.get(context, :combination_method, estimator.combination_method)
    weights = Map.get(context, :weights, estimator.weights)

    with {:ok, estimates} <- run_estimators(estimator.estimators, candidate, context),
         {:ok, combined} <- combine_estimates(estimates, combination_method, weights) do
      disagreement = disagreement_score(estimates, combined.score)

      reasoning = generate_ensemble_reasoning(estimates, combined, combination_method)

      estimate = ConfidenceEstimate.new!(%{
        score: combined.score,
        calibration: nil,
        method: :ensemble,
        reasoning: reasoning,
        token_level_confidence: nil,
        metadata: %{
          combination_method: combination_method,
          estimator_count: length(estimates),
          individual_scores: Enum.map(estimates, & &1.score),
          individual_methods: Enum.map(estimates, & &1.method),
          disagreement: disagreement
        }
      })

      {{:ok, estimate}, disagreement}
    else
      {:error, reason} -> {{:error, reason}, nil}
    end
  end

  # Private functions

  defp run_estimators(estimators, candidate, context) do
    results =
      Enum.map(estimators, fn {module, config} ->
        try do
          estimator = struct!(module, config_to_map(config))

          if function_exported?(module, :estimate, 3) do
            module.estimate(estimator, candidate, context)
          else
            {:error, :invalid_estimator}
          end
        rescue
          _ -> {:error, :invalid_estimator}
        end
      end)

    successful =
      Enum.filter(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    if Enum.empty?(successful) do
      {:error, :all_estimators_failed}
    else
      {:ok, Enum.map(successful, fn {:ok, e} -> e end)}
    end
  end

  defp combine_estimates(estimates, :weighted_mean, weights) when is_list(weights) do
    if length(weights) != length(estimates) do
      {:error, :weights_length_mismatch}
    else
      zipped = Enum.zip(estimates, weights)

      weighted_sum =
        Enum.reduce(zipped, 0.0, fn {%ConfidenceEstimate{score: score}, weight}, acc ->
          acc + score * weight
        end)

      total_weight = Enum.sum(weights)

      if total_weight > 0 do
        {:ok, %ConfidenceEstimate{score: weighted_sum / total_weight}}
      else
        {:error, :zero_total_weight}
      end
    end
  end

  defp combine_estimates(estimates, :weighted_mean, _weights) do
    # No weights provided, use equal weights
    scores = Enum.map(estimates, fn %ConfidenceEstimate{score: score} -> score end)
    n = length(scores)
    sum = Enum.sum(scores)
    {:ok, %ConfidenceEstimate{score: sum / n}}
  end

  defp combine_estimates(estimates, :mean, _weights) do
    scores = Enum.map(estimates, fn %ConfidenceEstimate{score: score} -> score end)
    n = length(scores)
    sum = Enum.sum(scores)
    {:ok, %ConfidenceEstimate{score: sum / n}}
  end

  defp combine_estimates(estimates, :voting, _weights) do
    # Vote on confidence level
    levels = Enum.map(estimates, &ConfidenceEstimate.confidence_level/1)

    # Count votes
    high_count = Enum.count(levels, &(&1 == :high))
    medium_count = Enum.count(levels, &(&1 == :medium))
    low_count = Enum.count(levels, &(&1 == :low))

    # Determine winner
    winning_level =
      cond do
        high_count >= medium_count and high_count >= low_count -> :high
        medium_count >= low_count -> :medium
        true -> :low
      end

    # Use midpoint of winning level
    score =
      case winning_level do
        :high -> 0.85  # Midpoint of [0.7, 1.0]
        :medium -> 0.55  # Midpoint of [0.4, 0.7]
        :low -> 0.2  # Midpoint of [0.0, 0.4]
      end

    {:ok, %ConfidenceEstimate{score: score}}
  end

  defp calculate_disagreement(estimates) do
    disagreement_score(estimates)
  end

  defp generate_ensemble_reasoning(estimates, combined, method) do
    scores = Enum.map(estimates, & &1.score)
    methods = Enum.map(estimates, &inspect/1)

    score_str =
      scores
      |> Enum.map(&:erlang.float_to_binary(&1, decimals: 3))
      |> Enum.join(", ")

    method_str =
      case method do
        :weighted_mean -> "weighted mean"
        :mean -> "mean"
        :voting -> "majority vote"
      end

    disagreement = calculate_disagreement(estimates)
    disagreement_str = :erlang.float_to_binary(disagreement, decimals: 3)

    "Ensemble confidence #{:erlang.float_to_binary(combined.score, decimals: 3)} via #{method_str} of #{length(estimates)} estimators (individual scores: [#{score_str}]). Disagreement: #{disagreement_str}. Methods: #{Enum.join(methods, ", ")}."
  end

  # Validation helpers

  defp validate_estimators(estimators) when is_list(estimators) do
    if Enum.empty?(estimators) do
      {:error, :no_estimators}
    else
      valid? =
        Enum.all?(estimators, fn
          {module, _config} when is_atom(module) -> true
          _ -> false
        end)

      if valid? do
        :ok
      else
        {:error, :invalid_estimator_format}
      end
    end
  end

  defp validate_estimators(_), do: {:error, :invalid_estimators}

  defp validate_weights(nil, _estimator_count), do: :ok

  defp validate_weights(weights, estimator_count) when is_list(weights) do
    cond do
      length(weights) != estimator_count ->
        {:error, :weights_length_mismatch}

      not Enum.all?(weights, fn w -> is_number(w) and w >= 0 and w <= 1 end) ->
        {:error, :invalid_weight_value}

      true ->
        :ok
    end
  end

  defp validate_weights(_, _), do: {:error, :invalid_weights}

  defp validate_combination_method(method) when method in [:weighted_mean, :mean, :voting], do: :ok
  defp validate_combination_method(_), do: {:error, :invalid_combination_method}

  defp config_to_map(config) when is_list(config), do: Map.new(config)
  defp config_to_map(config) when is_map(config), do: config
end
