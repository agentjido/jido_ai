defmodule Jido.AI.Accuracy.Stages.ReflectionStage do
  @moduledoc """
  Pipeline stage for reflection-based iterative improvement.

  This is an optional stage that runs reflection if the best candidate's
  score is below a threshold. The reflection loop iteratively improves
  the answer through critique-revise cycles.

  ## Configuration

  - `:enabled` - Whether reflection is enabled (default: true)
  - `:min_score_threshold` - Minimum score to skip reflection (default: 0.7)
  - `:max_iterations` - Maximum reflection iterations (default: 3)
  - `:convergence_threshold` - Score improvement threshold (default: 0.1)

  ## Output State

  Updates the pipeline state:
  - `:best_candidate` - Updates with reflected candidate
  - `:reflection_applied` - Whether reflection was applied
  - `:reflection_iterations` - Number of reflection iterations

  ## Usage

      stage = ReflectionStage.new(%{
        min_score_threshold: 0.7,
        max_iterations: 3
      })

  """

  alias Jido.AI.Accuracy.{
    PipelineStage,
    ReflectionLoop,
    Candidate
  }

  @behaviour PipelineStage

  @type t :: %__MODULE__{
          enabled: boolean(),
          min_score_threshold: float(),
          max_iterations: pos_integer(),
          convergence_threshold: float(),
          critiquer: module() | nil,
          reviser: module() | nil
        }

  defstruct [
    :critiquer,
    :reviser,
    enabled: true,
    min_score_threshold: 0.7,
    max_iterations: 3,
    convergence_threshold: 0.1
  ]

  @impl PipelineStage
  def name, do: :reflection

  @impl PipelineStage
  def required?, do: false

  @impl PipelineStage
  def execute(input, config) do
    enabled = Map.get(config, :enabled, true)
    best_candidate = Map.get(input, :best_candidate)

    cond do
      !enabled ->
        # Stage disabled, skip
        {:ok, Map.put(input, :reflection_applied, false), %{skipped: true}}

      is_nil(best_candidate) ->
        # No candidate to reflect on
        {:ok, Map.put(input, :reflection_applied, false), %{no_candidate: true}}

      should_reflect?(best_candidate, config) ->
        run_reflection(best_candidate, input, config)

      true ->
        # Score is high enough, skip reflection
        {:ok, Map.put(input, :reflection_applied, false), %{skipped: true, score_high: true}}
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      critiquer: Map.get(attrs, :critiquer),
      reviser: Map.get(attrs, :reviser),
      enabled: Map.get(attrs, :enabled, true),
      min_score_threshold: Map.get(attrs, :min_score_threshold, 0.7),
      max_iterations: Map.get(attrs, :max_iterations, 3),
      convergence_threshold: Map.get(attrs, :convergence_threshold, 0.1)
    }
  end

  # Private functions

  defp should_reflect?(%Candidate{score: score}, config) do
    threshold = Map.get(config, :min_score_threshold, 0.7)

    cond do
      is_nil(score) ->
        # No score, should reflect
        true

      score < threshold ->
        # Score below threshold, should reflect
        true

      true ->
        # Score high enough, don't reflect
        false
    end
  end

  defp run_reflection(candidate, input, config) do
    query = Map.get(input, :query)
    context = Map.get(input, :context, %{})

    # Get critiquer and reviser
    critiquer = Map.get(config, :critiquer)
    reviser = Map.get(config, :reviser)

    if is_nil(critiquer) or is_nil(reviser) do
      # Missing required components, skip
      {:ok, Map.put(input, :reflection_applied, false), %{missing_components: true}}
    else
      # Build reflection loop
      loop = build_loop(config)

      # Run reflection
      reflection_context =
        context
        |> Map.put(:initial_candidate, candidate)
        |> Map.put(:model, Map.get(context, :model))

      case ReflectionLoop.run(loop, query, reflection_context) do
        {:ok, result} ->
          updated_state =
            input
            |> Map.put(:best_candidate, result.best_candidate)
            |> Map.put(:reflection_applied, true)
            |> Map.put(:reflection_iterations, result.total_iterations)
            |> Map.put(:reflection_converged, result.converged)

          {:ok, updated_state,
           %{
             iterations: result.total_iterations,
             converged: result.converged,
             reason: result.reason
           }}

        {:error, :no_initial_candidate} ->
          # Should not happen since we have candidate, but handle gracefully
          {:ok, Map.put(input, :reflection_applied, false), %{no_initial_candidate: true}}

        {:error, reason} ->
          # Reflection failed, continue with original candidate
          {:ok, Map.put(input, :reflection_applied, false), %{reflection_failed: reason}}
      end
    end
  end

  defp build_loop(config) do
    critiquer = Map.get(config, :critiquer)
    reviser = Map.get(config, :reviser)
    max_iterations = Map.get(config, :max_iterations, 3)
    convergence_threshold = Map.get(config, :convergence_threshold, 0.1)

    ReflectionLoop.new!(%{
      critiquer: critiquer,
      reviser: reviser,
      max_iterations: max_iterations,
      convergence_threshold: convergence_threshold
    })
  end
end
