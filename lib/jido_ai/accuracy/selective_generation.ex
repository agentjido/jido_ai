defmodule Jido.AI.Accuracy.SelectiveGeneration do
  @moduledoc """
  Implements selective generation using expected value calculation.

  Selective generation decides whether to answer or abstain based on the
  economic trade-off between the potential reward for a correct answer
  and the penalty for a wrong answer.

  ## Expected Value Calculation

  The expected value (EV) of answering is calculated as:

      EV(answer) = confidence * reward - (1 - confidence) * penalty

  Where:
  - `confidence` - The estimated confidence in the answer [0-1]
  - `reward` - The benefit of a correct answer (default: 1.0)
  - `penalty` - The cost of a wrong answer (default: 1.0)

  The EV of abstaining is always 0 (neutral outcome).

  ## Decision Logic

  - If EV(answer) > 0 → Return the answer
  - If EV(answer) <= 0 → Abstain from answering

  ## Fields

  - `:reward` - Reward for correct answer (default: 1.0)
  - `:penalty` - Penalty for wrong answer (default: 1.0)
  - `:confidence_threshold` - Simple threshold mode (optional)
  - `:use_ev` - Use EV calculation (default: true)

  ## Usage

      # Create with default settings
      {:ok, sg} = SelectiveGeneration.new(%{})

      # Decide whether to answer
      {:ok, estimate} = ConfidenceEstimate.new(%{score: 0.8, method: :attention})
      {:ok, candidate} = Candidate.new(%{content: "The answer is 42"})

      {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
      # => %DecisionResult{decision: :answer, ...}

      # Create with custom reward/penalty
      {:ok, sg} = SelectiveGeneration.new(%{
        reward: 2.0,    # High reward for correct answers
        penalty: 5.0    # Very high penalty for wrong answers
      })

  ## Domain-Specific Costs

  Different domains have different costs:

  ### Medical (Safety-Critical)
      high_penalty = SelectiveGeneration.new!(%{
        reward: 1.0,
        penalty: 10.0  # Very high cost for wrong medical advice
      })

  ### Creative (Permissive)
      low_penalty = SelectiveGeneration.new!(%{
        reward: 1.0,
        penalty: 0.5   # Lower cost for being wrong
      })

  ### Legal (High Stakes)
      very_high_penalty = SelectiveGeneration.new!(%{
        reward: 1.0,
        penalty: 20.0  # Extremely high cost for incorrect legal advice
      })

  ## Expected Value Examples

  With default reward=1.0, penalty=1.0:

  | Confidence | EV Calculation | EV | Decision |
  |------------|----------------|-----|----------|
  | 0.9 | 0.9*1 - 0.1*1 | 0.8 | Answer |
  | 0.7 | 0.7*1 - 0.3*1 | 0.4 | Answer |
  | 0.5 | 0.5*1 - 0.5*1 | 0.0 | Abstain |
  | 0.3 | 0.3*1 - 0.7*1 | -0.4 | Abstain |
  | 0.1 | 0.1*1 - 0.9*1 | -0.8 | Abstain |

  With reward=2.0, penalty=1.0 (rewarding correctness):

  | Confidence | EV Calculation | EV | Decision |
  |------------|----------------|-----|----------|
  | 0.4 | 0.4*2 - 0.6*1 | 0.2 | Answer |
  | 0.3 | 0.3*2 - 0.7*1 | -0.1 | Abstain |

  """

  import Jido.AI.Accuracy.Helpers, only: [get_attr: 2, get_attr: 3]

  alias Jido.AI.Accuracy.{Candidate, ConfidenceEstimate, DecisionResult}

  @type t :: %__MODULE__{
          reward: float(),
          penalty: float(),
          confidence_threshold: float() | nil,
          use_ev: boolean()
        }

  defstruct reward: 1.0,
            penalty: 1.0,
            confidence_threshold: nil,
            use_ev: true

  @max_reward 1000.0
  @max_penalty 1000.0

  @doc """
  Creates a new SelectiveGeneration from the given attributes.

  ## Parameters

  - `attrs` - Map with selective generation attributes:
    - `:reward` (optional) - Reward for correct answer (default: 1.0, max: 1000.0)
    - `:penalty` (optional) - Penalty for wrong answer (default: 1.0, max: 1000.0)
    - `:confidence_threshold` (optional) - Simple threshold (overrides EV)
    - `:use_ev` (optional) - Use EV calculation (default: true)

  ## Returns

  `{:ok, sg}` on success, `{:error, reason}` on validation failure.

  ## Examples

      iex> SelectiveGeneration.new(%{})
      {:ok, %SelectiveGeneration{reward: 1.0, penalty: 1.0}}

      iex> SelectiveGeneration.new(%{reward: 2.0, penalty: 5.0})
      {:ok, %SelectiveGeneration{reward: 2.0, penalty: 5.0}}

      iex> SelectiveGeneration.new(%{reward: -1.0})
      {:error, :invalid_reward}

      iex> SelectiveGeneration.new(%{reward: 1001.0})
      {:error, :invalid_reward}

  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_list(attrs) or is_map(attrs) do
    reward = get_attr(attrs, :reward, 1.0)
    penalty = get_attr(attrs, :penalty, 1.0)
    confidence_threshold = get_attr(attrs, :confidence_threshold)
    use_ev = get_attr(attrs, :use_ev, true)

    with :ok <- validate_reward(reward),
         :ok <- validate_penalty(penalty),
         :ok <- validate_threshold(confidence_threshold) do
      sg = %__MODULE__{
        reward: reward,
        penalty: penalty,
        confidence_threshold: confidence_threshold,
        use_ev: use_ev
      }

      {:ok, sg}
    end
  end

  @doc """
  Creates a new SelectiveGeneration, raising on error.

  ## Examples

      iex> SelectiveGeneration.new!(%{})
      %SelectiveGeneration{reward: 1.0, penalty: 1.0}

  """
  @spec new!(keyword() | map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, sg} -> sg
      {:error, reason} -> raise ArgumentError, "Invalid SelectiveGeneration: #{format_error(reason)}"
    end
  end

  @doc """
  Decides whether to answer or abstain based on expected value.

  ## Parameters

  - `sg` - The selective generation configuration
  - `candidate` - The candidate response
  - `estimate` - The confidence estimate

  ## Returns

  `{:ok, result}` where result contains the decision and reasoning.

  ## Examples

      sg = SelectiveGeneration.new!(%{})
      candidate = Candidate.new!(%{content: "The answer is 42"})
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :attention})

      {:ok, result} = SelectiveGeneration.answer_or_abstain(sg, candidate, estimate)
      # => %DecisionResult{decision: :answer, ev_answer: 0.6, ...}

  """
  @spec answer_or_abstain(t(), Candidate.t(), ConfidenceEstimate.t()) :: {:ok, DecisionResult.t()}
  def answer_or_abstain(%__MODULE__{} = sg, %Candidate{} = candidate, %ConfidenceEstimate{score: score}) do
    confidence = score

    {ev_answer, ev_abstain} = calculate_ev(sg, confidence)

    decision = decide(sg, ev_answer, confidence)

    {final_candidate, reasoning} =
      case decision do
        :answer ->
          {candidate, build_answer_reasoning(confidence, ev_answer, sg.reward, sg.penalty)}

        :abstain ->
          abstention = build_abstention_candidate(confidence, ev_answer, sg.reward, sg.penalty)
          {abstention, build_abstain_reasoning(confidence, ev_answer, sg.reward, sg.penalty)}
      end

    result = %DecisionResult{
      decision: decision,
      candidate: final_candidate,
      confidence: confidence,
      ev_answer: ev_answer,
      ev_abstain: ev_abstain,
      reasoning: reasoning,
      metadata: %{
        reward: sg.reward,
        penalty: sg.penalty,
        use_ev: sg.use_ev
      }
    }

    {:ok, result}
  end

  @doc """
  Calculates the expected value of answering vs abstaining.

  ## Parameters

  - `sg` - The selective generation configuration
  - `confidence` - The confidence score [0-1]

  ## Returns

  `{ev_answer, ev_abstain}` where ev_abstain is always 0.

  ## Formula

      EV(answer) = confidence * reward - (1 - confidence) * penalty
      EV(abstain) = 0

  ## Examples

      sg = SelectiveGeneration.new!(%{reward: 1.0, penalty: 1.0})

      SelectiveGeneration.calculate_ev(sg, 0.8)
      # => {0.6, 0.0}

      SelectiveGeneration.calculate_ev(sg, 0.3)
      # => {-0.4, 0.0}

  """
  @spec calculate_ev(t(), float()) :: {float(), float()}
  def calculate_ev(%__MODULE__{} = sg, confidence) when is_number(confidence) do
    ev_answer = confidence * sg.reward - (1 - confidence) * sg.penalty
    ev_abstain = 0.0
    {ev_answer, ev_abstain}
  end

  # Private functions

  defp decide(%__MODULE__{use_ev: false, confidence_threshold: threshold}, _ev_answer, confidence)
       when not is_nil(threshold) do
    if confidence >= threshold, do: :answer, else: :abstain
  end

  defp decide(%__MODULE__{}, ev_answer, _confidence) do
    if ev_answer > 0, do: :answer, else: :abstain
  end

  defp build_answer_reasoning(confidence, ev_answer, reward, penalty) do
    "Positive expected value (#{format_float(ev_answer)}) at confidence #{format_float(confidence)} (reward: #{format_float(reward)}, penalty: #{format_float(penalty)}). Answering is optimal."
  end

  defp build_abstain_reasoning(confidence, ev_answer, reward, penalty) do
    "Non-positive expected value (#{format_float(ev_answer)}) at confidence #{format_float(confidence)} (reward: #{format_float(reward)}, penalty: #{format_float(penalty)}). Abstaining to avoid potential error."
  end

  defp build_abstention_candidate(confidence, ev_answer, reward, penalty) do
    content = """
    I'm not confident enough to provide a reliable answer.

    Confidence: #{format_float(confidence)}
    Expected value: #{format_float(ev_answer)}

    The risk of providing incorrect information outweighs the potential benefit.
    Please consider:
    - Rephrasing your question with more specific details
    - Providing additional context
    - Consulting a more specialized source
    """

    %Candidate{
      content: String.trim(content),
      score: nil,
      metadata: %{
        abstained: true,
        original_confidence: confidence,
        ev_answer: ev_answer,
        reward: reward,
        penalty: penalty
      }
    }
  end

  defp format_float(n) when is_float(n) do
    :erlang.float_to_binary(n, decimals: 3)
  end

  defp format_float(n), do: to_string(n)

  # Validation helpers

  defp validate_reward(reward) when is_number(reward) and reward > 0 and reward <= @max_reward, do: :ok
  defp validate_reward(_), do: {:error, :invalid_reward}

  defp validate_penalty(penalty) when is_number(penalty) and penalty >= 0 and penalty <= @max_penalty, do: :ok
  defp validate_penalty(_), do: {:error, :invalid_penalty}

  defp validate_threshold(nil), do: :ok
  defp validate_threshold(t) when is_number(t) and t >= 0 and t <= 1, do: :ok
  defp validate_threshold(_), do: {:error, :invalid_threshold}
  defp format_error(atom) when is_atom(atom), do: atom
  defp format_error(_), do: :invalid_attributes
end
