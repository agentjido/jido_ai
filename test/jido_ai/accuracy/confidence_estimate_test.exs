defmodule Jido.AI.Accuracy.ConfidenceEstimateTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.ConfidenceEstimate

  @moduletag :capture_log

  describe "new/1" do
    test "creates estimate with valid attributes" do
      assert {:ok, estimate} = ConfidenceEstimate.new(%{score: 0.8, method: :test})
      assert estimate.score == 0.8
      assert estimate.method == :test
      assert estimate.metadata == %{}
    end

    test "creates estimate with all fields" do
      attrs = %{
        score: 0.75,
        calibration: 0.9,
        method: :attention,
        reasoning: "High confidence",
        token_level_confidence: [0.9, 0.8, 0.7],
        metadata: %{key: "value"}
      }

      assert {:ok, estimate} = ConfidenceEstimate.new(attrs)
      assert estimate.score == 0.75
      assert estimate.calibration == 0.9
      assert estimate.method == :attention
      assert estimate.reasoning == "High confidence"
      assert estimate.token_level_confidence == [0.9, 0.8, 0.7]
      assert estimate.metadata == %{key: "value"}
    end

    test "accepts keyword list" do
      assert {:ok, estimate} = ConfidenceEstimate.new(score: 0.6, method: :test)
      assert estimate.score == 0.6
    end

    test "returns error for missing score" do
      assert {:error, :invalid_score} = ConfidenceEstimate.new(%{method: :test})
    end

    test "returns error for missing method" do
      assert {:error, :invalid_method} = ConfidenceEstimate.new(%{score: 0.5})
    end

    test "returns error for score > 1.0" do
      assert {:error, :invalid_score} = ConfidenceEstimate.new(%{score: 1.5, method: :test})
    end

    test "returns error for score < 0.0" do
      assert {:error, :invalid_score} = ConfidenceEstimate.new(%{score: -0.1, method: :test})
    end

    test "accepts score of 0.0" do
      assert {:ok, estimate} = ConfidenceEstimate.new(%{score: 0.0, method: :test})
      assert estimate.score == 0.0
    end

    test "accepts score of 1.0" do
      assert {:ok, estimate} = ConfidenceEstimate.new(%{score: 1.0, method: :test})
      assert estimate.score == 1.0
    end
  end

  describe "new!/1" do
    test "creates estimate with valid attributes" do
      estimate = ConfidenceEstimate.new!(%{score: 0.8, method: :test})
      assert estimate.score == 0.8
    end

    test "raises for invalid score" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        ConfidenceEstimate.new!(%{score: 1.5, method: :test})
      end
    end
  end

  describe "high_confidence?/1" do
    test "returns true for score >= 0.7" do
      assert ConfidenceEstimate.high_confidence?(new_estimate(0.7))
      assert ConfidenceEstimate.high_confidence?(new_estimate(0.8))
      assert ConfidenceEstimate.high_confidence?(new_estimate(1.0))
    end

    test "returns false for score < 0.7" do
      refute ConfidenceEstimate.high_confidence?(new_estimate(0.69))
      refute ConfidenceEstimate.high_confidence?(new_estimate(0.5))
      refute ConfidenceEstimate.high_confidence?(new_estimate(0.0))
    end
  end

  describe "medium_confidence?/1" do
    test "returns true for 0.4 <= score < 0.7" do
      assert ConfidenceEstimate.medium_confidence?(new_estimate(0.4))
      assert ConfidenceEstimate.medium_confidence?(new_estimate(0.5))
      assert ConfidenceEstimate.medium_confidence?(new_estimate(0.69))
    end

    test "returns false for score >= 0.7" do
      refute ConfidenceEstimate.medium_confidence?(new_estimate(0.7))
      refute ConfidenceEstimate.medium_confidence?(new_estimate(1.0))
    end

    test "returns false for score < 0.4" do
      refute ConfidenceEstimate.medium_confidence?(new_estimate(0.39))
      refute ConfidenceEstimate.medium_confidence?(new_estimate(0.0))
    end
  end

  describe "low_confidence?/1" do
    test "returns true for score < 0.4" do
      assert ConfidenceEstimate.low_confidence?(new_estimate(0.0))
      assert ConfidenceEstimate.low_confidence?(new_estimate(0.2))
      assert ConfidenceEstimate.low_confidence?(new_estimate(0.39))
    end

    test "returns false for score >= 0.4" do
      refute ConfidenceEstimate.low_confidence?(new_estimate(0.4))
      refute ConfidenceEstimate.low_confidence?(new_estimate(0.7))
      refute ConfidenceEstimate.low_confidence?(new_estimate(1.0))
    end
  end

  describe "confidence_level/1" do
    test "returns :high for score >= 0.7" do
      assert ConfidenceEstimate.confidence_level(new_estimate(0.7)) == :high
      assert ConfidenceEstimate.confidence_level(new_estimate(0.9)) == :high
      assert ConfidenceEstimate.confidence_level(new_estimate(1.0)) == :high
    end

    test "returns :medium for 0.4 <= score < 0.7" do
      assert ConfidenceEstimate.confidence_level(new_estimate(0.4)) == :medium
      assert ConfidenceEstimate.confidence_level(new_estimate(0.5)) == :medium
      assert ConfidenceEstimate.confidence_level(new_estimate(0.69)) == :medium
    end

    test "returns :low for score < 0.4" do
      assert ConfidenceEstimate.confidence_level(new_estimate(0.0)) == :low
      assert ConfidenceEstimate.confidence_level(new_estimate(0.2)) == :low
      assert ConfidenceEstimate.confidence_level(new_estimate(0.39)) == :low
    end
  end

  describe "to_map/1" do
    test "converts estimate to map" do
      estimate = ConfidenceEstimate.new!(%{
        score: 0.75,
        method: :attention,
        reasoning: "Test",
        token_level_confidence: [0.8, 0.7]
      })

      map = ConfidenceEstimate.to_map(estimate)

      assert Map.has_key?(map, "score")
      assert Map.has_key?(map, "method")
      assert Map.has_key?(map, "reasoning")
      assert Map.has_key?(map, "token_level_confidence")

      # Nil fields should not be included
      refute Map.has_key?(map, "calibration")
      refute Map.has_key?(map, "metadata")

      assert map["score"] == 0.75
    end

    test "converts estimate with nil fields" do
      estimate = ConfidenceEstimate.new!(%{score: 0.5, method: :test})
      map = ConfidenceEstimate.to_map(estimate)

      # Only non-nil fields
      assert map["score"] == 0.5
      assert map["method"] == :test
      refute Map.has_key?(map, "calibration")
    end
  end

  describe "from_map/1" do
    test "creates estimate from map" do
      map = %{"score" => 0.8, "method" => "attention"}

      assert {:ok, estimate} = ConfidenceEstimate.from_map(map)
      assert estimate.score == 0.8
      assert estimate.method == "attention"
    end

    test "creates estimate with all fields" do
      map = %{
        "score" => 0.75,
        "calibration" => 0.9,
        "method" => "ensemble",
        "reasoning" => "Test reasoning",
        "token_level_confidence" => [0.9, 0.8]
      }

      assert {:ok, estimate} = ConfidenceEstimate.from_map(map)
      assert estimate.score == 0.75
      assert estimate.calibration == 0.9
      assert estimate.reasoning == "Test reasoning"
      assert estimate.token_level_confidence == [0.9, 0.8]
    end

    test "returns error for invalid data" do
      assert {:error, :invalid_score} = ConfidenceEstimate.from_map(%{"score" => 2.0})
      assert {:error, :invalid_score} = ConfidenceEstimate.from_map(%{"method" => "test"})
    end
  end

  describe "round-trip serialization" do
    test "to_map and from_map preserve data" do
      original = ConfidenceEstimate.new!(%{
        score: 0.85,
        method: :attention,
        reasoning: "High confidence",
        token_level_confidence: [0.9, 0.8, 0.85]
      })

      map = ConfidenceEstimate.to_map(original)
      assert {:ok, restored} = ConfidenceEstimate.from_map(map)

      assert restored.score == original.score
      assert restored.method == original.method
      assert restored.reasoning == original.reasoning
      assert restored.token_level_confidence == original.token_level_confidence
    end
  end

  # Helper function

  defp new_estimate(score) do
    ConfidenceEstimate.new!(%{score: score, method: :test})
  end
end
