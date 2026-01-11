defmodule Jido.AI.Accuracy.Prm do
  @moduledoc """
  Behavior for Process Reward Models (PRMs) in the accuracy improvement system.

  A Process Reward Model evaluates individual reasoning steps rather than
  just the final answer. This enables early error detection, guided search,
  and targeted reflection.

  ## Required Callbacks

  Every PRM must implement:

  - `score_step/3` - Score a single reasoning step
  - `score_trace/3` - Score a full trace of reasoning steps

  ## Optional Callbacks

  - `classify_step/3` - Classify a step as :correct, :incorrect, or :neutral
  - `supports_streaming?/0` - Indicates if the PRM supports streaming evaluation

  ## Usage

  Implement this behavior to create custom PRMs:

      defmodule MyApp.Prms.Custom do
        @behaviour Jido.AI.Accuracy.Prm

        @impl true
        def score_step(step, context, opts) do
          # Score the individual step
          score = calculate_step_score(step, context, opts)
          {:ok, score}
        end

        @impl true
        def score_trace(trace, context, opts) do
          # Score each step in the trace
          Enum.map(trace, fn step ->
            {:ok, score} = score_step(step, context, opts)
            score
          end)
          |> then(&{:ok, &1})
        end
      end

  ## Process vs Outcome Verification

  ### Outcome Verification (Verifier behavior)

  Scores the final answer without examining reasoning:

      {:ok, result} = verifier.verify(candidate, %{})
      result.score  # => 0.85 (overall quality)

  ### Process Verification (PRM behavior)

  Scores each reasoning step for detailed feedback:

      {:ok, scores} = prm.score_trace(["Step 1", "Step 2", "Step 3"], %{}, [])
      # => [0.9, 0.7, 0.95] (individual step scores)

      {:ok, classification} = prm.classify_step("Step with error", %{}, [])
      # => :incorrect

  ## Step Classification

  The `classify_step/3` callback returns one of:

  - `:correct` - The step is logically sound and error-free
  - `:incorrect` - The step contains errors or flawed reasoning
  - `:neutral` - The step is ambiguous or cannot be determined

  ## Aggregation

  Step scores from a PRM can be aggregated into an overall score using
  `Jido.AI.Accuracy.PrmAggregation`:

      {:ok, step_scores} = prm.score_trace(trace, context, opts)
      aggregated = PrmAggregation.aggregate(step_scores, :product)

  ## Context

  The context map contains PRM-specific information:

  - `:prompt` - Original question/prompt
  - `:previous_steps` - Previous step scores (for dependency)
  - `:step_index` - Current position in trace
  - `:question` - The main question being answered
  - PRM-specific options

  ## Examples

      # Score a single reasoning step
      {:ok, score} = prm.score_step(
        "First, I'll add 15 and 23 to get 38.",
        %{question: "What is 15 * 23?"},
        []
      )

      # Score a full reasoning trace
      {:ok, scores} = prm.score_trace(
        [
          "Let me calculate 15 * 23.",
          "15 * 23 = 15 * 20 + 15 * 3 = 300 + 45 = 345",
          "Therefore, 15 * 23 = 345."
        ],
        %{question: "What is 15 * 23?"},
        []
      )

      # Classify a step
      {:ok, classification} = prm.classify_step(
        "2 + 2 = 5",
        %{question: "What is 2 + 2?"},
        []
      )
      # => :incorrect

  ## Return Values

  The `score_step/3` callback should return:

  - `{:ok, score}` - Successfully scored, where score is a number
  - `{:error, reason}` - Scoring failed

  The `score_trace/3` callback should return:

  - `{:ok, [number()]}` - List of step scores in order
  - `{:error, reason}` - Trace scoring failed

  The `classify_step/3` callback should return:

  - `{:ok, :correct | :incorrect | :neutral}` - Step classification
  - `{:error, reason}` - Classification failed

  ## See Also

  - `Jido.AI.Accuracy.Verifier` - Outcome verification behavior
  - `Jido.AI.Accuracy.VerificationResult` - Verification result type
  - `Jido.AI.Accuracy.Prms.LLMPrm` - LLM-based PRM implementation
  - `Jido.AI.Accuracy.PrmAggregation` - Step score aggregation strategies

  """

  @type t :: module()
  @type opts :: keyword()
  @type context :: %{
          optional(:prompt) => String.t(),
          optional(:question) => String.t(),
          optional(:previous_steps) => [String.t()],
          optional(:step_index) => non_neg_integer(),
          optional(atom()) => term()
        }

  @type step_score_result :: {:ok, number()} | {:error, term()}
  @type trace_score_result :: {:ok, [number()]} | {:error, term()}
  @type step_classification :: :correct | :incorrect | :neutral
  @type classify_result :: {:ok, step_classification()} | {:error, term()}

  @doc """
  Scores a single reasoning step.

  Evaluates the quality and correctness of an individual reasoning step.
  The score should reflect how sound and correct the step is.

  ## Parameters

  - `step` - The reasoning step text to score
  - `context` - Context including the original question and previous steps
  - `opts` - PRM-specific options

  ## Returns

  - `{:ok, score}` - Successfully scored with numeric score (higher = better)
  - `{:error, reason}` - Scoring failed

  ## Examples

      iex> {:ok, score} = prm.score_step("2 + 2 = 4", %{question: "What is 2+2?"}, [])
      iex> is_number(score)
      true

  """
  @callback score_step(step :: String.t(), context :: context(), opts :: opts()) ::
              step_score_result()

  @doc """
  Scores a full trace of reasoning steps.

  Evaluates each step in a reasoning trace, returning a list of scores
  corresponding to each step in order.

  ## Parameters

  - `trace` - List of reasoning step texts
  - `context` - Context including the original question
  - `opts` - PRM-specific options

  ## Returns

  - `{:ok, scores}` - List of numeric scores, one per step
  - `{:error, reason}` - Trace scoring failed

  ## Examples

      iex> {:ok, scores} = prm.score_trace(["Step 1", "Step 2"], %{}, [])
      iex> length(scores)
      2

  ## Default Implementation

  If not implemented, the default behavior is to call `score_step/3`
  for each step in the trace sequentially.

  """
  @callback score_trace(trace :: [String.t()], context :: context(), opts :: opts()) ::
              trace_score_result()

  @doc """
  Classifies a reasoning step as correct, incorrect, or neutral.

  Provides a categorical assessment of a step rather than a numeric score.
  This can be useful for:
  - Early error detection (stop on first :incorrect)
  - Quality filtering (only keep :correct steps)
  - Debugging (identify which steps are problematic)

  ## Parameters

  - `step` - The reasoning step text to classify
  - `context` - Context including the original question
  - `opts` - PRM-specific options

  ## Returns

  - `{:ok, :correct}` - Step is logically sound and error-free
  - `{:ok, :incorrect}` - Step contains errors or flawed reasoning
  - `{:ok, :neutral}` - Step is ambiguous or cannot be determined
  - `{:error, reason}` - Classification failed

  ## Examples

      iex> {:ok, :correct} = prm.classify_step("2 + 2 = 4", %{question: "What is 2+2?"}, [])

      iex> {:ok, :incorrect} = prm.classify_step("2 + 2 = 5", %{question: "What is 2+2?"}, [])

  """
  @callback classify_step(step :: String.t(), context :: context(), opts :: opts()) ::
              classify_result()

  @doc """
  Indicates whether the PRM supports streaming evaluation.

  Streaming PRMs can evaluate reasoning traces incrementally,
  useful for long-running reasoning chains.

  ## Returns

  - `true` - PRM supports streaming
  - `false` - PRM requires complete input

  ## Examples

      iex> prm.supports_streaming?()
      true

  """
  @callback supports_streaming?() :: boolean()

  @optional_callbacks [supports_streaming?: 0]
end
