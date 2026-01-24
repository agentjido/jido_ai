defmodule Jido.AI.Accuracy.Stages.CalibrationStage do
  @moduledoc """
  Pipeline stage for calibration-based confidence routing.

  This stage estimates confidence in the final answer and routes
  based on the confidence threshold. High confidence answers
  are returned directly, medium confidence gets verification
  suggestions, and low confidence results in abstention.

  ## Configuration

  - `:high_threshold` - High confidence threshold (default: 0.7)
  - `:low_threshold` - Low confidence threshold (default: 0.4)
  - `:medium_action` - Action for medium confidence (default: :with_verification)
  - `:low_action` - Action for low confidence (default: :abstain)

  ## Output State

  Updates the pipeline state:
  - `:answer` - Final answer (or nil if abstained)
  - `:confidence` - Confidence estimate
  - `:action` - Routing action taken

  ## Usage

      stage = CalibrationStage.new(%{
        high_threshold: 0.8,
        low_threshold: 0.5
      })

  """

  @behaviour Jido.AI.Accuracy.PipelineStage

  alias Jido.AI.Accuracy.{
    CalibrationGate,
    ConfidenceEstimate,
    Candidate,
    RoutingResult
  }

  @type t :: %__MODULE__{
          high_threshold: float(),
          low_threshold: float(),
          medium_action: RoutingResult.action(),
          low_action: RoutingResult.action(),
          emit_telemetry: boolean()
        }

  defstruct high_threshold: 0.7,
            low_threshold: 0.4,
            medium_action: :with_verification,
            low_action: :abstain,
            emit_telemetry: true

  @impl true
  def name, do: :calibration

  @impl true
  def required?, do: false

  @impl true
  def execute(input, config) do
    best_candidate = Map.get(input, :best_candidate)

    if is_nil(best_candidate) do
      {:error, :no_candidate}
    else
      apply_calibration(best_candidate, input, config)
    end
  end

  @doc """
  Creates a new stage configuration.

  """
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      high_threshold: Map.get(attrs, :high_threshold, 0.7),
      low_threshold: Map.get(attrs, :low_threshold, 0.4),
      medium_action: Map.get(attrs, :medium_action, :with_verification),
      low_action: Map.get(attrs, :low_action, :abstain),
      emit_telemetry: Map.get(attrs, :emit_telemetry, true)
    }
  end

  # Private functions

  defp apply_calibration(candidate, input, config) do
    # Estimate confidence
    confidence_estimate = estimate_confidence(candidate, input)

    # Build calibration gate
    gate = build_gate(config)

    # Route based on confidence
    {:ok, %RoutingResult{} = routing_result} =
      CalibrationGate.route(gate, candidate, confidence_estimate)

    # Extract final answer from routing result
    final_answer = extract_answer(routing_result.candidate)

    updated_state =
      input
      |> Map.put(:answer, final_answer)
      |> Map.put(:confidence, confidence_estimate.score)
      |> Map.put(:action, routing_result.action)
      |> Map.put(:routing_result, routing_result)

    {:ok, updated_state,
     %{
       confidence: confidence_estimate.score,
       confidence_level: routing_result.confidence_level,
       action: routing_result.action
     }}
  end

  defp estimate_confidence(candidate, _input) do
    # Try to use candidate score as confidence
    score =
      if is_number(candidate.score) do
        candidate.score
      else
        # Default confidence if no score
        0.5
      end

    ConfidenceEstimate.new!(%{
      score: score,
      method: :candidate_score,
      reasoning: "Confidence based on candidate verification score"
    })
  end

  defp build_gate(config) do
    CalibrationGate.new!(%{
      high_threshold: Map.get(config, :high_threshold, 0.7),
      low_threshold: Map.get(config, :low_threshold, 0.4),
      medium_action: Map.get(config, :medium_action, :with_verification),
      low_action: Map.get(config, :low_action, :abstain),
      emit_telemetry: Map.get(config, :emit_telemetry, true)
    })
  end

  defp extract_answer(%Candidate{content: content}), do: content
end
