defmodule Jido.AI.Runner.GEPA.FeedbackAggregation.Deduplicator do
  @moduledoc """
  Removes redundant and semantically similar suggestions.

  **Subtask 1.3.4.3**: Add suggestion deduplication removing redundant improvements.

  ## Deduplication Strategy

  Hierarchical deduplication using multiple similarity signals:

  1. **Exact matches** (1.0 similarity): Identical suggestions
  2. **High similarity** (0.85-0.99): Same intent, slight wording differences
  3. **Semantic clustering** (0.70-0.84): Related suggestions, can be combined
  4. **Related concepts** (0.50-0.69): Keep both but note relationship

  ## Similarity Signals

  - Text similarity (Jaro-Winkler distance on descriptions)
  - Category and type matching
  - Target section overlap
  - Rationale similarity

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregation.Deduplicator

      # Deduplicate suggestions
      {:ok, clusters} = Deduplicator.deduplicate_suggestions(
        suggestions,
        similarity_threshold: 0.7
      )
  """

  require Logger

  alias Jido.AI.Runner.GEPA.FeedbackAggregation.{
    CollectedSuggestion,
    SuggestionCluster
  }

  @default_similarity_threshold 0.7

  @doc """
  Deduplicates suggestions using hierarchical similarity clustering.

  ## Parameters

  - `suggestions` - List of CollectedSuggestion structs
  - `opts` - Options:
    - `:similarity_threshold` - Minimum similarity to cluster (default: 0.7)
    - `:prefer_highest_impact` - Select representative by impact (default: true)

  ## Returns

  - `{:ok, [SuggestionCluster.t()]}` - Deduplicated clusters
  - `{:error, reason}` - If deduplication fails
  """
  @spec deduplicate_suggestions([CollectedSuggestion.t()], keyword()) ::
          {:ok, list(SuggestionCluster.t())} | {:error, term()}
  def deduplicate_suggestions(suggestions, opts \\ []) when is_list(suggestions) do
    threshold = Keyword.get(opts, :similarity_threshold, @default_similarity_threshold)
    prefer_impact = Keyword.get(opts, :prefer_highest_impact, true)

    Logger.debug(
      "Deduplicating suggestions (count: #{length(suggestions)}, threshold: #{threshold})"
    )

    clusters = perform_clustering(suggestions, threshold, prefer_impact)

    Logger.debug(
      "Deduplication complete (original: #{length(suggestions)}, clusters: #{length(clusters)}, reduction: #{1 - length(clusters) / max(length(suggestions), 1)})"
    )

    {:ok, clusters}
  end

  @doc """
  Calculates similarity between two suggestions.

  Returns a score from 0.0 (completely different) to 1.0 (identical).

  ## Parameters

  - `suggestion1` - First CollectedSuggestion
  - `suggestion2` - Second CollectedSuggestion

  ## Returns

  - `float()` - Similarity score
  """
  @spec calculate_similarity(CollectedSuggestion.t(), CollectedSuggestion.t()) :: float()
  def calculate_similarity(%CollectedSuggestion{} = s1, %CollectedSuggestion{} = s2) do
    # Multi-signal similarity calculation

    # 1. Type and category match (40% weight)
    type_match = if s1.suggestion.type == s2.suggestion.type, do: 1.0, else: 0.0
    category_match = if s1.suggestion.category == s2.suggestion.category, do: 1.0, else: 0.0
    type_category_score = (type_match + category_match) / 2.0

    # 2. Description similarity (40% weight)
    desc_similarity =
      jaro_winkler_similarity(
        s1.suggestion.description,
        s2.suggestion.description
      )

    # 3. Rationale similarity (15% weight)
    rationale_similarity =
      jaro_winkler_similarity(
        s1.suggestion.rationale || "",
        s2.suggestion.rationale || ""
      )

    # 4. Target section match (5% weight)
    target_match =
      if s1.suggestion.target_section == s2.suggestion.target_section, do: 1.0, else: 0.0

    # Weighted combination
    similarity =
      type_category_score * 0.40 +
        desc_similarity * 0.40 +
        rationale_similarity * 0.15 +
        target_match * 0.05

    similarity
  end

  # Private functions

  defp perform_clustering(suggestions, threshold, prefer_impact) do
    # Start with each suggestion as its own cluster
    initial_clusters =
      Enum.map(suggestions, fn s ->
        %SuggestionCluster{
          id: generate_cluster_id(),
          representative: s,
          members: [s],
          similarity_scores: [],
          cluster_size: 1,
          combined_frequency: s.frequency,
          combined_impact: calculate_average_impact(s)
        }
      end)

    # Iteratively merge similar clusters
    merge_clusters(initial_clusters, threshold, prefer_impact)
  end

  defp merge_clusters(clusters, threshold, prefer_impact) do
    # Find most similar pair
    case find_most_similar_pair(clusters, threshold) do
      nil ->
        # No more clusters to merge
        clusters

      {cluster1, cluster2, similarity} ->
        # Merge the pair
        merged = merge_cluster_pair(cluster1, cluster2, similarity, prefer_impact)

        # Remove original clusters and add merged one
        remaining =
          clusters
          |> Enum.reject(&(&1.id == cluster1.id || &1.id == cluster2.id))

        # Continue merging
        merge_clusters([merged | remaining], threshold, prefer_impact)
    end
  end

  defp find_most_similar_pair(clusters, threshold) do
    # Find the most similar pair of clusters above threshold
    clusters
    |> all_pairs()
    |> Enum.map(fn {c1, c2} ->
      similarity = calculate_cluster_similarity(c1, c2)
      {c1, c2, similarity}
    end)
    |> Enum.filter(fn {_c1, _c2, sim} -> sim >= threshold end)
    |> Enum.max_by(fn {_c1, _c2, sim} -> sim end, fn -> nil end)
  end

  defp all_pairs(list) when length(list) < 2, do: []

  defp all_pairs(list) do
    for i <- 0..(length(list) - 2),
        j <- Range.new(i + 1, length(list) - 1, 1) do
      {Enum.at(list, i), Enum.at(list, j)}
    end
  end

  defp calculate_cluster_similarity(cluster1, cluster2) do
    # Similarity between clusters is the max similarity between any pair of members
    # (single-linkage clustering)
    for m1 <- cluster1.members,
        m2 <- cluster2.members do
      calculate_similarity(m1, m2)
    end
    |> case do
      [] -> 0.0
      similarities -> Enum.max(similarities)
    end
  end

  defp merge_cluster_pair(cluster1, cluster2, similarity, prefer_impact) do
    all_members = cluster1.members ++ cluster2.members

    # Select representative
    representative =
      if prefer_impact do
        Enum.max_by(all_members, &calculate_average_impact/1)
      else
        # Prefer higher frequency
        Enum.max_by(all_members, & &1.frequency)
      end

    combined_frequency =
      all_members
      |> Enum.flat_map(& &1.sources)
      |> Enum.uniq()
      |> length()
      |> Kernel.*(1.0)

    all_impact_scores = all_members |> Enum.flat_map(& &1.edit_impact_scores)

    combined_impact =
      if Enum.empty?(all_impact_scores) do
        0.5
      else
        Enum.sum(all_impact_scores) / length(all_impact_scores)
      end

    %SuggestionCluster{
      id: generate_cluster_id(),
      representative: representative,
      members: all_members,
      similarity_scores: [similarity | cluster1.similarity_scores ++ cluster2.similarity_scores],
      cluster_size: length(all_members),
      combined_frequency: combined_frequency,
      combined_impact: combined_impact
    }
  end

  defp calculate_average_impact(collected_suggestion) do
    case collected_suggestion.edit_impact_scores do
      [] -> 0.5
      scores -> Enum.sum(scores) / length(scores)
    end
  end

  # Jaro-Winkler similarity implementation
  # Simplified version for text similarity
  defp jaro_winkler_similarity(s1, s2) when is_binary(s1) and is_binary(s2) do
    s1_normalized = String.downcase(String.trim(s1))
    s2_normalized = String.downcase(String.trim(s2))

    # Handle edge cases
    cond do
      s1_normalized == s2_normalized -> 1.0
      s1_normalized == "" or s2_normalized == "" -> 0.0
      true -> calculate_jaro_winkler(s1_normalized, s2_normalized)
    end
  end

  defp jaro_winkler_similarity(_, _), do: 0.0

  defp calculate_jaro_winkler(s1, s2) do
    # Simplified Jaro similarity
    # For production, use a proper string similarity library
    jaro = calculate_jaro(s1, s2)

    # Winkler modification: boost score if strings have common prefix
    prefix_length = common_prefix_length(s1, s2, 4)
    prefix_scale = 0.1

    jaro + prefix_length * prefix_scale * (1.0 - jaro)
  end

  defp calculate_jaro(s1, s2) do
    # Simplified Jaro similarity using common substring ratio
    # Good enough for our deduplication needs
    len1 = String.length(s1)
    len2 = String.length(s2)

    if len1 == 0 or len2 == 0 do
      0.0
    else
      # Calculate longest common substring length
      common_length = longest_common_substring_length(s1, s2)

      # Approximate Jaro score based on common content
      score = common_length / max(len1, len2)

      # Adjust for relative lengths
      length_similarity = min(len1, len2) / max(len1, len2)

      (score + length_similarity) / 2.0
    end
  end

  defp longest_common_substring_length(s1, s2) do
    words1 = String.split(s1)
    words2 = String.split(s2)

    common_words = MapSet.intersection(MapSet.new(words1), MapSet.new(words2))
    common_text = Enum.join(MapSet.to_list(common_words), " ")

    String.length(common_text)
  end

  defp common_prefix_length(s1, s2, max_length) do
    String.graphemes(s1)
    |> Enum.zip(String.graphemes(s2))
    |> Enum.take(max_length)
    |> Enum.take_while(fn {c1, c2} -> c1 == c2 end)
    |> length()
  end

  defp generate_cluster_id do
    "cluster_#{:erlang.unique_integer([:positive])}"
  end
end
