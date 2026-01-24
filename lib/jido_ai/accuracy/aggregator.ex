defmodule Jido.AI.Accuracy.Aggregator do
  @moduledoc """
  Behavior for candidate aggregators in the accuracy improvement system.

  Aggregators select the best candidate from a list of generated candidates
  using various strategies such as majority voting, best-of-N selection, or
  weighted combination of strategies.

  ## Required Callbacks

  Every aggregator must implement:

  - `aggregate/2` - Select the best candidate from a list

  ## Usage

  Implement this behavior to create custom aggregators:

      defmodule MyApp.Aggregators.Custom do
        @behaviour Jido.AI.Accuracy.Aggregator

        @impl true
        def aggregate(candidates, opts) do
          # Select best candidate using custom logic
          {:ok, best_candidate, %{confidence: 0.9}}
        end
      end

  ## Aggregation Strategies

  Common strategies for candidate aggregation:

  - **Majority Vote**: Select the most common answer (self-consistency)
  - **Best-of-N**: Select the candidate with the highest score
  - **Weighted**: Combine multiple strategies with weights

  ## Return Value

  The `aggregate/2` callback should return:

  - `{:ok, candidate, metadata}` - Successfully selected candidate
  - `{:error, reason}` - Aggregation failed

  The metadata map must contain:
  - `:confidence` - Confidence score (0.0 to 1.0)
  - Optional strategy-specific data (vote distribution, etc.)

  ## Examples

      iex> {:ok, best, metadata} = MajorityVote.aggregate(candidates)
      iex> best.content
      "The answer is 42"
      iex> metadata.confidence
      0.8

  ## See Also

  - `Jido.AI.Accuracy.Aggregators.MajorityVote` - Majority voting implementation
  - `Jido.AI.Accuracy.Aggregators.BestOfN` - Score-based selection
  - `Jido.AI.Accuracy.Aggregators.Weighted` - Weighted combination
  """

  alias Jido.AI.Accuracy.Candidate

  @type t :: module()
  @type opts :: keyword()

  @type metadata :: %{
          optional(:confidence) => number(),
          optional(:vote_distribution) => %{String.t() => non_neg_integer()},
          optional(:score_distribution) => %{number() => non_neg_integer()},
          optional(atom()) => term()
        }

  @type aggregate_result :: {:ok, Candidate.t(), metadata()} | {:error, term()}

  @doc """
  Selects the best candidate from a list of candidates.

  ## Parameters

  - `candidates` - List of candidates to select from
  - `opts` - Aggregator-specific options

  ## Returns

  - `{:ok, candidate, metadata}` - Successfully selected candidate with metadata
  - `{:error, reason}` - Aggregation failed

  ## Metadata

  The returned metadata map must include:
  - `:confidence` - Confidence score (0.0 to 1.0)

  Additional metadata may be included based on the strategy:
  - `:vote_distribution` - For majority voting
  - `:score_distribution` - For score-based selection
  - Any strategy-specific data

  ## Examples

      iex> Aggregator.aggregate(candidates, [])
      {:ok, %Candidate{content: "42"}, %{confidence: 0.8}}

  ## Error Cases

  - `{:error, :no_candidates}` - Empty candidate list
  - `{:error, :no_scores}` - BestOfN with no scored candidates
  - `{:error, :invalid_strategy}` - Invalid strategy specified
  """
  @callback aggregate(candidates :: [Candidate.t()], opts :: opts()) :: aggregate_result()

  @doc """
  Optional callback for getting vote/score distribution.

  Returns a map showing how candidates were distributed for analysis.
  This is useful for understanding aggregation confidence.
  """
  @callback distribution(candidates :: [Candidate.t()]) :: %{String.t() => non_neg_integer()} | nil

  @optional_callbacks [distribution: 1]
end
