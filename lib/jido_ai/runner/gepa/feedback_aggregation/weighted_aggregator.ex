defmodule Jido.AI.Runner.GEPA.FeedbackAggregation.WeightedAggregator do
  @moduledoc """
  Applies confidence-weighted aggregation to prioritize suggestions.

  **Subtask 1.3.4.4**: Support weighted aggregation prioritizing high-confidence insights.

  ## Composite Confidence Scoring

  Combines multiple signals into a final confidence score:

  - **Frequency Score** (30%): How often the suggestion appears
  - **Impact Score** (30%): Average edit impact from Task 1.3.3
  - **Provenance Score** (25%): Quality of source reflections
  - **Recency Score** (15%): When the suggestion was last seen

  ## Priority Levels

  - **Critical** (weight >= 0.85): Act immediately, systemic issue
  - **High** (weight >= 0.70): High-impact, well-supported
  - **Medium** (weight >= 0.50): Worth applying, moderate confidence
  - **Low** (weight < 0.50): Consider but not priority

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregation.WeightedAggregator

      # Weight suggestions from clusters
      {:ok, weighted} = WeightedAggregator.weight_suggestions(clusters, collection)

      # Sort by priority
      sorted = WeightedAggregator.sort_by_priority(weighted)
  """

  require Logger

  alias Jido.AI.Runner.GEPA.FeedbackAggregation.{
    FeedbackCollection,
    SuggestionCluster,
    WeightedSuggestion
  }

  @frequency_weight 0.30
  @impact_weight 0.30
  @provenance_weight 0.25
  @recency_weight 0.15

  @critical_threshold 0.85
  @high_threshold 0.70
  @medium_threshold 0.50

  @doc """
  Applies weighted aggregation to suggestion clusters.

  ## Parameters

  - `clusters` - List of SuggestionCluster structs from deduplication
  - `collection` - Original FeedbackCollection for context
  - `opts` - Options:
    - `:frequency_weight` - Weight for frequency score (default: 0.30)
    - `:impact_weight` - Weight for impact score (default: 0.30)
    - `:provenance_weight` - Weight for provenance score (default: 0.25)
    - `:recency_weight` - Weight for recency score (default: 0.15)

  ## Returns

  - `{:ok, [WeightedSuggestion.t()]}` - Weighted suggestions
  - `{:error, reason}` - If weighting fails
  """
  @spec weight_suggestions([SuggestionCluster.t()], FeedbackCollection.t(), keyword()) ::
          {:ok, list(WeightedSuggestion.t())} | {:error, term()}
  def weight_suggestions(clusters, %FeedbackCollection{} = collection, opts \\ [])
      when is_list(clusters) do
    freq_weight = Keyword.get(opts, :frequency_weight, @frequency_weight)
    impact_weight = Keyword.get(opts, :impact_weight, @impact_weight)
    prov_weight = Keyword.get(opts, :provenance_weight, @provenance_weight)
    rec_weight = Keyword.get(opts, :recency_weight, @recency_weight)

    Logger.debug(
      "Weighting suggestions (clusters: #{length(clusters)}, weights: #{inspect({freq_weight, impact_weight, prov_weight, rec_weight})})"
    )

    weighted =
      Enum.map(clusters, fn cluster ->
        calculate_weighted_suggestion(
          cluster,
          collection,
          {freq_weight, impact_weight, prov_weight, rec_weight}
        )
      end)
      |> Enum.sort_by(& &1.weight, :desc)

    Logger.debug("Weighting complete (suggestions: #{length(weighted)})")

    {:ok, weighted}
  end

  @doc """
  Sorts weighted suggestions by priority level and weight.

  ## Parameters

  - `weighted_suggestions` - List of WeightedSuggestion structs

  ## Returns

  - `[WeightedSuggestion.t()]` - Sorted by priority then weight
  """
  @spec sort_by_priority([WeightedSuggestion.t()]) :: [WeightedSuggestion.t()]
  def sort_by_priority(weighted_suggestions) when is_list(weighted_suggestions) do
    priority_order = %{critical: 4, high: 3, medium: 2, low: 1}

    Enum.sort_by(weighted_suggestions, fn w ->
      {-Map.get(priority_order, w.priority, 0), -w.weight}
    end)
  end

  @doc """
  Groups weighted suggestions by priority level.

  ## Parameters

  - `weighted_suggestions` - List of WeightedSuggestion structs

  ## Returns

  - `{critical, high, medium, low}` - Tuple of grouped suggestions
  """
  @spec group_by_priority([WeightedSuggestion.t()]) ::
          {[WeightedSuggestion.t()], [WeightedSuggestion.t()], [WeightedSuggestion.t()],
           [WeightedSuggestion.t()]}
  def group_by_priority(weighted_suggestions) when is_list(weighted_suggestions) do
    grouped = Enum.group_by(weighted_suggestions, & &1.priority)

    {
      Map.get(grouped, :critical, []),
      Map.get(grouped, :high, []),
      Map.get(grouped, :medium, []),
      Map.get(grouped, :low, [])
    }
  end

  # Private functions

  defp calculate_weighted_suggestion(cluster, collection, weights) do
    {freq_weight, impact_weight, prov_weight, rec_weight} = weights

    # Calculate component scores
    frequency_score = calculate_frequency_score(cluster, collection)
    impact_score = calculate_impact_score(cluster)
    provenance_score = calculate_provenance_score(cluster, collection)
    recency_score = calculate_recency_score(cluster)

    # Composite weight
    composite_weight =
      frequency_score * freq_weight +
        impact_score * impact_weight +
        provenance_score * prov_weight +
        recency_score * rec_weight

    # Confidence score (same as weight for now)
    confidence_score = composite_weight

    # Determine priority
    priority = determine_priority(composite_weight)

    %WeightedSuggestion{
      suggestion: cluster.representative,
      weight: composite_weight,
      confidence_score: confidence_score,
      frequency_score: frequency_score,
      impact_score: impact_score,
      recency_score: recency_score,
      provenance_score: provenance_score,
      priority: priority
    }
  end

  defp calculate_frequency_score(cluster, collection) do
    # Normalize frequency to [0, 1]
    # Higher frequency relative to total evaluations = higher score
    max_frequency = collection.total_evaluations * 1.0

    if max_frequency > 0 do
      min(cluster.combined_frequency / max_frequency, 1.0)
    else
      0.5
    end
  end

  defp calculate_impact_score(cluster) do
    # Use combined impact from cluster
    # Already normalized to [0, 1] from Task 1.3.3
    cluster.combined_impact || 0.5
  end

  defp calculate_provenance_score(cluster, _collection) do
    # Score based on reflection confidence of sources
    # Get confidences from reflection metadata

    source_confidences =
      cluster.members
      |> Enum.flat_map(& &1.contexts)
      |> Enum.map(& &1[:reflection_confidence])
      |> Enum.filter(&(&1 != nil))

    if Enum.empty?(source_confidences) do
      0.5
    else
      # Convert confidence atoms to numeric scores
      numeric_scores =
        Enum.map(source_confidences, fn conf ->
          case conf do
            :high -> 1.0
            :medium -> 0.6
            :low -> 0.3
            _ -> 0.5
          end
        end)

      Enum.sum(numeric_scores) / length(numeric_scores)
    end
  end

  defp calculate_recency_score(cluster) do
    # Score based on how recently the suggestion was last seen
    # More recent = higher score

    last_seen = cluster.representative.last_seen

    if last_seen do
      # Calculate time delta in hours
      now = DateTime.utc_now()
      diff_seconds = DateTime.diff(now, last_seen, :second)
      diff_hours = diff_seconds / 3600.0

      # Decay function: score decreases as time increases
      # Full score (1.0) for < 1 hour
      # Half score (0.5) for ~24 hours
      # Minimum score (0.1) for > 7 days
      cond do
        diff_hours < 1 -> 1.0
        diff_hours < 24 -> 0.8
        diff_hours < 48 -> 0.6
        diff_hours < 168 -> 0.4
        true -> 0.2
      end
    else
      # No timestamp, assume moderate recency
      0.5
    end
  end

  defp determine_priority(weight) do
    cond do
      weight >= @critical_threshold -> :critical
      weight >= @high_threshold -> :high
      weight >= @medium_threshold -> :medium
      true -> :low
    end
  end
end
