defmodule Jido.AI.Accuracy.Stages.VerificationStage do
  @moduledoc """
  Pipeline stage for candidate verification.

  This stage verifies all generated candidates using configured verifiers.
  Candidates are scored and the best candidate is selected.

  ## Configuration

  - `:use_outcome` - Whether to use outcome verification (default: true)
  - `:use_process` - Whether to use process verification (default: true)
  - `:verifiers` - List of additional verifiers to use (default: [])
  - `:parallel` - Whether to run verifiers in parallel (default: false)

  ## Output State

  Updates the pipeline state:
  - `:candidates` - Replaces with scored candidates
  - `:best_candidate` - Updates with verified best candidate
  - `:verification_results` - Full verification results

  ## Usage

      stage = VerificationStage.new(%{
        use_outcome: true,
        use_process: true,
        parallel: false
      })

  """

  alias Jido.AI.Accuracy.{
    PipelineStage,
    VerificationRunner,
    VerificationResult,
    Candidate
  }

  @behaviour PipelineStage

  @type t :: %__MODULE__{
          use_outcome: boolean(),
          use_process: boolean(),
          verifiers: [term()],
          parallel: boolean(),
          timeout: pos_integer()
        }

  defstruct [
    use_outcome: true,
    use_process: true,
    verifiers: [],
    parallel: false,
    timeout: 30_000
  ]

  @impl PipelineStage
  def name, do: :verification

  @impl PipelineStage
  def required?, do: false

  @impl PipelineStage
  def execute(input, config) do
    candidates = Map.get(input, :candidates)

    cond do
      is_list(candidates) and candidates != [] ->
        verify_candidates(candidates, input, config)

      # If no candidates but we have a best_candidate, verify just that one
      not is_nil(Map.get(input, :best_candidate)) ->
        verify_single(Map.get(input, :best_candidate), input, config)

      # No candidates to verify
      true ->
        {:error, :no_candidates}
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      use_outcome: Map.get(attrs, :use_outcome, true),
      use_process: Map.get(attrs, :use_process, true),
      verifiers: Map.get(attrs, :verifiers, []),
      parallel: Map.get(attrs, :parallel, false),
      timeout: Map.get(attrs, :timeout, 30_000)
    }
  end

  # Private functions

  defp verify_candidates(candidates, input, config) do
    query = Map.get(input, :query)
    context = Map.get(input, :context, %{})

    # Build verifier list
    verifiers = build_verifiers(config, query, context)

    if verifiers == [] do
      # No verifiers configured, skip
      {:ok, input, %{skipped: true, no_verifiers: true}}
    else
      # Create verification runner
      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          parallel: Map.get(config, :parallel, false),
          timeout: Map.get(config, :timeout, 30_000)
        })

      # Verify all candidates
      case VerificationRunner.verify_all_candidates(runner, candidates, context) do
        {:ok, results} when is_list(results) ->
          # Update candidates with scores
          scored_candidates =
            Enum.zip(candidates, results)
            |> Enum.map(fn {candidate, result} ->
              Candidate.update_score(candidate, result.score)
            end)

          # Find best candidate
          best_candidate =
            scored_candidates
            |> Enum.filter(fn c -> is_number(c.score) end)
            |> Enum.sort_by(fn c -> c.score end, :desc)
            |> List.first()

          updated_state =
            input
            |> Map.put(:candidates, scored_candidates)
            |> Map.put(:best_candidate, best_candidate)
            |> Map.put(:verification_results, results)

          {:ok, updated_state,
           %{
             num_verified: length(results),
             best_score: if(best_candidate, do: best_candidate.score, else: nil)
           }}

        {:error, reason} ->
          {:error, {:verification_failed, reason}}
      end
    end
  end

  defp verify_single(candidate, input, config) do
    verify_candidates([candidate], input, config)
  end

  defp build_verifiers(config, query, context) do
    base_verifiers = []

    # Add outcome verifier if enabled
    base_verifiers =
      if Map.get(config, :use_outcome, true) do
        # Try to add outcome verifier
        case get_outcome_verifier() do
          {:ok, verifier} ->
            base_verifiers ++ [{verifier, %{query: query, context: context}, 1.0}]

          _ ->
            base_verifiers
        end
      else
        base_verifiers
      end

    # Add process verifier if enabled
    base_verifiers =
      if Map.get(config, :use_process, true) do
        case get_process_verifier() do
          {:ok, verifier} ->
            base_verifiers ++ [{verifier, %{query: query, context: context}, 1.0}]

          _ ->
            base_verifiers
        end
      else
        base_verifiers
      end

    # Add custom verifiers
    base_verifiers ++ Map.get(config, :verifiers, [])
  end

  # Try to get outcome verifier module if available
  defp get_outcome_verifier do
    try do
      module = Module.safe_concat([Jido, AI, Accuracy, Verifiers, LLMOutcomeVerifier])
      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error, :not_found}
      end
    rescue
      _ -> {:error, :not_found}
    end
  end

  # Try to get process verifier module if available
  defp get_process_verifier do
    try do
      module = Module.safe_concat([Jido, AI, Accuracy, Verifiers, LLMProcessVerifier])
      if Code.ensure_loaded?(module) do
        {:ok, module}
      else
        {:error, :not_found}
      end
    rescue
      _ -> {:error, :not_found}
    end
  end
end
