defmodule Jido.AI.Accuracy.Verifier do
  @moduledoc """
  Behavior for candidate verifiers in the accuracy improvement system.

  Verifiers evaluate candidate responses to determine quality and correctness.
  Each verifier implements the `verify/2` callback to score candidates.

  ## Required Callbacks

  Every verifier must implement:

  - `verify/2` - Verify a single candidate
  - `verify_batch/2` - Verify multiple candidates efficiently

  ## Optional Callbacks

  - `supports_streaming?/0` - Indicates if the verifier supports streaming verification

  ## Usage

  Implement this behavior to create custom verifiers:

      defmodule MyApp.Verifiers.Custom do
        @behaviour Jido.AI.Accuracy.Verifier

        @impl true
        def verify(candidate, context) do
          # Verify the candidate
          score = calculate_score(candidate, context)
          {:ok, VerificationResult.new!(%{score: score})}
        end

        @impl true
        def verify_batch(candidates, context) do
          # Verify multiple candidates efficiently
          results = Enum.map(candidates, &verify(&1, context))
          {:ok, Enum.map(results, fn {:ok, r} -> r end)}
        end
      end

  ## Verification Patterns

  ### Outcome Verification

  Scores the final answer without examining reasoning:

      {:ok, result} = verifier.verify(candidate, %{})

  ### Process Verification (PRM)

  Scores each reasoning step for detailed feedback:

      {:ok, result} = prm.verify(candidate_with_trace, %{})
      result.step_scores
      # => %{"step_1" => 0.9, "step_2" => 0.7, ...}

  ### Deterministic Verification

  Compares against known ground truth:

      {:ok, result} = deterministic_verifier.verify(candidate, %{
        ground_truth: "42"
      })

  ## Return Values

  The `verify/2` callback should return:

  - `{:ok, VerificationResult.t()}` - Successfully verified
  - `{:error, reason}` - Verification failed

  The `verify_batch/2` callback should return:

  - `{:ok, [VerificationResult.t()]}` - All candidates verified
  - `{:error, reason}` - Batch verification failed

  ## Context

  The context map contains verification-specific information:

  - `:ground_truth` - Known correct answer (for deterministic verifiers)
  - `:prompt` - Original prompt (for reference)
  - `:threshold` - Minimum passing score
  - `:domain` - Domain-specific context
  - Verifier-specific options

  ## Examples

      # Verify a candidate with LLM-based verifier
      {:ok, result} = LLMOutcomeVerifier.verify(candidate, %{
        prompt: "What is 15 * 23?",
        threshold: 0.7
      })

      # Check if verification passed
      if VerificationResult.pass?(result, 0.7) do
        # Candidate passed verification
      end

  ## See Also

  - `Jido.AI.Accuracy.VerificationResult` - Verification result type
  - `Jido.AI.Accuracy.Verifiers.LLMOutcomeVerifier` - LLM-based verification (future)
  - `Jido.AI.Accuracy.Verifiers.DeterministicVerifier` - Deterministic verification (future)

  """

  alias Jido.AI.Accuracy.{Candidate, VerificationResult}

  @type t :: module()
  @type opts :: keyword()
  @type context :: %{
          optional(:ground_truth) => String.t() | number(),
          optional(:prompt) => String.t(),
          optional(:threshold) => number(),
          optional(:domain) => atom(),
          optional(atom()) => term()
        }

  @type verify_result :: {:ok, VerificationResult.t()} | {:error, term()}
  @type verify_batch_result :: {:ok, [VerificationResult.t()]} | {:error, term()}

  @doc """
  Verifies a single candidate response.

  ## Parameters

  - `candidate` - The candidate to verify
  - `context` - Verification context (ground truth, prompt, options)

  ## Returns

  - `{:ok, result}` - Successfully verified with verification result
  - `{:error, reason}` - Verification failed

  ## Examples

      iex> {:ok, result} = verifier.verify(candidate, %{})
      iex> result.score
      0.85

  """
  @callback verify(candidate :: Candidate.t(), context :: context()) :: verify_result()

  @doc """
  Verifies multiple candidates in batch.

  This callback allows verifiers to optimize batch processing,
  such as parallel verification or batch LLM calls.

  ## Parameters

  - `candidates` - List of candidates to verify
  - `context` - Verification context

  ## Returns

  - `{:ok, results}` - List of verification results
  - `{:error, reason}` - Batch verification failed

  ## Examples

      iex> {:ok, results} = verifier.verify_batch(candidates, %{})
      iex> length(results)
      3

  ## Default Implementation

  If not implemented, the default behavior is to call `verify/2`
  for each candidate sequentially.

  """
  @callback verify_batch(
              candidates :: [Candidate.t()],
              context :: context()
            ) :: verify_batch_result()

  @doc """
  Indicates whether the verifier supports streaming verification.

  Streaming verifiers can process candidates incrementally,
  useful for long-running reasoning traces.

  ## Returns

  - `true` - Verifier supports streaming
  - `false` - Verifier requires complete input

  ## Examples

      iex> verifier.supports_streaming?()
      true

  """
  @callback supports_streaming?() :: boolean()

  @optional_callbacks [supports_streaming?: 0]
end
