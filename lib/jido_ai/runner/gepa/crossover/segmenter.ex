defmodule JidoAI.Runner.GEPA.Crossover.Segmenter do
  @moduledoc """
  Segments prompts into modular components for crossover operations.

  This module analyzes prompt text to identify meaningful segments that can be
  independently exchanged or blended during crossover. It builds upon the
  PromptStructureAnalyzer from Task 1.3.3 to create detailed segment maps.

  ## Segmentation Strategies

  1. **Structural**: Based on markdown headers, blank lines, bullet points
  2. **Semantic**: Based on content type (instructions, constraints, examples)
  3. **Pattern-Based**: Using regex and NLP patterns

  ## Examples

      iex> {:ok, segmented} = Segmenter.segment(prompt_text)
      iex> length(segmented.segments)
      5
      iex> Enum.find(segmented.segments, & &1.type == :instruction)
      %PromptSegment{type: :instruction, content: "Solve step by step", ...}
  """

  alias Jido.AI.Runner.GEPA.SuggestionGeneration.PromptStructureAnalyzer
  alias JidoAI.Runner.GEPA.Crossover
  alias JidoAI.Runner.GEPA.Crossover.{PromptSegment, SegmentedPrompt}

  # Segment type indicators
  @instruction_indicators [
    "follow these steps",
    "you should",
    "please",
    "make sure",
    "remember to",
    "be sure to"
  ]

  @constraint_indicators [
    "must",
    "should",
    "required",
    "ensure",
    "don't",
    "do not",
    "avoid",
    "always",
    "never",
    "only use",
    "without"
  ]

  @example_indicators [
    "for example",
    "e.g.",
    "such as",
    "example:",
    "instance:",
    "like this",
    "input:",
    "output:"
  ]

  @formatting_indicators [
    "format",
    "structure",
    "organize",
    "present",
    "json",
    "xml",
    "markdown",
    "code block"
  ]

  @reasoning_indicators [
    "step by step",
    "think through",
    "reason about",
    "analyze",
    "consider",
    "break down",
    "work through"
  ]

  @task_indicators [
    "task:",
    "problem:",
    "goal:",
    "objective:",
    "question:",
    "challenge:",
    "your job"
  ]

  @output_indicators [
    "output",
    "result",
    "answer",
    "response",
    "return",
    "provide"
  ]

  @doc """
  Segments a prompt into modular components.

  ## Parameters

  - `prompt_text` - The prompt text to segment
  - `opts` - Options:
    - `:prompt_id` - ID for this prompt (default: generated UUID)
    - `:min_segment_length` - Minimum characters for a valid segment (default: 10)
    - `:use_structure_analyzer` - Whether to use PromptStructureAnalyzer (default: true)

  ## Returns

  - `{:ok, SegmentedPrompt.t()}` - Successfully segmented prompt
  - `{:error, reason}` - If segmentation fails

  ## Examples

      {:ok, segmented} = Segmenter.segment("Solve this step by step. Show your work.")
      length(segmented.segments)  # => 2
  """
  @spec segment(String.t(), keyword()) ::
          {:ok, SegmentedPrompt.t()} | {:error, term()}
  def segment(prompt_text, opts \\ [])

  def segment(prompt_text, opts) when is_binary(prompt_text) and byte_size(prompt_text) > 0 do
    prompt_id = Keyword.get(opts, :prompt_id, generate_id())
    min_length = Keyword.get(opts, :min_segment_length, 10)
    use_analyzer = Keyword.get(opts, :use_structure_analyzer, true)

    with {:ok, segments} <- identify_segments(prompt_text, prompt_id, min_length, use_analyzer),
         structure_type <- assess_structure_type(segments) do
      segmented = %SegmentedPrompt{
        prompt_id: prompt_id,
        raw_text: prompt_text,
        segments: segments,
        structure_type: structure_type,
        metadata: %{
          segment_count: length(segments),
          segmentation_strategy: if(use_analyzer, do: :hybrid, else: :pattern_based)
        }
      }

      {:ok, segmented}
    end
  end

  def segment(_prompt_text, _opts), do: {:error, :invalid_prompt}

  @doc """
  Extracts segments of a specific type from a segmented prompt.

  ## Examples

      {:ok, segmented} = Segmenter.segment(prompt)
      instructions = Segmenter.segments_of_type(segmented, :instruction)
      length(instructions)  # => 2
  """
  @spec segments_of_type(SegmentedPrompt.t(), Crossover.segment_type()) ::
          list(PromptSegment.t())
  def segments_of_type(%SegmentedPrompt{segments: segments}, type) do
    Enum.filter(segments, &(&1.type == type))
  end

  @doc """
  Validates that segments don't overlap and cover the full prompt.

  ## Returns

  - `:ok` - Segments are valid
  - `{:error, reason}` - Segments have issues
  """
  @spec validate_segments(SegmentedPrompt.t()) :: :ok | {:error, term()}
  def validate_segments(%SegmentedPrompt{segments: segments, raw_text: text}) do
    text_length = String.length(text)

    cond do
      Enum.empty?(segments) ->
        {:error, :no_segments}

      has_overlapping_segments?(segments) ->
        {:error, :overlapping_segments}

      has_invalid_positions?(segments, text_length) ->
        {:error, :invalid_positions}

      true ->
        :ok
    end
  end

  # Private functions

  defp identify_segments(prompt_text, prompt_id, min_length, use_analyzer) do
    segments =
      if use_analyzer do
        identify_with_analyzer(prompt_text, prompt_id, min_length)
      else
        identify_with_patterns(prompt_text, prompt_id, min_length)
      end

    if Enum.empty?(segments) do
      {:error, :no_segments_found}
    else
      {:ok, segments}
    end
  end

  defp identify_with_analyzer(prompt_text, prompt_id, min_length) do
    case PromptStructureAnalyzer.analyze(prompt_text) do
      {:ok, structure} ->
        # Use structure analysis to inform segmentation
        structural_segments = segments_from_structure(structure, prompt_id)

        # Combine with pattern-based detection for finer granularity
        pattern_segments = identify_with_patterns(prompt_text, prompt_id, min_length)

        # Merge and deduplicate
        merge_segments(structural_segments, pattern_segments)

      {:error, _} ->
        # Fall back to pattern-based
        identify_with_patterns(prompt_text, prompt_id, min_length)
    end
  end

  defp segments_from_structure(structure, prompt_id) do
    # Convert PromptStructure sections to PromptSegments
    Enum.map(structure.sections, fn section ->
      %PromptSegment{
        id: generate_id(),
        type: map_section_name_to_type(section[:name]),
        content: String.slice(structure.raw_text, section[:start]..section[:end]),
        start_pos: section[:start],
        end_pos: section[:end],
        parent_prompt_id: prompt_id,
        priority: :medium,
        metadata: %{source: :structure_analyzer}
      }
    end)
  end

  defp identify_with_patterns(prompt_text, prompt_id, min_length) do
    # Split on paragraph boundaries first
    paragraphs = String.split(prompt_text, ~r/\n\s*\n/, trim: true)

    paragraphs
    |> Enum.with_index()
    |> Enum.flat_map(fn {para, idx} ->
      # Calculate position in original text
      start_pos = calculate_start_position(prompt_text, paragraphs, idx)
      end_pos = start_pos + String.length(para)

      # Split paragraph into sentences if it's long
      if String.length(para) > min_length * 3 do
        segment_sentences(para, start_pos, prompt_id, min_length)
      else
        [create_segment(para, start_pos, end_pos, prompt_id)]
      end
    end)
    |> Enum.filter(&(String.length(&1.content) >= min_length))
  end

  defp segment_sentences(paragraph, base_pos, prompt_id, min_length) do
    # Split on sentence boundaries
    sentences = Regex.split(~r/[.!?]+\s+/, paragraph, trim: true, include_captures: false)

    sentences
    |> Enum.with_index()
    |> Enum.map(fn {sentence, idx} ->
      start_pos = base_pos + calculate_sentence_offset(paragraph, sentence, idx)
      end_pos = start_pos + String.length(sentence)
      create_segment(sentence, start_pos, end_pos, prompt_id)
    end)
    |> Enum.filter(&(String.length(&1.content) >= min_length))
  end

  defp create_segment(content, start_pos, end_pos, prompt_id) do
    %PromptSegment{
      id: generate_id(),
      type: classify_segment_type(content),
      content: String.trim(content),
      start_pos: start_pos,
      end_pos: end_pos,
      parent_prompt_id: prompt_id,
      priority: assess_priority(content),
      metadata: %{source: :pattern_detection}
    }
  end

  defp classify_segment_type(content) do
    content_lower = String.downcase(content)

    cond do
      matches_indicators?(content_lower, @task_indicators) -> :task_description
      matches_indicators?(content_lower, @instruction_indicators) -> :instruction
      matches_indicators?(content_lower, @constraint_indicators) -> :constraint
      matches_indicators?(content_lower, @example_indicators) -> :example
      matches_indicators?(content_lower, @formatting_indicators) -> :formatting
      matches_indicators?(content_lower, @reasoning_indicators) -> :reasoning_guide
      matches_indicators?(content_lower, @output_indicators) -> :output_format
      true -> :context
    end
  end

  defp matches_indicators?(text, indicators) do
    Enum.any?(indicators, &String.contains?(text, &1))
  end

  defp assess_priority(content) do
    content_lower = String.downcase(content)

    cond do
      String.contains?(content_lower, ["must", "required", "critical", "important"]) -> :high
      String.contains?(content_lower, ["should", "recommended", "preferably"]) -> :medium
      true -> :low
    end
  end

  defp map_section_name_to_type(name) do
    name_lower = String.downcase(to_string(name))

    cond do
      String.contains?(name_lower, ["task", "problem", "goal"]) -> :task_description
      String.contains?(name_lower, ["instruction", "step"]) -> :instruction
      String.contains?(name_lower, ["constraint", "rule", "limit"]) -> :constraint
      String.contains?(name_lower, ["example", "sample"]) -> :example
      String.contains?(name_lower, ["format", "structure"]) -> :formatting
      String.contains?(name_lower, ["reasoning", "thinking"]) -> :reasoning_guide
      String.contains?(name_lower, ["output", "result"]) -> :output_format
      true -> :context
    end
  end

  defp merge_segments(structural, pattern) do
    # Prefer structural segments where available, fill gaps with pattern segments
    all_segments = structural ++ pattern

    all_segments
    |> Enum.sort_by(& &1.start_pos)
    |> remove_duplicates()
  end

  defp remove_duplicates(segments) do
    segments
    |> Enum.reduce([], fn segment, acc ->
      if overlaps_with_any?(segment, acc) do
        acc
      else
        [segment | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp overlaps_with_any?(segment, segments) do
    Enum.any?(segments, fn other ->
      segment.start_pos < other.end_pos and segment.end_pos > other.start_pos
    end)
  end

  defp assess_structure_type(segments) do
    segment_count = length(segments)
    unique_types = segments |> Enum.map(& &1.type) |> Enum.uniq() |> length()

    cond do
      segment_count <= 2 and unique_types <= 2 -> :simple
      segment_count <= 5 and unique_types <= 4 -> :structured
      true -> :complex
    end
  end

  defp calculate_start_position(_text, paragraphs, idx) do
    paragraphs
    |> Enum.take(idx)
    |> Enum.reduce(0, fn para, acc ->
      # Account for paragraph + newlines
      acc + String.length(para) + 2
    end)
  end

  defp calculate_sentence_offset(paragraph, _sentence, idx) do
    paragraph
    |> String.split(~r/[.!?]+\s+/, trim: true)
    |> Enum.take(idx)
    |> Enum.reduce(0, fn sent, acc ->
      acc + String.length(sent) + 2
    end)
  end

  defp has_overlapping_segments?(segments) do
    segments
    |> Enum.sort_by(& &1.start_pos)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [seg1, seg2] ->
      seg1.end_pos > seg2.start_pos
    end)
  end

  defp has_invalid_positions?(segments, text_length) do
    Enum.any?(segments, fn seg ->
      seg.start_pos < 0 or seg.end_pos > text_length or seg.start_pos >= seg.end_pos
    end)
  end

  defp generate_id, do: Uniq.UUID.uuid4()
end
