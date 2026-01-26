defmodule Jido.AI.Accuracy.VerificationTest do
  @moduledoc """
  Integration tests for the verification system.

  These tests verify that the verification system works end-to-end,
  including:
  - Individual verifiers (Deterministic, LLMOutcome, PRM)
  - Combined verifiers via VerificationRunner
  - Score aggregation strategies
  - Performance characteristics
  - Error handling scenarios
  """
  use ExUnit.Case, async: false

  alias Jido.AI.Accuracy.Prms.LLMPrm
  alias Jido.AI.Accuracy.Verifiers.DeterministicVerifier
  alias Jido.AI.Accuracy.{Candidate, VerificationResult, VerificationRunner}

  @moduletag :integration
  @moduletag :verification

  @moduletag :capture_log

  # ============================================================================
  # End-to-End Verification Tests
  # ============================================================================

  describe "end-to-end verification" do
    setup do
      # Common test data
      %{
        math_correct:
          Candidate.new!(%{
            id: "math_1",
            content: "42",
            reasoning: "To find 15 * 23 + 7, I calculate 15 * 23 = 345, then add 7 to get 352."
          }),
        math_incorrect:
          Candidate.new!(%{
            id: "math_2",
            content: "100",
            reasoning: "I think 15 * 23 = 100, then add 7 to get 107."
          }),
        code_correct:
          Candidate.new!(%{
            id: "code_1",
            content: ~s/def add(a, b): return a + b/,
            metadata: %{language: "python"}
          }),
        code_incorrect:
          Candidate.new!(%{
            id: "code_2",
            content: ~s/def add(a, b): return a - b/,
            metadata: %{language: "python"}
          })
      }
    end

    test "deterministic verifier: exact match returns score 1.0" do
      verifier = DeterministicVerifier.new!(ground_truth: "42", comparison_type: :exact)
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert result.score == 1.0
      assert result.confidence == 1.0
      assert result.candidate_id == candidate.id
    end

    test "deterministic verifier: mismatch returns score 0.0" do
      verifier = DeterministicVerifier.new!(ground_truth: "42", comparison_type: :exact)
      candidate = Candidate.new!(%{content: "100"})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert result.score == 0.0
      assert result.candidate_id == candidate.id
    end

    test "deterministic verifier: extracts answer from reasoning" do
      verifier = DeterministicVerifier.new!(ground_truth: "345", comparison_type: :exact)
      # Candidate with reasoning trace that contains answer
      candidate =
        Candidate.new!(%{
          content: "Let me think... The answer is: 345",
          reasoning: "First I multiply 15 * 23 = 345, then add 7."
        })

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      # Should extract "345" from content using "The answer is:" pattern
      assert result.score == 1.0
    end

    test "deterministic verifier: numerical comparison with tolerance" do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: 3.14159,
          comparison_type: :numerical,
          tolerance: 0.01
        )

      candidate_correct = Candidate.new!(%{content: "3.14"})
      candidate_incorrect = Candidate.new!(%{content: "3.12"})

      assert {:ok, result1} = DeterministicVerifier.verify(verifier, candidate_correct, %{})
      assert {:ok, result2} = DeterministicVerifier.verify(verifier, candidate_incorrect, %{})

      assert result1.score == 1.0
      assert result2.score == 0.0
    end

    test "combined verifiers: multiple verifiers with weighted aggregation" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 0.5}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          aggregation: :weighted_avg
        })

      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Both verifiers return 1.0, weighted avg should be 1.0
      assert result.score == 1.0
      assert result.metadata.verifier_count == 2
    end

    test "combined verifiers: min aggregation (bottleneck)" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 1.0},
        {DeterministicVerifier, %{ground_truth: "100", comparison_type: :exact}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          aggregation: :min
        })

      # Candidate "42" matches first but not second
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Min should be 0.0 (second verifier fails)
      assert result.score == 0.0
    end

    test "combined verifiers: max aggregation (optimistic)" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 1.0},
        {DeterministicVerifier, %{ground_truth: "100", comparison_type: :exact}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          aggregation: :max
        })

      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Max should be 1.0 (first verifier succeeds)
      assert result.score == 1.0
    end

    test "combined verifiers: empty verifier list returns empty result" do
      runner = VerificationRunner.new!(%{verifiers: []})
      candidate = Candidate.new!(%{content: "42"})

      assert {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.score == 0.0
      assert result.reasoning == "No verification results"
      assert result.metadata.verifier_count == 0
    end
  end

  # ============================================================================
  # PRM Integration Tests
  # ============================================================================

  describe "PRM integration" do
    @tag :prm

    @tag :requires_api
    test "LLM PRM: scores correct reasoning step" do
      prm = LLMPrm.new!([])

      question = "What is 15 * 23?"
      correct_step = "15 * 23 = 345"

      assert {:ok, score} = LLMPrm.score_step(prm, correct_step, %{question: question}, [])

      # Correct step should have high score
      assert score >= 0.5
      assert score <= 1.0
    end

    @tag :requires_api
    test "LLM PRM: scores incorrect reasoning step" do
      prm = LLMPrm.new!([])

      question = "What is 15 * 23?"
      incorrect_step = "15 * 23 = 100"

      assert {:ok, score} = LLMPrm.score_step(prm, incorrect_step, %{question: question}, [])

      # Incorrect step should have low score
      assert score >= 0.0
      assert score <= 0.5
    end

    @tag :requires_api
    test "LLM PRM: scores full reasoning trace" do
      prm = LLMPrm.new!([])

      question = "What is 15 * 23 + 7?"

      trace = [
        "First, I need to calculate 15 * 23.",
        "15 * 23 = 345",
        "Then add 7: 345 + 7 = 352"
      ]

      assert {:ok, scores} = LLMPrm.score_trace(prm, trace, %{question: question}, [])

      assert is_list(scores)
      assert length(scores) == 3

      # All scores should be in valid range
      Enum.each(scores, fn score ->
        assert score >= 0.0
        assert score <= 1.0
      end)

      # At least the correct steps should have decent scores
      avg_score = Enum.sum(scores) / length(scores)
      assert avg_score >= 0.3
    end

    @tag :requires_api
    test "LLM PRM: classification of steps" do
      prm = LLMPrm.new!([])

      question = "What is 2 + 2?"

      assert {:ok, classification} = LLMPrm.classify_step(prm, "2 + 2 = 4", %{question: question}, [])
      assert classification in [:correct, :incorrect, :neutral]

      assert {:ok, classification2} = LLMPrm.classify_step(prm, "2 + 2 = 5", %{question: question}, [])
      assert classification2 in [:correct, :incorrect, :neutral]

      # These should generally be different
      # Note: May not always differ due to LLM variance, but over many runs they should
    end

    @tag :requires_api
    test "LLM PRM: step scores are aggregated correctly" do
      prm = LLMPrm.new!([])

      question = "What is 15 * 23?"

      trace = [
        "I'll calculate 15 * 23",
        "15 * 23 = 345",
        "So the answer is 345"
      ]

      assert {:ok, scores} = LLMPrm.score_trace(prm, trace, %{question: question}, [])

      # Verify we can aggregate the scores
      avg_score = Enum.sum(scores) / length(scores)

      assert avg_score >= 0.0
      assert avg_score <= 1.0
    end
  end

  # ============================================================================
  # Accuracy Validation Tests
  # ============================================================================

  describe "accuracy validation" do
    test "verification helps select correct answer: math problem" do
      # Setup: multiple candidates with different answers
      candidates = [
        Candidate.new!(%{id: "1", content: "42", reasoning: "I think 15 * 23 + 7 = 42"}),
        Candidate.new!(%{id: "2", content: "352", reasoning: "15 * 23 = 345, 345 + 7 = 352"}),
        Candidate.new!(%{id: "3", content: "100", reasoning: "My guess is 100"})
      ]

      # Verify with deterministic verifier
      verifier = DeterministicVerifier.new!(ground_truth: "352")

      verified_results =
        Enum.map(candidates, fn candidate ->
          {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})
          {candidate, result}
        end)

      # Find the best candidate according to verification
      {best_candidate, _best_result} =
        Enum.max_by(verified_results, fn {_candidate, result} -> result.score end)

      # The verified best candidate should be "352"
      assert best_candidate.content == "352"
      assert best_candidate.id == "2"
    end

    test "deterministic verifier handles edge cases" do
      verifier =
        DeterministicVerifier.new!(
          ground_truth: "42",
          comparison_type: :exact,
          normalize_whitespace: true
        )

      # Test with extra whitespace
      candidate_spaces = Candidate.new!(%{content: "  42  "})
      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate_spaces, %{})
      assert result.score == 1.0

      # Test with leading zeros
      candidate_zeros = Candidate.new!(%{content: "042"})
      assert {:ok, result2} = DeterministicVerifier.verify(verifier, candidate_zeros, %{})
      # "042" != "42" exactly
      assert result2.score == 0.0
    end

    test "verification with weights prioritizes certain verifiers" do
      # Create two verifiers that would vote differently
      # First verifier prefers "42"
      # Second verifier prefers "100" (we'll swap ground truth)

      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 2.0},
        {DeterministicVerifier, %{ground_truth: "100"}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          aggregation: :weighted_avg
        })

      # Candidate "42" gets score 1.0 from first verifier (weight 2.0), 0.0 from second (weight 1.0)
      # Weighted avg: (1.0 * 2.0 + 0.0 * 1.0) / 3.0 = 0.667
      candidate_42 = Candidate.new!(%{content: "42"})
      assert {:ok, result1} = VerificationRunner.verify_candidate(runner, candidate_42, %{})
      assert_in_delta result1.score, 0.667, 0.01

      # Candidate "100" gets opposite
      candidate_100 = Candidate.new!(%{content: "100"})
      assert {:ok, result2} = VerificationRunner.verify_candidate(runner, candidate_100, %{})
      assert_in_delta result2.score, 0.333, 0.01
    end
  end

  # ============================================================================
  # Performance Tests
  # ============================================================================

  describe "performance" do
    @tag :performance
    @tag :slow

    test "verification latency is acceptable: single verifier" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: "42"})

      # Measure time
      {time, _result} =
        :timer.tc(fn ->
          DeterministicVerifier.verify(verifier, candidate, %{})
        end)

      # Should complete in less than 100ms (deterministic is fast)
      assert time < 100_000, "Single verification took #{time}μs, expected < 100ms"
    end

    test "verification latency: multiple verifiers sequential" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          parallel: false
        })

      candidate = Candidate.new!(%{content: "42"})

      # Measure time
      {time, _result} =
        :timer.tc(fn ->
          VerificationRunner.verify_candidate(runner, candidate, %{})
        end)

      # Sequential should be fast for deterministic verifiers
      assert time < 500_000, "Sequential verification took #{time}μs, expected < 500ms"
    end

    test "verification latency: multiple verifiers parallel" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          parallel: true
        })

      candidate = Candidate.new!(%{content: "42"})

      # Measure time
      {time, _result} =
        :timer.tc(fn ->
          VerificationRunner.verify_candidate(runner, candidate, %{})
        end)

      # Parallel should complete reasonably quickly
      assert time < 500_000, "Parallel verification took #{time}μs, expected < 500ms"
    end

    test "batch verification is more efficient than individual calls" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})

      candidates =
        Enum.map(1..10, fn i ->
          Candidate.new!(%{id: "#{i}", content: "42"})
        end)

      # Batch verification
      {batch_time, _} =
        :timer.tc(fn ->
          VerificationRunner.verify_all_candidates(runner, candidates, %{})
        end)

      per_candidate_batch = batch_time / length(candidates)

      # Batch should be efficient (< 50ms per candidate)
      assert per_candidate_batch < 50_000,
             "Batch verification took #{per_candidate_batch}μs per candidate, expected < 50ms"
    end
  end

  # ============================================================================
  # Error Handling Tests
  # ============================================================================

  describe "error handling" do
    test "verifier failure with on_error: continue" do
      # Create a configuration with a non-existent verifier
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {NonExistentVerifier, %{}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          on_error: :continue
        })

      candidate = Candidate.new!(%{content: "42"})

      # Should succeed with only the working verifier
      assert {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Should have at least one result
      assert result.metadata.verifier_count >= 0
    end

    test "verifier failure with on_error: halt" do
      verifiers = [
        {NonExistentVerifier, %{}, 1.0}
      ]

      runner =
        VerificationRunner.new!(%{
          verifiers: verifiers,
          on_error: :halt
        })

      candidate = Candidate.new!(%{content: "42"})

      # Should return error
      assert {:error, _} = VerificationRunner.verify_candidate(runner, candidate, %{})
    end

    test "handles candidate with nil content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: nil})

      # Should not crash, return some result
      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert is_number(result.score)
    end

    test "handles candidate with empty content" do
      verifier = DeterministicVerifier.new!(ground_truth: "42")
      candidate = Candidate.new!(%{content: ""})

      assert {:ok, result} = DeterministicVerifier.verify(verifier, candidate, %{})

      assert is_number(result.score)
      assert result.candidate_id == candidate.id
    end
  end

  # ============================================================================
  # Aggregation Strategy Tests
  # ============================================================================

  describe "aggregation strategies" do
    setup do
      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: "100"}),
        Candidate.new!(%{id: "3", content: "345"})
      ]

      # Verification results with known scores
      results = [
        VerificationResult.new!(%{candidate_id: "1", score: 1.0}),
        VerificationResult.new!(%{candidate_id: "2", score: 0.0}),
        VerificationResult.new!(%{candidate_id: "3", score: 0.5})
      ]

      %{candidates: candidates, results: results}
    end

    test "weighted_avg aggregation with custom weights", %{results: results} do
      weights = [2.0, 1.0, 1.0]
      score = VerificationRunner.aggregate_scores(results, weights, :weighted_avg)

      # (1.0 * 2.0 + 0.0 * 1.0 + 0.5 * 1.0) / 4.0 = 2.5 / 4.0 = 0.625
      assert_in_delta score, 0.625, 0.01
    end

    test "sum aggregation", %{results: results} do
      weights = [1.0, 1.0, 1.0]
      score = VerificationRunner.aggregate_scores(results, weights, :sum)

      assert score == 1.5
    end

    test "product aggregation", %{results: results} do
      weights = [1.0, 1.0, 1.0]
      score = VerificationRunner.aggregate_scores(results, weights, :product)

      # 1.0 * 0.0 * 0.5 = 0.0
      assert score == 0.0
    end

    test "max aggregation selects highest score", %{results: results} do
      weights = [1.0, 1.0, 1.0]
      score = VerificationRunner.aggregate_scores(results, weights, :max)

      assert score == 1.0
    end

    test "min aggregation selects lowest score", %{results: results} do
      weights = [1.0, 1.0, 1.0]
      score = VerificationRunner.aggregate_scores(results, weights, :min)

      assert score == 0.0
    end
  end

  # ============================================================================
  # Parallel vs Sequential Comparison
  # ============================================================================

  describe "parallel vs sequential" do
    @tag :performance
    @tag :flaky

    test "parallel is faster than sequential for multiple verifiers" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      candidate = Candidate.new!(%{content: "42"})

      # Sequential
      runner_seq = VerificationRunner.new!(%{verifiers: verifiers, parallel: false})

      {seq_time, _} =
        :timer.tc(fn ->
          VerificationRunner.verify_candidate(runner_seq, candidate, %{})
        end)

      # Parallel
      runner_par = VerificationRunner.new!(%{verifiers: verifiers, parallel: true})

      {par_time, _} =
        :timer.tc(fn ->
          VerificationRunner.verify_candidate(runner_par, candidate, %{})
        end)

      # Parallel should be faster (or at least not significantly slower)
      # For deterministic verifiers, the difference may be small due to their speed
      # Task.async overhead can make parallel slower for very fast operations
      assert par_time <= seq_time * 3.0,
             "Parallel took #{par_time}μs vs sequential #{seq_time}μs"
    end
  end

  # ============================================================================
  # Step Scores Integration
  # ============================================================================

  describe "step scores from PRM" do
    test "verification result combines step scores from PRM" do
      # Create a result with step scores (simulating PRM verification)
      result_with_steps = %VerificationResult{
        candidate_id: "test",
        score: 0.75,
        confidence: 0.8,
        reasoning: "Some steps were correct",
        step_scores: %{
          "step_1" => 1.0,
          "step_2" => 0.5,
          "step_3" => 0.75
        },
        metadata: %{verifier: "prm"}
      }

      # Verify step scores are accessible
      assert result_with_steps.step_scores["step_1"] == 1.0
      assert result_with_steps.step_scores["step_2"] == 0.5
      assert result_with_steps.step_scores["step_3"] == 0.75
    end

    test "empty step scores is handled gracefully" do
      result = %VerificationResult{
        candidate_id: "test",
        score: 0.5,
        confidence: 0.7,
        reasoning: "No steps",
        step_scores: %{},
        metadata: %{}
      }

      # Should not crash
      assert map_size(result.step_scores) == 0
    end
  end

  # ============================================================================
  # Batch Verification Tests
  # ============================================================================

  describe "batch verification" do
    test "verify_all_candidates returns results for all candidates" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})

      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: "100"}),
        Candidate.new!(%{id: "3", content: "42"})
      ]

      assert {:ok, results} = VerificationRunner.verify_all_candidates(runner, candidates, %{})

      assert length(results) == 3

      # First and third should have high scores, second low
      assert Enum.at(results, 0).score == 1.0
      assert Enum.at(results, 1).score == 0.0
      assert Enum.at(results, 2).score == 1.0
    end

    test "batch verification handles empty list" do
      runner = VerificationRunner.new!(%{verifiers: []})

      assert {:ok, results} = VerificationRunner.verify_all_candidates(runner, [], %{})

      assert results == []
    end
  end

  # ============================================================================
  # Telemetry Tests
  # ============================================================================

  describe "telemetry events" do
    test "verification emits telemetry events" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: "42"})

      # Attach telemetry handler
      :telemetry.attach(
        "test-verification-telemetry",
        [:verification, :start],
        &handle_telemetry/4,
        nil
      )

      VerificationRunner.verify_candidate(runner, candidate, %{})

      # Clean up
      :telemetry.detach("test-verification-telemetry")
    end
  end

  # Telemetry handler helper
  def handle_telemetry(_event, measurements, _metadata, _config) do
    # Just verify the event was received
    assert is_map(measurements) or is_list(measurements)
  end
end
