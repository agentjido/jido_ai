defmodule Jido.AI.Runner.GEPA.FeedbackAggregator do
  @moduledoc """
  Main orchestrator for feedback aggregation (Task 1.3.4).

  Aggregates feedback across multiple evaluations for robust improvement guidance,
  coordinating the complete pipeline from collection to weighted prioritization.

  ## Pipeline Stages

  1. **Collection** (1.3.4.1): Accumulate suggestions from reflections
  2. **Pattern Detection** (1.3.4.2): Identify recurring failure modes
  3. **Deduplication** (1.3.4.3): Remove redundant suggestions
  4. **Weighted Aggregation** (1.3.4.4): Confidence-based prioritization

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregator

      # Aggregate feedback from multiple evaluations
      {:ok, aggregated} = FeedbackAggregator.aggregate_feedback(
        reflections: reflections,
        edit_plans: edit_plans,
        min_frequency: 0.2,
        similarity_threshold: 0.7
      )

      # Access prioritized guidance
      aggregated.high_confidence         # Top suggestions
      aggregated.failure_patterns        # Recurring issues
      aggregated.suggestion_patterns     # Thematic groups

  ## Integration

  **Input**:
  - `ParsedReflection` structs from Task 1.3.2 (Reflector)
  - `EditPlan` structs from Task 1.3.3 (SuggestionGenerator)

  **Output**:
  - `AggregatedFeedback` for Task 1.4 (Mutation Operators)
  """

  require Logger

  alias Jido.AI.Runner.GEPA.FeedbackAggregation

  alias Jido.AI.Runner.GEPA.FeedbackAggregation.{
    AggregatedFeedback,
    Collector,
    Deduplicator,
    PatternDetector,
    WeightedAggregator
  }

  alias Jido.AI.Runner.GEPA.Reflector
  alias Jido.AI.Runner.GEPA.SuggestionGeneration

  @doc """
  Aggregates feedback from multiple evaluations.

  Executes the complete aggregation pipeline producing prioritized,
  deduplicated suggestions ready for mutation operators.

  ## Parameters

  - `opts` - Options (all keyword):
    - `:reflections` - List of ParsedReflection structs (required)
    - `:edit_plans` - List of EditPlan structs (optional but recommended)
    - `:evaluation_ids` - List of evaluation IDs (optional, auto-generated)
    - `:min_frequency` - Minimum pattern frequency (default: 0.2)
    - `:similarity_threshold` - Deduplication similarity (default: 0.7)
    - `:confidence_weighting` - Enable weighted aggregation (default: true)

  ## Returns

  - `{:ok, AggregatedFeedback.t()}` - Complete aggregated feedback
  - `{:error, reason}` - If aggregation fails

  ## Examples

      # Basic aggregation
      {:ok, feedback} = FeedbackAggregator.aggregate_feedback(
        reflections: [reflection1, reflection2]
      )

      # With edit plans and custom thresholds
      {:ok, feedback} = FeedbackAggregator.aggregate_feedback(
        reflections: reflections,
        edit_plans: edit_plans,
        min_frequency: 0.3,
        similarity_threshold: 0.75
      )
  """
  @spec aggregate_feedback(keyword()) :: {:ok, AggregatedFeedback.t()} | {:error, term()}
  def aggregate_feedback(opts \\ []) do
    Logger.info("Starting feedback aggregation pipeline")

    with {:ok, reflections} <- get_required_reflections(opts),
         {:ok, collection} <- collect_feedback(reflections, opts),
         {:ok, enriched} <- enrich_with_edit_plans(collection, opts),
         {:ok, failure_patterns} <- detect_failure_patterns(enriched, opts),
         {:ok, suggestion_patterns} <- detect_suggestion_patterns(enriched, opts),
         {:ok, clusters} <- deduplicate_suggestions(enriched, opts),
         {:ok, weighted} <- weight_suggestions(clusters, enriched, opts),
         {:ok, aggregated} <-
           build_aggregated_feedback(
             enriched,
             failure_patterns,
             suggestion_patterns,
             clusters,
             weighted
           ) do
      Logger.info(
        "Feedback aggregation complete (total_evaluations: #{collection.total_evaluations}, unique_suggestions: #{aggregated.total_unique_suggestions}, high_confidence: #{length(aggregated.high_confidence)})"
      )

      {:ok, aggregated}
    else
      {:error, reason} = error ->
        Logger.error("Feedback aggregation failed", reason: reason)
        error
    end
  end

  @doc """
  Aggregates feedback incrementally from a single new evaluation.

  Useful for streaming aggregation as evaluations complete.

  ## Parameters

  - `existing_feedback` - Previous AggregatedFeedback
  - `new_reflection` - New ParsedReflection to add
  - `new_edit_plan` - Optional new EditPlan
  - `opts` - Same options as aggregate_feedback/1

  ## Returns

  - `{:ok, AggregatedFeedback.t()}` - Updated aggregated feedback
  - `{:error, reason}` - If incremental aggregation fails
  """
  @spec aggregate_incremental(
          AggregatedFeedback.t(),
          Reflector.ParsedReflection.t(),
          SuggestionGeneration.EditPlan.t() | nil,
          keyword()
        ) :: {:ok, AggregatedFeedback.t()} | {:error, term()}
  def aggregate_incremental(
        %AggregatedFeedback{} = existing,
        %Reflector.ParsedReflection{} = new_reflection,
        new_edit_plan \\ nil,
        opts \\ []
      ) do
    Logger.debug(
      "Incremental aggregation (existing_evals: #{existing.collection.total_evaluations})"
    )

    # Merge new reflection into existing collection
    all_reflections = [new_reflection | existing.collection.reflections]

    all_edit_plans =
      if new_edit_plan do
        [new_edit_plan | existing.collection.edit_plans]
      else
        existing.collection.edit_plans
      end

    # Re-aggregate with updated data
    aggregate_feedback(
      Keyword.merge(opts,
        reflections: all_reflections,
        edit_plans: all_edit_plans
      )
    )
  end

  # Private pipeline stages

  defp get_required_reflections(opts) do
    case Keyword.get(opts, :reflections) do
      nil -> {:error, :missing_reflections}
      [] -> {:error, :empty_reflections}
      reflections when is_list(reflections) -> {:ok, reflections}
      _ -> {:error, :invalid_reflections}
    end
  end

  defp collect_feedback(reflections, opts) do
    Logger.debug("Stage 1: Collecting feedback (reflections: #{length(reflections)})")

    collector_opts =
      case Keyword.get(opts, :evaluation_ids) do
        nil -> []
        ids -> [evaluation_ids: ids]
      end

    Collector.collect_from_reflections(reflections, collector_opts)
  end

  defp enrich_with_edit_plans(collection, opts) do
    case Keyword.get(opts, :edit_plans) do
      nil ->
        Logger.debug("Stage 2: Skipping edit plan enrichment (no plans provided)")
        {:ok, collection}

      [] ->
        {:ok, collection}

      edit_plans when is_list(edit_plans) ->
        Logger.debug("Stage 2: Enriching with edit plans (plans: #{length(edit_plans)})")
        Collector.add_edit_plans(collection, edit_plans)
    end
  end

  defp detect_failure_patterns(collection, opts) do
    Logger.debug("Stage 3: Detecting failure patterns")

    pattern_opts = [
      min_frequency: Keyword.get(opts, :min_frequency, 0.2),
      require_significance: Keyword.get(opts, :require_significance, true)
    ]

    PatternDetector.detect_failure_patterns(collection, pattern_opts)
  end

  defp detect_suggestion_patterns(collection, opts) do
    Logger.debug("Stage 4: Detecting suggestion patterns")

    pattern_opts = [
      min_frequency: Keyword.get(opts, :min_frequency, 0.2)
    ]

    PatternDetector.detect_suggestion_patterns(collection, pattern_opts)
  end

  defp deduplicate_suggestions(collection, opts) do
    Logger.debug("Stage 5: Deduplicating suggestions")

    dedup_opts = [
      similarity_threshold: Keyword.get(opts, :similarity_threshold, 0.7),
      prefer_highest_impact: Keyword.get(opts, :prefer_highest_impact, true)
    ]

    Deduplicator.deduplicate_suggestions(collection.suggestions, dedup_opts)
  end

  defp weight_suggestions(clusters, collection, opts) do
    if Keyword.get(opts, :confidence_weighting, true) do
      Logger.debug("Stage 6: Weighting suggestions")

      weight_opts = []

      WeightedAggregator.weight_suggestions(clusters, collection, weight_opts)
    else
      Logger.debug("Stage 6: Skipping weighting (disabled)")
      # Create unweighted suggestions
      weighted =
        Enum.map(clusters, fn cluster ->
          %FeedbackAggregation.WeightedSuggestion{
            suggestion: cluster.representative,
            weight: 0.5,
            confidence_score: 0.5,
            frequency_score: 0.5,
            impact_score: 0.5,
            recency_score: 0.5,
            provenance_score: 0.5,
            priority: :medium
          }
        end)

      {:ok, weighted}
    end
  end

  defp build_aggregated_feedback(
         collection,
         failure_patterns,
         suggestion_patterns,
         clusters,
         weighted
       ) do
    {high_conf, medium_conf, low_conf, _} = partition_by_priority(weighted)

    total_unique = length(clusters)

    dedup_rate =
      if length(collection.suggestions) > 0 do
        1.0 - total_unique / length(collection.suggestions)
      else
        0.0
      end

    # Calculate pattern coverage: what % of evaluations have identified patterns
    pattern_coverage = calculate_pattern_coverage(failure_patterns, collection)

    aggregated = %AggregatedFeedback{
      id: generate_feedback_id(),
      collection: collection,
      failure_patterns: failure_patterns,
      suggestion_patterns: suggestion_patterns,
      clusters: clusters,
      weighted_suggestions: weighted,
      high_confidence: high_conf,
      medium_confidence: medium_conf,
      low_confidence: low_conf,
      total_unique_suggestions: total_unique,
      deduplication_rate: dedup_rate,
      pattern_coverage: pattern_coverage,
      aggregation_timestamp: DateTime.utc_now(),
      metadata: %{
        total_raw_suggestions: length(collection.suggestions),
        failure_patterns_count: length(failure_patterns),
        suggestion_patterns_count: length(suggestion_patterns)
      }
    }

    {:ok, aggregated}
  end

  defp partition_by_priority(weighted_suggestions) do
    high = Enum.filter(weighted_suggestions, &(&1.priority in [:critical, :high]))
    medium = Enum.filter(weighted_suggestions, &(&1.priority == :medium))
    low = Enum.filter(weighted_suggestions, &(&1.priority == :low))

    {high, medium, low, []}
  end

  defp calculate_pattern_coverage(failure_patterns, collection) do
    if collection.total_evaluations == 0 do
      0.0
    else
      affected_evals =
        failure_patterns
        |> Enum.flat_map(& &1.affected_evaluations)
        |> Enum.uniq()
        |> length()

      affected_evals / collection.total_evaluations
    end
  end

  defp generate_feedback_id do
    "feedback_#{:erlang.unique_integer([:positive])}"
  end
end
