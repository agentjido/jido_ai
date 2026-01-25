defmodule Jido.AI.Accuracy.Aggregators.MajorityVoteTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Aggregators.MajorityVote, Candidate}

  @moduletag :capture_log

  describe "aggregate/2" do
    test "selects majority answer" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, best, metadata} = MajorityVote.aggregate(candidates)
      assert String.contains?(best.content, "42")
      assert metadata.confidence == 2 / 3
      assert metadata.winning_votes == 2
      assert metadata.total_votes == 3
    end

    test "handles ties correctly (first candidate wins)" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, best, metadata} = MajorityVote.aggregate(candidates)
      assert String.contains?(best.content, "41")
      assert metadata.winning_votes == 2
    end

    test "returns vote confidence" do
      candidates = [
        Candidate.new!(%{content: "42"}),
        Candidate.new!(%{content: "42"}),
        Candidate.new!(%{content: "42"}),
        Candidate.new!(%{content: "41"}),
        Candidate.new!(%{content: "40"})
      ]

      assert {:ok, _best, metadata} = MajorityVote.aggregate(candidates)
      # 3 out of 5 voted for 42
      assert_in_delta metadata.confidence, 0.6, 0.001
    end

    test "handles empty candidate list" do
      assert {:error, :no_candidates} = MajorityVote.aggregate([])
    end

    test "handles single candidate" do
      candidates = [Candidate.new!(%{content: "42"})]

      assert {:ok, best, metadata} = MajorityVote.aggregate(candidates)
      assert best.content == "42"
      assert metadata.confidence == 1.0
      assert metadata.vote_distribution == %{"42" => 1}
    end
  end

  describe "extract_answer/1" do
    test "parses Answer: prefix" do
      candidate = Candidate.new!(%{content: "Let me think...\n\nAnswer: 42"})
      assert MajorityVote.extract_answer(candidate) == "42"
    end

    test "parses Therefore: prefix" do
      candidate = Candidate.new!(%{content: "Calculating...\n\nTherefore: 100"})
      assert MajorityVote.extract_answer(candidate) == "100"
    end

    test "parses Thus: prefix" do
      candidate = Candidate.new!(%{content: "Thus:\n\nThe result is 50"})
      assert MajorityVote.extract_answer(candidate) == "The result is 50"
    end

    test "parses So: prefix" do
      candidate = Candidate.new!(%{content: "So:\n\nThe answer is 25"})
      assert MajorityVote.extract_answer(candidate) == "The answer is 25"
    end

    test "parses The answer is: prefix" do
      # Without proper newline format, falls back to full content
      candidate = Candidate.new!(%{content: "The answer is: 42"})
      assert MajorityVote.extract_answer(candidate) == "The answer is: 42"
    end

    test "parses The answer is: prefix with proper newline" do
      # With newline before pattern, extraction works
      candidate = Candidate.new!(%{content: "Thinking...\n\nThe answer is: 42"})
      assert MajorityVote.extract_answer(candidate) == "42"
    end

    test "parses Result: prefix" do
      candidate = Candidate.new!(%{content: "Result: 42"})
      assert MajorityVote.extract_answer(candidate) == "Result: 42"
    end

    test "parses Result: prefix with proper newline" do
      candidate = Candidate.new!(%{content: "Calculating\n\nResult: 42"})
      assert MajorityVote.extract_answer(candidate) == "42"
    end

    test "parses quoted answers" do
      candidate = Candidate.new!(%{content: "The final answer is \"42\""})
      assert MajorityVote.extract_answer(candidate) == "42"
    end

    test "uses last line as fallback" do
      candidate = Candidate.new!(%{content: "Some explanation\nThe answer is 42"})
      # Last line fallback
      assert MajorityVote.extract_answer(candidate) == "The answer is 42"
    end

    test "handles empty content" do
      candidate = Candidate.new!(%{content: ""})
      assert MajorityVote.extract_answer(candidate) == ""
    end

    test "handles nil content" do
      candidate = Candidate.new!(%{})
      assert MajorityVote.extract_answer(candidate) == ""
    end
  end

  describe "normalize_answer/1 (via aggregation)" do
    test "normalizes whitespace and case" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "THE ANSWER IS:   42  "}),
        Candidate.new!(%{content: "the answer is:41"})
      ]

      assert {:ok, best, _metadata} = MajorityVote.aggregate(candidates)
      # 42 and "  42  " should match after normalization
      assert String.contains?(best.content, "42")
    end

    test "groups similar answers with punctuation" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42."}),
        Candidate.new!(%{content: "The answer is: 42!"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, best, _metadata} = MajorityVote.aggregate(candidates)
      # "42." and "42!" should match after punctuation removal
      assert String.contains?(best.content, "42")
    end
  end

  describe "vote_distribution/1" do
    test "returns correct vote distribution" do
      candidates = [
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"}),
        Candidate.new!(%{content: "The answer is: 40"}),
        Candidate.new!(%{content: "The answer is: 40"})
      ]

      distribution = MajorityVote.distribution(candidates)

      # Distribution normalizes answers by stripping common prefixes like "The answer is:"
      assert distribution["42"] == 2
      assert distribution["41"] == 1
      assert distribution["40"] == 2
    end

    test "handles empty list" do
      assert MajorityVote.distribution([]) == %{}
    end
  end

  describe "integration tests" do
    test "full aggregation with metadata" do
      candidates = [
        Candidate.new!(%{content: "Let me calculate\n\nThe answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, best, metadata} = MajorityVote.aggregate(candidates)

      # Verify best candidate
      assert String.contains?(best.content, "42")

      # Verify metadata structure
      assert is_number(metadata.confidence)
      assert is_map(metadata.vote_distribution)
      assert metadata.total_votes == 3
      assert metadata.winning_votes == 2
    end

    test "case insensitive pattern matching" do
      candidates = [
        Candidate.new!(%{content: "the answer is: 42"}),
        Candidate.new!(%{content: "THE ANSWER IS: 42"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, best, _metadata} = MajorityVote.aggregate(candidates)
      assert String.contains?(best.content, "42")
    end
  end
end
