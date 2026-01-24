defmodule Jido.AI.Accuracy.RoutingResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, RoutingResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates result with valid attributes" do
      assert {:ok, result} = RoutingResult.new(%{action: :direct, original_score: 0.8})

      assert result.action == :direct
      assert result.original_score == 0.8
    end

    test "creates result with all attributes" do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, result} =
               RoutingResult.new(%{
                 action: :abstain,
                 candidate: candidate,
                 original_score: 0.3,
                 confidence_level: :low,
                 reasoning: "Low confidence"
               })

      assert result.action == :abstain
      assert result.candidate.content == "Test"
      assert result.original_score == 0.3
      assert result.confidence_level == :low
      assert result.reasoning == "Low confidence"
    end

    test "returns error for invalid action" do
      assert {:error, :invalid_action} = RoutingResult.new(%{action: :invalid_action})
    end

    test "returns error for invalid score" do
      assert {:error, :invalid_score} = RoutingResult.new(%{action: :direct, original_score: 1.5})
      assert {:error, :invalid_score} = RoutingResult.new(%{action: :direct, original_score: -0.1})
    end

    test "returns error for invalid confidence level" do
      assert {:error, :invalid_confidence_level} =
               RoutingResult.new(%{action: :direct, confidence_level: :invalid})
    end

    test "accepts all valid actions" do
      actions = [:direct, :with_verification, :with_citations, :abstain, :escalate]

      Enum.each(actions, fn action ->
        assert {:ok, %RoutingResult{action: ^action}} = RoutingResult.new(%{action: action})
      end)
    end
  end

  describe "new!/1" do
    test "creates result with valid attributes" do
      result = RoutingResult.new!(%{action: :direct, original_score: 0.8})

      assert result.action == :direct
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        RoutingResult.new!(%{action: :invalid})
      end
    end
  end

  describe "action helpers" do
    setup do
      {:ok, result: RoutingResult.new!(%{action: :direct, original_score: 0.8})}
    end

    test "direct?/1 returns true for direct action", %{result: result} do
      assert RoutingResult.direct?(result)
    end

    test "direct?/1 returns false for other actions" do
      result = RoutingResult.new!(%{action: :abstain})
      refute RoutingResult.direct?(result)
    end

    test "with_verification?/1 returns true for with_verification action" do
      result = RoutingResult.new!(%{action: :with_verification})
      assert RoutingResult.with_verification?(result)
    end

    test "with_citations?/1 returns true for with_citations action" do
      result = RoutingResult.new!(%{action: :with_citations})
      assert RoutingResult.with_citations?(result)
    end

    test "abstained?/1 returns true for abstain action" do
      result = RoutingResult.new!(%{action: :abstain})
      assert RoutingResult.abstained?(result)
    end

    test "escalated?/1 returns true for escalate action" do
      result = RoutingResult.new!(%{action: :escalate})
      assert RoutingResult.escalated?(result)
    end
  end

  describe "unmodified?/1 and modified?/1" do
    test "unmodified?/1 returns true for direct action" do
      result = RoutingResult.new!(%{action: :direct})
      assert RoutingResult.unmodified?(result)
      refute RoutingResult.modified?(result)
    end

    test "unmodified?/1 returns false for non-direct actions" do
      actions = [:with_verification, :with_citations, :abstain, :escalate]

      Enum.each(actions, fn action ->
        result = RoutingResult.new!(%{action: action})
        refute RoutingResult.unmodified?(result)
        assert RoutingResult.modified?(result)
      end)
    end
  end

  describe "to_map/1" do
    test "converts result to map" do
      result = RoutingResult.new!(%{action: :direct, original_score: 0.8})

      map = RoutingResult.to_map(result)

      assert Map.has_key?(map, "action")
      assert Map.has_key?(map, "original_score")
      assert map["action"] == :direct
      assert map["original_score"] == 0.8
    end

    test "excludes nil and empty values" do
      result = RoutingResult.new!(%{action: :direct})

      map = RoutingResult.to_map(result)

      # Should have action but not nil values
      assert Map.has_key?(map, "action")
      refute Map.has_key?(map, "candidate")
      refute Map.has_key?(map, "reasoning")
    end

    test "includes populated metadata" do
      result =
        RoutingResult.new!(%{
          action: :direct,
          metadata: %{key: "value"}
        })

      map = RoutingResult.to_map(result)

      assert Map.has_key?(map, "metadata")
      # Nested maps keep their original key types
      assert map["metadata"] == %{key: "value"}
    end

    test "excludes empty metadata" do
      result = RoutingResult.new!(%{action: :direct})

      map = RoutingResult.to_map(result)

      refute Map.has_key?(map, "metadata")
    end
  end

  describe "from_map/1" do
    test "creates result from map" do
      map = %{"action" => "direct", "original_score" => 0.8}

      assert {:ok, result} = RoutingResult.from_map(map)
      assert result.action == :direct
      assert result.original_score == 0.8
    end

    test "creates result with all attributes" do
      map = %{
        "action" => "abstain",
        "original_score" => 0.3,
        "confidence_level" => "low",
        "reasoning" => "Low confidence"
      }

      assert {:ok, result} = RoutingResult.from_map(map)
      assert result.action == :abstain
      assert result.original_score == 0.3
      assert result.confidence_level == :low
      assert result.reasoning == "Low confidence"
    end

    test "returns error for invalid data" do
      map = %{"action" => "invalid"}

      assert {:error, :invalid_action} = RoutingResult.from_map(map)
    end
  end

  describe "round trip serialization" do
    test "to_map and from_map are inverses" do
      original =
        RoutingResult.new!(%{
          action: :with_verification,
          original_score: 0.5,
          confidence_level: :medium,
          reasoning: "Test reasoning",
          metadata: %{key: "value"}
        })

      map = RoutingResult.to_map(original)
      {:ok, restored} = RoutingResult.from_map(map)

      assert restored.action == original.action
      assert restored.original_score == original.original_score
      assert restored.confidence_level == original.confidence_level
      assert restored.reasoning == original.reasoning
    end
  end
end
