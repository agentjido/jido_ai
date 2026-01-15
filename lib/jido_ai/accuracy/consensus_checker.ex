defmodule Jido.AI.Accuracy.ConsensusChecker do
  @moduledoc """
  Behavior for consensus checking strategies in adaptive generation.

  A ConsensusChecker determines whether enough agreement has been reached
  among generated candidates to stop generation early.

  ## Required Callbacks

  Every consensus checker must implement:

  - `check/2` - Check if consensus has been reached

  ## Optional Callbacks

  - `check/3` - Check with additional options

  ## Usage

  Implement this behavior to create custom consensus checking strategies:

      defmodule MyApp.CustomConsensus do
        @behaviour Jido.AI.Accuracy.ConsensusChecker

        defstruct [:threshold]

        def check(candidates, opts) do
          # Custom consensus logic
          agreement = calculate_agreement(candidates)
          threshold = Keyword.get(opts, :threshold, 0.8)

          {:ok, agreement >= threshold, agreement}
        end
      end

  ## Built-in Implementations

  - `Jido.AI.Accuracy.Consensus.MajorityVote` - Uses majority vote aggregator

  """

  alias Jido.AI.Accuracy.Candidate

  @doc """
  Checks if consensus has been reached among the candidates.

  ## Parameters

  - `candidates` - List of candidates to check
  - `opts` - Options for the consensus check

  ## Returns

  - `{:ok, true, agreement_score}` - Consensus reached
  - `{:ok, false, agreement_score}` - Consensus not reached
  - `{:error, reason}` - Error during check

  ## Examples

      {:ok, reached, agreement} = ConsensusChecker.check(candidates, threshold: 0.8)

  """
  @callback check([Candidate.t()], keyword()) :: {:ok, boolean(), float()} | {:error, term()}

  @doc """
  Checks if consensus has been reached with default options.

  ## Parameters

  - `candidates` - List of candidates to check

  ## Returns

  - `{:ok, true, agreement_score}` - Consensus reached
  - `{:ok, false, agreement_score}` - Consensus not reached
  - `{:error, reason}` - Error during check

  """
  @callback check([Candidate.t()]) :: {:ok, boolean(), float()} | {:error, term()}

  @optional_callbacks [check: 1]

  @doc """
  Returns true if the module implements the ConsensusChecker behavior.

  ## Examples

      ConsensusChecker.consensus_checker?(MyModule)
      # => true or false

  """
  def consensus_checker?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :check, 2)
  end

  @doc """
  Returns the ConsensusChecker behavior module.

  """
  def behaviour, do: __MODULE__
end
