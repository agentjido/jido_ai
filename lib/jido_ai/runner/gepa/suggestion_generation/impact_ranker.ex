defmodule Jido.AI.Runner.GEPA.SuggestionGeneration.ImpactRanker do
  @moduledoc """
  Ranks edits by their expected impact on prompt effectiveness.

  Calculates impact scores based on multiple factors:
  - Suggestion priority (from LLM)
  - Edit category (clarity, constraints, examples have different impacts)
  - Edit specificity (specific_text provided vs. generated)
  - Target location (some locations are more impactful)
  - Validation status (validated edits rank higher)

  ## Scoring Algorithm

  Impact score ranges from 0.0 to 1.0, combining:
  - Base priority score (0.3 weight)
  - Category score (0.25 weight)
  - Specificity score (0.20 weight)
  - Location score (0.15 weight)
  - Validation bonus (0.10 weight)

  ## Usage

      ranked_edits = ImpactRanker.rank_by_impact(edits)
      top_edit = hd(ranked_edits)  # Highest impact edit
  """

  require Logger

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.PromptEdit

  @doc """
  Ranks edits by expected impact, returning them in descending order.

  ## Parameters

  - `edits` - List of edits to rank

  ## Returns

  - `[PromptEdit.t()]` - Edits sorted by impact score (highest first)

  ## Examples

      ranked = ImpactRanker.rank_by_impact(edits)
      high_impact = Enum.take(ranked, 3)
  """
  @spec rank_by_impact(list(PromptEdit.t())) :: list(PromptEdit.t())
  def rank_by_impact(edits) when is_list(edits) do
    edits
    |> Enum.map(&calculate_impact_score/1)
    |> Enum.sort_by(& &1.impact_score, :desc)
  end

  @doc """
  Calculates the impact score for a single edit.

  ## Parameters

  - `edit` - The edit to score

  ## Returns

  - `PromptEdit.t()` - Edit with updated impact_score

  ## Examples

      scored_edit = ImpactRanker.calculate_impact_score(edit)
      scored_edit.impact_score  # => 0.75
  """
  @spec calculate_impact_score(PromptEdit.t()) :: PromptEdit.t()
  def calculate_impact_score(%PromptEdit{} = edit) do
    priority_score = calculate_priority_score(edit.priority) * 0.3
    category_score = calculate_category_score(edit.source_suggestion.category) * 0.25
    specificity_score = calculate_specificity_score(edit) * 0.20
    location_score = calculate_location_score(edit.location) * 0.15
    validation_bonus = if edit.validated, do: 0.10, else: 0.0

    impact_score =
      priority_score + category_score + specificity_score + location_score + validation_bonus

    # Clamp to [0.0, 1.0]
    clamped_score = min(max(impact_score, 0.0), 1.0)

    %{edit | impact_score: clamped_score}
  end

  # Private scoring functions

  defp calculate_priority_score(:high), do: 1.0
  defp calculate_priority_score(:medium), do: 0.6
  defp calculate_priority_score(:low), do: 0.3
  defp calculate_priority_score(_), do: 0.5

  defp calculate_category_score(category) do
    case category do
      # Clarity improvements highly impactful
      :clarity -> 0.9
      # Constraints enforce correctness
      :constraint -> 0.85
      # Reasoning guidance valuable
      :reasoning -> 0.8
      # Examples helpful but not critical
      :example -> 0.7
      # Structure changes moderate impact
      :structure -> 0.6
      _ -> 0.5
    end
  end

  defp calculate_specificity_score(edit) do
    cond do
      # Has specific text from LLM
      edit.source_suggestion.specific_text &&
          String.trim(edit.source_suggestion.specific_text) != "" ->
        1.0

      # Has concrete content generated
      edit.content && String.length(edit.content) > 20 ->
        0.7

      # Has target text for replacement/deletion
      edit.target_text && edit.operation in [:replace, :delete] ->
        0.6

      # Generic or low specificity
      true ->
        0.3
    end
  end

  defp calculate_location_score(location) do
    case location.type do
      # Appending is safe and common
      :end -> 0.7
      # Prepending can be very impactful
      :start -> 0.8
      # Targeted edits are most impactful
      :within -> 0.9
      # Relative positioning good
      :before -> 0.75
      :after -> 0.75
      # Bulk replacements risky
      :replace_all -> 0.5
      _ -> 0.5
    end
  end
end
