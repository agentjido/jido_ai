defmodule JidoAI.Runner.GEPA.Crossover.SegmenterTest do
  use ExUnit.Case, async: true

  alias JidoAI.Runner.GEPA.Crossover.{SegmentedPrompt, Segmenter}

  describe "segment/2" do
    test "segments a simple prompt" do
      prompt = "Solve this problem step by step."

      assert {:ok, %SegmentedPrompt{} = segmented} = Segmenter.segment(prompt)
      assert segmented.raw_text == prompt
      assert is_list(segmented.segments)
      assert length(segmented.segments) > 0
    end

    test "segments a structured prompt with multiple sections" do
      prompt = """
      Task: Solve the math problem.

      Instructions: Show your work step by step.

      Constraints: Use only basic arithmetic. Do not use calculators.

      Example: 2 + 2 = 4
      """

      assert {:ok, %SegmentedPrompt{} = segmented} = Segmenter.segment(prompt)
      assert length(segmented.segments) >= 4
      assert segmented.structure_type in [:structured, :complex]

      # Check that different segment types are identified
      types = Enum.map(segmented.segments, & &1.type) |> Enum.uniq()
      assert :task_description in types or :context in types
      assert :instruction in types or :context in types
    end

    test "returns error for empty prompt" do
      assert {:error, :invalid_prompt} = Segmenter.segment("")
    end

    test "respects min_segment_length option" do
      prompt = "A. B. C."

      assert {:ok, segmented} = Segmenter.segment(prompt, min_segment_length: 5)
      # Short segments should be filtered out
      assert Enum.all?(segmented.segments, fn seg ->
               String.length(seg.content) >= 5
             end)
    end

    test "segments have correct position information" do
      prompt = "First segment. Second segment."

      assert {:ok, segmented} = Segmenter.segment(prompt)

      # Check positions are valid
      assert Enum.all?(segmented.segments, fn seg ->
               seg.start_pos >= 0 and
                 seg.end_pos <= String.length(prompt) and
                 seg.start_pos < seg.end_pos
             end)
    end

    test "identifies different segment types" do
      prompt = """
      Task: Calculate the total.
      You must show your work.
      For example: 2 + 3 = 5
      Format your answer as JSON.
      """

      assert {:ok, segmented} = Segmenter.segment(prompt)

      types = Enum.map(segmented.segments, & &1.type)

      # Should identify various types
      assert Enum.any?(types, &(&1 in [:task_description, :context]))
      assert Enum.any?(types, &(&1 in [:constraint, :instruction]))
    end
  end

  describe "segments_of_type/2" do
    test "filters segments by type" do
      prompt = "You must solve this. You should show work. Context here."

      assert {:ok, segmented} = Segmenter.segment(prompt)
      constraints = Segmenter.segments_of_type(segmented, :constraint)

      assert is_list(constraints)
      assert Enum.all?(constraints, &(&1.type == :constraint))
    end

    test "returns empty list if type not found" do
      prompt = "Simple prompt."

      assert {:ok, segmented} = Segmenter.segment(prompt)
      examples = Segmenter.segments_of_type(segmented, :example)

      assert examples == []
    end
  end

  describe "validate_segments/1" do
    test "validates correct segments" do
      prompt = "Test prompt"

      assert {:ok, segmented} = Segmenter.segment(prompt)
      assert :ok = Segmenter.validate_segments(segmented)
    end

    test "detects empty segments" do
      segmented = %SegmentedPrompt{
        prompt_id: "test",
        raw_text: "test",
        segments: [],
        structure_type: :simple
      }

      assert {:error, :no_segments} = Segmenter.validate_segments(segmented)
    end
  end
end
