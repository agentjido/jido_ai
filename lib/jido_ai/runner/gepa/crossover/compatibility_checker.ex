defmodule JidoAI.Runner.GEPA.Crossover.CompatibilityChecker do
  @moduledoc """
  Checks if two prompts can be safely crossed to produce valid offspring.

  This module analyzes parent prompts to detect:
  - Contradictory constraints ("use calculators" vs "no calculators")
  - Duplicate content (low-value crossover)
  - Structural incompatibilities
  - Semantic mismatches

  ## Compatibility Scoring

  - **0.8-1.0**: Highly compatible, any strategy recommended
  - **0.6-0.8**: Moderately compatible, semantic or uniform crossover recommended
  - **0.4-0.6**: Low compatibility, blending only
  - **0.0-0.4**: Incompatible, skip crossover

  ## Examples

      iex> {:ok, result} = CompatibilityChecker.check_compatibility(parent_a, parent_b)
      iex> result.compatible
      true
      iex> result.compatibility_score
      0.85
      iex> result.recommended_strategy
      :semantic
  """

  alias JidoAI.Runner.GEPA.Crossover.{CompatibilityResult, SegmentedPrompt}

  # Contradiction patterns
  @negation_pairs [
    {"use", "don't use"},
    {"use", "avoid"},
    {"include", "exclude"},
    {"with", "without"},
    {"allow", "prohibit"},
    {"must", "must not"},
    {"should", "should not"},
    {"always", "never"}
  ]

  # Compatibility thresholds
  @high_compatibility 0.8
  @moderate_compatibility 0.6
  @low_compatibility 0.4
  @min_segment_overlap 0.3

  @doc """
  Checks if two segmented prompts can be crossed.

  ## Parameters

  - `parent_a` - First segmented prompt
  - `parent_b` - Second segmented prompt
  - `opts` - Options:
    - `:strict` - Use strict compatibility checking (default: false)
    - `:min_score` - Minimum compatibility score (default: 0.4)

  ## Returns

  - `{:ok, CompatibilityResult.t()}` - Compatibility analysis
  - `{:error, reason}` - If checking fails

  ## Examples

      {:ok, result} = CompatibilityChecker.check_compatibility(parent_a, parent_b)
      if result.compatible do
        perform_crossover(parent_a, parent_b, result.recommended_strategy)
      end
  """
  @spec check_compatibility(SegmentedPrompt.t(), SegmentedPrompt.t(), keyword()) ::
          {:ok, CompatibilityResult.t()} | {:error, term()}
  def check_compatibility(parent_a, parent_b, opts \\ [])

  def check_compatibility(
        %SegmentedPrompt{} = parent_a,
        %SegmentedPrompt{} = parent_b,
        opts
      ) do
    strict = Keyword.get(opts, :strict, false)
    min_score = Keyword.get(opts, :min_score, @low_compatibility)

    issues = detect_issues(parent_a, parent_b, strict)
    score = calculate_compatibility_score(parent_a, parent_b, issues)
    strategy = recommend_strategy(score, issues)
    compatible = score >= min_score and not has_blocking_issues?(issues)

    result = %CompatibilityResult{
      compatible: compatible,
      issues: issues,
      compatibility_score: score,
      recommended_strategy: strategy,
      metadata: %{
        parent_a_structure: parent_a.structure_type,
        parent_b_structure: parent_b.structure_type,
        segment_overlap: calculate_segment_type_overlap(parent_a, parent_b),
        content_diversity: calculate_content_diversity(parent_a, parent_b)
      }
    }

    {:ok, result}
  end

  def check_compatibility(_parent_a, _parent_b, _opts) do
    {:error, :invalid_segmented_prompts}
  end

  @doc """
  Quick check if two prompts are compatible without full analysis.

  Returns true/false only, useful for fast filtering.
  """
  @spec compatible?(SegmentedPrompt.t(), SegmentedPrompt.t()) :: boolean()
  def compatible?(parent_a, parent_b) do
    case check_compatibility(parent_a, parent_b) do
      {:ok, %{compatible: compatible}} -> compatible
      {:error, _} -> false
    end
  end

  # Private functions

  defp detect_issues(parent_a, parent_b, strict) do
    []
    |> add_structural_issues(parent_a, parent_b)
    |> add_contradiction_issues(parent_a, parent_b)
    |> add_duplication_issues(parent_a, parent_b, strict)
    |> add_semantic_issues(parent_a, parent_b, strict)
  end

  defp add_structural_issues(issues, parent_a, parent_b) do
    cond do
      Enum.empty?(parent_a.segments) or Enum.empty?(parent_b.segments) ->
        [:incompatible_structure | issues]

      calculate_segment_type_overlap(parent_a, parent_b) < @min_segment_overlap ->
        [:incompatible_structure | issues]

      true ->
        issues
    end
  end

  defp add_contradiction_issues(issues, parent_a, parent_b) do
    contradictions = find_contradictions(parent_a, parent_b)

    if Enum.empty?(contradictions) do
      issues
    else
      [:contradictory_constraints | issues]
    end
  end

  defp add_duplication_issues(issues, parent_a, parent_b, strict) do
    similarity = calculate_content_similarity(parent_a, parent_b)

    cond do
      similarity > 0.9 and strict -> [:duplicate_content | issues]
      similarity > 0.95 -> [:duplicate_content | issues]
      true -> issues
    end
  end

  defp add_semantic_issues(issues, parent_a, parent_b, strict) do
    if strict and has_semantic_mismatch?(parent_a, parent_b) do
      [:semantic_mismatch | issues]
    else
      issues
    end
  end

  defp find_contradictions(parent_a, parent_b) do
    # Get all constraint and instruction segments
    segments_a =
      Enum.filter(parent_a.segments, &(&1.type in [:constraint, :instruction]))

    segments_b =
      Enum.filter(parent_b.segments, &(&1.type in [:constraint, :instruction]))

    # Check for contradictions between segments
    for seg_a <- segments_a,
        seg_b <- segments_b,
        contradicts?(seg_a.content, seg_b.content),
        do: {seg_a, seg_b}
  end

  defp contradicts?(text_a, text_b) do
    text_a_lower = String.downcase(text_a)
    text_b_lower = String.downcase(text_b)

    Enum.any?(@negation_pairs, fn {term, negation} ->
      (String.contains?(text_a_lower, term) and String.contains?(text_b_lower, negation)) or
        (String.contains?(text_a_lower, negation) and String.contains?(text_b_lower, term))
    end)
  end

  defp calculate_compatibility_score(parent_a, parent_b, issues) do
    # Base score from segment overlap
    segment_overlap = calculate_segment_type_overlap(parent_a, parent_b)

    # Diversity bonus
    diversity = calculate_content_diversity(parent_a, parent_b)

    # Issue penalties
    contradiction_penalty = if :contradictory_constraints in issues, do: 0.4, else: 0.0
    structure_penalty = if :incompatible_structure in issues, do: 0.3, else: 0.0
    duplicate_penalty = if :duplicate_content in issues, do: 0.2, else: 0.0
    semantic_penalty = if :semantic_mismatch in issues, do: 0.1, else: 0.0

    total_penalty =
      contradiction_penalty + structure_penalty + duplicate_penalty + semantic_penalty

    # Calculate final score
    base_score = segment_overlap * 0.4 + diversity * 0.4
    final_score = max(0.0, base_score - total_penalty * 0.6)

    Float.round(final_score, 2)
  end

  defp calculate_segment_type_overlap(parent_a, parent_b) do
    types_a = parent_a.segments |> Enum.map(& &1.type) |> MapSet.new()
    types_b = parent_b.segments |> Enum.map(& &1.type) |> MapSet.new()

    intersection = MapSet.intersection(types_a, types_b) |> MapSet.size()
    union = MapSet.union(types_a, types_b) |> MapSet.size()

    if union > 0 do
      Float.round(intersection / union, 2)
    else
      0.0
    end
  end

  defp calculate_content_diversity(parent_a, parent_b) do
    # Higher diversity = better for crossover
    similarity = calculate_content_similarity(parent_a, parent_b)
    Float.round(1.0 - similarity, 2)
  end

  defp calculate_content_similarity(parent_a, parent_b) do
    # Simple word-level Jaccard similarity
    words_a = extract_words(parent_a.raw_text)
    words_b = extract_words(parent_b.raw_text)

    intersection = MapSet.intersection(words_a, words_b) |> MapSet.size()
    union = MapSet.union(words_a, words_b) |> MapSet.size()

    if union > 0 do
      Float.round(intersection / union, 2)
    else
      0.0
    end
  end

  defp extract_words(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\w\s]/, " ")
    |> String.split(~r/\s+/, trim: true)
    |> MapSet.new()
  end

  defp has_semantic_mismatch?(parent_a, parent_b) do
    # Check if both prompts have task descriptions
    task_a = Enum.find(parent_a.segments, &(&1.type == :task_description))
    task_b = Enum.find(parent_b.segments, &(&1.type == :task_description))

    if is_nil(task_a) or is_nil(task_b) do
      false
    else
      # Check if tasks are semantically different
      similarity = word_overlap_similarity(task_a.content, task_b.content)
      similarity < 0.2
    end
  end

  defp word_overlap_similarity(text_a, text_b) do
    words_a = extract_words(text_a)
    words_b = extract_words(text_b)

    intersection = MapSet.intersection(words_a, words_b) |> MapSet.size()
    union = MapSet.union(words_a, words_b) |> MapSet.size()

    if union > 0 do
      intersection / union
    else
      0.0
    end
  end

  defp recommend_strategy(score, issues) do
    cond do
      score >= @high_compatibility and not has_blocking_issues?(issues) ->
        :semantic

      score >= @moderate_compatibility ->
        :uniform

      score >= @low_compatibility ->
        :two_point

      true ->
        nil
    end
  end

  defp has_blocking_issues?(issues) do
    :contradictory_constraints in issues or :incompatible_structure in issues
  end
end
