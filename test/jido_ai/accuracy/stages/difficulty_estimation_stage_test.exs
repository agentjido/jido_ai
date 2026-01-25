defmodule Jido.AI.Accuracy.Stages.DifficultyEstimationStageTest do
  @moduledoc """
  Tests for DifficultyEstimationStage.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.DifficultyEstimate
  alias Jido.AI.Accuracy.Estimators.HeuristicDifficulty
  alias Jido.AI.Accuracy.Stages.DifficultyEstimationStage

  describe "name/0" do
    test "returns stage name" do
      assert DifficultyEstimationStage.name() == :difficulty_estimation
    end
  end

  describe "required?/0" do
    test "returns false (optional stage)" do
      refute DifficultyEstimationStage.required?()
    end
  end

  describe "new/1" do
    test "creates stage configuration" do
      stage = DifficultyEstimationStage.new(%{estimator: HeuristicDifficulty})

      assert stage.estimator == HeuristicDifficulty
      assert stage.timeout == 5000
    end

    test "creates stage with custom timeout" do
      stage = DifficultyEstimationStage.new(%{timeout: 10_000})
      assert stage.timeout == 10_000
    end
  end

  describe "execute/2" do
    test "estimates difficulty for valid query" do
      input = %{query: "What is 2+2?", context: %{}}
      config = %{estimator: HeuristicDifficulty}

      assert {:ok, state, metadata} = DifficultyEstimationStage.execute(input, config)
      assert Map.has_key?(state, :difficulty)
      assert Map.has_key?(state, :difficulty_level)
      assert state.difficulty_level in [:easy, :medium, :hard]
      assert metadata.difficulty_level in [:easy, :medium, :hard]
    end

    test "returns error for empty query" do
      input = %{query: ""}
      config = %{estimator: HeuristicDifficulty}

      assert {:error, :invalid_query} = DifficultyEstimationStage.execute(input, config)
    end

    test "returns error for nil query" do
      input = %{query: nil}
      config = %{estimator: HeuristicDifficulty}

      assert {:error, :invalid_query} = DifficultyEstimationStage.execute(input, config)
    end

    test "uses default estimator when none provided" do
      input = %{query: "test query", context: %{}}
      config = %{}

      assert {:ok, state, _metadata} = DifficultyEstimationStage.execute(input, config)
      assert Map.has_key?(state, :difficulty_level)
    end

    test "reuses existing difficulty if present" do
      difficulty =
        DifficultyEstimate.new!(%{
          level: :hard,
          score: 0.8,
          confidence: 0.9
        })

      input = %{query: "test", difficulty: difficulty}
      config = %{}

      assert {:ok, state, metadata} = DifficultyEstimationStage.execute(input, config)
      assert state.difficulty == difficulty
      assert metadata.from_cache == true
    end
  end
end
