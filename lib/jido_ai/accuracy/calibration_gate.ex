defmodule Jido.AI.Accuracy.CalibrationGate do
  @moduledoc """
  Routes candidates based on confidence levels.

  A CalibrationGate implements the calibration gate pattern, which routes
  responses based on their confidence scores. This prevents wrong answers
  by applying different strategies depending on the confidence level.

  ## Routing Behavior

  - **High confidence (≥ high_threshold)** - Return answer directly
  - **Medium confidence (low_threshold ≤ score < high_threshold)** - Add verification/citations
  - **Low confidence (< low_threshold)** - Abstain or escalate

  ## Fields

  - `:high_threshold` - Threshold for high confidence (default: 0.7)
  - `:low_threshold` - Threshold for low confidence (default: 0.4)
  - `:medium_action` - Action for medium confidence (default: `:with_verification`)
  - `:low_action` - Action for low confidence (default: `:abstain`)

  ## Actions

  - `:direct` - Return candidate unchanged
  - `:with_verification` - Add verification suggestions
  - `:with_citations` - Add source citations
  - `:abstain` - Return abstention message
  - `:escalate` - Escalate to human review

  ## Usage

      # Create a gate with default settings
      {:ok, gate} = CalibrationGate.new(%{})

      # Route a candidate based on confidence
      {:ok, estimate} = ConfidenceEstimate.new(%{score: 0.85, method: :attention})
      {:ok, candidate} = Candidate.new(%{content: "The answer is 42"})

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)
      # => %RoutingResult{action: :direct, ...}

      # Create a gate with custom thresholds
      {:ok, gate} = CalibrationGate.new(%{
        high_threshold: 0.8,
        low_threshold: 0.5,
        low_action: :escalate
      })

  ## Telemetry

  The gate emits telemetry events when routing decisions are made:

  ```elixir
  [:jido, :accuracy, :calibration, :route]
  ```

  Measurements:
  - `:duration` - Time taken for routing (in native time units)

  Metadata:
  - `:action` - The action taken
  - `:confidence_level` - :high, :medium, or :low
  - `:score` - The actual confidence score

  """

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate, RoutingResult, Thresholds}

  @type t :: %__MODULE__{
          high_threshold: float(),
          low_threshold: float(),
          medium_action: RoutingResult.action(),
          low_action: RoutingResult.action(),
          emit_telemetry: boolean()
        }

  @default_actions [:direct, :with_verification, :with_citations, :abstain, :escalate]

  # Epsilon for float comparison to handle floating-point precision errors
  @float_epsilon 0.0001

  # NOTE: Default thresholds now use centralized values from Thresholds module
  @default_high_threshold Thresholds.calibration_high_confidence()
  @default_low_threshold Thresholds.calibration_medium_confidence()

  @enforce_keys [:high_threshold, :low_threshold]
  defstruct high_threshold: @default_high_threshold,
            low_threshold: @default_low_threshold,
            medium_action: :with_verification,
            low_action: :abstain,
            emit_telemetry: true

  @doc """
  Creates a new CalibrationGate from the given attributes.

  ## Parameters

  - `attrs` - Map with gate attributes:
    - `:high_threshold` (optional) - High confidence threshold (default: 0.7)
    - `:low_threshold` (optional) - Low confidence threshold (default: 0.4)
    - `:medium_action` (optional) - Action for medium confidence (default: :with_verification)
    - `:low_action` (optional) - Action for low confidence (default: :abstain)
    - `:emit_telemetry` (optional) - Whether to emit telemetry events (default: true)

  ## Returns

  `{:ok, gate}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> CalibrationGate.new(%{})
      {:ok, %CalibrationGate{high_threshold: 0.7, low_threshold: 0.4}}

      iex> CalibrationGate.new(%{high_threshold: 0.8, low_threshold: 0.5})
      {:ok, %CalibrationGate{high_threshold: 0.8, low_threshold: 0.5}}

      iex> CalibrationGate.new(%{high_threshold: 0.3, low_threshold: 0.5})
      {:error, :invalid_thresholds}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    high_threshold = get_attr(attrs, :high_threshold, 0.7)
    low_threshold = get_attr(attrs, :low_threshold, 0.4)
    medium_action = get_attr(attrs, :medium_action, :with_verification)
    low_action = get_attr(attrs, :low_action, :abstain)
    emit_telemetry = get_attr(attrs, :emit_telemetry, true)

    with :ok <- validate_thresholds(high_threshold, low_threshold),
         :ok <- validate_action(medium_action),
         :ok <- validate_action(low_action) do
      gate = %__MODULE__{
        high_threshold: high_threshold,
        low_threshold: low_threshold,
        medium_action: medium_action,
        low_action: low_action,
        emit_telemetry: emit_telemetry
      }

      {:ok, gate}
    end
  end

  @doc """
  Creates a new CalibrationGate, raising on error.

  ## Examples

      iex> CalibrationGate.new!(%{})
      %CalibrationGate{high_threshold: 0.7, low_threshold: 0.4}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, gate} -> gate
      {:error, reason} -> raise ArgumentError, "Invalid CalibrationGate: #{format_error(reason)}"
    end
  end

  @doc """
  Routes a candidate based on its confidence estimate.

  ## Parameters

  - `gate` - The calibration gate
  - `candidate` - The candidate to route
  - `estimate` - The confidence estimate for the candidate

  ## Returns

  `{:ok, result}` on success, `{:error, reason}` on failure.

  ## Examples

      gate = CalibrationGate.new!(%{})
      candidate = Candidate.new!(%{content: "The answer is 42"})
      estimate = ConfidenceEstimate.new!(%{score: 0.85, method: :attention})

      {:ok, result} = CalibrationGate.route(gate, candidate, estimate)
      # => %RoutingResult{action: :direct, ...}

  """
  @spec route(t(), Candidate.t(), ConfidenceEstimate.t()) :: {:ok, RoutingResult.t()} | {:error, term()}
  def route(%__MODULE__{} = gate, %Candidate{} = candidate, %ConfidenceEstimate{score: score}) do
    start_time = if gate.emit_telemetry, do: System.monotonic_time()

    result = do_route(gate, candidate, score)

    if gate.emit_telemetry and start_time do
      duration = System.monotonic_time() - start_time

      :telemetry.execute(
        [:jido, :accuracy, :calibration, :route],
        %{duration: duration},
        %{
          action: result.action,
          confidence_level: result.confidence_level,
          score: result.original_score
        }
      )
    end

    {:ok, result}
  end

  @doc """
  Checks if a candidate would be routed with the given confidence score.

  This is a pre-flight check that returns the action that would be taken
  without actually routing the candidate.

  ## Parameters

  - `gate` - The calibration gate
  - `score` - The confidence score to check

  ## Returns

  `{:ok, action}` where action is one of: `:direct`, `:with_verification`,
  `:with_citations`, `:abstain`, or `:escalate`.

  ## Examples

      gate = CalibrationGate.new!(%{})

      {:ok, :direct} = CalibrationGate.should_route?(gate, 0.8)
      {:ok, :with_verification} = CalibrationGate.should_route?(gate, 0.5)
      {:ok, :abstain} = CalibrationGate.should_route?(gate, 0.2)

  """
  @spec should_route?(t(), float()) :: {:ok, RoutingResult.action()} | {:error, term()}
  def should_route?(%__MODULE__{} = gate, score) when is_number(score) do
    cond do
      score >= gate.high_threshold -> {:ok, :direct}
      score >= gate.low_threshold -> {:ok, gate.medium_action}
      true -> {:ok, gate.low_action}
    end
  end

  @doc """
  Returns the confidence level for a given score.

  ## Parameters

  - `gate` - The calibration gate
  - `score` - The confidence score

  ## Returns

  `:high`, `:medium`, or `:low`

  ## Examples

      gate = CalibrationGate.new!(%{})

      CalibrationGate.confidence_level(gate, 0.8)
      # => :high

      CalibrationGate.confidence_level(gate, 0.5)
      # => :medium

      CalibrationGate.confidence_level(gate, 0.2)
      # => :low

  """
  @spec confidence_level(t(), float()) :: :high | :medium | :low
  def confidence_level(%__MODULE__{} = gate, score) when is_number(score) do
    cond do
      score >= gate.high_threshold -> :high
      score >= gate.low_threshold -> :medium
      true -> :low
    end
  end

  # Private functions

  defp do_route(%__MODULE__{} = gate, %Candidate{} = candidate, score) do
    level = confidence_level(gate, score)

    action =
      case level do
        :high -> :direct
        :medium -> gate.medium_action
        :low -> gate.low_action
      end

    {modified_candidate, reasoning} = apply_strategy(action, candidate, score, level)

    %RoutingResult{
      action: action,
      candidate: modified_candidate,
      original_score: score,
      confidence_level: level,
      reasoning: reasoning,
      metadata: %{
        high_threshold: gate.high_threshold,
        low_threshold: gate.low_threshold
      }
    }
  end

  defp apply_strategy(:direct, %Candidate{} = candidate, score, :high) do
    {candidate, "High confidence (#{:erlang.float_to_binary(score, decimals: 3)}), returning answer directly"}
  end

  defp apply_strategy(:with_verification, %Candidate{} = candidate, score, :medium) do
    modified = add_verification_suffix(candidate)
    {modified, "Medium confidence (#{:erlang.float_to_binary(score, decimals: 3)}), adding verification suggestion"}
  end

  defp apply_strategy(:with_citations, %Candidate{} = candidate, score, :medium) do
    modified = add_citation_suffix(candidate)
    {modified, "Medium confidence (#{:erlang.float_to_binary(score, decimals: 3)}), adding citations"}
  end

  defp apply_strategy(:abstain, %Candidate{}, score, :low) do
    abstention = build_abstention_candidate(score)
    {abstention, "Low confidence (#{:erlang.float_to_binary(score, decimals: 3)}), abstaining from answer"}
  end

  defp apply_strategy(:escalate, %Candidate{}, score, :low) do
    escalation = build_escalation_candidate(score)
    {escalation, "Low confidence (#{:erlang.float_to_binary(score, decimals: 3)}), escalating for review"}
  end

  defp add_verification_suffix(%Candidate{content: content} = candidate) when is_binary(content) do
    suffix = "\n\n[Confidence: Medium] Please verify this information independently."
    %{candidate | content: content <> suffix}
  end

  defp add_verification_suffix(%Candidate{} = candidate), do: candidate

  defp add_citation_suffix(%Candidate{content: content} = candidate) when is_binary(content) do
    suffix = "\n\n[Confidence: Medium] Consider verifying this with additional sources."
    %{candidate | content: content <> suffix}
  end

  defp add_citation_suffix(%Candidate{} = candidate), do: candidate

  defp build_abstention_candidate(score) do
    content = """
    I'm not confident enough to provide a definitive answer to this question (confidence: #{:erlang.float_to_binary(score, decimals: 2)}).

    This could be because:
    - The question is ambiguous or unclear
    - I don't have sufficient information to answer accurately
    - There are multiple valid interpretations

    Suggestions:
    - Try rephrasing your question with more specific details
    - Break the question into smaller parts
    - Provide additional context
    """

    %Candidate{
      content: String.trim(content),
      score: nil,
      metadata: %{abstained: true, original_confidence: score}
    }
  end

  defp build_escalation_candidate(score) do
    content = """
    I'm not confident enough to provide a definitive answer (confidence: #{:erlang.float_to_binary(score, decimals: 2)}).

    This question has been escalated for human review. Someone will provide assistance shortly.
    """

    %Candidate{
      content: String.trim(content),
      score: nil,
      metadata: %{escalated: true, original_confidence: score}
    }
  end

  # Validation helpers

  defp validate_thresholds(high, low) when is_number(high) and is_number(low) do
    # Use epsilon for float comparison to handle floating-point precision errors
    if high - low > @float_epsilon do
      :ok
    else
      {:error, :invalid_thresholds}
    end
  end

  defp validate_thresholds(_, _), do: {:error, :invalid_thresholds}

  defp validate_action(action) when action in @default_actions, do: :ok
  defp validate_action(_), do: {:error, :invalid_action}

  # Attribute helpers

  defp get_attr(attrs, key, default) when is_list(attrs) do
    Keyword.get(attrs, key, default)
  end

  defp get_attr(attrs, key, default) when is_map(attrs) do
    Map.get(attrs, key, default)
  end

  defp format_error(atom) when is_atom(atom), do: atom
end
