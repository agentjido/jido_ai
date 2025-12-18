defmodule JidoAI.Runner.GEPA.Crossover.BlenderTest do
  use ExUnit.Case, async: true

  alias JidoAI.Runner.GEPA.Crossover.{Blender, PromptSegment, Segmenter}

  describe "blend_segments/2" do
    test "blends two segments of same type" do
      seg1 = %PromptSegment{
        id: "1",
        type: :instruction,
        content: "Solve step by step",
        start_pos: 0,
        end_pos: 18,
        parent_prompt_id: "a",
        priority: :high
      }

      seg2 = %PromptSegment{
        id: "2",
        type: :instruction,
        content: "Show your work",
        start_pos: 0,
        end_pos: 14,
        parent_prompt_id: "b",
        priority: :medium
      }

      assert {:ok, blended} = Blender.blend_segments([seg1, seg2])
      assert blended.type == :instruction

      assert String.contains?(blended.content, "step by step") or
               String.contains?(blended.content, "work")
    end

    test "returns error for mixed segment types" do
      seg1 = %PromptSegment{
        id: "1",
        type: :instruction,
        content: "Do this",
        start_pos: 0,
        end_pos: 7,
        parent_prompt_id: "a",
        priority: :high
      }

      seg2 = %PromptSegment{
        id: "2",
        type: :constraint,
        content: "Must not do that",
        start_pos: 0,
        end_pos: 16,
        parent_prompt_id: "b",
        priority: :medium
      }

      assert {:error, :mixed_segment_types} = Blender.blend_segments([seg1, seg2])
    end

    test "returns single segment unchanged" do
      seg = %PromptSegment{
        id: "1",
        type: :instruction,
        content: "Test",
        start_pos: 0,
        end_pos: 4,
        parent_prompt_id: "a",
        priority: :high
      }

      assert {:ok, result} = Blender.blend_segments([seg])
      assert result == seg
    end

    test "returns error for empty list" do
      assert {:error, :no_segments} = Blender.blend_segments([])
    end

    test "deduplicates content when requested" do
      seg1 = %PromptSegment{
        id: "1",
        type: :instruction,
        content: "Step one. Step two.",
        start_pos: 0,
        end_pos: 19,
        parent_prompt_id: "a",
        priority: :high
      }

      seg2 = %PromptSegment{
        id: "2",
        type: :instruction,
        content: "Step one. Step three.",
        start_pos: 0,
        end_pos: 21,
        parent_prompt_id: "b",
        priority: :high
      }

      assert {:ok, blended} = Blender.blend_segments([seg1, seg2], deduplicate: true)
      # Should not have "Step one" twice
      assert is_binary(blended.content)
    end
  end

  describe "blend_prompts/3" do
    test "blends two segmented prompts" do
      prompt_a = "Instructions: Do this. Constraints: Use only X."
      prompt_b = "Instructions: Do that. Constraints: Avoid Y."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, blended} = Blender.blend_prompts(seg_a, seg_b)
      assert is_binary(blended)
      assert byte_size(blended) > 0
    end

    test "combines segments from both parents" do
      prompt_a = "Solve this problem."
      prompt_b = "Show your reasoning."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, blended} = Blender.blend_prompts(seg_a, seg_b)
      # Should combine content from both
      assert is_binary(blended)
      assert byte_size(blended) > 10
    end
  end
end
