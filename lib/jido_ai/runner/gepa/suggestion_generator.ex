defmodule Jido.AI.Runner.GEPA.SuggestionGenerator do
  @moduledoc """
  Main orchestrator for converting LLM suggestions into concrete prompt edits.

  This module is the primary interface for Task 1.3.3, coordinating all the
  sub-modules to transform abstract suggestions from the Reflector (Task 1.3.2)
  into actionable edit plans for mutation operators (Task 1.4).

  ## Pipeline

  1. Analyze prompt structure (PromptStructureAnalyzer)
  2. Build concrete edits from suggestions (EditBuilder)
  3. Validate each edit (EditValidator)
  4. Resolve conflicts (ConflictResolver)
  5. Rank by impact (ImpactRanker)
  6. Return complete EditPlan

  ## Usage

      # From ParsedReflection (Task 1.3.2 output)
      reflection = %Reflector.ParsedReflection{
        suggestions: [suggestion1, suggestion2, ...],
        ...
      }

      {:ok, edit_plan} = SuggestionGenerator.generate_edit_plan(
        reflection,
        original_prompt: "Solve this problem"
      )

      # Access validated, ranked edits
      edit_plan.edits          # All valid edits, ranked by impact
      edit_plan.total_edits    # Count
      edit_plan.validated      # true
      edit_plan.ranked         # true

  ## Integration

  **Input**: `Reflector.ParsedReflection` from Task 1.3.2
  **Output**: `EditPlan` for Task 1.4 Mutation Operators
  """

  require Logger

  alias Jido.AI.Runner.GEPA.Reflector.ParsedReflection
  alias Jido.AI.Runner.GEPA.SuggestionGeneration

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.{
    ConflictResolver,
    EditBuilder,
    EditPlan,
    EditValidator,
    ImpactRanker,
    PromptStructureAnalyzer
  }

  @doc """
  Generates a complete edit plan from a parsed reflection.

  This is the main entry point for Task 1.3.3. Takes suggestions from
  the Reflector and produces concrete, validated, ranked edits.

  ## Parameters

  - `reflection` - ParsedReflection from Task 1.3.2 (Reflector)
  - `opts` - Options:
    - `:original_prompt` - The prompt to edit (required)
    - `:max_edits` - Limit total edits (default: 10)
    - `:conflict_resolution_strategy` - Strategy for conflicts (default: :highest_impact)
    - `:min_impact_score` - Filter edits below this score (default: 0.3)

  ## Returns

  - `{:ok, EditPlan.t()}` - Complete edit plan
  - `{:error, reason}` - If generation fails

  ## Examples

      {:ok, plan} = SuggestionGenerator.generate_edit_plan(
        reflection,
        original_prompt: "Solve this math problem",
        max_edits: 5
      )

      Enum.each(plan.edits, fn e ->
        IO.puts "\#{e.operation}: \#{e.content}"
      end)
  """
  @spec generate_edit_plan(ParsedReflection.t(), keyword()) ::
          {:ok, EditPlan.t()} | {:error, term()}
  def generate_edit_plan(%ParsedReflection{} = reflection, opts \\ []) do
    Logger.info("Starting edit plan generation (suggestions: #{length(reflection.suggestions)})")

    with {:ok, prompt} <- get_original_prompt(opts),
         {:ok, structure} <- PromptStructureAnalyzer.analyze(prompt),
         {:ok, raw_edits} <- build_all_edits(reflection.suggestions, structure, opts),
         {:ok, validated_edits} <- validate_all_edits(raw_edits, structure),
         {:ok, conflict_resolved_edits} <- resolve_all_conflicts(validated_edits, opts),
         {:ok, ranked_edits} <- rank_all_edits(conflict_resolved_edits),
         {:ok, filtered_edits} <- filter_by_criteria(ranked_edits, opts) do
      plan = %EditPlan{
        id: generate_plan_id(),
        original_prompt: prompt,
        prompt_structure: structure,
        edits: filtered_edits,
        total_edits: length(filtered_edits),
        high_impact_edits: count_high_impact(filtered_edits),
        conflicts_resolved: count_conflicts_resolved(conflict_resolved_edits),
        validated: true,
        ranked: true,
        metadata: %{
          source_reflection_confidence: reflection.confidence,
          total_suggestions: length(reflection.suggestions),
          generation_timestamp: DateTime.utc_now()
        }
      }

      Logger.info(
        "Edit plan generated successfully (total_edits: #{plan.total_edits}, high_impact: #{plan.high_impact_edits})"
      )

      {:ok, plan}
    else
      {:error, reason} = error ->
        Logger.error("Edit plan generation failed", reason: reason)
        error
    end
  end

  @doc """
  Generates edits for a single suggestion.

  Useful for testing or incremental edit generation.

  ## Parameters

  - `suggestion` - Single suggestion from Reflector
  - `prompt` - The prompt to edit
  - `opts` - Options (same as generate_edit_plan)

  ## Returns

  - `{:ok, [PromptEdit.t()]}` - Generated edits
  - `{:error, reason}` - If generation fails
  """
  @spec generate_edits_for_suggestion(
          Reflector.Suggestion.t(),
          String.t(),
          keyword()
        ) :: {:ok, list(SuggestionGeneration.PromptEdit.t())} | {:error, term()}
  def generate_edits_for_suggestion(suggestion, prompt, opts \\ []) do
    with {:ok, structure} <- PromptStructureAnalyzer.analyze(prompt),
         {:ok, edits} <- EditBuilder.build_edits(suggestion, structure, opts) do
      validate_edits(edits, structure)
    end
  end

  # Private helper functions

  defp get_original_prompt(opts) do
    case Keyword.get(opts, :original_prompt) do
      nil -> {:error, :missing_original_prompt}
      prompt when is_binary(prompt) -> {:ok, prompt}
      _ -> {:error, :invalid_prompt}
    end
  end

  defp build_all_edits(suggestions, structure, opts) do
    Logger.debug("Building edits from suggestions (count: #{length(suggestions)})")

    edits_results =
      Enum.map(suggestions, fn suggestion ->
        EditBuilder.build_edits(suggestion, structure, opts)
      end)

    # Collect successful edits
    edits =
      edits_results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.flat_map(fn {:ok, edits} -> edits end)

    # Log any failures
    failures = Enum.filter(edits_results, &match?({:error, _}, &1))

    if failures != [] do
      Logger.warning("Some edit generations failed", failures: length(failures))
    end

    {:ok, edits}
  end

  defp validate_all_edits(edits, structure) do
    Logger.debug("Validating edits (count: #{length(edits)})")

    validated_edits =
      edits
      |> Enum.map(fn edit ->
        case EditValidator.validate(edit, structure) do
          {:ok, validated} ->
            validated

          {:error, reason} ->
            Logger.warning(
              "Edit validation failed (edit_id: #{edit.id}, reason: #{inspect(reason)})"
            )

            # Return edit marked as invalid
            %{edit | validated: false}
        end
      end)

    # Filter out completely invalid edits
    valid_edits = Enum.filter(validated_edits, & &1.validated)

    Logger.debug(
      "Validation complete (valid: #{length(valid_edits)}, invalid: #{length(edits) - length(valid_edits)})"
    )

    {:ok, valid_edits}
  end

  defp resolve_all_conflicts(edits, opts) do
    strategy = Keyword.get(opts, :conflict_resolution_strategy, :highest_impact)

    Logger.debug("Resolving conflicts (strategy: #{inspect(strategy)})")

    case ConflictResolver.resolve_conflicts(edits, strategy: strategy) do
      {:ok, resolved} ->
        # Filter out edits that lost conflict resolution
        non_conflicting = Enum.filter(resolved, &(&1.conflicts_with == []))

        Logger.debug(
          "Conflicts resolved (original: #{length(edits)}, resolved: #{length(non_conflicting)}, removed: #{length(edits) - length(non_conflicting)})"
        )

        {:ok, non_conflicting}

      error ->
        error
    end
  end

  defp rank_all_edits(edits) do
    Logger.debug("Ranking edits by impact")

    ranked = ImpactRanker.rank_by_impact(edits)

    {:ok, ranked}
  end

  defp filter_by_criteria(edits, opts) do
    max_edits = Keyword.get(opts, :max_edits, 10)
    min_impact = Keyword.get(opts, :min_impact_score, 0.3)

    filtered =
      edits
      |> Enum.filter(&(&1.impact_score >= min_impact))
      |> Enum.take(max_edits)

    Logger.debug(
      "Applied filters (before: #{length(edits)}, after: #{length(filtered)}, max_edits: #{max_edits}, min_impact: #{min_impact})"
    )

    {:ok, filtered}
  end

  defp validate_edits(edits, structure) do
    validated =
      Enum.map(edits, fn edit ->
        case EditValidator.validate(edit, structure) do
          {:ok, v} -> v
          {:error, _} -> %{edit | validated: false}
        end
      end)

    {:ok, Enum.filter(validated, & &1.validated)}
  end

  defp count_high_impact(edits) do
    Enum.count(edits, &(&1.impact_score >= 0.7))
  end

  defp count_conflicts_resolved(edits) do
    # Count edits that had conflicts but were resolved
    Enum.count(edits, &(&1.conflicts_with != []))
  end

  defp generate_plan_id do
    "plan_#{:erlang.unique_integer([:positive])}"
  end
end
