defmodule Jido.AI.Accuracy.ConfidenceEstimator do
  @moduledoc """
  Behavior for confidence estimation in the accuracy improvement system.

  Confidence estimators analyze candidate responses to determine how confident
  the system should be in the answer. This confidence is used for calibration
  gates, selective generation, and uncertainty quantification.

  ## Required Callbacks

  Every confidence estimator must implement:

  - `estimate/2` - Estimate confidence for a single candidate

  ## Optional Callbacks

  - `estimate_batch/2` - Estimate confidence for multiple candidates efficiently

  ## Usage

  Implement this behavior to create custom confidence estimators:

      defmodule MyApp.Estimators.Custom do
        @behaviour Jido.AI.Accuracy.ConfidenceEstimator

        defstruct [:config]

        @impl true
        def estimate(estimator, candidate, context) do
          # Calculate confidence score
          score = calculate_confidence(candidate, context)

          {:ok, ConfidenceEstimate.new!(%{
            score: score,
            method: :custom,
            reasoning: "Confidence based on custom analysis"
          })}
        end
      end

  ## Estimation Methods

  ### Attention-Based (Logprob)

  Uses token-level log probabilities from the model:

      {:ok, estimate} = AttentionConfidence.estimate(candidate, %{})

  ### Ensemble

  Combines multiple estimation methods:

      {:ok, estimate} = EnsembleConfidence.estimate(estimator, candidate, %{
        estimators: [AttentionConfidence, AnotherMethod]
      })

  ### Length-Based

  Shorter answers tend to be more confident (heuristic):

      score = 1.0 - min(String.length(content) / 1000, 0.5)

  ### Keyword-Based

  Looks for uncertainty indicators:

      uncertainty_words = ["maybe", "possibly", "I think", "probably"]
      has_uncertainty = Enum.any?(uncertainty_words, &String.contains?(content, &1))

  ## Context

  The context map may contain:
  - `:prompt` - Original prompt/question
  - `:domain` - Domain for specialized estimation (e.g., :math, :code)
  - `:aggregation` - How to aggregate token probabilities (for logprob methods)
  - `:thresholds` - Custom thresholds for confidence levels
  - Custom keys for specific estimator implementations

  ## Confidence Levels

  Estimates should produce scores in range [0.0, 1.0]:
  - **High (≥ 0.7)**: Direct answer is acceptable
  - **Medium (0.4 - 0.7)**: Include verification/citations
  - **Low (< 0.4)**: Abstain or escalate

  ## Return Values

  The `estimate/2` callback should return:

  - `{:ok, ConfidenceEstimate.t()}` - Successfully estimated
  - `{:error, reason}` - Estimation failed (e.g., missing data)

  The `estimate_batch/2` callback should return:

  - `{:ok, [ConfidenceEstimate.t()]}` - All candidates estimated
  - `{:error, reason}` - Batch estimation failed

  """

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate}

  @type context :: map()
  @type estimate_result :: {:ok, ConfidenceEstimate.t()} | {:error, term()}

  @doc """
  Estimates confidence for the given candidate.

  ## Parameters

  - `estimator` - The estimator struct (self)
  - `candidate` - The candidate to estimate confidence for
  - `context` - Additional context for estimation

  ## Returns

  - `{:ok, ConfidenceEstimate.t()}` on success
  - `{:error, reason}` on failure

  """
  @callback estimate(struct(), Candidate.t(), context()) :: estimate_result()

  @doc """
  Estimates confidence for multiple candidates.

  This callback is optional. If not implemented, the default
  implementation calls `estimate/3` for each candidate.

  ## Parameters

  - `estimator` - The estimator struct (self)
  - `candidates` - List of candidates to estimate
  - `context` - Additional context for estimation

  ## Returns

  - `{:ok, [ConfidenceEstimate.t()]}` on success
  - `{:error, reason}` on failure

  """
  @callback estimate_batch(struct(), [Candidate.t()], context()) :: {:ok, [ConfidenceEstimate.t()]} | {:error, term()}

  @optional_callbacks [estimate_batch: 3]

  @doc """
  Default implementation for batch confidence estimation.

  Calls `estimate/3` for each candidate sequentially.

  """
  @spec estimate_batch([Candidate.t()], context(), module()) :: {:ok, [ConfidenceEstimate.t()]} | {:error, term()}
  def estimate_batch(candidates, context, estimator) when is_list(candidates) do
    results =
      Enum.map(candidates, fn candidate ->
        estimator.estimate(estimator, candidate, context)
      end)

    errors =
      Enum.filter(results, fn
        {:error, _} -> true
        _ -> false
      end)

    if Enum.empty?(errors) do
      {:ok,
       Enum.map(results, fn
         {:ok, estimate} -> estimate
         _ -> nil
       end)}
    else
      {:error, :batch_estimation_failed}
    end
  end

  @doc """
  Checks if the given module is a confidence estimator.

  A module is considered a confidence estimator if it exports `estimate/3`.

  """
  @spec estimator?(term()) :: boolean()
  def estimator?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :estimate, 3)
  end

  def estimator?(_), do: false

  @doc """
  Gets the confidence estimator behavior.

  """
  @spec behaviour() :: module()
  def behaviour, do: __MODULE__
end
