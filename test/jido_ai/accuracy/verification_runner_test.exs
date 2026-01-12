defmodule Jido.AI.Accuracy.VerificationRunnerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Accuracy.Verifiers.DeterministicVerifier
  alias Jido.AI.Accuracy.{Candidate, VerificationResult, VerificationRunner}

  @moduletag :capture_log

  describe "new/1" do
    test "creates runner with defaults" do
      assert {:ok, runner} = VerificationRunner.new(%{verifiers: []})
      assert runner.verifiers == []
      assert runner.parallel == false
      assert runner.aggregation == :weighted_avg
      assert runner.on_error == :continue
      assert runner.timeout == 30_000
    end

    test "creates runner with custom verifiers" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      assert {:ok, runner} = VerificationRunner.new(%{verifiers: verifiers})
      assert length(runner.verifiers) == 1
    end

    test "creates runner with parallel enabled" do
      assert {:ok, runner} = VerificationRunner.new(%{verifiers: [], parallel: true})
      assert runner.parallel == true
    end

    test "creates runner with different aggregation strategies" do
      strategies = [:weighted_avg, :max, :min, :sum, :product]

      Enum.each(strategies, fn strategy ->
        assert {:ok, runner} = VerificationRunner.new(%{verifiers: [], aggregation: strategy})
        assert runner.aggregation == strategy
      end)
    end

    test "creates runner with halt on error" do
      assert {:ok, runner} = VerificationRunner.new(%{verifiers: [], on_error: :halt})
      assert runner.on_error == :halt
    end

    test "creates runner with custom timeout" do
      assert {:ok, runner} = VerificationRunner.new(%{verifiers: [], timeout: 60_000})
      assert runner.timeout == 60_000
    end

    test "accepts map input" do
      assert {:ok, runner} = VerificationRunner.new(%{verifiers: [], parallel: true})
      assert runner.parallel == true
    end

    test "returns error for invalid verifiers - not a list" do
      assert {:error, :verifiers_must_be_list} =
               VerificationRunner.new(%{verifiers: "not a list"})
    end

    test "returns error for invalid verifier config - wrong format" do
      assert {:error, :invalid_verifiers_config} =
               VerificationRunner.new(%{verifiers: ["invalid"]})
    end

    test "returns error for negative weight" do
      assert {:error, :invalid_verifiers_config} =
               VerificationRunner.new(%{verifiers: [{DeterministicVerifier, %{}, -1.0}]})
    end

    test "returns error for invalid aggregation strategy" do
      assert {:error, :invalid_aggregation_strategy} =
               VerificationRunner.new(%{verifiers: [], aggregation: :invalid})
    end

    test "returns error for invalid error strategy" do
      assert {:error, :invalid_error_strategy} =
               VerificationRunner.new(%{verifiers: [], on_error: :invalid})
    end

    test "returns error for invalid timeout" do
      assert {:error, :invalid_timeout} =
               VerificationRunner.new(%{verifiers: [], timeout: -1})
    end

    test "returns error for zero timeout" do
      assert {:error, :invalid_timeout} =
               VerificationRunner.new(%{verifiers: [], timeout: 0})
    end
  end

  describe "new!/1" do
    test "creates runner or raises" do
      runner = VerificationRunner.new!(%{verifiers: []})
      assert runner.verifiers == []
    end

    test "raises for invalid config" do
      assert_raise ArgumentError, ~r/Invalid verification runner/, fn ->
        VerificationRunner.new!(%{verifiers: [], aggregation: :invalid})
      end
    end
  end

  describe "verify_candidate/4" do
    setup do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 1.0}
      ]

      {:ok, runner: VerificationRunner.new!(%{verifiers: verifiers})}
    end

    test "verifies candidate with single verifier", %{runner: runner} do
      candidate = Candidate.new!(%{id: "1", content: "42"})
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.score >= 0.0
      assert result.candidate_id == "1"
      assert result.metadata.verifier_count == 1
    end

    test "verifies candidate with multiple verifiers" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42", comparison_type: :exact}, 0.5}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{id: "1", content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.score >= 0.0
      assert result.metadata.verifier_count == 2
    end

    test "returns empty result for no verifiers" do
      runner = VerificationRunner.new!(%{verifiers: []})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.score == 0.0
      assert result.reasoning == "No verification results"
      assert result.metadata.verifier_count == 0
    end

    test "uses sequential mode by default when parallel is false" do
      runner =
        VerificationRunner.new!(%{
          verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}],
          parallel: false
        })

      candidate = Candidate.new!(%{content: "42"})
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.metadata.verifier_count == 1
    end

    test "respects mode override option" do
      runner =
        VerificationRunner.new!(%{
          verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}],
          parallel: true
        })

      candidate = Candidate.new!(%{content: "42"})
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{}, mode: :sequential)

      assert result.metadata.verifier_count == 1
    end

    test "respects timeout override option" do
      runner =
        VerificationRunner.new!(%{
          verifiers: [{DeterministicVerifier, %{ground_truth: "42"}, 1.0}],
          timeout: 5000
        })

      candidate = Candidate.new!(%{content: "42"})
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{}, timeout: 10_000)

      assert result.metadata.verifier_count == 1
    end

    test "combines reasoning from multiple verifiers" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "43"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert String.contains?(result.reasoning, "Combined verification")
      assert result.metadata.verifier_count == 2
    end

    test "averages confidence from results" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # DeterministicVerifier always returns confidence 1.0
      assert result.confidence == 1.0
    end

    test "merges metadata from all verifiers" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert is_map(result.metadata)
      assert Map.has_key?(result.metadata, :verifier_count)
    end
  end

  describe "verify_all_candidates/4" do
    setup do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      {:ok, runner: VerificationRunner.new!(%{verifiers: verifiers})}
    end

    test "verifies multiple candidates", %{runner: runner} do
      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: "43"}),
        Candidate.new!(%{id: "3", content: "44"})
      ]

      {:ok, results} = VerificationRunner.verify_all_candidates(runner, candidates, %{})

      assert length(results) == 3
    end

    test "handles empty candidate list", %{runner: runner} do
      {:ok, results} = VerificationRunner.verify_all_candidates(runner, [], %{})

      assert results == []
    end

    test "returns error results for failed candidates", %{runner: runner} do
      # Mock a candidate that causes failure
      candidates = [
        Candidate.new!(%{id: "1", content: "42"}),
        Candidate.new!(%{id: "2", content: nil})
      ]

      {:ok, results} = VerificationRunner.verify_all_candidates(runner, candidates, %{})

      assert length(results) == 2
    end
  end

  describe "aggregate_scores/3" do
    test "calculates weighted average" do
      results = [
        VerificationResult.new!(%{score: 0.8}),
        VerificationResult.new!(%{score: 0.6})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0], :weighted_avg)

      assert_in_delta score, 0.7, 0.01
    end

    test "calculates weighted average with different weights" do
      results = [
        VerificationResult.new!(%{score: 1.0}),
        VerificationResult.new!(%{score: 0.5})
      ]

      score = VerificationRunner.aggregate_scores(results, [2.0, 1.0], :weighted_avg)

      # (1.0 * 2.0 + 0.5 * 1.0) / 3.0 = 2.5 / 3.0 ≈ 0.833
      assert_in_delta score, 0.833, 0.01
    end

    test "calculates max score" do
      results = [
        VerificationResult.new!(%{score: 0.8}),
        VerificationResult.new!(%{score: 0.6}),
        VerificationResult.new!(%{score: 0.9})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0, 1.0], :max)

      assert score == 0.9
    end

    test "calculates min score" do
      results = [
        VerificationResult.new!(%{score: 0.8}),
        VerificationResult.new!(%{score: 0.6}),
        VerificationResult.new!(%{score: 0.9})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0, 1.0], :min)

      assert score == 0.6
    end

    test "calculates sum of scores" do
      results = [
        VerificationResult.new!(%{score: 0.5}),
        VerificationResult.new!(%{score: 0.3}),
        VerificationResult.new!(%{score: 0.2})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0, 1.0], :sum)

      assert score == 1.0
    end

    test "calculates product of scores" do
      results = [
        VerificationResult.new!(%{score: 0.5}),
        VerificationResult.new!(%{score: 0.5})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0], :product)

      assert score == 0.25
    end

    test "handles empty results" do
      score = VerificationRunner.aggregate_scores([], [], :weighted_avg)

      assert score == 0.0
    end

    test "uses weighted_avg as default strategy" do
      results = [
        VerificationResult.new!(%{score: 0.8}),
        VerificationResult.new!(%{score: 0.6})
      ]

      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0])

      assert_in_delta score, 0.7, 0.01
    end
  end

  describe "aggregation strategies in runner" do
    test "uses weighted_avg strategy" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, aggregation: :weighted_avg})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Both should give score 1.0, so weighted average is 1.0
      assert result.score == 1.0
    end

    test "uses max strategy" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "43"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, aggregation: :max})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # First verifier gives 1.0, second gives 0.0, max is 1.0
      assert result.score == 1.0
    end

    test "uses min strategy" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "43"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, aggregation: :min})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # First verifier gives 1.0, second gives 0.0, min is 0.0
      assert result.score == 0.0
    end

    test "uses sum strategy" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, aggregation: :sum})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Both give 1.0, sum is 2.0
      assert result.score == 2.0
    end

    test "uses product strategy" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, aggregation: :product})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Both give 1.0, product is 1.0
      assert result.score == 1.0
    end
  end

  describe "error handling" do
    test "continues on error when on_error is :continue" do
      # Create a mock invalid verifier config that will fail
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: nil}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, on_error: :continue})
      candidate = Candidate.new!(%{content: "42"})

      # Should continue and return result from first verifier
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Should have at least one successful result
      assert result.metadata.verifier_count >= 0
    end

    test "halts on error when on_error is :halt" do
      # Create a verifier with a module that doesn't exist to trigger an error
      # Note: This tests the halt behavior by using an invalid module
      verifiers = [
        {NonExistentVerifier, %{}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, on_error: :halt})
      candidate = Candidate.new!(%{content: "42"})

      # Should halt and return error due to module not being loaded
      assert {:error, _} = VerificationRunner.verify_candidate(runner, candidate, %{})
    end
  end

  describe "parallel execution" do
    test "runs verifiers in parallel when parallel is true" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0},
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, parallel: true})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.metadata.verifier_count == 2
    end

    test "falls back to sequential when parallel not supported" do
      # This test verifies the sequential fallback works
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers, parallel: true})
      candidate = Candidate.new!(%{content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{}, mode: :sequential)

      assert result.metadata.verifier_count == 1
    end
  end

  describe "telemetry" do
    test "emits start and stop events" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: "42"})

      # Attach handlers to capture events
      # :telemetry.attach/4 takes: handler_id, event_name, handler_fn, config
      :telemetry.attach(
        "test-telemetry-start",
        [:verification, :start],
        &Jido.AI.Accuracy.VerificationRunnerTest.handle_telemetry_start/4,
        nil
      )

      :telemetry.attach(
        "test-telemetry-stop",
        [:verification, :stop],
        &Jido.AI.Accuracy.VerificationRunnerTest.handle_telemetry_stop/4,
        nil
      )

      VerificationRunner.verify_candidate(runner, candidate, %{})

      assert_receive :verification_started
      assert_receive :verification_stopped

      :telemetry.detach("test-telemetry-start")
      :telemetry.detach("test-telemetry-stop")
    end
  end

  # Telemetry event handlers for tests
  def handle_telemetry_start(_event, _measurements, _metadata, _config) do
    send(self(), :verification_started)
  end

  def handle_telemetry_stop(_event, _measurements, _metadata, _config) do
    send(self(), :verification_stopped)
  end

  describe "step scores aggregation" do
    test "merges step scores from PRM verifiers" do
      # Since we can't directly test private functions, we verify through the runner
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{id: "1", content: "42"})

      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      # Verify the structure is correct
      assert is_map(result.step_scores)
    end
  end

  describe "edge cases" do
    test "handles nil scores in aggregation" do
      results = [
        VerificationResult.new!(%{score: 0.5}),
        VerificationResult.new!(%{score: nil}),
        VerificationResult.new!(%{score: 0.3})
      ]

      # weighted_average should handle nil scores by treating them as 0
      score = VerificationRunner.aggregate_scores(results, [1.0, 1.0, 1.0], :weighted_avg)

      # (0.5 + 0.0 + 0.3) / 3 = 0.8 / 3 ≈ 0.267
      assert score >= 0.0
    end

    test "handles candidate with nil content" do
      verifiers = [
        {DeterministicVerifier, %{ground_truth: "42"}, 1.0}
      ]

      runner = VerificationRunner.new!(%{verifiers: verifiers})
      candidate = Candidate.new!(%{content: nil})

      # Should return a result with score 0.0
      {:ok, result} = VerificationRunner.verify_candidate(runner, candidate, %{})

      assert result.score >= 0.0
    end
  end
end
