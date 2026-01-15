defmodule Jido.AI.Accuracy.Thresholds do
  @moduledoc """
  Centralized threshold constants for accuracy modules.

  This module provides a single source of truth for threshold values
  used across the accuracy system, making it easier to maintain
  consistent behavior and tune parameters.

  ## Difficulty Thresholds

  Difficulty estimates are categorized based on score thresholds:

  - Score < 0.35 → `:easy`
  - Score 0.35 - 0.65 → `:medium`
  - Score > 0.65 → `:hard`

  ## Consensus Thresholds

  Early stopping in self-consistency uses consensus thresholds:

  - Default: 0.8 (80% agreement)
  - High consensus: 0.9 (90% agreement)
  - Low consensus: 0.6 (60% agreement)

  ## Examples

      # Get easy threshold
      Thresholds.easy_threshold()
      # => 0.35

      # Get hard threshold
      Thresholds.hard_threshold()
      # => 0.65

      # Get early stop threshold
      Thresholds.early_stop_threshold()
      # => 0.8

  """

  @type threshold :: float()

  # Difficulty thresholds
  @easy_threshold 0.35
  @hard_threshold 0.65

  # Consensus thresholds
  @early_stop_threshold 0.8
  @high_consensus_threshold 0.9
  @low_consensus_threshold 0.6

  # Confidence thresholds
  @high_confidence_threshold 0.8
  @medium_confidence_threshold 0.5
  @low_confidence_threshold 0.3

  # Calibration thresholds
  @calibration_high_confidence 0.7
  @calibration_medium_confidence 0.4

  @doc """
  Easy difficulty threshold.

  Scores below this value are classified as `:easy`.
  """
  @spec easy_threshold() :: threshold()
  def easy_threshold, do: @easy_threshold

  @doc """
  Hard difficulty threshold.

  Scores above this value are classified as `:hard`.
  """
  @spec hard_threshold() :: threshold()
  def hard_threshold, do: @hard_threshold

  @doc """
  Default early stop consensus threshold.

  When this level of agreement is reached in self-consistency,
  generation stops early to save compute.
  """
  @spec early_stop_threshold() :: threshold()
  def early_stop_threshold, do: @early_stop_threshold

  @doc """
  High consensus threshold for early stopping.

  Use this when you want stronger agreement before stopping.
  """
  @spec high_consensus_threshold() :: threshold()
  def high_consensus_threshold, do: @high_consensus_threshold

  @doc """
  Low consensus threshold for early stopping.

  Use this when you want to stop earlier with weaker agreement.
  """
  @spec low_consensus_threshold() :: threshold()
  def low_consensus_threshold, do: @low_consensus_threshold

  @doc """
  High confidence threshold.

  Estimates above this are considered high confidence.
  """
  @spec high_confidence_threshold() :: threshold()
  def high_confidence_threshold, do: @high_confidence_threshold

  @doc """
  Medium confidence threshold.

  Estimates above this are considered medium confidence.
  """
  @spec medium_confidence_threshold() :: threshold()
  def medium_confidence_threshold, do: @medium_confidence_threshold

  @doc """
  Low confidence threshold.

  Estimates below this are considered low confidence.
  """
  @spec low_confidence_threshold() :: threshold()
  def low_confidence_threshold, do: @low_confidence_threshold

  @doc """
  High confidence threshold for calibration-based routing.

  Responses with confidence above this may be returned directly.
  """
  @spec calibration_high_confidence() :: threshold()
  def calibration_high_confidence, do: @calibration_high_confidence

  @doc """
  Medium confidence threshold for calibration-based routing.

  Responses with confidence in this range require verification.
  """
  @spec calibration_medium_confidence() :: threshold()
  def calibration_medium_confidence, do: @calibration_medium_confidence

  @doc """
  Converts a score to a difficulty level using centralized thresholds.

  ## Parameters

  - `score` - Difficulty score between 0.0 and 1.0

  ## Returns

  - `:easy` if score < #{@easy_threshold}
  - `:hard` if score > #{@hard_threshold}
  - `:medium` otherwise

  ## Examples

      Thresholds.score_to_level(0.2)
      # => :easy

      Thresholds.score_to_level(0.5)
      # => :medium

      Thresholds.score_to_level(0.8)
      # => :hard

  """
  @spec score_to_level(float()) :: DifficultyEstimate.level()
  def score_to_level(score) when is_number(score) do
    cond do
      score < @easy_threshold -> :easy
      score > @hard_threshold -> :hard
      true -> :medium
    end
  end

  @doc """
  Converts a difficulty level to a representative score.

  ## Parameters

  - `:easy` - Returns #{@easy_threshold / 2}
  - `:medium` - Returns (@easy_threshold + #{@hard_threshold}) / 2
  - `:hard` - Returns (@hard_threshold + 1.0) / 2

  ## Examples

      Thresholds.level_to_score(:easy)
      # => 0.175

  """
  @spec level_to_score(DifficultyEstimate.level()) :: float()
  def level_to_score(:easy), do: @easy_threshold / 2
  def level_to_score(:medium), do: (@easy_threshold + @hard_threshold) / 2
  def level_to_score(:hard), do: (@hard_threshold + 1.0) / 2

  @doc """
  Gets all threshold values as a map.

  Useful for inspection and testing.

  ## Examples

      Thresholds.all()
      # => %{
      #   easy_threshold: 0.35,
      #   hard_threshold: 0.65,
      #   early_stop_threshold: 0.8,
      #   ...
      # }

  """
  @spec all() :: map()
  def all do
    %{
      easy_threshold: @easy_threshold,
      hard_threshold: @hard_threshold,
      early_stop_threshold: @early_stop_threshold,
      high_consensus_threshold: @high_consensus_threshold,
      low_consensus_threshold: @low_consensus_threshold,
      high_confidence_threshold: @high_confidence_threshold,
      medium_confidence_threshold: @medium_confidence_threshold,
      low_confidence_threshold: @low_confidence_threshold,
      calibration_high_confidence: @calibration_high_confidence,
      calibration_medium_confidence: @calibration_medium_confidence
    }
  end
end
