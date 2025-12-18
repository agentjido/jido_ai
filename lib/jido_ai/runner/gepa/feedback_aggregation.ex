defmodule Jido.AI.Runner.GEPA.FeedbackAggregation do
  @moduledoc """
  Core data structures for GEPA feedback aggregation (Task 1.3.4).

  Provides TypedStruct definitions for aggregating feedback across multiple
  evaluations to identify robust, recurring patterns for mutation operators.

  ## Data Flow

  ```
  ParsedReflection (1.3.2) ──┐
  EditPlan (1.3.3) ──────────┤
  Trajectories (1.3.1) ──────┼──> FeedbackCollection
                             │    (CollectedSuggestion with provenance)
                             │             ↓
                             │    Pattern Detection
                             │    (FailurePattern, SuggestionPattern)
                             │             ↓
                             │    Deduplication
                             │    (Similarity grouping)
                             │             ↓
                             │    Weighted Aggregation
                             │    (Confidence scoring)
                             │             ↓
                             └──> AggregatedFeedback
                                   (for Task 1.4 Mutation Operators)
  ```

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregation

      # Collected suggestion with provenance
      suggestion = %FeedbackAggregation.CollectedSuggestion{
        suggestion: original_suggestion,
        sources: ["eval_1", "eval_3"],
        frequency: 0.2,
        edit_impact_scores: [0.8, 0.85]
      }

      # Aggregated feedback output
      feedback = %FeedbackAggregation.AggregatedFeedback{
        patterns: patterns,
        suggestions: weighted_suggestions,
        high_confidence: top_suggestions
      }
  """

  use TypedStruct

  alias Jido.AI.Runner.GEPA.Reflector
  alias Jido.AI.Runner.GEPA.SuggestionGeneration

  # ===== 1.3.4.1: Collection Data Structures =====

  typedstruct module: CollectedSuggestion do
    @moduledoc """
    A suggestion with full provenance tracking.

    Tracks where a suggestion came from, how often it appears, and its
    impact scores from edit plans.
    """

    field(:id, String.t(), enforce: true)
    field(:suggestion, Reflector.Suggestion.t(), enforce: true)
    field(:sources, list(String.t()), default: [])
    field(:frequency, float(), default: 1.0)
    field(:edit_impact_scores, list(float()), default: [])
    field(:contexts, list(map()), default: [])
    field(:first_seen, DateTime.t())
    field(:last_seen, DateTime.t())
  end

  typedstruct module: FeedbackCollection do
    @moduledoc """
    Accumulated feedback from multiple evaluation sources.

    The initial collection stage before pattern detection and deduplication.
    """

    field(:id, String.t(), enforce: true)
    field(:suggestions, list(CollectedSuggestion.t()), default: [])
    field(:reflections, list(Reflector.ParsedReflection.t()), default: [])
    field(:edit_plans, list(SuggestionGeneration.EditPlan.t()), default: [])
    field(:total_evaluations, non_neg_integer(), default: 0)
    field(:source_metadata, map(), default: %{})
    field(:collection_timestamp, DateTime.t())
  end

  # ===== 1.3.4.2: Pattern Detection Data Structures =====

  typedstruct module: FailurePattern do
    @moduledoc """
    A detected recurring failure pattern.

    Represents a systemic issue appearing across multiple evaluations with
    statistical significance.
    """

    field(:id, String.t(), enforce: true)
    field(:pattern_type, atom(), enforce: true)
    field(:description, String.t(), enforce: true)
    field(:frequency, float(), enforce: true)
    field(:confidence, :high | :medium | :low, enforce: true)
    field(:statistical_significance, float())
    field(:affected_evaluations, list(String.t()), default: [])
    field(:root_causes, list(String.t()), default: [])
    field(:suggested_fixes, list(String.t()), default: [])
    field(:example_trajectories, list(String.t()), default: [])
  end

  typedstruct module: SuggestionPattern do
    @moduledoc """
    A detected recurring suggestion pattern.

    Groups similar suggestions appearing across multiple evaluations,
    indicating a systemic improvement need.
    """

    field(:id, String.t(), enforce: true)
    field(:category, atom(), enforce: true)
    field(:theme, String.t(), enforce: true)
    field(:frequency, float(), enforce: true)
    field(:suggestions, list(CollectedSuggestion.t()), default: [])
    field(:combined_rationale, String.t())
    field(:aggregate_impact, float())
    field(:confidence, :high | :medium | :low, enforce: true)
  end

  # ===== 1.3.4.3: Deduplication Data Structures =====

  typedstruct module: SuggestionCluster do
    @moduledoc """
    A cluster of semantically similar suggestions.

    Groups suggestions that express the same underlying improvement idea
    in different words.
    """

    field(:id, String.t(), enforce: true)
    field(:representative, CollectedSuggestion.t(), enforce: true)
    field(:members, list(CollectedSuggestion.t()), default: [])
    field(:similarity_scores, list(float()), default: [])
    field(:cluster_size, non_neg_integer(), default: 1)
    field(:combined_frequency, float())
    field(:combined_impact, float())
  end

  # ===== 1.3.4.4: Weighted Aggregation Data Structures =====

  typedstruct module: WeightedSuggestion do
    @moduledoc """
    A suggestion with composite confidence score.

    Combines multiple signals (frequency, impact, confidence) into a
    final prioritization score.
    """

    field(:suggestion, CollectedSuggestion.t(), enforce: true)
    field(:weight, float(), enforce: true)
    field(:confidence_score, float(), enforce: true)
    field(:frequency_score, float(), enforce: true)
    field(:impact_score, float(), enforce: true)
    field(:recency_score, float(), enforce: true)
    field(:provenance_score, float(), enforce: true)
    field(:priority, :critical | :high | :medium | :low, enforce: true)
  end

  # ===== Final Output Data Structure =====

  typedstruct module: AggregatedFeedback do
    @moduledoc """
    Final aggregated feedback for mutation operators.

    The complete output of Task 1.3.4, ready for Task 1.4 to consume.
    Provides patterns, deduplicated suggestions, and confidence-weighted
    prioritization.
    """

    field(:id, String.t(), enforce: true)
    field(:collection, FeedbackCollection.t(), enforce: true)
    field(:failure_patterns, list(FailurePattern.t()), default: [])
    field(:suggestion_patterns, list(SuggestionPattern.t()), default: [])
    field(:clusters, list(SuggestionCluster.t()), default: [])
    field(:weighted_suggestions, list(WeightedSuggestion.t()), default: [])
    field(:high_confidence, list(WeightedSuggestion.t()), default: [])
    field(:medium_confidence, list(WeightedSuggestion.t()), default: [])
    field(:low_confidence, list(WeightedSuggestion.t()), default: [])
    field(:total_unique_suggestions, non_neg_integer(), default: 0)
    field(:deduplication_rate, float())
    field(:pattern_coverage, float())
    field(:aggregation_timestamp, DateTime.t())
    field(:metadata, map(), default: %{})
  end

  # ===== Helper Types =====

  @type pattern_type ::
          :reasoning_error
          | :tool_failure
          | :constraint_violation
          | :clarity_issue
          | :example_missing
          | :structure_problem

  @type suggestion_theme :: String.t()

  @type confidence_level :: :high | :medium | :low

  @type priority_level :: :critical | :high | :medium | :low
end
