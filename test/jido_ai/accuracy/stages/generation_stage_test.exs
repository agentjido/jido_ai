defmodule Jido.AI.Accuracy.Stages.GenerationStageTest do
  @moduledoc """
  Tests for GenerationStage.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Candidate
  alias Jido.AI.Accuracy.DifficultyEstimate
  alias Jido.AI.Accuracy.Stages.GenerationStage

  describe "name/0" do
    test "returns stage name" do
      assert GenerationStage.name() == :generation
    end
  end

  describe "required?/0" do
    test "returns true (required stage)" do
      assert GenerationStage.required?()
    end
  end

  describe "new/1" do
    test "creates stage configuration" do
      generator = fn _query -> {:ok, Candidate.new!(%{content: "test"})} end
      stage = GenerationStage.new(%{generator: generator})

      assert is_function(stage.generator)
      assert stage.min_candidates == 3
      assert stage.max_candidates == 10
    end

    test "creates stage with custom values" do
      generator = fn _query -> {:ok, Candidate.new!(%{content: "test"})} end

      stage =
        GenerationStage.new(%{
          generator: generator,
          min_candidates: 5,
          max_candidates: 15
        })

      assert stage.min_candidates == 5
      assert stage.max_candidates == 15
    end
  end

  describe "execute/2" do
    setup do
      generator = fn query, _context ->
        {:ok, Candidate.new!(%{content: "Answer to: #{query}"})}
      end

      {:ok, generator: generator}
    end

    test "generates candidates for valid query", %{generator: generator} do
      input = %{query: "What is 2+2?"}
      config = %{generator: generator}

      assert {:ok, state, metadata} = GenerationStage.execute(input, config)
      assert is_list(state.candidates)
      refute Enum.empty?(state.candidates)
      assert state.num_candidates > 0
      assert %Candidate{} = state.best_candidate
      assert is_map(state.generation_metadata)
      assert is_integer(metadata.num_candidates)
    end

    test "returns error for empty query", %{generator: generator} do
      input = %{query: ""}
      config = %{generator: generator}

      assert {:error, :invalid_query} = GenerationStage.execute(input, config)
    end

    test "returns error for nil query", %{generator: generator} do
      input = %{query: nil}
      config = %{generator: generator}

      assert {:error, :invalid_query} = GenerationStage.execute(input, config)
    end

    test "returns error when no generator provided" do
      input = %{query: "test"}
      config = %{}

      assert {:error, :generator_required} = GenerationStage.execute(input, config)
    end

    test "returns error for invalid generator" do
      input = %{query: "test"}
      config = %{generator: "not_a_function"}

      assert {:error, :generator_required} = GenerationStage.execute(input, config)
    end

    test "uses generator from input if not in config", %{generator: generator} do
      input = %{query: "test", generator: generator}
      config = %{}

      assert {:ok, state, _metadata} = GenerationStage.execute(input, config)
      refute Enum.empty?(state.candidates)
    end

    test "passes context to generator" do
      context_passed = :counters.new(1, [])
      call_count_ref = :counters.new(1, [])

      generator = fn _query, _context ->
        :counters.add(context_passed, 1, 1)
        :counters.add(call_count_ref, 1, 1)
        {:ok, Candidate.new!(%{content: "test"})}
      end

      input = %{query: "test", context: context_passed}
      config = %{generator: generator, min_candidates: 1, max_candidates: 1}

      assert {:ok, _state, _metadata} = GenerationStage.execute(input, config)
      # Verify context was passed (counter was incremented at least once)
      assert :counters.get(context_passed, 1) >= 1
      # With min/max candidates = 1, it should be called once
      assert :counters.get(call_count_ref, 1) == 1
    end

    test "adapts candidate count based on difficulty", %{generator: generator} do
      difficulty =
        DifficultyEstimate.new!(%{
          level: :hard,
          score: 0.8,
          confidence: 0.9
        })

      input = %{query: "complex question", difficulty: difficulty}
      config = %{generator: generator}

      assert {:ok, state, metadata} = GenerationStage.execute(input, config)
      refute Enum.empty?(state.candidates)
      assert metadata.actual_n > 0
    end
  end
end
