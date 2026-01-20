defmodule Jido.AI.Accuracy.VerificationResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.VerificationResult

  describe "new/1" do
    test "creates valid result with all fields" do
      assert {:ok, result} =
               VerificationResult.new(%{
                 candidate_id: "candidate_1",
                 score: 0.95,
                 confidence: 0.9,
                 reasoning: "Correct answer",
                 step_scores: %{"step_1" => 0.8},
                 metadata: %{verifier: :test}
               })

      assert result.candidate_id == "candidate_1"
      assert result.score == 0.95
      assert result.confidence == 0.9
      assert result.reasoning == "Correct answer"
      assert result.step_scores == %{"step_1" => 0.8}
      assert result.metadata.verifier == :test
    end

    test "creates valid result with minimal fields" do
      assert {:ok, result} = VerificationResult.new(%{})

      assert result.candidate_id == nil
      assert result.score == nil
      assert result.confidence == nil
      assert result.reasoning == nil
      assert result.step_scores == nil
      assert result.metadata == %{}
    end

    test "creates valid result with only score" do
      assert {:ok, result} = VerificationResult.new(%{score: 0.8})

      assert result.score == 0.8
      assert result.confidence == nil
    end

    test "returns error for invalid confidence > 1" do
      assert {:error, :invalid_confidence} =
               VerificationResult.new(%{confidence: 1.5})
    end

    test "returns error for invalid confidence < 0" do
      assert {:error, :invalid_confidence} =
               VerificationResult.new(%{confidence: -0.1})
    end

    test "returns error for invalid score type" do
      assert {:error, :invalid_score} =
               VerificationResult.new(%{score: "not_a_number"})
    end

    test "returns error for invalid step_scores (non-string keys)" do
      assert {:error, :invalid_step_scores} =
               VerificationResult.new(%{step_scores: %{1 => 0.8}})
    end

    test "returns error for invalid step_scores (non-numeric values)" do
      assert {:error, :invalid_step_scores} =
               VerificationResult.new(%{step_scores: %{"step_1" => "not_a_number"}})
    end

    test "accepts confidence of exactly 0.0" do
      assert {:ok, result} = VerificationResult.new(%{confidence: 0.0})
      assert result.confidence == 0.0
    end

    test "accepts confidence of exactly 1.0" do
      assert {:ok, result} = VerificationResult.new(%{confidence: 1.0})
      assert result.confidence == 1.0
    end

    test "accepts nil score" do
      assert {:ok, result} = VerificationResult.new(%{score: nil})
      assert result.score == nil
    end

    test "accepts nil confidence" do
      assert {:ok, result} = VerificationResult.new(%{confidence: nil})
      assert result.confidence == nil
    end

    test "accepts nil step_scores" do
      assert {:ok, result} = VerificationResult.new(%{step_scores: nil})
      assert result.step_scores == nil
    end

    test "accepts empty step_scores map" do
      assert {:ok, result} = VerificationResult.new(%{step_scores: %{}})
      assert result.step_scores == %{}
    end

    test "accepts negative score" do
      # Some verifiers may use negative scores (e.g., log-likelihood)
      assert {:ok, result} = VerificationResult.new(%{score: -1.5})
      assert result.score == -1.5
    end

    test "accepts score greater than 1" do
      # Some verifiers may use unbounded scores
      assert {:ok, result} = VerificationResult.new(%{score: 2.5})
      assert result.score == 2.5
    end
  end

  describe "new!/1" do
    test "returns result when valid" do
      result = VerificationResult.new!(%{score: 0.8})

      assert result.score == 0.8
    end

    test "raises when invalid confidence" do
      assert_raise ArgumentError, ~r/Invalid verification result/, fn ->
        VerificationResult.new!(%{confidence: 1.5})
      end
    end

    test "raises when invalid score type" do
      assert_raise ArgumentError, ~r/Invalid verification result/, fn ->
        VerificationResult.new!(%{score: "invalid"})
      end
    end

    test "raises when invalid step_scores" do
      assert_raise ArgumentError, ~r/Invalid verification result/, fn ->
        VerificationResult.new!(%{step_scores: %{invalid: :keys}})
      end
    end
  end

  describe "pass?/2" do
    test "returns true when score >= threshold" do
      result = VerificationResult.new!(%{score: 0.8})

      assert VerificationResult.pass?(result, 0.7) == true
      assert VerificationResult.pass?(result, 0.8) == true
    end

    test "returns false when score < threshold" do
      result = VerificationResult.new!(%{score: 0.5})

      assert VerificationResult.pass?(result, 0.7) == false
    end

    test "returns false when score is nil" do
      result = VerificationResult.new!(%{})

      assert VerificationResult.pass?(result, 0.5) == false
    end

    test "uses default threshold of 0.5" do
      result = VerificationResult.new!(%{score: 0.6})

      assert VerificationResult.pass?(result) == true
    end

    test "default threshold fails for score 0.4" do
      result = VerificationResult.new!(%{score: 0.4})

      assert VerificationResult.pass?(result) == false
    end

    test "works with negative scores" do
      result = VerificationResult.new!(%{score: -0.5})

      assert VerificationResult.pass?(result, -1.0) == true
      assert VerificationResult.pass?(result, 0.0) == false
    end
  end

  describe "merge_step_scores/2" do
    test "merges step scores into existing result with step_scores" do
      result =
        VerificationResult.new!(%{
          step_scores: %{"step_1" => 0.8}
        })

      updated = VerificationResult.merge_step_scores(result, %{"step_2" => 0.9})

      assert updated.step_scores == %{"step_1" => 0.8, "step_2" => 0.9}
    end

    test "merges step scores into result without existing step_scores" do
      result = VerificationResult.new!(%{})

      updated = VerificationResult.merge_step_scores(result, %{"step_1" => 0.8})

      assert updated.step_scores == %{"step_1" => 0.8}
    end

    test "overwrites duplicate keys" do
      result =
        VerificationResult.new!(%{
          step_scores: %{"step_1" => 0.5}
        })

      updated = VerificationResult.merge_step_scores(result, %{"step_1" => 0.9})

      assert updated.step_scores == %{"step_1" => 0.9}
    end

    test "handles empty new_scores map" do
      result =
        VerificationResult.new!(%{
          step_scores: %{"step_1" => 0.8}
        })

      updated = VerificationResult.merge_step_scores(result, %{})

      assert updated.step_scores == %{"step_1" => 0.8}
    end

    test "preserves other fields" do
      result =
        VerificationResult.new!(%{
          score: 0.7,
          confidence: 0.8,
          reasoning: "Test"
        })

      updated = VerificationResult.merge_step_scores(result, %{"step_1" => 0.9})

      assert updated.score == 0.7
      assert updated.confidence == 0.8
      assert updated.reasoning == "Test"
    end
  end

  describe "to_map/1" do
    test "serializes all fields to string keys" do
      result =
        VerificationResult.new!(%{
          candidate_id: "candidate_1",
          score: 0.95,
          confidence: 0.9,
          reasoning: "Good",
          step_scores: %{"step_1" => 0.8},
          metadata: %{key: :value}
        })

      map = VerificationResult.to_map(result)

      assert map["candidate_id"] == "candidate_1"
      assert map["score"] == 0.95
      assert map["confidence"] == 0.9
      assert map["reasoning"] == "Good"
      assert map["step_scores"] == %{"step_1" => 0.8}
      assert map["metadata"] == %{key: :value}
    end

    test "serializes result with nil fields" do
      result = VerificationResult.new!(%{})

      map = VerificationResult.to_map(result)

      assert map["candidate_id"] == nil
      assert map["score"] == nil
      assert map["confidence"] == nil
      assert map["reasoning"] == nil
      assert map["step_scores"] == nil
      assert map["metadata"] == %{}
    end

    test "serializes numeric score and confidence correctly" do
      result = VerificationResult.new!(%{score: 0.8, confidence: 0.75})

      map = VerificationResult.to_map(result)

      assert map["score"] == 0.8
      assert map["confidence"] == 0.75
      assert is_number(map["score"])
      assert is_number(map["confidence"])
    end
  end

  describe "from_map/1" do
    test "deserializes from map with string keys" do
      map = %{
        "candidate_id" => "candidate_1",
        "score" => 0.95,
        "confidence" => 0.9,
        "reasoning" => "Good",
        "step_scores" => %{"step_1" => 0.8},
        "metadata" => %{key: :value}
      }

      assert {:ok, result} = VerificationResult.from_map(map)

      assert result.candidate_id == "candidate_1"
      assert result.score == 0.95
      assert result.confidence == 0.9
      assert result.reasoning == "Good"
      assert result.step_scores == %{"step_1" => 0.8}
      assert result.metadata.key == :value
    end

    test "deserializes from map with atom keys" do
      map = %{
        candidate_id: "candidate_1",
        score: 0.95,
        confidence: 0.9
      }

      assert {:ok, result} = VerificationResult.from_map(map)

      assert result.candidate_id == "candidate_1"
      assert result.score == 0.95
      assert result.confidence == 0.9
    end

    test "deserializes from map with mixed keys" do
      # Build map with mixed keys properly
      map = %{"candidate_id" => "candidate_1"}
      map = Map.put(map, :score, 0.95)
      map = Map.put(map, "confidence", 0.9)

      assert {:ok, result} = VerificationResult.from_map(map)

      assert result.candidate_id == "candidate_1"
      assert result.score == 0.95
      assert result.confidence == 0.9
    end

    test "returns error for invalid confidence in map" do
      map = %{"confidence" => 1.5}

      assert {:error, :invalid_confidence} = VerificationResult.from_map(map)
    end

    test "returns error for invalid score in map" do
      map = %{"score" => "invalid"}

      assert {:error, :invalid_score} = VerificationResult.from_map(map)
    end

    test "returns error for invalid step_scores in map" do
      map = %{"step_scores" => %{1 => 0.8}}

      assert {:error, :invalid_step_scores} = VerificationResult.from_map(map)
    end

    test "handles empty map" do
      assert {:ok, result} = VerificationResult.from_map(%{})
      assert result.metadata == %{}
    end

    test "handles map with only metadata" do
      map = %{"metadata" => %{key: :value}}

      assert {:ok, result} = VerificationResult.from_map(map)
      assert result.metadata == %{key: :value}
    end
  end

  describe "from_map!/1" do
    test "deserializes from valid map" do
      map = %{"score" => 0.8, "confidence" => 0.9}

      result = VerificationResult.from_map!(map)

      assert result.score == 0.8
      assert result.confidence == 0.9
    end

    test "raises when invalid confidence" do
      map = %{"confidence" => 1.5}

      assert_raise ArgumentError, ~r/Invalid verification result map/, fn ->
        VerificationResult.from_map!(map)
      end
    end

    test "raises when invalid score" do
      map = %{"score" => "invalid"}

      assert_raise ArgumentError, ~r/Invalid verification result map/, fn ->
        VerificationResult.from_map!(map)
      end
    end

    test "raises when invalid step_scores" do
      map = %{"step_scores" => :invalid}

      assert_raise ArgumentError, ~r/Invalid verification result map/, fn ->
        VerificationResult.from_map!(map)
      end
    end
  end

  describe "serialization round-trip" do
    test "to_map then from_map returns equivalent result" do
      original =
        VerificationResult.new!(%{
          candidate_id: "candidate_1",
          score: 0.95,
          confidence: 0.9,
          reasoning: "Good answer",
          step_scores: %{"step_1" => 0.8, "step_2" => 0.9},
          metadata: %{verifier: :test, domain: :math}
        })

      map = VerificationResult.to_map(original)
      assert {:ok, restored} = VerificationResult.from_map(map)

      assert restored.candidate_id == original.candidate_id
      assert restored.score == original.score
      assert restored.confidence == original.confidence
      assert restored.reasoning == original.reasoning
      assert restored.step_scores == original.step_scores
      assert restored.metadata == original.metadata
    end

    test "round-trip with nil fields" do
      original =
        VerificationResult.new!(%{
          score: nil,
          confidence: nil,
          reasoning: nil,
          step_scores: nil
        })

      map = VerificationResult.to_map(original)
      assert {:ok, restored} = VerificationResult.from_map(map)

      assert restored.score == original.score
      assert restored.confidence == original.confidence
      assert restored.reasoning == original.reasoning
      assert restored.step_scores == original.step_scores
    end

    test "round-trip with empty metadata" do
      original =
        VerificationResult.new!(%{
          score: 0.8,
          metadata: %{}
        })

      map = VerificationResult.to_map(original)
      assert {:ok, restored} = VerificationResult.from_map(map)

      assert restored.score == original.score
      assert restored.metadata == %{}
    end
  end
end
