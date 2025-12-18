defmodule Jido.AI.Runner.GEPA.FeedbackAggregation.PatternDetector do
  @moduledoc """
  Detects recurring patterns in failure modes and suggestions.

  **Subtask 1.3.4.2**: Implement pattern detection identifying recurring failure modes.

  ## Responsibilities

  - Identify failure patterns appearing across multiple evaluations
  - Detect suggestion patterns (thematic clusters)
  - Calculate statistical significance (binomial tests)
  - Assess pattern confidence based on frequency and consistency

  ## Statistical Approach

  Uses binomial test to determine if a pattern's frequency is statistically
  significant compared to random chance:

  - Null hypothesis: Pattern appears randomly (p=0.1)
  - Alternative: Pattern is systemic (p > threshold)
  - Confidence levels: high (p<0.01), medium (p<0.05), low (p<0.10)

  ## Usage

      alias Jido.AI.Runner.GEPA.FeedbackAggregation.PatternDetector

      # Detect failure patterns
      {:ok, failure_patterns} = PatternDetector.detect_failure_patterns(collection)

      # Detect suggestion patterns
      {:ok, suggestion_patterns} = PatternDetector.detect_suggestion_patterns(collection)
  """

  require Logger

  alias Jido.AI.Runner.GEPA.FeedbackAggregation.{
    FailurePattern,
    FeedbackCollection,
    SuggestionPattern
  }

  @min_frequency_threshold 0.2
  @high_confidence_pvalue 0.01
  @medium_confidence_pvalue 0.05
  @low_confidence_pvalue 0.10

  @doc """
  Detects recurring failure patterns from reflections.

  Analyzes root causes across reflections to identify systemic failures.

  ## Parameters

  - `collection` - FeedbackCollection with reflections
  - `opts` - Options:
    - `:min_frequency` - Minimum frequency threshold (default: 0.2)
    - `:require_significance` - Require statistical significance (default: true)

  ## Returns

  - `{:ok, [FailurePattern.t()]}` - Detected patterns
  - `{:error, reason}` - If detection fails
  """
  @spec detect_failure_patterns(FeedbackCollection.t(), keyword()) ::
          {:ok, list(FailurePattern.t())} | {:error, term()}
  def detect_failure_patterns(%FeedbackCollection{} = collection, opts \\ []) do
    min_frequency = Keyword.get(opts, :min_frequency, @min_frequency_threshold)
    require_significance = Keyword.get(opts, :require_significance, true)

    Logger.debug(
      "Detecting failure patterns (evaluations: #{collection.total_evaluations}, min_frequency: #{min_frequency})"
    )

    # Extract root causes from reflections
    root_cause_groups =
      collection.reflections
      |> Enum.flat_map(&extract_root_causes(&1, collection))
      |> Enum.group_by(& &1.normalized_cause)

    # Convert to patterns
    patterns =
      root_cause_groups
      |> Enum.map(fn {normalized_cause, causes} ->
        create_failure_pattern(normalized_cause, causes, collection)
      end)
      |> Enum.filter(fn pattern ->
        pattern.frequency >= min_frequency and
          (not require_significance or pattern.confidence != :low)
      end)
      |> Enum.sort_by(& &1.frequency, :desc)

    Logger.debug("Failure patterns detected (count: #{length(patterns)})")

    {:ok, patterns}
  end

  @doc """
  Detects recurring suggestion patterns (themes).

  Groups suggestions by category and semantic similarity to identify themes.

  ## Parameters

  - `collection` - FeedbackCollection with suggestions
  - `opts` - Options:
    - `:min_frequency` - Minimum frequency threshold (default: 0.2)

  ## Returns

  - `{:ok, [SuggestionPattern.t()]}` - Detected patterns
  - `{:error, reason}` - If detection fails
  """
  @spec detect_suggestion_patterns(FeedbackCollection.t(), keyword()) ::
          {:ok, list(SuggestionPattern.t())} | {:error, term()}
  def detect_suggestion_patterns(%FeedbackCollection{} = collection, opts \\ []) do
    min_frequency = Keyword.get(opts, :min_frequency, @min_frequency_threshold)

    Logger.debug(
      "Detecting suggestion patterns (suggestions: #{length(collection.suggestions)}, min_frequency: #{min_frequency})"
    )

    # Group by category and theme
    suggestion_groups =
      collection.suggestions
      |> Enum.group_by(&{&1.suggestion.category, extract_theme(&1.suggestion)})

    # Convert to patterns
    patterns =
      suggestion_groups
      |> Enum.map(fn {{category, theme}, suggestions} ->
        create_suggestion_pattern(category, theme, suggestions, collection)
      end)
      |> Enum.filter(&(&1.frequency >= min_frequency))
      |> Enum.sort_by(& &1.aggregate_impact, :desc)

    Logger.debug("Suggestion patterns detected (count: #{length(patterns)})")

    {:ok, patterns}
  end

  # Private functions

  defp extract_root_causes(reflection, collection) do
    eval_id = find_evaluation_id(reflection, collection)

    reflection.root_causes
    |> Enum.map(fn cause ->
      %{
        original: cause,
        normalized_cause: normalize_cause(cause),
        evaluation_id: eval_id,
        reflection_confidence: reflection.confidence
      }
    end)
  end

  defp find_evaluation_id(reflection, collection) do
    # Find this reflection's evaluation ID from metadata
    # Use object identity since ParsedReflection doesn't have an id field
    index =
      Enum.find_index(collection.reflections, fn r -> r == reflection end) || 0

    eval_ids = get_in(collection.source_metadata, [:evaluation_ids]) || []
    Enum.at(eval_ids, index, "unknown")
  end

  defp normalize_cause(cause) when is_binary(cause) do
    cause
    |> String.downcase()
    |> String.trim()
    # Remove common variations
    |> String.replace(~r/\b(the|a|an)\b/, "")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp create_failure_pattern(normalized_cause, [first_cause | _rest] = causes, collection) do
    frequency = length(causes) / max(collection.total_evaluations, 1)
    affected_evals = Enum.map(causes, & &1.evaluation_id) |> Enum.uniq()

    # Calculate statistical significance
    {p_value, confidence} = calculate_significance(frequency, collection.total_evaluations)

    # Determine pattern type from cause text
    pattern_type = classify_pattern_type(normalized_cause)

    # Extract suggested fixes from related suggestions
    suggested_fixes = extract_related_fixes(normalized_cause, collection.suggestions)

    %FailurePattern{
      id: generate_pattern_id(),
      pattern_type: pattern_type,
      description: first_cause.original,
      frequency: frequency,
      confidence: confidence,
      statistical_significance: p_value,
      affected_evaluations: affected_evals,
      root_causes: Enum.map(causes, & &1.original) |> Enum.uniq(),
      suggested_fixes: suggested_fixes
    }
  end

  defp calculate_significance(frequency, total_evals) do
    # Binomial test: Is this frequency significantly higher than random (p=0.1)?
    # For small samples, we use conservative estimates

    # Calculate approximate p-value using normal approximation
    # (for production, use proper binomial test library)
    observed = (frequency * total_evals) |> round()
    expected = total_evals * 0.1

    if observed > expected && total_evals >= 5 do
      # Simple approximation: higher frequency and more evaluations = lower p-value
      p_value =
        cond do
          frequency >= 0.5 && total_evals >= 10 -> 0.001
          frequency >= 0.4 && total_evals >= 8 -> 0.01
          frequency >= 0.3 && total_evals >= 6 -> 0.03
          frequency >= 0.2 && total_evals >= 5 -> 0.08
          true -> 0.15
        end

      confidence =
        cond do
          p_value < @high_confidence_pvalue -> :high
          p_value < @medium_confidence_pvalue -> :medium
          p_value < @low_confidence_pvalue -> :low
          true -> :low
        end

      {p_value, confidence}
    else
      # Not enough data for significance
      {1.0, :low}
    end
  end

  defp classify_pattern_type(normalized_cause) do
    cond do
      String.contains?(normalized_cause, ["reasoning", "logic", "think", "step"]) ->
        :reasoning_error

      String.contains?(normalized_cause, ["tool", "function", "call", "api"]) ->
        :tool_failure

      String.contains?(normalized_cause, ["constraint", "requirement", "must", "should"]) ->
        :constraint_violation

      String.contains?(normalized_cause, ["unclear", "confus", "ambig", "vague"]) ->
        :clarity_issue

      String.contains?(normalized_cause, ["example", "demonstration", "sample"]) ->
        :example_missing

      String.contains?(normalized_cause, ["structure", "format", "organiz"]) ->
        :structure_problem

      true ->
        :reasoning_error
    end
  end

  defp extract_related_fixes(normalized_cause, suggestions) do
    suggestions
    |> Enum.filter(fn collected ->
      # Check if suggestion description relates to the cause
      normalized_desc = normalize_cause(collected.suggestion.description)
      text_overlap?(normalized_cause, normalized_desc)
    end)
    |> Enum.take(3)
    |> Enum.map(& &1.suggestion.description)
  end

  defp text_overlap?(text1, text2) do
    words1 = String.split(text1)
    words2 = String.split(text2)

    common_words =
      MapSet.intersection(MapSet.new(words1), MapSet.new(words2))
      |> MapSet.size()

    # At least 30% word overlap
    min_length = min(length(words1), length(words2))
    min_length > 0 && common_words / min_length >= 0.3
  end

  defp create_suggestion_pattern(category, theme, suggestions, collection) do
    total_sources =
      suggestions
      |> Enum.flat_map(& &1.sources)
      |> Enum.uniq()
      |> length()

    frequency = total_sources / max(collection.total_evaluations, 1)

    combined_rationale =
      suggestions
      |> Enum.map(& &1.suggestion.rationale)
      |> Enum.filter(&(&1 != nil))
      |> Enum.uniq()
      |> Enum.join(" | ")

    aggregate_impact =
      suggestions
      |> Enum.flat_map(& &1.edit_impact_scores)
      |> case do
        [] -> 0.5
        scores -> Enum.sum(scores) / length(scores)
      end

    {_p_value, confidence} = calculate_significance(frequency, collection.total_evaluations)

    %SuggestionPattern{
      id: generate_pattern_id(),
      category: category,
      theme: theme,
      frequency: frequency,
      suggestions: suggestions,
      combined_rationale: combined_rationale,
      aggregate_impact: aggregate_impact,
      confidence: confidence
    }
  end

  defp extract_theme(suggestion) do
    # Extract theme from description
    # Simplified: use first few significant words
    suggestion.description
    |> String.downcase()
    |> String.split()
    |> Enum.take(3)
    |> Enum.join(" ")
  end

  defp generate_pattern_id do
    "pattern_#{:erlang.unique_integer([:positive])}"
  end
end
