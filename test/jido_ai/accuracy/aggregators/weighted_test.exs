defmodule Jido.AI.Accuracy.Aggregators.WeightedTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Aggregators.Weighted, Candidate}
  alias Jido.AI.Accuracy.Aggregators.{BestOfN, MajorityVote}

  @moduletag :capture_log

  describe "aggregate/2" do
    test "combines majority vote and best-of-N by default" do
      # 42 wins majority vote (2/3), 41 wins best-of-N (higher score)
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.7}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.6}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.8})
      ]

      # With equal weights (0.5, 0.5):
      # - 42 gets 0.5 from majority vote
      # - 41 gets 0.5 from best-of-N
      # Result depends on which wins - could be either with equal weights
      assert {:ok, _best, metadata} = Weighted.aggregate(candidates)
      assert is_map(metadata.strategy_weights)
      assert metadata.total_strategies == 2
    end

    test "normalizes weights to sum to 1.0" do
      candidates = [
        Candidate.new!(%{content: "42", score: 0.9}),
        Candidate.new!(%{content: "41", score: 0.7})
      ]

      # Unequal weights that should be normalized
      assert {:ok, _best, metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {MajorityVote, 2},
                   {BestOfN, 1}
                 ]
               )

      # Check weights were normalized (2/3 and 1/3)
      assert_in_delta metadata.strategy_weights[MajorityVote], 0.666, 0.01
      assert_in_delta metadata.strategy_weights[BestOfN], 0.333, 0.01
    end

    test "handles all-zero weights" do
      candidates = [
        Candidate.new!(%{content: "42", score: 0.9}),
        Candidate.new!(%{content: "41", score: 0.7})
      ]

      assert {:ok, _best, metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {MajorityVote, 0},
                   {BestOfN, 0}
                 ]
               )

      # Should normalize to equal weights (0.5 each)
      assert metadata.strategy_weights[MajorityVote] == 0.5
      assert metadata.strategy_weights[BestOfN] == 0.5
    end

    test "handles custom weights via opts" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.8}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.7}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.6})
      ]

      # Majority vote gets 80%, BestOfN gets 20%
      assert {:ok, best, _metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {MajorityVote, 0.8},
                   {BestOfN, 0.2}
                 ]
               )

      # 42 should win since it has strong majority vote support
      assert String.contains?(best.content, "42")
    end

    test "handles empty candidate list" do
      assert {:error, :no_candidates} = Weighted.aggregate([])
    end

    test "handles single candidate" do
      candidates = [Candidate.new!(%{content: "42", score: 0.8})]

      assert {:ok, best, metadata} = Weighted.aggregate(candidates)
      assert best.content == "42"
      assert metadata.confidence == 1.0
    end

    test "handles no strategies" do
      candidates = [
        Candidate.new!(%{content: "42", score: 0.8}),
        Candidate.new!(%{content: "41", score: 0.7})
      ]

      assert {:error, :no_strategies} = Weighted.aggregate(candidates, strategies: [])
    end

    test "continues when one strategy fails" do
      # Create a mock strategy that fails
      defmodule FailingStrategy do
        @behaviour Jido.AI.Accuracy.Aggregator

        def aggregate(_candidates, _opts), do: {:error, :failed}
      end

      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.9}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.7})
      ]

      # FailingStrategy + MajorityVote should still work
      assert {:ok, best, _metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {FailingStrategy, 0.5},
                   {MajorityVote, 0.5}
                 ]
               )

      assert String.contains?(best.content, "42")
    end

    test "returns weighted scores in metadata" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.9}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.7})
      ]

      assert {:ok, _best, metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {MajorityVote, 0.6},
                   {BestOfN, 0.4}
                 ]
               )

      # Check that weighted scores are present
      assert is_list(metadata.weighted_scores)
      assert length(metadata.weighted_scores) == 2
    end
  end

  describe "distribution/1" do
    test "returns nil for weighted aggregator" do
      candidates = [
        Candidate.new!(%{content: "42", score: 0.9}),
        Candidate.new!(%{content: "41", score: 0.7})
      ]

      assert Weighted.distribution(candidates) == nil
    end

    test "handles empty list" do
      assert Weighted.distribution([]) == nil
    end
  end

  describe "integration tests" do
    test "strategies agree on winner" do
      # Both majority vote and best-of-N should select 42
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.9}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.85}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.8}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.6})
      ]

      assert {:ok, best, metadata} = Weighted.aggregate(candidates)
      assert String.contains?(best.content, "42")
      # With both strategies agreeing, confidence should be 1.0
      assert metadata.confidence == 1.0
    end

    test "strategies disagree on winner" do
      # Majority vote picks 42 (3/5), best-of-N picks 41 (highest score)
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.6}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.5}),
        Candidate.new!(%{content: "The answer is: 42", score: 0.4}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.9}),
        Candidate.new!(%{content: "The answer is: 40", score: 0.3})
      ]

      # With equal weights, 42 should win (3 vs 1 votes)
      assert {:ok, best, metadata} = Weighted.aggregate(candidates)
      assert String.contains?(best.content, "42")
      # Confidence should be between 0 and 1
      assert metadata.confidence > 0 and metadata.confidence <= 1.0
    end

    test "single strategy" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42", score: 0.9}),
        Candidate.new!(%{content: "The answer is: 41", score: 0.7})
      ]

      assert {:ok, best, metadata} =
               Weighted.aggregate(candidates,
                 strategies: [
                   {BestOfN, 1.0}
                 ]
               )

      assert String.contains?(best.content, "42")
      # With single strategy, confidence equals the weight (1.0)
      assert metadata.confidence == 1.0
    end
  end
end
