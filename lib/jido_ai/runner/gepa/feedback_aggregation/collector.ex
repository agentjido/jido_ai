defmodule Jido.AI.Runner.GEPA.FeedbackAggregation.Collector do
  @moduledoc """
  Collects and organizes feedback from multiple evaluation sources.

  **Subtask 1.3.4.1**: Create feedback collector accumulating suggestions
  from multiple reflections.

  ## Responsibilities

  - Accumulate suggestions from ParsedReflection structs
  - Track provenance (which evaluations generated which suggestions)
  - Calculate initial frequency metrics
  - Merge edit plan impact scores
  - Support incremental collection as evaluations complete

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregation.Collector

      # Collect from reflections
      {:ok, collection} = Collector.collect_from_reflections(reflections)

      # Add edit plan data
      {:ok, enriched} = Collector.add_edit_plans(collection, edit_plans)

      # Merge multiple collections
      {:ok, merged} = Collector.merge_collections([collection1, collection2])
  """

  require Logger

  alias Jido.AI.Runner.GEPA.FeedbackAggregation.{CollectedSuggestion, FeedbackCollection}
  alias Jido.AI.Runner.GEPA.Reflector
  alias Jido.AI.Runner.GEPA.SuggestionGeneration

  @doc """
  Collects suggestions from multiple parsed reflections.

  ## Parameters

  - `reflections` - List of ParsedReflection structs from Task 1.3.2
  - `opts` - Options:
    - `:evaluation_ids` - List of evaluation IDs (optional, auto-generated if not provided)

  ## Returns

  - `{:ok, FeedbackCollection.t()}` - Collection with suggestions and provenance
  - `{:error, reason}` - If collection fails
  """
  @spec collect_from_reflections([Reflector.ParsedReflection.t()], keyword()) ::
          {:ok, FeedbackCollection.t()} | {:error, term()}
  def collect_from_reflections(reflections, opts \\ []) when is_list(reflections) do
    Logger.debug("Collecting feedback from reflections (count: #{length(reflections)})")

    evaluation_ids = Keyword.get(opts, :evaluation_ids, generate_evaluation_ids(reflections))

    if length(evaluation_ids) != length(reflections) do
      {:error, :evaluation_id_count_mismatch}
    else
      collected_suggestions =
        reflections
        |> Enum.zip(evaluation_ids)
        |> Enum.flat_map(fn {reflection, eval_id} ->
          collect_from_single_reflection(reflection, eval_id)
        end)
        |> group_and_merge_suggestions()

      collection = %FeedbackCollection{
        id: generate_collection_id(),
        suggestions: collected_suggestions,
        reflections: reflections,
        total_evaluations: length(reflections),
        collection_timestamp: DateTime.utc_now(),
        source_metadata: %{
          evaluation_ids: evaluation_ids,
          reflection_confidences: Enum.map(reflections, & &1.confidence)
        }
      }

      Logger.debug(
        "Collection complete (unique_suggestions: #{length(collected_suggestions)}, total_evaluations: #{length(reflections)})"
      )

      {:ok, collection}
    end
  end

  @doc """
  Adds edit plan information to an existing collection.

  Enriches collected suggestions with impact scores from edit plans.

  ## Parameters

  - `collection` - Existing FeedbackCollection
  - `edit_plans` - List of EditPlan structs from Task 1.3.3

  ## Returns

  - `{:ok, FeedbackCollection.t()}` - Enriched collection
  - `{:error, reason}` - If enrichment fails
  """
  @spec add_edit_plans(FeedbackCollection.t(), [SuggestionGeneration.EditPlan.t()]) ::
          {:ok, FeedbackCollection.t()} | {:error, term()}
  def add_edit_plans(%FeedbackCollection{} = collection, edit_plans)
      when is_list(edit_plans) do
    Logger.debug("Enriching collection with edit plans (edit_plan_count: #{length(edit_plans)})")

    # Build a map of suggestion -> impact scores from edit plans
    suggestion_to_scores = build_impact_score_map(edit_plans)

    # Update suggestions with impact scores
    enriched_suggestions =
      Enum.map(collection.suggestions, fn collected ->
        key = suggestion_key(collected.suggestion)
        impact_scores = Map.get(suggestion_to_scores, key, [])

        %{collected | edit_impact_scores: impact_scores}
      end)

    enriched = %{
      collection
      | suggestions: enriched_suggestions,
        edit_plans: edit_plans
    }

    {:ok, enriched}
  end

  @doc """
  Merges multiple feedback collections into one.

  Useful for combining collections from different optimization runs or
  incremental collection as evaluations complete.

  ## Parameters

  - `collections` - List of FeedbackCollection structs

  ## Returns

  - `{:ok, FeedbackCollection.t()}` - Merged collection
  - `{:error, reason}` - If merge fails
  """
  @spec merge_collections([FeedbackCollection.t()]) ::
          {:ok, FeedbackCollection.t()} | {:error, term()}
  def merge_collections(collections) when is_list(collections) do
    Logger.debug("Merging collections (count: #{length(collections)})")

    merged_suggestions =
      collections
      |> Enum.flat_map(& &1.suggestions)
      |> group_and_merge_suggestions()

    merged_reflections =
      collections
      |> Enum.flat_map(& &1.reflections)
      |> Enum.uniq_by(& &1.id)

    merged_edit_plans =
      collections
      |> Enum.flat_map(& &1.edit_plans)
      |> Enum.uniq_by(& &1.id)

    total_evaluations =
      collections
      |> Enum.map(& &1.total_evaluations)
      |> Enum.sum()

    merged_metadata =
      collections
      |> Enum.map(& &1.source_metadata)
      |> Enum.reduce(%{}, &Map.merge/2)

    merged = %FeedbackCollection{
      id: generate_collection_id(),
      suggestions: merged_suggestions,
      reflections: merged_reflections,
      edit_plans: merged_edit_plans,
      total_evaluations: total_evaluations,
      collection_timestamp: DateTime.utc_now(),
      source_metadata: merged_metadata
    }

    {:ok, merged}
  end

  # Private functions

  defp collect_from_single_reflection(reflection, eval_id) do
    timestamp = DateTime.utc_now()

    Enum.map(reflection.suggestions, fn suggestion ->
      %CollectedSuggestion{
        id: generate_suggestion_id(),
        suggestion: suggestion,
        sources: [eval_id],
        frequency: 1.0,
        contexts: [
          %{
            evaluation_id: eval_id,
            reflection_confidence: reflection.confidence,
            root_causes: reflection.root_causes,
            timestamp: timestamp
          }
        ],
        first_seen: timestamp,
        last_seen: timestamp
      }
    end)
  end

  defp group_and_merge_suggestions(collected_suggestions) do
    collected_suggestions
    |> Enum.group_by(&suggestion_key(&1.suggestion))
    |> Enum.map(fn {_key, group} ->
      merge_suggestion_group(group)
    end)
  end

  defp merge_suggestion_group([single]), do: single

  defp merge_suggestion_group([first | _rest] = group) do
    all_sources = group |> Enum.flat_map(& &1.sources) |> Enum.uniq()
    all_contexts = group |> Enum.flat_map(& &1.contexts)
    all_impact_scores = group |> Enum.flat_map(& &1.edit_impact_scores)

    timestamps = Enum.map(group, & &1.first_seen)
    # Safe min/max with DateTime comparator function
    first_seen = Enum.min(timestamps, DateTime)
    last_seen = Enum.max(timestamps, DateTime)

    %{
      first
      | sources: all_sources,
        frequency: length(all_sources) * 1.0,
        contexts: all_contexts,
        edit_impact_scores: all_impact_scores,
        first_seen: first_seen,
        last_seen: last_seen
    }
  end

  defp build_impact_score_map(edit_plans) do
    edit_plans
    |> Enum.flat_map(fn plan ->
      plan.edits
      |> Enum.map(fn edit ->
        {suggestion_key(edit.source_suggestion), edit.impact_score}
      end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
  end

  defp suggestion_key(suggestion) do
    # Create a key for grouping similar suggestions
    # Uses type, category, and description (normalized)
    {
      suggestion.type,
      suggestion.category,
      normalize_text(suggestion.description)
    }
  end

  defp normalize_text(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.trim()
  end

  defp normalize_text(_), do: ""

  defp generate_collection_id do
    "collection_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_suggestion_id do
    "suggestion_#{:erlang.unique_integer([:positive])}"
  end

  defp generate_evaluation_ids(reflections) do
    Enum.map(1..length(reflections), fn i ->
      "eval_#{i}_#{:erlang.unique_integer([:positive])}"
    end)
  end
end
