defmodule Jido.AI.Accuracy.Revision do
  @moduledoc """
  Behavior for revision generation.

  Revisers improve candidate responses based on critique feedback.
  This behavior defines the interface for all revision implementations.

  ## Revision Patterns

  There are several patterns for generating revisions:

  1. **LLM-based revision** - Uses an LLM to incorporate critique feedback
  2. **Targeted revision** - Applies specific fixes for known issue types
  3. **Rule-based revision** - Applies deterministic transformations
  4. **Hybrid revision** - Combines multiple approaches

  ## Implementing the Behavior

  To implement the Revision behavior:

      defmodule MyReviser do
        @behaviour Jido.AI.Accuracy.Revision

        @impl true
        def revise(candidate, critique, context) do
          # Analyze the critique
          issues = critique.issues
          suggestions = critique.suggestions

          # Generate improved content
          improved_content = apply_improvements(candidate.content, issues, suggestions)

          {:ok, Candidate.new!(%{
            id: candidate.id,
            content: improved_content,
            metadata: Map.put(candidate.metadata || %{}, :revision_of, candidate.id)
          })}
        end
      end

  ## Context

  The context map may contain:
  - `:prompt` - Original prompt/question
  - `:domain` - Domain for specialized revision (e.g., :math, :code)
  - `:preserve_correct` - Whether to preserve parts without issues
  - `:max_length` - Maximum length for revised content
  - `:revision_count` - Current iteration number
  - Custom keys for specific reviser implementations

  ## Examples

      # LLM-based revision
      {:ok, revised} = LLMReviser.revise(candidate, critique, %{
        prompt: "What is 15 * 23?",
        preserve_correct: true
      })

      # Targeted code revision
      {:ok, revised} = TargetedReviser.revise_code(candidate, critique, %{
        fix_syntax: true,
        apply_linting: true
      })

  """

  alias Jido.AI.Accuracy.{Candidate, CritiqueResult}

  @type context :: map()
  @type revision_result :: {:ok, Candidate.t()} | {:error, term()}

  @doc """
  Revise a candidate based on critique feedback.

  ## Parameters

  - `candidate` - The candidate to revise
  - `critique` - The critique feedback to incorporate
  - `context` - Additional context for the revision

  ## Returns

  - `{:ok, Candidate.t()}` on success - The revised candidate
  - `{:error, reason}` on failure

  """
  @callback revise(Candidate.t(), CritiqueResult.t(), context()) :: revision_result()

  @doc """
  Generate a diff showing changes between original and revised content.

  This callback is optional. If not implemented, a simple text diff
  will be generated.

  ## Parameters

  - `original` - The original candidate
  - `revised` - The revised candidate

  ## Returns

  - `{:ok, diff_map}` - Map with change information

  """
  @callback diff(Candidate.t(), Candidate.t()) :: {:ok, map()} | {:error, term()}

  @optional_callbacks [diff: 2]

  @doc """
  Default implementation for generating a diff.

  Compares content and metadata between two candidates.

  """
  @spec diff(Candidate.t(), Candidate.t()) :: {:ok, map()}
  def diff(%Candidate{} = original, %Candidate{} = revised) do
    content_diff = compute_content_diff(original.content || "", revised.content || "")

    metadata_diff = compute_metadata_diff(original.metadata || %{}, revised.metadata || %{})

    {:ok,
     %{
       original_id: original.id,
       revised_id: revised.id,
       content_changed: content_diff != :unchanged,
       content_diff: content_diff,
       metadata_changed: metadata_diff != :unchanged,
       metadata_diff: metadata_diff,
       timestamp: System.system_time(:millisecond)
     }}
  end

  @doc """
  Checks if the given module is a reviser.

  A module is considered a reviser if it exports:
  - `revise/3` - for module-level implementations, or
  - `revise/4` - for struct-based implementations (self, candidate, critique, context)

  """
  @spec reviser?(term()) :: boolean()
  def reviser?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      (function_exported?(module, :revise, 3) or function_exported?(module, :revise, 4))
  end

  def reviser?(_), do: false

  @doc """
  Gets the revision behavior.

  """
  @spec behaviour() :: module()
  def behaviour, do: __MODULE__

  # Private functions

  defp compute_content_diff("", ""), do: :unchanged
  defp compute_content_diff(original, original), do: :unchanged
  defp compute_content_diff(original, revised) do
    # Simple word-level diff
    original_words = String.split(original, ~r/\s+/, trim: true)
    revised_words = String.split(revised, ~r/\s+/, trim: true)

    if original_words == revised_words do
      # Only whitespace changed
      {:whitespace_only, original, revised}
    else
      # Substantive changes
      {removed, added} = compute_word_changes(original_words, revised_words)

      %{
        type: :substantive,
        original_length: length(original_words),
        revised_length: length(revised_words),
        removed_words: removed,
        added_words: added,
        removed_count: length(removed),
        added_count: length(added)
      }
    end
  end

  defp compute_word_changes(original_words, revised_words) do
    original_set = MapSet.new(original_words)
    revised_set = MapSet.new(revised_words)

    removed = MapSet.to_list(MapSet.difference(original_set, revised_set))
    added = MapSet.to_list(MapSet.difference(revised_set, original_set))

    {removed, added}
  end

  defp compute_metadata_diff(original, original), do: :unchanged
  defp compute_metadata_diff(original, revised) do
    changed_keys =
      original
      |> Map.keys()
      |> Enum.concat(Map.keys(revised))
      |> Enum.uniq()
      |> Enum.filter(fn key ->
        Map.get(original, key) != Map.get(revised, key)
      end)

    if Enum.empty?(changed_keys) do
      :unchanged
    else
      %{
        changed_keys: changed_keys,
        original_keys: Map.keys(original) |> MapSet.new(),
        revised_keys: Map.keys(revised) |> MapSet.new(),
        added_keys: MapSet.difference(MapSet.new(Map.keys(revised)), MapSet.new(Map.keys(original))) |> MapSet.to_list(),
        removed_keys: MapSet.difference(MapSet.new(Map.keys(original)), MapSet.new(Map.keys(revised))) |> MapSet.to_list()
      }
    end
  end
end
