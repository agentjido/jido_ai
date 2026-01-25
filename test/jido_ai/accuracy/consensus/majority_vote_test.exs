defmodule Jido.AI.Accuracy.Consensus.MajorityVoteTest do
  @moduledoc """
  Tests for the MajorityVote consensus checker.
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.{Candidate, Consensus.MajorityVote}

  describe "new/1" do
    test "creates checker with default threshold" do
      assert {:ok, checker} = MajorityVote.new(%{})
      assert %MajorityVote{} = checker
      # Default threshold is 0.8 from the struct field default
      assert checker.threshold == 0.8
    end

    test "creates checker with custom threshold" do
      assert {:ok, checker} = MajorityVote.new(%{threshold: 0.9})
      assert checker.threshold == 0.9
    end

    test "returns error for invalid threshold" do
      assert {:error, :invalid_threshold} = MajorityVote.new(%{threshold: 1.5})
    end

    test "returns error for negative threshold" do
      assert {:error, :invalid_threshold} = MajorityVote.new(%{threshold: -0.1})
    end
  end

  describe "new!/1" do
    test "creates checker or raises" do
      checker = MajorityVote.new!(%{})
      assert %MajorityVote{} = checker
    end

    test "raises for invalid threshold" do
      assert_raise ArgumentError, ~r/Invalid MajorityVote/, fn ->
        MajorityVote.new!(%{threshold: 2.0})
      end
    end
  end

  describe "check/2" do
    test "returns true when consensus reached" do
      checker = MajorityVote.new!(%{threshold: 0.7})

      # Use proper answer format for majority voting
      candidates = [
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 42"}),
        Candidate.new!(%{content: "The answer is: 41"})
      ]

      assert {:ok, true, agreement} = MajorityVote.check(checker, candidates)
      # 3 out of 4
      assert agreement == 0.75
    end

    test "returns false when consensus not reached" do
      checker = MajorityVote.new!(%{threshold: 0.8})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: B"}),
        Candidate.new!(%{content: "The answer is: B"})
      ]

      assert {:ok, false, agreement} = MajorityVote.check(checker, candidates)
      # 2 out of 4
      assert agreement == 0.5
    end

    test "returns 1.0 agreement for unanimous candidates" do
      checker = MajorityVote.new!(%{threshold: 0.9})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: A"})
      ]

      assert {:ok, true, 1.0} = MajorityVote.check(checker, candidates)
    end

    test "returns true for single candidate" do
      checker = MajorityVote.new!(%{threshold: 0.5})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"})
      ]

      # With only 1 candidate, agreement is 1.0 (1/1)
      # So it should be true since threshold is 0.5
      assert {:ok, true, 1.0} = MajorityVote.check(checker, candidates)
    end

    test "returns error for empty candidates" do
      checker = MajorityVote.new!(%{threshold: 0.8})

      assert {:error, :no_candidates} = MajorityVote.check(checker, [])
    end
  end

  describe "check/2 with options" do
    test "uses threshold from options" do
      _checker = MajorityVote.new!(%{})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: A"}),
        Candidate.new!(%{content: "The answer is: B"})
      ]

      # With threshold 0.6, should pass (2/3 = 0.67)
      assert {:ok, true, agreement} = MajorityVote.check(candidates, threshold: 0.6)
      assert agreement > 0.6

      # With threshold 0.7, should fail
      assert {:ok, false, ^agreement} = MajorityVote.check(candidates, threshold: 0.7)
    end

    test "returns error for invalid threshold in options" do
      _checker = MajorityVote.new!(%{})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"})
      ]

      assert {:error, :invalid_threshold} = MajorityVote.check(candidates, threshold: 1.5)
    end

    test "returns error when no threshold provided" do
      checker = MajorityVote.new!(%{})

      candidates = [
        Candidate.new!(%{content: "The answer is: A"})
      ]

      assert {:error, :no_threshold} = MajorityVote.check(candidates, [])
    end
  end

  describe "ConsensusChecker.consensus_checker?/1" do
    alias Jido.AI.Accuracy.ConsensusChecker

    test "returns true for MajorityVote module" do
      assert ConsensusChecker.consensus_checker?(MajorityVote)
    end

    test "returns false for other modules" do
      refute ConsensusChecker.consensus_checker?(String)
    end
  end

  describe "ConsensusChecker.behaviour/0" do
    alias Jido.AI.Accuracy.ConsensusChecker

    test "returns the ConsensusChecker behavior module" do
      assert ConsensusChecker.behaviour() == ConsensusChecker
    end
  end
end
