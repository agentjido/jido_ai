defmodule Jido.AI.TRM.ACT do
  @moduledoc """
  Adaptive Computational Time (ACT) module for TRM strategy.

  Uses `Jido.AI.TRM.Helpers.clamp/3` for value clamping.

  This module implements early stopping logic based on confidence thresholds
  and convergence detection. It helps the TRM strategy decide when to stop
  iterating and return the best answer found.

  ## Overview

  ACT monitors the progression of answer quality across supervision steps and
  decides whether to continue iterating or halt early. Key mechanisms:

  1. **Confidence Threshold**: Stop when confidence exceeds a threshold
  2. **Convergence Detection**: Stop when improvements have plateaued
  3. **Expected Improvement**: Estimate whether continuing is worthwhile

  ## Usage

      # Calculate combined confidence
      confidence = ACT.calculate_confidence(latent_state, quality_score)

      # Check if should halt
      ACT.should_halt?(confidence, threshold)
      #=> true

      # Detect convergence from history
      ACT.detect_convergence([0.5, 0.6, 0.62, 0.63, 0.63])
      #=> true

      # Make a decision with full context
      state = %{threshold: 0.9, current_confidence: 0.85, history: [0.5, 0.7, 0.85]}
      ACT.make_decision(state, latent_state)
      #=> {:continue, %{expected_improvement: 0.08}}
  """

  import Jido.AI.TRM.Helpers, only: [clamp: 3]

  @type act_state :: %{
          threshold: float(),
          current_confidence: float(),
          history: [float()]
        }

  @type decision :: :continue | :halt

  @type halt_reason :: :threshold_exceeded | :convergence_detected | :max_improvement_reached

  # Import shared helpers

  # Default convergence detection settings
  @convergence_window 3
  @convergence_epsilon 0.02

  # Weight factors for confidence calculation
  @quality_weight 0.6
  @latent_weight 0.4

  # ============================================================================
  # ACT State Management
  # ============================================================================

  @doc """
  Creates a new ACT state with the given threshold.

  ## Parameters

  - `threshold` - Confidence threshold for early stopping (0.0-1.0)

  ## Examples

      iex> ACT.new(0.9)
      %{threshold: 0.9, current_confidence: 0.0, history: []}
  """
  @spec new(float()) :: act_state()
  def new(threshold \\ 0.9) do
    %{
      threshold: clamp(threshold, 0.0, 1.0),
      current_confidence: 0.0,
      history: []
    }
  end

  @doc """
  Updates the ACT state with a new confidence value.

  Adds the new confidence to the history and updates the current confidence.

  ## Parameters

  - `state` - Current ACT state
  - `confidence` - New confidence value to record

  ## Examples

      iex> state = ACT.new(0.9)
      iex> ACT.update(state, 0.7)
      %{threshold: 0.9, current_confidence: 0.7, history: [0.7]}
  """
  @spec update(act_state(), float()) :: act_state()
  def update(state, confidence) do
    clamped = clamp(confidence, 0.0, 1.0)

    %{
      state
      | current_confidence: clamped,
        history: state.history ++ [clamped]
    }
  end

  # ============================================================================
  # Confidence Calculation
  # ============================================================================

  @doc """
  Calculates combined confidence from latent state and quality score.

  Combines the reasoning confidence from latent state with the quality
  score from supervision feedback using weighted averaging.

  ## Parameters

  - `latent_state` - The machine's latent state containing reasoning confidence
  - `quality_score` - Quality score from supervision (0.0-1.0)

  ## Returns

  Combined confidence score between 0.0 and 1.0.

  ## Examples

      iex> latent_state = %{confidence_score: 0.8}
      iex> ACT.calculate_confidence(latent_state, 0.9)
      0.86
  """
  @spec calculate_confidence(map(), float()) :: float()
  def calculate_confidence(latent_state, quality_score) when is_map(latent_state) do
    latent_confidence = Map.get(latent_state, :confidence_score, 0.0)

    combined =
      @quality_weight * clamp(quality_score, 0.0, 1.0) +
        @latent_weight * clamp(latent_confidence, 0.0, 1.0)

    clamp(combined, 0.0, 1.0)
  end

  def calculate_confidence(_, quality_score) do
    clamp(quality_score, 0.0, 1.0)
  end

  @doc """
  Checks if the current confidence exceeds the threshold for early stopping.

  ## Parameters

  - `confidence` - Current confidence score
  - `threshold` - Threshold for early stopping

  ## Returns

  `true` if confidence >= threshold, `false` otherwise.

  ## Examples

      iex> ACT.should_halt?(0.95, 0.9)
      true

      iex> ACT.should_halt?(0.85, 0.9)
      false
  """
  @spec should_halt?(float(), float()) :: boolean()
  def should_halt?(confidence, threshold) do
    confidence >= threshold
  end

  @doc """
  Updates the confidence history with a new value.

  Maintains a rolling history of confidence scores for convergence detection.

  ## Parameters

  - `history` - List of previous confidence scores
  - `new_confidence` - New confidence score to add

  ## Returns

  Updated history list.

  ## Examples

      iex> ACT.update_confidence_history([0.5, 0.6], 0.7)
      [0.5, 0.6, 0.7]
  """
  @spec update_confidence_history([float()], float()) :: [float()]
  def update_confidence_history(history, new_confidence) when is_list(history) do
    history ++ [clamp(new_confidence, 0.0, 1.0)]
  end

  def update_confidence_history(_, new_confidence) do
    [clamp(new_confidence, 0.0, 1.0)]
  end

  # ============================================================================
  # Convergence Detection
  # ============================================================================

  @doc """
  Detects if improvements have plateaued based on confidence history.

  Analyzes the recent confidence scores to determine if the improvement
  rate has dropped below a meaningful threshold.

  ## Parameters

  - `history` - List of confidence scores from oldest to newest

  ## Returns

  `true` if improvements have plateaued, `false` otherwise.

  ## Examples

      iex> ACT.detect_convergence([0.5, 0.6, 0.7, 0.8])
      false

      iex> ACT.detect_convergence([0.7, 0.72, 0.73, 0.73])
      true
  """
  @spec detect_convergence([float()]) :: boolean()
  def detect_convergence(history) when is_list(history) do
    if length(history) < @convergence_window do
      false
    else
      recent = Enum.take(history, -@convergence_window)
      range = Enum.max(recent) - Enum.min(recent)
      range < @convergence_epsilon
    end
  end

  def detect_convergence(_), do: false

  @doc """
  Detects convergence with custom window and epsilon parameters.

  ## Parameters

  - `history` - List of confidence scores
  - `window` - Number of recent scores to consider
  - `epsilon` - Maximum range for convergence

  ## Examples

      iex> ACT.detect_convergence([0.7, 0.71, 0.72], 3, 0.05)
      true
  """
  @spec detect_convergence([float()], pos_integer(), float()) :: boolean()
  def detect_convergence(history, window, epsilon) when is_list(history) and is_integer(window) and window > 0 do
    if length(history) < window do
      false
    else
      recent = Enum.take(history, -window)
      range = Enum.max(recent) - Enum.min(recent)
      range < epsilon
    end
  end

  # ============================================================================
  # ACT Decision Logic
  # ============================================================================

  @doc """
  Makes a continue/halt decision based on ACT state and latent state.

  Evaluates multiple factors:
  1. Whether confidence exceeds threshold
  2. Whether improvements have converged
  3. Expected improvement from continuing

  ## Parameters

  - `act_state` - Current ACT state with threshold and history
  - `latent_state` - Machine's latent state (optional)

  ## Returns

  A tuple of `{:continue, metadata}` or `{:halt, reason}`.

  ## Examples

      iex> state = %{threshold: 0.9, current_confidence: 0.95, history: [0.8, 0.9, 0.95]}
      iex> ACT.make_decision(state, %{})
      {:halt, :threshold_exceeded}

      iex> state = %{threshold: 0.9, current_confidence: 0.7, history: [0.5, 0.6, 0.7]}
      iex> ACT.make_decision(state, %{})
      {:continue, %{expected_improvement: ...}}
  """
  @spec make_decision(act_state(), map()) :: {:continue, map()} | {:halt, halt_reason()}
  def make_decision(act_state, latent_state \\ %{})

  def make_decision(%{threshold: threshold, current_confidence: confidence, history: history}, _latent_state) do
    cond do
      # Check threshold first
      should_halt?(confidence, threshold) ->
        {:halt, :threshold_exceeded}

      # Check for convergence
      detect_convergence(history) ->
        {:halt, :convergence_detected}

      # Check if we've reached near-maximum improvement
      confidence >= 0.98 ->
        {:halt, :max_improvement_reached}

      # Continue with expected improvement info
      true ->
        expected = calculate_expected_improvement(history)
        {:continue, %{expected_improvement: expected}}
    end
  end

  def make_decision(_, _), do: {:continue, %{expected_improvement: 0.1}}

  @doc """
  Calculates the expected improvement from continuing.

  Uses the recent improvement trend to estimate how much additional
  improvement is likely from another iteration.

  ## Parameters

  - `history` - List of confidence scores

  ## Returns

  Expected improvement as a float (0.0-1.0).

  ## Examples

      iex> ACT.calculate_expected_improvement([0.5, 0.6, 0.7, 0.8])
      0.1

      iex> ACT.calculate_expected_improvement([0.8, 0.82, 0.83])
      0.02
  """
  @spec calculate_expected_improvement([float()]) :: float()
  def calculate_expected_improvement(history) when is_list(history) do
    if length(history) < 2 do
      0.1
    else
      # Calculate average improvement over last few steps
      recent = Enum.take(history, -min(length(history), 4))
      improvements = calculate_deltas(recent)

      if Enum.empty?(improvements) do
        0.1
      else
        avg_improvement = Enum.sum(improvements) / length(improvements)
        # Apply decay factor (later improvements tend to be smaller)
        clamp(avg_improvement * 0.8, 0.0, 1.0)
      end
    end
  end

  def calculate_expected_improvement(_), do: 0.1

  @doc """
  Returns the reason for halting based on the ACT state.

  ## Parameters

  - `act_state` - Current ACT state

  ## Returns

  A halt reason atom or `nil` if should continue.

  ## Examples

      iex> state = %{threshold: 0.9, current_confidence: 0.95, history: [0.9, 0.92, 0.95]}
      iex> ACT.get_halt_reason(state)
      :threshold_exceeded
  """
  @spec get_halt_reason(act_state()) :: halt_reason() | nil
  def get_halt_reason(%{threshold: threshold, current_confidence: confidence, history: history}) do
    cond do
      should_halt?(confidence, threshold) -> :threshold_exceeded
      detect_convergence(history) -> :convergence_detected
      confidence >= 0.98 -> :max_improvement_reached
      true -> nil
    end
  end

  def get_halt_reason(_), do: nil

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Calculates the improvement rate from confidence history.

  Returns the average rate of improvement per step.

  ## Parameters

  - `history` - List of confidence scores

  ## Examples

      iex> ACT.improvement_rate([0.5, 0.6, 0.7, 0.8])
      0.1
  """
  @spec improvement_rate([float()]) :: float()
  def improvement_rate(history) when is_list(history) and length(history) >= 2 do
    deltas = calculate_deltas(history)

    if Enum.empty?(deltas) do
      0.0
    else
      Enum.sum(deltas) / length(deltas)
    end
  end

  def improvement_rate(_), do: 0.0

  @doc """
  Calculates the total improvement from first to last confidence score.

  ## Parameters

  - `history` - List of confidence scores

  ## Examples

      iex> ACT.total_improvement([0.5, 0.6, 0.7, 0.8])
      0.3
  """
  @spec total_improvement([float()]) :: float()
  def total_improvement([first | _] = history) when length(history) >= 2 do
    last = List.last(history)
    max(last - first, 0.0)
  end

  def total_improvement(_), do: 0.0

  @doc """
  Estimates the number of steps remaining to reach a target confidence.

  ## Parameters

  - `current` - Current confidence score
  - `target` - Target confidence to reach
  - `history` - Confidence history for trend estimation

  ## Returns

  Estimated steps remaining, or `:infinity` if improvement rate is too low.

  ## Examples

      iex> ACT.estimated_steps_remaining(0.7, 0.9, [0.5, 0.6, 0.7])
      2
  """
  @spec estimated_steps_remaining(float(), float(), [float()]) :: non_neg_integer() | :infinity
  def estimated_steps_remaining(current, target, history) when current < target do
    rate = improvement_rate(history)

    if rate <= 0.001 do
      :infinity
    else
      gap = target - current
      steps = ceil(gap / rate)
      max(steps, 1)
    end
  end

  def estimated_steps_remaining(_, _, _), do: 0

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp calculate_deltas([]), do: []
  defp calculate_deltas([_]), do: []

  defp calculate_deltas(history) do
    history
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.map(fn [a, b] -> b - a end)
  end
end
