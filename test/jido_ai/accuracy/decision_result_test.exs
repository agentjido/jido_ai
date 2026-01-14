defmodule Jido.AI.Accuracy.DecisionResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, DecisionResult}

  @moduletag :capture_log

  describe "new/1" do
    test "creates result with valid attributes" do
      assert {:ok, result} = DecisionResult.new(%{decision: :answer})

      assert result.decision == :answer
    end

    test "creates result with all attributes" do
      candidate = Candidate.new!(%{content: "Test"})

      assert {:ok, result} =
               DecisionResult.new(%{
                 decision: :abstain,
                 candidate: candidate,
                 confidence: 0.3,
                 ev_answer: -0.4,
                 ev_abstain: 0.0,
                 reasoning: "Low expected value"
               })

      assert result.decision == :abstain
      assert result.candidate.content == "Test"
      assert result.confidence == 0.3
      assert result.ev_answer == -0.4
      assert result.ev_abstain == 0.0
    end

    test "returns error for invalid decision" do
      assert {:error, :invalid_decision} = DecisionResult.new(%{decision: :invalid})
    end

    test "accepts all valid decisions" do
      decisions = [:answer, :abstain]

      Enum.each(decisions, fn decision ->
        assert {:ok, %DecisionResult{decision: ^decision}} = DecisionResult.new(%{decision: decision})
      end)
    end

    test "sets default EV values" do
      assert {:ok, result} = DecisionResult.new(%{decision: :answer})

      assert result.ev_answer == 0.0
      assert result.ev_abstain == 0.0
    end
  end

  describe "new!/1" do
    test "creates result with valid attributes" do
      result = DecisionResult.new!(%{decision: :answer})
      assert result.decision == :answer
    end

    test "raises for invalid attributes" do
      assert_raise ArgumentError, ~r/Invalid/, fn ->
        DecisionResult.new!(%{decision: :invalid})
      end
    end
  end

  describe "decision helpers" do
    test "answered?/1 returns true for answer decision" do
      result = DecisionResult.new!(%{decision: :answer})
      assert DecisionResult.answered?(result)
    end

    test "answered?/1 returns false for abstain decision" do
      result = DecisionResult.new!(%{decision: :abstain})
      refute DecisionResult.answered?(result)
    end

    test "abstained?/1 returns true for abstain decision" do
      result = DecisionResult.new!(%{decision: :abstain})
      assert DecisionResult.abstained?(result)
    end

    test "abstained?/1 returns false for answer decision" do
      result = DecisionResult.new!(%{decision: :answer})
      refute DecisionResult.abstained?(result)
    end
  end

  describe "to_map/1" do
    test "converts result to map" do
      result = DecisionResult.new!(%{decision: :answer, confidence: 0.8})

      map = DecisionResult.to_map(result)

      assert Map.has_key?(map, "decision")
      assert Map.has_key?(map, "confidence")
      assert map["decision"] == :answer
      assert map["confidence"] == 0.8
    end

    test "excludes nil and empty values" do
      result = DecisionResult.new!(%{decision: :answer})

      map = DecisionResult.to_map(result)

      # Should have decision but not nil values
      assert Map.has_key?(map, "decision")
      refute Map.has_key?(map, "candidate")
      refute Map.has_key?(map, "reasoning")
    end

    test "includes populated metadata" do
      result =
        DecisionResult.new!(%{
          decision: :answer,
          metadata: %{key: "value"}
        })

      map = DecisionResult.to_map(result)

      assert Map.has_key?(map, "metadata")
      assert map["metadata"] == %{key: "value"}
    end
  end

  describe "from_map/1" do
    test "creates result from map" do
      map = %{"decision" => "answer", "confidence" => 0.8}

      assert {:ok, result} = DecisionResult.from_map(map)
      assert result.decision == :answer
      assert result.confidence == 0.8
    end

    test "creates result with all attributes" do
      map = %{
        "decision" => "abstain",
        "confidence" => 0.3,
        "ev_answer" => -0.4,
        "reasoning" => "Low EV"
      }

      assert {:ok, result} = DecisionResult.from_map(map)
      assert result.decision == :abstain
      assert result.confidence == 0.3
      assert result.ev_answer == -0.4
    end

    test "returns error for invalid data" do
      map = %{"decision" => "invalid"}

      assert {:error, :invalid_decision} = DecisionResult.from_map(map)
    end
  end

  describe "round trip serialization" do
    test "to_map and from_map are inverses" do
      original =
        DecisionResult.new!(%{
          decision: :answer,
          confidence: 0.7,
          ev_answer: 0.4,
          reasoning: "Test"
        })

      map = DecisionResult.to_map(original)
      {:ok, restored} = DecisionResult.from_map(map)

      assert restored.decision == original.decision
      assert restored.confidence == original.confidence
      assert restored.ev_answer == original.ev_answer
    end
  end
end
