defmodule Jido.AI.Accuracy.Stages.DifficultyEstimationStage do
  @moduledoc """
  Pipeline stage for estimating query difficulty.

  This stage estimates the difficulty of a query using a configured
  difficulty estimator. The difficulty estimate is used by downstream
  stages to adjust resource allocation (e.g., number of candidates).

  ## Configuration

  - `:estimator` - The difficulty estimator module to use (default: HeuristicDifficulty)
  - `:timeout` - Maximum time for estimation in milliseconds (default: 5000)

  ## Output State

  Adds to the pipeline state:
  - `:difficulty` - The DifficultyEstimate result
  - `:difficulty_level` - The difficulty level atom (:easy, :medium, :hard)

  ## Usage

      stage = DifficultyEstimationStage.new(%{
        estimator: HeuristicDifficulty
      })

      {:ok, state, metadata} = DifficultyEstimationStage.execute(
        %{query: "What is 2+2?"},
        %{estimator: HeuristicDifficulty}
      )

  """

  alias Jido.AI.Accuracy.{
    PipelineStage,
    DifficultyEstimate,
    Estimators.HeuristicDifficulty
  }

  @behaviour PipelineStage

  @type t :: %__MODULE__{
          estimator: module() | nil,
          timeout: pos_integer()
        }

  defstruct [
    :estimator,
    timeout: 5000
  ]

  @impl PipelineStage
  def name, do: :difficulty_estimation

  @impl PipelineStage
  def required?, do: false

  @impl PipelineStage
  def execute(input, config) do
    query = Map.get(input, :query)
    estimator = Map.get(config, :estimator, HeuristicDifficulty)

    if is_binary(query) and query != "" do
      estimate_difficulty(estimator, query, input, config)
    else
      {:error, :invalid_query}
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    estimator = Map.get(attrs, :estimator)
    timeout = Map.get(attrs, :timeout, 5000)

    %__MODULE__{
      estimator: estimator,
      timeout: timeout
    }
  end

  # Private functions

  defp estimate_difficulty(estimator, query, input, config) do
    # Check if difficulty was already estimated
    case Map.get(input, :difficulty) do
      %DifficultyEstimate{} = estimate ->
        # Already estimated, return as-is
        state_with_level = Map.put(input, :difficulty_level, estimate.level)
        {:ok, state_with_level, %{from_cache: true, difficulty_level: estimate.level}}

      _ ->
        # Perform estimation
        context = Map.get(input, :context, %{})
        timeout = Map.get(config, :timeout, 5000)

        # Wrap in task for timeout protection
        task =
          Task.async(fn ->
            estimator.estimate(estimator, query, context)
          end)

        case Task.yield(task, timeout) do
          {:ok, {:ok, %DifficultyEstimate{} = estimate}} ->
            # Add difficulty to state
            updated_state =
              input
              |> Map.put(:difficulty, estimate)
              |> Map.put(:difficulty_level, estimate.level)

            {:ok, updated_state, %{difficulty_level: estimate.level, score: estimate.score}}

          {:ok, {:error, _reason}} ->
            # Estimation failed, use default
            fallback_state =
              input
              |> Map.put(:difficulty, default_estimate())
              |> Map.put(:difficulty_level, :medium)

            {:ok, fallback_state, %{fallback: true, difficulty_level: :medium}}

          {:exit, _} ->
            # Estimator crashed, use default
            {:ok, Map.put(input, :difficulty_level, :medium), %{estimator_crashed: true, difficulty_level: :medium}}

          nil ->
            # Timeout, use default
            {:ok, Map.put(input, :difficulty_level, :medium), %{timeout: true, difficulty_level: :medium}}
        end
    end
  end

  defp default_estimate do
    DifficultyEstimate.new!(%{
      level: :medium,
      score: 0.5,
      confidence: 0.5,
      reasoning: "Default estimate (estimation failed)"
    })
  end
end
