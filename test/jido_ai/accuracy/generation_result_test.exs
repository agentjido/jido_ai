defmodule Jido.AI.Accuracy.GenerationResultTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Candidate
  alias Jido.AI.Accuracy.GenerationResult

  describe "new/2" do
    test "creates result from empty candidate list" do
      assert {:ok, result} = GenerationResult.new([])
      assert result.candidates == []
      assert result.total_tokens == 0
      assert result.best_candidate == nil
      assert result.aggregation_method == :none
    end

    test "creates result from single candidate" do
      candidate = Candidate.new!(%{content: "Answer A", score: 0.8})

      assert {:ok, result} = GenerationResult.new([candidate])
      assert length(result.candidates) == 1
      assert result.total_tokens == 0
      assert result.best_candidate == candidate
    end

    test "creates result from multiple candidates" do
      c1 = Candidate.new!(%{content: "A", score: 0.5})
      c2 = Candidate.new!(%{content: "B", score: 0.9})
      c3 = Candidate.new!(%{content: "C", score: 0.7})

      assert {:ok, result} = GenerationResult.new([c1, c2, c3])
      assert length(result.candidates) == 3
      assert result.best_candidate == c2
    end

    test "computes total_tokens from candidates" do
      c1 = Candidate.new!(%{tokens_used: 100})
      c2 = Candidate.new!(%{tokens_used: 50})
      c3 = Candidate.new!(%{tokens_used: 25})

      assert {:ok, result} = GenerationResult.new([c1, c2, c3])
      assert result.total_tokens == 175
    end

    test "handles nil tokens_used correctly" do
      c1 = Candidate.new!(%{tokens_used: 100})
      c2 = Candidate.new!(%{tokens_used: nil})
      c3 = Candidate.new!(%{tokens_used: 50})

      assert {:ok, result} = GenerationResult.new([c1, c2, c3])
      assert result.total_tokens == 150
    end

    test "sets aggregation_method from opts" do
      candidate = Candidate.new!(%{content: "A"})

      assert {:ok, result} = GenerationResult.new([candidate], aggregation_method: :best_of_n)
      assert result.aggregation_method == :best_of_n
    end

    test "defaults aggregation_method to :none" do
      candidate = Candidate.new!(%{content: "A"})

      assert {:ok, result} = GenerationResult.new([candidate])
      assert result.aggregation_method == :none
    end

    test "sets metadata from opts" do
      candidate = Candidate.new!(%{content: "A"})
      metadata = %{temperature: 0.7}

      assert {:ok, result} = GenerationResult.new([candidate], metadata: metadata)
      assert result.metadata == metadata
    end

    test "defaults metadata to empty map" do
      candidate = Candidate.new!(%{content: "A"})

      assert {:ok, result} = GenerationResult.new([candidate])
      assert result.metadata == %{}
    end

    test "returns error for invalid candidate list" do
      assert {:error, :invalid_candidates} = GenerationResult.new([:not_a_candidate])
    end

    test "returns error for mixed valid and invalid candidates" do
      valid = Candidate.new!(%{content: "A"})
      invalid = :not_a_candidate

      assert {:error, :invalid_candidates} = GenerationResult.new([valid, invalid])
    end

    test "finds best_candidate with highest score" do
      c1 = Candidate.new!(%{content: "A", score: 0.3})
      c2 = Candidate.new!(%{content: "B", score: 0.9})
      c3 = Candidate.new!(%{content: "C", score: 0.6})

      assert {:ok, result} = GenerationResult.new([c1, c2, c3])
      assert result.best_candidate.content == "B"
    end

    test "handles all nil scores - best_candidate is nil" do
      c1 = Candidate.new!(%{content: "A"})
      c2 = Candidate.new!(%{content: "B"})

      assert {:ok, result} = GenerationResult.new([c1, c2])
      assert result.best_candidate == nil
    end

    test "handles mix of nil and numeric scores" do
      c1 = Candidate.new!(%{content: "A"})
      c2 = Candidate.new!(%{content: "B", score: 0.5})
      c3 = Candidate.new!(%{content: "C"})

      assert {:ok, result} = GenerationResult.new([c1, c2, c3])
      assert result.best_candidate.content == "B"
    end
  end

  describe "new!/2" do
    test "returns result when valid" do
      candidate = Candidate.new!(%{content: "A"})

      result = GenerationResult.new!([candidate])
      assert length(result.candidates) == 1
    end

    test "raises when invalid" do
      assert_raise ArgumentError, ~r/Invalid generation result/, fn ->
        GenerationResult.new!([:invalid])
      end
    end
  end

  describe "best_candidate/1" do
    test "returns nil for empty candidates" do
      result = GenerationResult.new!([], aggregation_method: :none)
      assert GenerationResult.best_candidate(result) == nil
    end

    test "returns highest scored candidate" do
      c1 = Candidate.new!(%{content: "Low", score: 0.2})
      c2 = Candidate.new!(%{content: "High", score: 0.9})
      c3 = Candidate.new!(%{content: "Mid", score: 0.5})

      result = GenerationResult.new!([c1, c2, c3])
      assert GenerationResult.best_candidate(result).content == "High"
    end
  end

  describe "total_tokens/1" do
    test "returns 0 for empty candidates" do
      result = GenerationResult.new!([])
      assert GenerationResult.total_tokens(result) == 0
    end

    test "returns sum of all candidate tokens" do
      c1 = Candidate.new!(%{tokens_used: 100})
      c2 = Candidate.new!(%{tokens_used: 200})
      c3 = Candidate.new!(%{tokens_used: 50})

      result = GenerationResult.new!([c1, c2, c3])
      assert GenerationResult.total_tokens(result) == 350
    end
  end

  describe "candidates/1" do
    test "returns empty list for no candidates" do
      result = GenerationResult.new!([])
      assert GenerationResult.candidates(result) == []
    end

    test "returns list of candidates" do
      c1 = Candidate.new!(%{content: "A"})
      c2 = Candidate.new!(%{content: "B"})

      result = GenerationResult.new!([c1, c2])
      candidates = GenerationResult.candidates(result)

      assert length(candidates) == 2
      assert Enum.at(candidates, 0).content == "A"
      assert Enum.at(candidates, 1).content == "B"
    end
  end

  describe "select_by_strategy/2" do
    setup do
      c1 = Candidate.new!(%{content: "A", score: 0.3})
      c2 = Candidate.new!(%{content: "B", score: 0.9})
      c3 = Candidate.new!(%{content: "C", score: 0.6})

      %{candidates: [c1, c2, c3], result: GenerationResult.new!([c1, c2, c3])}
    end

    test "returns nil for empty candidates" do
      result = GenerationResult.new!([])
      assert GenerationResult.select_by_strategy(result, :best) == nil
      assert GenerationResult.select_by_strategy(result, :first) == nil
      assert GenerationResult.select_by_strategy(result, :last) == nil
    end

    test ":best returns highest scored candidate", context do
      selected = GenerationResult.select_by_strategy(context.result, :best)
      assert selected.content == "B"
      assert selected.score == 0.9
    end

    test ":first returns first candidate", context do
      selected = GenerationResult.select_by_strategy(context.result, :first)
      assert selected.content == "A"
    end

    test ":last returns last candidate", context do
      selected = GenerationResult.select_by_strategy(context.result, :last)
      assert selected.content == "C"
    end

    test ":vote returns candidate with most common content (simple majority)" do
      # Create candidates with some duplicates
      c1 = Candidate.new!(%{content: "Answer A", score: 0.5})
      c2 = Candidate.new!(%{content: "Answer B", score: 0.7})
      c3 = Candidate.new!(%{content: "Answer A", score: 0.6})
      c4 = Candidate.new!(%{content: "Answer B", score: 0.8})

      result = GenerationResult.new!([c1, c2, c3, c4])

      # Should return one of the "Answer A" or "Answer B" candidates
      selected = GenerationResult.select_by_strategy(result, :vote)
      assert selected.content in ["Answer A", "Answer B"]
    end

    test "unknown strategy falls back to :best", context do
      selected = GenerationResult.select_by_strategy(context.result, :unknown)
      assert selected.content == "B"
    end
  end

  describe "add_candidate/2" do
    test "adds candidate to empty result" do
      result = GenerationResult.new!([])
      new_candidate = Candidate.new!(%{content: "New", tokens_used: 50})

      updated = GenerationResult.add_candidate(result, new_candidate)

      assert length(updated.candidates) == 1
      assert Enum.at(updated.candidates, 0).content == "New"
      assert updated.total_tokens == 50
    end

    test "adds candidate to existing result" do
      c1 = Candidate.new!(%{content: "A", tokens_used: 100})
      result = GenerationResult.new!([c1])

      new_candidate = Candidate.new!(%{content: "B", tokens_used: 50})
      updated = GenerationResult.add_candidate(result, new_candidate)

      assert length(updated.candidates) == 2
      assert Enum.at(updated.candidates, 1).content == "B"
      assert updated.total_tokens == 150
    end

    test "recomputes best_candidate after adding" do
      c1 = Candidate.new!(%{content: "A", score: 0.5})
      result = GenerationResult.new!([c1])

      new_candidate = Candidate.new!(%{content: "B", score: 0.9})
      updated = GenerationResult.add_candidate(result, new_candidate)

      assert updated.best_candidate.content == "B"
    end

    test "preserves aggregation_method" do
      c1 = Candidate.new!(%{content: "A"})
      result = GenerationResult.new!([c1], aggregation_method: :majority_vote)

      new_candidate = Candidate.new!(%{content: "B"})
      updated = GenerationResult.add_candidate(result, new_candidate)

      assert updated.aggregation_method == :majority_vote
    end
  end

  describe "to_map/1" do
    test "serializes result to map" do
      c1 = Candidate.new!(%{content: "A", score: 0.5})
      result = GenerationResult.new!([c1], aggregation_method: :best_of_n)

      map = GenerationResult.to_map(result)

      assert is_map(map)
      assert is_list(map["candidates"])
      assert map["total_tokens"] == 0
      assert map["aggregation_method"] == :best_of_n
      assert is_map(map["best_candidate"])
    end

    test "serializes multiple candidates" do
      c1 = Candidate.new!(%{content: "A", tokens_used: 100})
      c2 = Candidate.new!(%{content: "B", tokens_used: 50})

      result = GenerationResult.new!([c1, c2])
      map = GenerationResult.to_map(result)

      assert length(map["candidates"]) == 2
      assert map["total_tokens"] == 150
    end

    test "serializes nil best_candidate as nil" do
      # Result with candidates that have nil scores
      c1 = Candidate.new!(%{content: "A"})
      c2 = Candidate.new!(%{content: "B"})

      result = GenerationResult.new!([c1, c2])
      map = GenerationResult.to_map(result)

      assert map["best_candidate"] == nil
    end

    test "serializes metadata" do
      c1 = Candidate.new!(%{content: "A"})
      metadata = %{temperature: 0.7, model: "test"}

      result = GenerationResult.new!([c1], metadata: metadata)
      map = GenerationResult.to_map(result)

      assert map["metadata"] == metadata
    end
  end

  describe "from_map/1" do
    test "deserializes map with empty candidates" do
      map = %{
        "candidates" => [],
        "total_tokens" => 0,
        "best_candidate" => nil,
        "aggregation_method" => :none,
        "metadata" => %{}
      }

      assert {:ok, result} = GenerationResult.from_map(map)
      assert result.candidates == []
      assert result.total_tokens == 0
    end

    test "deserializes map with single candidate" do
      candidate_map = %{
        "id" => "cand_123",
        "content" => "Answer",
        "score" => 0.9,
        "tokens_used" => 100,
        "model" => "test:model",
        "timestamp" => "2024-01-01T00:00:00Z",
        "reasoning" => nil,
        "metadata" => %{}
      }

      map = %{
        "candidates" => [candidate_map],
        "total_tokens" => 100,
        "best_candidate" => candidate_map,
        "aggregation_method" => :best_of_n,
        "metadata" => %{key: "value"}
      }

      assert {:ok, result} = GenerationResult.from_map(map)

      assert length(result.candidates) == 1
      assert Enum.at(result.candidates, 0).content == "Answer"
      assert result.total_tokens == 100
      assert result.aggregation_method == :best_of_n
      assert result.metadata == %{key: "value"}
    end

    test "deserializes map with multiple candidates" do
      c1_map = %{"id" => "c1", "content" => "A", "score" => 0.5, "tokens_used" => 50}
      c2_map = %{"id" => "c2", "content" => "B", "score" => 0.9, "tokens_used" => 100}

      map = %{
        "candidates" => [c1_map, c2_map],
        "total_tokens" => 150,
        "aggregation_method" => :best_of_n,
        "metadata" => %{}
      }

      assert {:ok, result} = GenerationResult.from_map(map)

      assert length(result.candidates) == 2
      assert result.total_tokens == 150
      # best_candidate should be recomputed as the one with highest score
      assert result.best_candidate.content == "B"
    end

    test "handles candidate with all nil fields" do
      # A candidate map with only invalid fields produces a candidate with nil values
      map = %{
        "candidates" => [%{"invalid" => "data"}],
        "total_tokens" => 0,
        "aggregation_method" => :none,
        "metadata" => %{}
      }

      # This creates a valid result with a candidate that has nil fields
      assert {:ok, result} = GenerationResult.from_map(map)
      assert length(result.candidates) == 1
      assert Enum.at(result.candidates, 0).content == nil
    end

    test "returns error for invalid map" do
      assert {:error, :invalid_map} = GenerationResult.from_map("not a map")
      assert {:error, :invalid_map} = GenerationResult.from_map(123)
    end
  end

  describe "from_map!/1" do
    test "returns result when map is valid" do
      c1_map = %{"id" => "c1", "content" => "A"}

      map = %{
        "candidates" => [c1_map],
        "total_tokens" => 0,
        "aggregation_method" => :none,
        "metadata" => %{}
      }

      result = GenerationResult.from_map!(map)
      assert length(result.candidates) == 1
    end

    test "raises when map is invalid" do
      assert_raise ArgumentError, ~r/Invalid generation result map/, fn ->
        GenerationResult.from_map!("not a map")
      end
    end
  end

  describe "serialization round-trip" do
    test "to_map and from_map are inverses" do
      c1 = Candidate.new!(%{content: "A", score: 0.5, tokens_used: 100})
      c2 = Candidate.new!(%{content: "B", score: 0.9, tokens_used: 200})

      original = GenerationResult.new!([c1, c2], aggregation_method: :best_of_n, metadata: %{key: "value"})

      map = GenerationResult.to_map(original)
      assert {:ok, restored} = GenerationResult.from_map(map)

      assert length(restored.candidates) == length(original.candidates)
      assert restored.total_tokens == original.total_tokens
      assert restored.aggregation_method == original.aggregation_method
      assert restored.metadata == original.metadata
    end

    test "round-trip with nil best_candidate" do
      c1 = Candidate.new!(%{content: "A"})
      c2 = Candidate.new!(%{content: "B"})

      original = GenerationResult.new!([c1, c2])

      map = GenerationResult.to_map(original)
      assert {:ok, restored} = GenerationResult.from_map(map)

      # best_candidate should still be nil (no scores)
      assert restored.best_candidate == nil
    end
  end
end
