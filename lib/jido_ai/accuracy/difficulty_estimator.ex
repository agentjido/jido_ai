defmodule Jido.AI.Accuracy.DifficultyEstimator do
  @moduledoc """
  Behavior for difficulty estimation in adaptive compute budgeting.

  Difficulty estimators analyze queries to determine how complex they are,
  enabling efficient resource allocation by giving more compute to difficult
  tasks and less to easy tasks.

  ## Required Callbacks

  Every difficulty estimator must implement:

  - `estimate/3` - Estimate difficulty for a query

  ## Optional Callbacks

  - `estimate_batch/3` - Estimate difficulty for multiple queries efficiently

  ## Usage

  Implement this behavior to create custom difficulty estimators:

      defmodule MyApp.Estimators.CustomDifficulty do
        @behaviour Jido.AI.Accuracy.DifficultyEstimator

        defstruct [:config]

        @impl true
        def estimate(_estimator, query, _context) do
          # Calculate difficulty based on custom logic
          score = calculate_difficulty(query)

          {:ok, DifficultyEstimate.new!(%{
            level: DifficultyEstimate.to_level(score),
            score: score,
            confidence: 0.8,
            reasoning: "Difficulty based on custom analysis"
          })}
        end
      end

  ## Estimation Methods

  ### Heuristic-Based

  Uses rule-based analysis of query features:

      {:ok, estimate} = HeuristicDifficulty.estimate(estimator, query, %{})

  Features considered:
  - Query length
  - Word complexity
  - Domain indicators (math, code, reasoning)
  - Question type (why/how vs what/when)

  ### LLM-Based

  Uses an LLM to classify difficulty:

      {:ok, estimate} = LLMDifficulty.estimate(estimator, query, %{})

  More accurate but slower than heuristic methods.

  ### Ensemble

  Combines multiple estimation methods for robustness.

  ## Context

  The context map may contain:
  - `:domain` - Known domain for specialized estimation (e.g., :math, :code)
  - `:thresholds` - Custom thresholds for difficulty levels
  - `:features` - Pre-computed features to use
  - Custom keys for specific estimator implementations

  ## Difficulty Levels

  Estimates should produce levels and scores:
  - **Easy** (score < 0.35): Simple factual questions, direct lookup
  - **Medium** (0.35 ≤ score ≤ 0.65): Some reasoning required, multi-step
  - **Hard** (score > 0.65): Complex reasoning, synthesis, creative tasks

  ## Return Values

  The `estimate/3` callback should return:

  - `{:ok, DifficultyEstimate.t()}` - Successfully estimated
  - `{:error, reason}` - Estimation failed

  The `estimate_batch/3` callback should return:

  - `{:ok, [DifficultyEstimate.t()]}` - All queries estimated
  - `{:error, reason}` - Batch estimation failed

  ## Compute Budget Mapping

  Difficulty levels map to compute budgets:

  | Level | Candidates | PRM | Search |
  |-------|-----------|-----|--------|
  | Easy  | 3         | No  | No     |
  | Medium| 5         | Yes | No     |
  | Hard  | 10        | Yes | Yes    |

  """

  alias Jido.AI.Accuracy.DifficultyEstimate

  @type context :: map()
  @type estimate_result :: {:ok, DifficultyEstimate.t()} | {:error, term()}

  @doc """
  Estimates difficulty for the given query.

  ## Parameters

  - `estimator` - The estimator struct (self)
  - `query` - The query string to analyze
  - `context` - Additional context for estimation

  ## Returns

  - `{:ok, DifficultyEstimate.t()}` on success
  - `{:error, reason}` on failure

  ## Examples

      iex> estimator = HeuristicDifficulty.new!(%{})
      iex> HeuristicDifficulty.estimate(estimator, "What is 2+2?", %{})
      {:ok, %DifficultyEstimate{level: :easy, score: 0.1, ...}}

  """
  @callback estimate(struct(), String.t(), context()) :: estimate_result()

  @doc """
  Estimates difficulty for multiple queries.

  This callback is optional. If not implemented, the default
  implementation calls `estimate/3` for each query.

  ## Parameters

  - `estimator` - The estimator struct (self)
  - `queries` - List of query strings to analyze
  - `context` - Additional context for estimation

  ## Returns

  - `{:ok, [DifficultyEstimate.t()]}` on success
  - `{:error, reason}` on failure

  """
  @callback estimate_batch(struct(), [String.t()], context()) :: {:ok, [DifficultyEstimate.t()]} | {:error, term()}

  @optional_callbacks [estimate_batch: 3]

  @doc """
  Default implementation for batch difficulty estimation.

  Calls `estimate/3` for each query sequentially.

  """
  @spec estimate_batch([String.t()], context(), module()) :: {:ok, [DifficultyEstimate.t()]} | {:error, term()}
  def estimate_batch(queries, context, estimator) when is_list(queries) do
    # Create an instance of the estimator module
    estimator_instance = estimator.new!(%{})

    results =
      Enum.map(queries, fn query ->
        estimator.estimate(estimator_instance, query, context)
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
  Checks if the given module is a difficulty estimator.

  A module is considered a difficulty estimator if it exports `estimate/3`.

  """
  @spec estimator?(term()) :: boolean()
  def estimator?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :estimate, 3)
  end

  def estimator?(_), do: false

  @doc """
  Gets the difficulty estimator behavior.

  """
  @spec behaviour() :: module()
  def behaviour, do: __MODULE__
end
