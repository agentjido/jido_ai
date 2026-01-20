defmodule Jido.AI.Accuracy.Consensus.MajorityVote do
  @moduledoc """
  Consensus checker using majority vote aggregation.

  This consensus checker uses the majority vote aggregator to determine
  if enough agreement has been reached among candidates.

  ## Usage

      checker = MajorityVote.new!(%{threshold: 0.8})

      {:ok, reached, agreement} = MajorityVote.check(candidates)
      # => {:ok, true, 0.85}

  With options:

      {:ok, reached, agreement} = MajorityVote.check(candidates, threshold: 0.9)

  """

  @behaviour Jido.AI.Accuracy.ConsensusChecker

  alias Jido.AI.Accuracy.Aggregators.MajorityVote, as: MVAggregator
  alias Jido.AI.Accuracy.ConsensusChecker

  @default_threshold 0.8

  defstruct threshold: @default_threshold

  @type t :: %__MODULE__{
          threshold: float()
        }

  @doc """
  Creates a new MajorityVote consensus checker.

  ## Parameters

  - `attrs` - Map with:
    - `:threshold` - Agreement threshold (default: 0.8)

  ## Returns

  `{:ok, checker}` on success, `{:error, reason}` on validation failure.

  """
  def new(attrs) when is_map(attrs) do
    threshold = Map.get(attrs, :threshold, @default_threshold)

    with :ok <- validate_threshold(threshold) do
      {:ok, %__MODULE__{threshold: threshold}}
    end
  end

  @doc """
  Creates a new MajorityVote consensus checker, raising on error.

  """
  def new!(attrs) do
    case new(attrs) do
      {:ok, checker} -> checker
      {:error, reason} -> raise ArgumentError, "Invalid MajorityVote consensus checker: #{format_error(reason)}"
    end
  end

  @doc """
  Checks if consensus has been reached using majority vote.

  Uses the configured threshold from the struct.

  ## Examples

      checker = MajorityVote.new!(%{threshold: 0.8})
      {:ok, reached, agreement} = MajorityVote.check(checker, candidates)

  """
  @impl ConsensusChecker
  def check(%__MODULE__{threshold: threshold}, candidates) do
    check(candidates, threshold: threshold)
  end

  @impl ConsensusChecker
  def check(candidates, opts) when is_list(candidates) and is_list(opts) do
    threshold = Keyword.get(opts, :threshold)

    cond do
      candidates == [] ->
        {:error, :no_candidates}

      threshold == nil ->
        {:error, :no_threshold}

      not is_number(threshold) or threshold < 0.0 or threshold > 1.0 ->
        {:error, :invalid_threshold}

      true ->
        do_check(candidates, threshold)
    end
  end

  def check(_candidates, _opts) do
    {:error, :invalid_arguments}
  end

  # Private functions

  defp do_check(candidates, threshold) do
    # Use the MajorityVote aggregator to get vote distribution
    case MVAggregator.aggregate(candidates) do
      {:ok, _best, metadata} ->
        vote_distribution = Map.get(metadata, :vote_distribution, %{})
        total_candidates = length(candidates)

        if total_candidates > 0 do
          # Calculate agreement as max vote count / total
          max_votes =
            vote_distribution
            |> Map.values()
            |> Enum.max(fn -> 0 end)

          agreement = max_votes / total_candidates

          {:ok, agreement >= threshold, agreement}
        else
          {:ok, false, 0.0}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp validate_threshold(threshold) when is_number(threshold) and threshold >= 0.0 and threshold <= 1.0, do: :ok
  defp validate_threshold(_), do: {:error, :invalid_threshold}

  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
