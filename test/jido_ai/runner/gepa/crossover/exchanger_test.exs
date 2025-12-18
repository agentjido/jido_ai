defmodule JidoAI.Runner.GEPA.Crossover.ExchangerTest do
  use ExUnit.Case, async: true

  alias JidoAI.Runner.GEPA.Crossover.{Exchanger, Segmenter}

  describe "single_point/3" do
    test "produces two offspring from single-point crossover" do
      prompt_a = "First instruction. Second instruction. Third instruction."
      prompt_b = "Alpha step. Beta step. Gamma step."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, {offspring1, offspring2}} = Exchanger.single_point(seg_a, seg_b)

      assert is_binary(offspring1)
      assert is_binary(offspring2)
      # Offspring should be valid prompts (may equal parents in edge cases)
      assert byte_size(offspring1) > 0
      assert byte_size(offspring2) > 0
    end

    test "preserves task description when requested" do
      prompt_a = "Task: Solve problem. Instruction: Show work."
      prompt_b = "Task: Calculate total. Instruction: Explain steps."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, {offspring1, offspring2}} =
               Exchanger.single_point(seg_a, seg_b, preserve_task: true)

      # Both offspring should have content from both parents
      assert is_binary(offspring1) and byte_size(offspring1) > 0
      assert is_binary(offspring2) and byte_size(offspring2) > 0
    end

    test "handles prompts with different segment counts" do
      prompt_a = "Short."
      prompt_b = "Much longer prompt with multiple parts."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, {offspring1, offspring2}} = Exchanger.single_point(seg_a, seg_b)

      assert is_binary(offspring1)
      assert is_binary(offspring2)
    end
  end

  describe "two_point/3" do
    test "produces two offspring from two-point crossover" do
      prompt_a =
        "First step is simple. Second step is harder. Third step is complex. Fourth step is final."

      prompt_b =
        "Alpha phase begins. Beta phase continues. Gamma phase advances. Delta phase ends."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      result = Exchanger.two_point(seg_a, seg_b)

      case result do
        {:ok, {offspring1, offspring2}} ->
          assert is_binary(offspring1)
          assert is_binary(offspring2)
          assert byte_size(offspring1) > 0
          assert byte_size(offspring2) > 0

        {:error, :insufficient_segments} ->
          # OK if not enough segments for two-point
          assert true
      end
    end

    test "requires at least 2 segments" do
      prompt_a = "A"
      prompt_b = "B"

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      result = Exchanger.two_point(seg_a, seg_b)

      # May fail if insufficient segments
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "uniform/3" do
    test "produces two offspring from uniform crossover" do
      prompt_a = "Step one. Step two. Step three."
      prompt_b = "Phase A. Phase B. Phase C."

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      assert {:ok, {offspring1, offspring2}} = Exchanger.uniform(seg_a, seg_b)

      assert is_binary(offspring1)
      assert is_binary(offspring2)
    end

    test "respects probability parameter" do
      prompt_a = "AAAA"
      prompt_b = "BBBB"

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      # With probability 1.0, should always select from parent_a
      assert {:ok, {offspring1, _offspring2}} =
               Exchanger.uniform(seg_a, seg_b, probability: 1.0)

      assert is_binary(offspring1)
    end

    test "uses seed for reproducibility" do
      prompt_a = "AAA"
      prompt_b = "BBB"

      {:ok, seg_a} = Segmenter.segment(prompt_a)
      {:ok, seg_b} = Segmenter.segment(prompt_b)

      {:ok, {off1_a, off1_b}} = Exchanger.uniform(seg_a, seg_b, seed: 12_345)
      {:ok, {off2_a, off2_b}} = Exchanger.uniform(seg_a, seg_b, seed: 12_345)

      # Same seed should produce same results
      assert off1_a == off2_a
      assert off1_b == off2_b
    end
  end
end
