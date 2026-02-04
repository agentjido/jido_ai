defmodule Jido.AI.Accuracy.Aggregators.BestOfNTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Aggregators.BestOfN, Candidate}

  @moduletag :capture_log

  describe "aggregate/2" do
    test "selects highest scored candidate" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.7}),
        Candidate.new!(%{content: "B", score: 0.95}),
        Candidate.new!(%{content: "C", score: 0.6})
      ]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)
      assert best.content == "B"
      assert best.score == 0.95
      assert metadata.confidence == 0.95
    end

    test "handles equal scores with token efficiency" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8, tokens_used: 150}),
        Candidate.new!(%{content: "B", score: 0.8, tokens_used: 100}),
        Candidate.new!(%{content: "C", score: 0.7, tokens_used: 80})
      ]

      assert {:ok, best, _metadata} = BestOfN.aggregate(candidates)
      # B wins with lower token usage
      assert best.content == "B"
      assert best.tokens_used == 100
    end

    test "handles equal scores and tokens with timestamp" do
      earlier = DateTime.utc_now() |> DateTime.add(-10, :second)
      later = DateTime.utc_now()

      candidates = [
        Candidate.new!(%{content: "A", score: 0.8, tokens_used: 100, timestamp: earlier}),
        Candidate.new!(%{content: "B", score: 0.8, tokens_used: 100, timestamp: later})
      ]

      assert {:ok, best, _metadata} = BestOfN.aggregate(candidates)
      # A wins with earlier timestamp
      assert best.content == "A"
    end

    test "handles ties with nil tokens" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8}),
        Candidate.new!(%{content: "B", score: 0.8, tokens_used: 100})
      ]

      assert {:ok, best, _metadata} = BestOfN.aggregate(candidates)
      # A wins with nil tokens (treated as more efficient)
      assert best.content == "A"
    end

    test "returns score metadata" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8}),
        Candidate.new!(%{content: "B", score: 0.8}),
        Candidate.new!(%{content: "C", score: 0.6})
      ]

      assert {:ok, _best, metadata} = BestOfN.aggregate(candidates)
      assert metadata.score_distribution[0.8] == 2
      assert metadata.score_distribution[0.6] == 1
    end

    test "confidence equals score value" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.95}),
        Candidate.new!(%{content: "B", score: 0.7})
      ]

      assert {:ok, _best, metadata} = BestOfN.aggregate(candidates)
      assert metadata.confidence == 0.95
    end

    test "handles empty candidate list" do
      assert {:error, :no_candidates} = BestOfN.aggregate([])
    end

    test "handles single candidate" do
      candidates = [Candidate.new!(%{content: "A", score: 0.8})]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)
      assert best.content == "A"
      assert metadata.confidence == 0.8
    end

    test "handles candidates with no scores" do
      candidates = [
        Candidate.new!(%{content: "A"}),
        Candidate.new!(%{content: "B"})
      ]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)
      assert best.content == "A"
      assert metadata.fallback == :no_scores
      assert metadata.confidence == 0.0
    end

    test "filters out candidates without scores" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8}),
        Candidate.new!(%{content: "B"}),
        Candidate.new!(%{content: "C", score: 0.7})
      ]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)
      assert best.content == "A"
      assert metadata.scored_candidates == 2
    end

    test "handles single candidate with score" do
      candidates = [Candidate.new!(%{content: "A", score: 0.8})]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)
      assert best.content == "A"
      assert metadata.confidence == 0.8
    end

    test "handles negative scores" do
      candidates = [
        Candidate.new!(%{content: "A", score: -0.5}),
        Candidate.new!(%{content: "B", score: 0.3})
      ]

      assert {:ok, best, _metadata} = BestOfN.aggregate(candidates)
      assert best.content == "B"
    end
  end

  describe "distribution/1" do
    test "returns correct score distribution" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8}),
        Candidate.new!(%{content: "B", score: 0.8}),
        Candidate.new!(%{content: "C", score: 0.6}),
        Candidate.new!(%{content: "D", score: 0.6}),
        Candidate.new!(%{content: "E", score: 0.6})
      ]

      distribution = BestOfN.distribution(candidates)

      assert distribution[0.8] == 2
      assert distribution[0.6] == 3
    end

    test "filters out candidates without scores" do
      candidates = [
        Candidate.new!(%{content: "A", score: 0.8}),
        Candidate.new!(%{content: "B"}),
        Candidate.new!(%{content: "C", score: 0.6})
      ]

      distribution = BestOfN.distribution(candidates)

      assert distribution[0.8] == 1
      assert distribution[0.6] == 1
      assert map_size(distribution) == 2
    end

    test "handles empty list" do
      assert BestOfN.distribution([]) == %{}
    end
  end

  describe "integration tests" do
    test "full aggregation with complex candidates" do
      timestamp = DateTime.utc_now()

      candidates = [
        Candidate.new!(%{
          content: "Answer A",
          score: 0.85,
          tokens_used: 120,
          model: "model1",
          timestamp: timestamp,
          metadata: %{}
        }),
        Candidate.new!(%{
          content: "Answer B",
          score: 0.92,
          tokens_used: 110,
          model: "model1",
          timestamp: timestamp,
          metadata: %{}
        }),
        Candidate.new!(%{
          content: "Answer C",
          score: 0.75,
          tokens_used: 100,
          model: "model1",
          timestamp: timestamp,
          metadata: %{}
        })
      ]

      assert {:ok, best, metadata} = BestOfN.aggregate(candidates)

      # Verify best is selected by score
      assert best.content == "Answer B"
      assert best.score == 0.92

      # Verify metadata
      assert metadata.confidence == 0.92
      assert metadata.total_candidates == 3
      assert metadata.scored_candidates == 3
      assert is_map(metadata.score_distribution)
    end
  end
end
