defmodule Jido.AI.Accuracy.DifficultyEstimateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.DifficultyEstimate

  @moduletag :capture_log

  describe "new/1" do
    test "creates estimate with valid attributes" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})
      assert estimate.level == :easy
      assert estimate.score == 0.2
    end

    test "creates estimate with all attributes" do
      assert {:ok, estimate} =
               DifficultyEstimate.new(%{
                 level: :hard,
                 score: 0.8,
                 confidence: 0.9,
                 reasoning: "Complex query",
                 features: %{length: 100},
                 metadata: %{key: "value"}
               })

      assert estimate.level == :hard
      assert estimate.score == 0.8
      assert estimate.confidence == 0.9
      assert estimate.reasoning == "Complex query"
      assert estimate.features == %{length: 100}
      assert estimate.metadata == %{key: "value"}
    end

    test "derives level from score when level not provided" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{score: 0.2})
      assert estimate.level == :easy

      assert {:ok, estimate} = DifficultyEstimate.new(%{score: 0.5})
      assert estimate.level == :medium

      assert {:ok, estimate} = DifficultyEstimate.new(%{score: 0.8})
      assert estimate.level == :hard
    end

    test "returns error for invalid level" do
      assert {:error, :invalid_level} = DifficultyEstimate.new(%{level: :invalid})
      assert {:error, :invalid_level} = DifficultyEstimate.new(%{level: "easy"})
    end

    test "returns error for invalid score" do
      assert {:error, :invalid_score} = DifficultyEstimate.new(%{score: 1.5})
      assert {:error, :invalid_score} = DifficultyEstimate.new(%{score: -0.1})
      assert {:error, :invalid_score} = DifficultyEstimate.new(%{score: "invalid"})
    end

    test "returns error for invalid confidence" do
      assert {:error, :invalid_confidence} = DifficultyEstimate.new(%{confidence: 1.5})
      assert {:error, :invalid_confidence} = DifficultyEstimate.new(%{confidence: -0.1})
    end

    test "accepts nil for optional fields" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{level: :easy})
      assert is_nil(estimate.score)
      assert is_nil(estimate.confidence)
      assert is_nil(estimate.reasoning)
    end

    test "allows 0 and 1 boundary values for score" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{score: 0.0, level: :easy})
      assert estimate.score == 0.0

      assert {:ok, estimate} = DifficultyEstimate.new(%{score: 1.0, level: :hard})
      assert estimate.score == 1.0
    end

    test "allows 0 and 1 boundary values for confidence" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{confidence: 0.0})
      assert estimate.confidence == 0.0

      assert {:ok, estimate} = DifficultyEstimate.new(%{confidence: 1.0})
      assert estimate.confidence == 1.0
    end
  end

  describe "new!/1" do
    test "creates estimate with valid attributes" do
      estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      assert estimate.level == :easy
      assert estimate.score == 0.2
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        DifficultyEstimate.new!(%{level: :invalid})
      end
    end
  end

  describe "easy?/1" do
    test "returns true for easy level" do
      estimate = DifficultyEstimate.new!(%{level: :easy})
      assert DifficultyEstimate.easy?(estimate)
    end

    test "returns false for other levels" do
      refute DifficultyEstimate.easy?(DifficultyEstimate.new!(%{level: :medium}))
      refute DifficultyEstimate.easy?(DifficultyEstimate.new!(%{level: :hard}))
    end
  end

  describe "medium?/1" do
    test "returns true for medium level" do
      estimate = DifficultyEstimate.new!(%{level: :medium})
      assert DifficultyEstimate.medium?(estimate)
    end

    test "returns false for other levels" do
      refute DifficultyEstimate.medium?(DifficultyEstimate.new!(%{level: :easy}))
      refute DifficultyEstimate.medium?(DifficultyEstimate.new!(%{level: :hard}))
    end
  end

  describe "hard?/1" do
    test "returns true for hard level" do
      estimate = DifficultyEstimate.new!(%{level: :hard})
      assert DifficultyEstimate.hard?(estimate)
    end

    test "returns false for other levels" do
      refute DifficultyEstimate.hard?(DifficultyEstimate.new!(%{level: :easy}))
      refute DifficultyEstimate.hard?(DifficultyEstimate.new!(%{level: :medium}))
    end
  end

  describe "level/1" do
    test "returns the difficulty level" do
      estimate = DifficultyEstimate.new!(%{level: :easy})
      assert DifficultyEstimate.level(estimate) == :easy
    end
  end

  describe "to_level/1" do
    test "converts score to easy for low values" do
      assert DifficultyEstimate.to_level(0.0) == :easy
      assert DifficultyEstimate.to_level(0.1) == :easy
      assert DifficultyEstimate.to_level(0.34) == :easy
    end

    test "converts score to medium for middle values" do
      assert DifficultyEstimate.to_level(0.35) == :medium
      assert DifficultyEstimate.to_level(0.5) == :medium
      assert DifficultyEstimate.to_level(0.65) == :medium
    end

    test "converts score to hard for high values" do
      assert DifficultyEstimate.to_level(0.66) == :hard
      assert DifficultyEstimate.to_level(0.8) == :hard
      assert DifficultyEstimate.to_level(1.0) == :hard
    end

    test "handles boundary values correctly" do
      # 0.35 is the threshold - values < 0.35 are easy, >= 0.35 are medium
      assert DifficultyEstimate.to_level(0.34) == :easy
      assert DifficultyEstimate.to_level(0.35) == :medium
      # 0.65 is the threshold - values <= 0.65 are medium, > 0.65 are hard
      assert DifficultyEstimate.to_level(0.65) == :medium
      assert DifficultyEstimate.to_level(0.66) == :hard
    end

    test "returns medium for non-numeric input" do
      assert DifficultyEstimate.to_level(nil) == :medium
      assert DifficultyEstimate.to_level("invalid") == :medium
    end
  end

  describe "easy_threshold/0" do
    test "returns the easy threshold" do
      assert DifficultyEstimate.easy_threshold() == 0.35
    end
  end

  describe "hard_threshold/0" do
    test "returns the hard threshold" do
      assert DifficultyEstimate.hard_threshold() == 0.65
    end
  end

  describe "to_map/1" do
    test "converts estimate to map" do
      estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2, confidence: 0.9})
      map = DifficultyEstimate.to_map(estimate)

      assert is_map(map)
      assert Map.get(map, "level") == :easy
      assert Map.get(map, "score") == 0.2
      assert Map.get(map, "confidence") == 0.9
    end

    test "excludes nil and empty values from map" do
      estimate = DifficultyEstimate.new!(%{level: :easy})
      map = DifficultyEstimate.to_map(estimate)

      # Should have level, but not nil/empty values
      assert Map.has_key?(map, "level")
      refute Map.has_key?(map, "score")
      refute Map.has_key?(map, "reasoning")
      refute Map.has_key?(map, "features")
    end

    test "converts atom keys to strings" do
      estimate = DifficultyEstimate.new!(%{level: :easy, score: 0.2})
      map = DifficultyEstimate.to_map(estimate)

      assert Enum.all?(Map.keys(map), fn
               key when is_binary(key) -> true
               _ -> false
             end)
    end
  end

  describe "from_map/1" do
    test "creates estimate from map" do
      map = %{"level" => "easy", "score" => 0.2, "confidence" => 0.9}
      assert {:ok, estimate} = DifficultyEstimate.from_map(map)
      assert estimate.level == :easy
      assert estimate.score == 0.2
      assert estimate.confidence == 0.9
    end

    test "converts string level to atom" do
      map = %{"level" => "hard"}
      assert {:ok, estimate} = DifficultyEstimate.from_map(map)
      assert estimate.level == :hard
    end

    test "returns error for invalid data" do
      map = %{"level" => "invalid", "score" => 2.0}
      assert {:error, _reason} = DifficultyEstimate.from_map(map)
    end
  end

  describe "round-trip serialization" do
    test "to_map and from_map are inverses" do
      original =
        DifficultyEstimate.new!(%{
          level: :hard,
          score: 0.8,
          confidence: 0.9,
          reasoning: "Test"
        })

      map = DifficultyEstimate.to_map(original)
      assert {:ok, restored} = DifficultyEstimate.from_map(map)

      assert restored.level == original.level
      assert restored.score == original.score
      assert restored.confidence == original.confidence
      assert restored.reasoning == original.reasoning
    end
  end
end
