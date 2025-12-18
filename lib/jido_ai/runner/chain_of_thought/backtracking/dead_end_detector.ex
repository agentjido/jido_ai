defmodule Jido.AI.Runner.ChainOfThought.Backtracking.DeadEndDetector do
  @moduledoc """
  Detects dead-ends in reasoning where forward progress is impossible.

  Provides:
  - Dead-end detection heuristics (repeated failures, circular reasoning, constraint violations)
  - Confidence scoring to identify low-quality reasoning branches
  - Timeout-based detection for stalled reasoning progress
  - Custom dead-end predicates for domain-specific detection
  """

  require Logger

  @default_confidence_threshold 0.3
  @default_repetition_threshold 3
  @default_stall_threshold 5

  @type detection_result :: %{
          is_dead_end: boolean(),
          reasons: list(atom()),
          confidence: float()
        }

  @doc """
  Detects if current result represents a dead-end.

  ## Parameters

  - `result` - Current reasoning result
  - `history` - Reasoning history
  - `opts` - Detection options:
    - `:confidence_threshold` - Minimum confidence (default: 0.3)
    - `:repetition_threshold` - Max repeated failures (default: 3)
    - `:stall_threshold` - Max iterations without progress (default: 5)
    - `:custom_predicate` - Custom detection function

  ## Returns

  Boolean indicating if dead-end detected

  ## Examples

      if DeadEndDetector.detect(result, history) do
        # Trigger backtracking
      end
  """
  @spec detect(term(), list(), keyword()) :: boolean()
  def detect(result, history, opts \\ []) do
    detection = detect_with_reasons(result, history, opts)
    detection.is_dead_end
  end

  @doc """
  Detects dead-end with detailed reasons.

  ## Parameters

  - `result` - Current reasoning result
  - `history` - Reasoning history
  - `opts` - Detection options

  ## Returns

  Detection result map with reasons
  """
  @spec detect_with_reasons(term(), list(), keyword()) :: detection_result()
  def detect_with_reasons(result, history, opts \\ []) do
    custom_predicate = Keyword.get(opts, :custom_predicate)

    # Check custom predicate first
    if custom_predicate && custom_predicate.(result, history) do
      %{
        is_dead_end: true,
        reasons: [:custom_predicate],
        confidence: 1.0
      }
    else
      reasons = []

      confidence_threshold =
        Keyword.get(opts, :confidence_threshold, @default_confidence_threshold)

      repetition_threshold =
        Keyword.get(opts, :repetition_threshold, @default_repetition_threshold)

      stall_threshold = Keyword.get(opts, :stall_threshold, @default_stall_threshold)

      # Check various heuristics
      reasons = check_repeated_failures(result, history, repetition_threshold, reasons)
      reasons = check_circular_reasoning(result, history, reasons)
      reasons = check_low_confidence(result, confidence_threshold, reasons)
      reasons = check_stalled_progress(history, stall_threshold, reasons)
      reasons = check_constraint_violations(result, reasons)

      %{
        is_dead_end: length(reasons) > 0,
        reasons: reasons,
        confidence: calculate_detection_confidence(reasons)
      }
    end
  end

  @doc """
  Checks for repeated failures in history.

  ## Parameters

  - `result` - Current result
  - `history` - Reasoning history
  - `threshold` - Number of repetitions to trigger detection

  ## Returns

  Boolean indicating repeated failures
  """
  @spec repeated_failures?(term(), list(), pos_integer()) :: boolean()
  def repeated_failures?(result, history, threshold \\ @default_repetition_threshold) do
    failure_count = count_similar_failures(result, history)
    failure_count >= threshold
  end

  @doc """
  Checks for circular reasoning patterns.

  ## Parameters

  - `result` - Current result
  - `history` - Reasoning history

  ## Returns

  Boolean indicating circular reasoning detected
  """
  @spec circular_reasoning?(term(), list()) :: boolean()
  def circular_reasoning?(_result, history) when length(history) < 3, do: false

  def circular_reasoning?(result, history) do
    # Look for repeating patterns in history
    result_hash = hash_result(result)
    recent_hashes = Enum.take(history, 5) |> Enum.map(&hash_result/1)

    # Check if current result matches any recent result
    Enum.member?(recent_hashes, result_hash)
  end

  @doc """
  Extracts confidence score from result.

  ## Parameters

  - `result` - Result to extract confidence from

  ## Returns

  Confidence score (0.0 to 1.0)
  """
  @spec extract_confidence(term()) :: float()
  def extract_confidence(result) when is_map(result) do
    cond do
      Map.has_key?(result, :confidence) -> result.confidence
      Map.has_key?(result, "confidence") -> result["confidence"]
      true -> 0.7
    end
  end

  def extract_confidence(_result), do: 0.7

  @doc """
  Checks if confidence score is below threshold.

  ## Parameters

  - `result` - Result to check
  - `threshold` - Minimum confidence threshold

  ## Returns

  Boolean indicating low confidence
  """
  @spec low_confidence?(term(), float()) :: boolean()
  def low_confidence?(result, threshold \\ @default_confidence_threshold) do
    extract_confidence(result) < threshold
  end

  @doc """
  Checks for stalled progress in reasoning.

  ## Parameters

  - `history` - Reasoning history
  - `threshold` - Max iterations without progress

  ## Returns

  Boolean indicating stalled progress
  """
  @spec stalled_progress?(list(), pos_integer()) :: boolean()
  def stalled_progress?(history, threshold \\ @default_stall_threshold) do
    if length(history) < threshold do
      false
    else
      # Check if recent results are all similar (no progress)
      recent = Enum.take(history, threshold)
      hashes = Enum.map(recent, &hash_result/1)
      unique_count = Enum.uniq(hashes) |> length()

      # If most recent results are the same, progress has stalled
      unique_count <= 2
    end
  end

  @doc """
  Checks for constraint violations in result.

  ## Parameters

  - `result` - Result to check

  ## Returns

  Boolean indicating constraint violation
  """
  @spec constraint_violation?(term()) :: boolean()
  def constraint_violation?(result) when is_map(result) do
    Map.get(result, :constraint_violated, false) ||
      Map.get(result, "constraint_violated", false)
  end

  def constraint_violation?(_result), do: false

  # Private functions

  defp check_repeated_failures(result, history, threshold, reasons) do
    if repeated_failures?(result, history, threshold) do
      [:repeated_failures | reasons]
    else
      reasons
    end
  end

  defp check_circular_reasoning(result, history, reasons) do
    if circular_reasoning?(result, history) do
      [:circular_reasoning | reasons]
    else
      reasons
    end
  end

  defp check_low_confidence(result, threshold, reasons) do
    if low_confidence?(result, threshold) do
      [:low_confidence | reasons]
    else
      reasons
    end
  end

  defp check_stalled_progress(history, threshold, reasons) do
    if stalled_progress?(history, threshold) do
      [:stalled_progress | reasons]
    else
      reasons
    end
  end

  defp check_constraint_violations(result, reasons) do
    if constraint_violation?(result) do
      [:constraint_violation | reasons]
    else
      reasons
    end
  end

  defp count_similar_failures(result, history) do
    result_hash = hash_result(result)

    history
    |> Enum.map(&hash_result/1)
    |> Enum.count(&(&1 == result_hash))
  end

  defp hash_result(result) do
    :erlang.phash2(result)
  end

  defp calculate_detection_confidence(reasons) do
    # More reasons = higher confidence in detection
    base_confidence = min(length(reasons) * 0.25, 1.0)

    # Boost confidence for certain critical reasons
    critical_boost =
      if Enum.member?(reasons, :constraint_violation) or
           Enum.member?(reasons, :circular_reasoning) do
        0.2
      else
        0.0
      end

    min(base_confidence + critical_boost, 1.0)
  end
end
