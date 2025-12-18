defmodule Jido.AI.Runner.GEPA.SuggestionGeneration.ConflictResolver do
  @moduledoc """
  Resolves conflicts between overlapping or contradictory edits.

  Identifies groups of edits that cannot all be applied together and
  selects which edits to keep based on resolution strategies.

  ## Conflict Types

  - **Overlapping**: Edits affect the same location in the prompt
  - **Contradictory**: Edits have opposing effects (add vs. remove same content)
  - **Dependent**: Edits have circular or unresolvable dependencies

  ## Resolution Strategies

  - `:highest_impact` - Keep edit with highest impact score
  - `:highest_priority` - Keep edit with highest priority
  - `:first` - Keep first edit encountered
  - `:merge` - Attempt to merge compatible edits

  ## Usage

      edits_with_conflicts = ConflictResolver.resolve_conflicts(edits)
      valid_edits = Enum.reject(edits_with_conflicts, & &1.conflicts_with != [])
  """

  require Logger

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.{ConflictGroup, PromptEdit}

  @doc """
  Resolves conflicts in a list of edits.

  ## Parameters

  - `edits` - List of edits to check for conflicts
  - `opts` - Options:
    - `:strategy` - Resolution strategy (default: :highest_impact)

  ## Returns

  - `{:ok, [PromptEdit.t()]}` - Edits with conflicts resolved
  - `{:error, reason}` - If resolution fails

  ## Examples

      {:ok, resolved_edits} = ConflictResolver.resolve_conflicts(edits)
  """
  @spec resolve_conflicts(list(PromptEdit.t()), keyword()) ::
          {:ok, list(PromptEdit.t())} | {:error, term()}
  def resolve_conflicts(edits, opts \\ []) when is_list(edits) do
    strategy = Keyword.get(opts, :strategy, :highest_impact)

    # Find conflict groups
    conflict_groups = identify_conflicts(edits)

    # Resolve each conflict group
    resolved_groups =
      Enum.map(conflict_groups, fn group ->
        resolve_conflict_group(group, strategy)
      end)

    # Get selected edits from resolved groups
    selected_edit_ids =
      resolved_groups
      |> Enum.filter(& &1.resolved)
      |> Enum.map(& &1.selected_edit)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(& &1.id)
      |> MapSet.new()

    # Mark conflicting edits
    resolved_edits =
      Enum.map(edits, fn edit ->
        if edit.id in selected_edit_ids or not has_conflicts?(edit, conflict_groups) do
          # No conflicts or was selected
          edit
        else
          # Has conflicts and wasn't selected - mark as conflicting
          conflict_ids = get_conflict_ids(edit, conflict_groups)
          %{edit | conflicts_with: conflict_ids}
        end
      end)

    {:ok, resolved_edits}
  end

  # Private functions

  defp identify_conflicts(edits) do
    # Check for overlapping locations
    overlapping_groups = find_overlapping_edits(edits)

    # Check for contradictory operations
    contradictory_groups = find_contradictory_edits(edits)

    overlapping_groups ++ contradictory_groups
  end

  defp find_overlapping_edits(edits) do
    # Group edits by their target location
    location_groups =
      edits
      |> Enum.group_by(&get_location_key/1)
      |> Enum.filter(fn {_key, group} -> length(group) > 1 end)
      |> Enum.map(fn {_key, group} -> group end)

    Enum.map(location_groups, fn group ->
      %ConflictGroup{
        edits: group,
        conflict_type: :overlapping,
        resolution_strategy: :highest_impact,
        resolved: false
      }
    end)
  end

  defp find_contradictory_edits(edits) do
    # Find add/delete pairs for same content
    additions = Enum.filter(edits, &(&1.operation == :insert))
    deletions = Enum.filter(edits, &(&1.operation == :delete))

    contradictory_pairs =
      for add <- additions,
          del <- deletions,
          content_overlaps?(add.content, del.target_text) do
        [add, del]
      end

    Enum.map(contradictory_pairs, fn pair ->
      %ConflictGroup{
        edits: pair,
        conflict_type: :contradictory,
        resolution_strategy: :highest_impact,
        resolved: false
      }
    end)
  end

  defp get_location_key(edit) do
    location = edit.location

    case location.type do
      :within when location.pattern ->
        {:within, normalize_pattern(location.pattern)}

      :before when location.relative_marker ->
        {:before, location.relative_marker}

      :after when location.relative_marker ->
        {:after, location.relative_marker}

      type ->
        {type, nil}
    end
  end

  defp normalize_pattern(pattern) when is_binary(pattern), do: String.downcase(pattern)
  defp normalize_pattern(%Regex{} = pattern), do: Regex.source(pattern)
  defp normalize_pattern(_), do: nil

  defp content_overlaps?(content1, content2) when is_binary(content1) and is_binary(content2) do
    # Simple check: see if one contains significant portion of the other
    c1 = String.downcase(String.trim(content1))
    c2 = String.downcase(String.trim(content2))

    String.contains?(c1, c2) or String.contains?(c2, c1)
  end

  defp content_overlaps?(_, _), do: false

  defp resolve_conflict_group(group, strategy) do
    selected = select_edit_from_group(group.edits, strategy)

    %{group | resolved: true, selected_edit: selected}
  end

  defp select_edit_from_group([first | _rest] = edits, :highest_impact) do
    Enum.max_by(edits, & &1.impact_score, fn -> first end)
  end

  defp select_edit_from_group([first | _rest] = edits, :highest_priority) do
    priority_order = %{high: 3, medium: 2, low: 1}

    Enum.max_by(edits, &Map.get(priority_order, &1.priority, 0), fn -> first end)
  end

  defp select_edit_from_group([first | _rest], :first) do
    first
  end

  defp select_edit_from_group(edits, _) do
    # Default to highest impact
    select_edit_from_group(edits, :highest_impact)
  end

  defp has_conflicts?(edit, conflict_groups) do
    Enum.any?(conflict_groups, fn group ->
      Enum.any?(group.edits, &(&1.id == edit.id))
    end)
  end

  defp get_conflict_ids(edit, conflict_groups) do
    conflict_groups
    |> Enum.filter(fn group ->
      Enum.any?(group.edits, &(&1.id == edit.id))
    end)
    |> Enum.flat_map(fn group ->
      group.edits
      |> Enum.reject(&(&1.id == edit.id))
      |> Enum.map(& &1.id)
    end)
    |> Enum.uniq()
  end
end
