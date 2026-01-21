defmodule Jido.AI.Accuracy.Estimators.AttentionConfidence do
  @moduledoc """
  Confidence estimator based on token-level log probabilities.

  This estimator uses the model's own uncertainty signals (log probabilities)
  from the response tokens to estimate confidence. Lower log probabilities
  indicate higher uncertainty in the generated tokens.

  ## Configuration

  - `:aggregation` - How to aggregate token probabilities:
    - `:product` - Multiply all probabilities (most conservative, default)
    - `:mean` - Average of all token probabilities
    - `:min` - Use the minimum token probability
  - `:token_threshold` - Minimum per-token probability (default: 0.01)

  ## Usage

      # Create estimator with default settings
      estimator = AttentionConfidence.new!(%{})

      # Estimate confidence for a candidate with logprobs
      {:ok, candidate} = Candidate.new(%{
        content: "The answer is 42",
        metadata: %{
          logprobs: [-0.1, -0.2, -0.05, -0.3]  # Token log probabilities
        }
      })

      {:ok, estimate} = AttentionConfidence.estimate(estimator, candidate, %{})

  ## Aggregation Methods

  ### Product (Default)

  Multiplies all token probabilities together. This is the most conservative
  as it assumes all tokens must be correct:

      confidence = exp(sum(logprobs))

  ### Mean

  Takes the average of all token probabilities:

      confidence = mean(exp.(logprobs))

  ### Min

  Uses the minimum (worst) token probability:

      confidence = min(exp.(logprobs))

  ## Missing Logprobs

  If logprobs are not available in the candidate metadata, this estimator
  returns `{:error, :no_logprobs}`.

  ## Token-Level Analysis

  Use `token_confidences/1` to get per-token confidence scores:

      token_confs = AttentionConfidence.token_confidences(estimate)
      # => [0.90, 0.82, 0.95, 0.74]

  """

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate, ConfidenceEstimator, Helpers}

  import Helpers, only: [get_attr: 3]

  @behaviour ConfidenceEstimator

  @type t :: %__MODULE__{
          aggregation: :product | :mean | :min,
          token_threshold: float()
        }

  defstruct aggregation: :product,
            token_threshold: 0.01

  @doc """
  Creates a new AttentionConfidence estimator from the given attributes.

  ## Options

  - `:aggregation` - Aggregation method (default: `:product`)
  - `:token_threshold` - Minimum per-token probability (default: 0.01)

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    aggregation = get_attr(attrs, :aggregation, :product)
    token_threshold = get_attr(attrs, :token_threshold, 0.01)

    with :ok <- validate_aggregation(aggregation),
         :ok <- validate_token_threshold(token_threshold) do
      estimator = %__MODULE__{
        aggregation: aggregation,
        token_threshold: token_threshold
      }

      {:ok, estimator}
    end
  end

  @doc """
  Creates a new AttentionConfidence estimator, raising on error.

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, estimator} -> estimator
      {:error, reason} -> raise ArgumentError, "Invalid AttentionConfidence: #{format_error(reason)}"
    end
  end

  @impl true
  @doc """
  Estimates confidence based on token log probabilities.

  ## Context Options

  - `:aggregation` - Override default aggregation method
  - `:token_threshold` - Override default token threshold

  """
  @spec estimate(t(), Candidate.t(), map()) :: {:ok, ConfidenceEstimate.t()} | {:error, term()}
  def estimate(%__MODULE__{} = estimator, %Candidate{} = candidate, context) do
    aggregation = Map.get(context, :aggregation, estimator.aggregation)

    with {:ok, logprobs} <- extract_logprobs(candidate),
         {:ok, token_probs} <- calculate_token_probabilities(logprobs, estimator.token_threshold) do
      score = aggregate_confidence(token_probs, aggregation)
      reasoning = generate_reasoning(score, token_probs, aggregation)

      estimate =
        ConfidenceEstimate.new!(%{
          score: score,
          calibration: nil,
          method: :attention,
          reasoning: reasoning,
          token_level_confidence: token_probs,
          metadata: %{
            aggregation: aggregation,
            token_count: length(token_probs),
            min_token_prob: Enum.min(token_probs),
            max_token_prob: Enum.max(token_probs)
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
    results =
      Enum.map(candidates, fn candidate ->
        estimate(estimator, candidate, context)
      end)

    errors =
      Enum.filter(results, fn
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
  Extracts token-level confidences from a confidence estimate.

  Returns `nil` if the estimate doesn't contain token-level confidence.

  ## Examples

      token_confs = AttentionConfidence.token_confidences(estimate)
      # => [0.90, 0.82, 0.95, 0.74]

  """
  @spec token_confidences(ConfidenceEstimate.t()) :: [float()] | nil
  def token_confidences(%ConfidenceEstimate{token_level_confidence: confidences}) do
    confidences
  end

  # Private functions

  defp extract_logprobs(%Candidate{metadata: metadata}) when is_map(metadata) do
    case Map.get(metadata, :logprobs) do
      nil -> {:error, :no_logprobs}
      [] -> {:error, :empty_logprobs}
      logprobs when is_list(logprobs) -> validate_logprobs(logprobs)
      _ -> {:error, :invalid_logprobs}
    end
  end

  defp extract_logprobs(_), do: {:error, :no_metadata}

  # Validates that logprobs are all numeric and <= 0.0
  # Log probabilities must be negative or zero (probabilities are 0-1, so log space is non-positive)
  defp validate_logprobs(logprobs) do
    cond do
      not Enum.all?(logprobs, &is_number/1) ->
        {:error, :invalid_logprobs}

      Enum.any?(logprobs, &(&1 > 0.0)) ->
        {:error, :invalid_logprobs}

      true ->
        {:ok, logprobs}
    end
  end

  defp calculate_token_probabilities(logprobs, threshold) do
    probs =
      Enum.map(logprobs, fn logprob ->
        prob = :math.exp(logprob)
        # Clamp to threshold
        max(prob, threshold)
      end)

    {:ok, probs}
  end

  defp aggregate_confidence(token_probs, :product) do
    # Product of all probabilities (most conservative)
    Enum.reduce(token_probs, 1.0, fn prob, acc -> acc * prob end)
  end

  defp aggregate_confidence(token_probs, :mean) do
    # Mean of all probabilities
    Enum.sum(token_probs) / length(token_probs)
  end

  defp aggregate_confidence(token_probs, :min) do
    # Minimum probability (worst token)
    Enum.min(token_probs)
  end

  defp generate_reasoning(score, token_probs, aggregation) do
    min_prob = Enum.min(token_probs)
    max_prob = Enum.max(token_probs)
    token_count = length(token_probs)

    range_desc =
      if max_prob - min_prob < 0.2 do
        "consistent"
      else
        "variable"
      end

    agg_desc =
      case aggregation do
        :product -> "product aggregation"
        :mean -> "mean aggregation"
        :min -> "minimum token"
      end

    "Confidence #{:erlang.float_to_binary(score, decimals: 3)} based on #{token_count} tokens using #{agg_desc}. Token probabilities are #{range_desc} (min: #{:erlang.float_to_binary(min_prob, decimals: 3)}, max: #{:erlang.float_to_binary(max_prob, decimals: 3)})."
  end

  # Validation helpers

  defp validate_aggregation(aggregation) when aggregation in [:product, :mean, :min], do: :ok
  defp validate_aggregation(_), do: {:error, :invalid_aggregation}

  defp validate_token_threshold(t) when is_number(t) and t >= 0.0 and t <= 1.0, do: :ok
  defp validate_token_threshold(_), do: {:error, :invalid_token_threshold}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
