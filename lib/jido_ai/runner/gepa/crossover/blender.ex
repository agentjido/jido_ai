defmodule JidoAI.Runner.GEPA.Crossover.Blender do
  @moduledoc """
  Blends segments from multiple prompts intelligently.

  Unlike exchange strategies that swap entire segments, blending merges
  the content of similar segments to combine complementary information.

  ## Blending Strategies

  - **Instruction Blending**: Combines instructions into coherent sequences
  - **Constraint Combination**: Merges constraints from both parents
  - **Example Merging**: Combines example sets
  - **Deduplication**: Removes redundant content

  ## Examples

      iex> {:ok, blended} = Blender.blend_segments([seg_a, seg_b])
      iex> String.contains?(blended.content, "step by step")
      true
  """

  alias JidoAI.Runner.GEPA.Crossover.PromptSegment

  @doc """
  Blends multiple segments of the same type into one cohesive segment.

  ## Parameters

  - `segments` - List of segments to blend (must be same type)
  - `opts` - Options:
    - `:strategy` - :concatenate | :merge | :deduplicate (default: :merge)
    - `:separator` - String to join segments (default: auto-detect)
    - `:deduplicate` - Remove duplicate content (default: true)

  ## Returns

  - `{:ok, PromptSegment.t()}` - Blended segment
  - `{:error, reason}` - If blending fails

  ## Examples

      {:ok, blended} = Blender.blend_segments([seg1, seg2], strategy: :merge)
  """
  @spec blend_segments(list(PromptSegment.t()), keyword()) ::
          {:ok, PromptSegment.t()} | {:error, term()}
  def blend_segments(segments, opts \\ [])

  def blend_segments([], _opts), do: {:error, :no_segments}

  def blend_segments([single], _opts), do: {:ok, single}

  def blend_segments(segments, opts) when is_list(segments) do
    # Verify all segments are same type
    types = Enum.map(segments, & &1.type) |> Enum.uniq()

    if length(types) > 1 do
      {:error, :mixed_segment_types}
    else
      segment_type = hd(types)
      strategy = Keyword.get(opts, :strategy, :merge)
      deduplicate = Keyword.get(opts, :deduplicate, true)

      blended_content = apply_blending_strategy(segments, segment_type, strategy, deduplicate)

      blended_segment = %PromptSegment{
        id: Uniq.UUID.uuid4(),
        type: segment_type,
        content: blended_content,
        start_pos: 0,
        end_pos: String.length(blended_content),
        parent_prompt_id: "blended",
        priority: aggregate_priority(segments),
        metadata: %{
          blended_from: Enum.map(segments, & &1.id),
          blending_strategy: strategy
        }
      }

      {:ok, blended_segment}
    end
  end

  def blend_segments(_segments, _opts), do: {:error, :invalid_segments}

  @doc """
  Blends two segmented prompts by merging overlapping segment types.

  For each segment type that appears in both parents, blend the segments
  together. For types that appear in only one parent, keep them as-is.

  ## Parameters

  - `parent_a` - First segmented prompt
  - `parent_b` - Second segmented prompt
  - `opts` - Blending options

  ## Returns

  - `{:ok, blended_prompt}` - Single blended prompt text
  - `{:error, reason}` - If blending fails
  """
  @spec blend_prompts(map(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def blend_prompts(parent_a, parent_b, opts \\ [])

  def blend_prompts(
        %{segments: segs_a, structure_type: structure_a},
        %{segments: segs_b, structure_type: _structure_b},
        opts
      ) do
    # Group segments by type
    by_type_a = Enum.group_by(segs_a, & &1.type)
    by_type_b = Enum.group_by(segs_b, & &1.type)

    # Get all unique types
    all_types = (Map.keys(by_type_a) ++ Map.keys(by_type_b)) |> Enum.uniq()

    # Blend or select segments for each type
    blended_segments =
      Enum.flat_map(all_types, fn type ->
        segs_from_a = Map.get(by_type_a, type, [])
        segs_from_b = Map.get(by_type_b, type, [])

        case {segs_from_a, segs_from_b} do
          {[], []} ->
            []

          {segs, []} ->
            segs

          {[], segs} ->
            segs

          {segs_a, segs_b} ->
            # Blend segments from both parents
            case blend_segments(segs_a ++ segs_b, opts) do
              {:ok, blended} -> [blended]
              {:error, _} -> segs_a ++ segs_b
            end
        end
      end)

    # Reconstruct prompt from blended segments
    prompt = reconstruct_blended_prompt(blended_segments, structure_a)
    {:ok, prompt}
  end

  def blend_prompts(_parent_a, _parent_b, _opts) do
    {:error, :invalid_prompts}
  end

  # Private functions

  defp apply_blending_strategy(segments, type, strategy, deduplicate) do
    contents = Enum.map(segments, & &1.content)

    blended =
      case {type, strategy} do
        {_, :concatenate} ->
          concatenate_contents(contents)

        {:instruction, :merge} ->
          merge_instructions(contents)

        {:constraint, :merge} ->
          merge_constraints(contents)

        {:example, :merge} ->
          merge_examples(contents)

        {:formatting, :merge} ->
          # Take first formatting instruction (they often conflict)
          hd(contents)

        {:task_description, :merge} ->
          # Combine task descriptions
          merge_task_descriptions(contents)

        {:reasoning_guide, :merge} ->
          merge_instructions(contents)

        {:output_format, :merge} ->
          # Take first output format (they often conflict)
          hd(contents)

        {:context, :merge} ->
          concatenate_contents(contents)

        _ ->
          concatenate_contents(contents)
      end

    if deduplicate do
      deduplicate_content(blended)
    else
      blended
    end
  end

  defp concatenate_contents(contents) do
    contents
    |> Enum.reject(&(&1 == "" or is_nil(&1)))
    |> Enum.join(". ")
    |> String.trim()
  end

  defp merge_instructions(contents) do
    # Combine instructions into step-by-step or bullet list
    instructions =
      contents
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    cond do
      length(instructions) == 1 ->
        hd(instructions)

      length(instructions) <= 3 ->
        # Join with commas and "and"
        join_with_and(instructions)

      true ->
        # Use bullet list for many instructions
        "Instructions:\n" <> Enum.map_join(instructions, "\n", &"- #{&1}")
    end
  end

  defp merge_constraints(contents) do
    # Combine constraints with "and"
    constraints =
      contents
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    case length(constraints) do
      0 -> ""
      1 -> hd(constraints)
      _ -> Enum.join(constraints, " and ")
    end
  end

  defp merge_examples(contents) do
    # Combine examples into a list
    examples =
      contents
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    case length(examples) do
      0 -> ""
      1 -> hd(examples)
      _ -> "Examples:\n" <> Enum.map_join(examples, "\n", &"- #{&1}")
    end
  end

  defp merge_task_descriptions(contents) do
    # Combine task descriptions intelligently
    tasks =
      contents
      |> Enum.reject(&(&1 == "" or is_nil(&1)))
      |> Enum.map(&String.trim/1)
      |> Enum.uniq()

    case length(tasks) do
      0 -> ""
      1 -> hd(tasks)
      2 -> "#{hd(tasks)}. #{Enum.at(tasks, 1)}"
      _ -> Enum.join(tasks, ". ")
    end
  end

  defp join_with_and(items) when length(items) <= 1 do
    hd(items)
  end

  defp join_with_and(items) when length(items) == 2 do
    "#{hd(items)} and #{Enum.at(items, 1)}"
  end

  defp join_with_and(items) do
    {init, last} = Enum.split(items, -1)
    Enum.join(init, ", ") <> ", and " <> hd(last)
  end

  defp deduplicate_content(text) do
    # Remove duplicate sentences
    text
    |> String.split(~r/[.!?]\s+/, trim: true)
    |> Enum.uniq()
    |> Enum.join(". ")
    |> then(&(&1 <> "."))
    |> String.replace("..", ".")
  end

  defp aggregate_priority(segments) do
    priorities = Enum.map(segments, & &1.priority)

    cond do
      :high in priorities -> :high
      :medium in priorities -> :medium
      true -> :low
    end
  end

  defp reconstruct_blended_prompt(segments, structure_type) do
    # Sort segments by type in logical order
    type_order = [
      :task_description,
      :instruction,
      :reasoning_guide,
      :constraint,
      :example,
      :output_format,
      :formatting,
      :context
    ]

    sorted =
      Enum.sort_by(segments, fn seg ->
        Enum.find_index(type_order, &(&1 == seg.type)) || 999
      end)

    # Join with appropriate spacing
    separator =
      case structure_type do
        :simple -> " "
        :structured -> "\n\n"
        :complex -> "\n\n"
      end

    sorted
    |> Enum.map(& &1.content)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(separator)
    |> String.trim()
  end
end
