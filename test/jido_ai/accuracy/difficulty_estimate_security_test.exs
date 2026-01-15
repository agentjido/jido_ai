defmodule Jido.AI.Accuracy.DifficultyEstimateSecurityTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.DifficultyEstimate

  @moduletag :security
  @moduletag :difficulty_estimate

  describe "from_map/1 security" do
    test "rejects invalid level strings (atom exhaustion prevention)" do
      # Before fix: String.to_existing_atom would crash with ArgumentError
      # After fix: Invalid levels return nil, causing validation to fail
      assert {:error, :invalid_level} = DifficultyEstimate.from_map(%{"level" => "malicious_atom"})
    end

    test "rejects random string levels" do
      random_string = :crypto.strong_rand_bytes(16) |> Base.encode64()

      assert {:error, :invalid_level} =
               DifficultyEstimate.from_map(%{"level" => random_string})
    end

    test "accepts valid level strings" do
      assert {:ok, %DifficultyEstimate{level: :easy}} =
               DifficultyEstimate.from_map(%{"level" => "easy", "score" => 0.2})

      assert {:ok, %DifficultyEstimate{level: :medium}} =
               DifficultyEstimate.from_map(%{"level" => "medium", "score" => 0.5})

      assert {:ok, %DifficultyEstimate{level: :hard}} =
               DifficultyEstimate.from_map(%{"level" => "hard", "score" => 0.8})
    end

    test "handles nil level gracefully" do
      assert {:ok, %DifficultyEstimate{}} = DifficultyEstimate.from_map(%{"score" => 0.5})
    end

    test "round-trip serialization works" do
      original = DifficultyEstimate.new!(%{level: :easy, score: 0.2, confidence: 0.9})

      assert {:ok, deserialized} =
               original
               |> DifficultyEstimate.to_map()
               |> DifficultyEstimate.from_map()

      assert deserialized.level == :easy
      assert deserialized.score == 0.2
      assert deserialized.confidence == 0.9
    end
  end

  describe "new/1 validation" do
    test "rejects invalid level atoms" do
      assert {:error, :invalid_level} = DifficultyEstimate.new(%{level: :invalid})
    end

    test "rejects invalid score range" do
      assert {:error, :invalid_score} = DifficultyEstimate.new(%{level: :easy, score: -0.1})
      assert {:error, :invalid_score} = DifficultyEstimate.new(%{level: :easy, score: 1.1})
    end

    test "rejects invalid confidence range" do
      assert {:error, :invalid_confidence} =
               DifficultyEstimate.new(%{level: :easy, score: 0.2, confidence: -0.1})

      assert {:error, :invalid_confidence} =
               DifficultyEstimate.new(%{level: :easy, score: 0.2, confidence: 1.1})
    end
  end

  describe "reasoning field limits" do
    test "handles very long reasoning strings" do
      long_reasoning = String.duplicate("a", 10_000)

      assert {:ok, estimate} =
               DifficultyEstimate.new(%{
                 level: :easy,
                 score: 0.2,
                 reasoning: long_reasoning
               })

      assert byte_size(estimate.reasoning) == 10_000
    end

    test "handles empty reasoning" do
      assert {:ok, estimate} = DifficultyEstimate.new(%{level: :easy, score: 0.2})
      assert estimate.reasoning == nil
    end
  end

  describe "features map validation" do
    test "handles empty features map" do
      assert {:ok, estimate} =
               DifficultyEstimate.new(%{level: :easy, score: 0.2, features: %{}})

      assert estimate.features == %{}
    end

    test "handles nested features map" do
      nested_features = %{
        complexity: %{score: 0.5, factors: ["length", "domain"]},
        metadata: %{source: "test"}
      }

      assert {:ok, estimate} =
               DifficultyEstimate.new(%{level: :medium, score: 0.5, features: nested_features})

      assert estimate.features == nested_features
    end
  end
end
