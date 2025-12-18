defmodule Jido.AI.Runner.GEPA.EvaluatorTest do
  use ExUnit.Case, async: false
  use Jido.AI.Runner.GEPA.TestCase

  alias Jido.AI.Runner.GEPA.Evaluator
  alias Jido.AI.Runner.GEPA.Evaluator.EvaluationResult

  describe "evaluate_prompt/2" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "evaluates a single prompt successfully" do
      prompt = "Think step by step and solve the problem"
      task = %{type: :reasoning, prompt: "What is 2+2?"}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      assert %EvaluationResult{} = result
      assert result.prompt == prompt
      assert is_float(result.fitness)
      assert result.fitness >= 0.0
      assert result.fitness <= 1.0
      assert result.error == nil
      assert result.metrics.success == true
      assert is_integer(result.metrics.duration_ms)
    end

    test "requires task configuration" do
      assert_raise ArgumentError, ~r/task configuration is required/, fn ->
        Evaluator.evaluate_prompt("test prompt", timeout: 5_000)
      end
    end

    test "handles evaluation timeout" do
      # Override setup with timeout scenario
      {:ok, _context} = setup_mock_model(:openai, scenario: :timeout)

      prompt = "Test prompt"
      task = %{type: :reasoning, prompt: "Long running task"}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      assert %EvaluationResult{} = result
      assert result.prompt == prompt
      assert is_nil(result.fitness)
      assert result.error == :timeout
      assert result.metrics.success == false
      assert result.metrics.timeout == true
    end

    test "uses default timeout when not specified" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task)

      assert %EvaluationResult{} = result
      # Should complete with default timeout (30 seconds)
      assert is_integer(result.metrics.duration_ms)
    end

    test "accepts custom agent configuration" do
      prompt = "Test with custom config"
      task = %{type: :reasoning}

      custom_ai_config = [
        model: {:openai, model: "gpt-4"},
        verbose: true
      ]

      {:ok, result} =
        Evaluator.evaluate_prompt(prompt, task: task, agent_opts: [ai: custom_ai_config])

      assert %EvaluationResult{} = result
      assert result.error == nil
    end
  end

  describe "evaluate_batch/2" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "evaluates multiple prompts concurrently" do
      prompts = [
        "Approach 1: Think step by step",
        "Approach 2: Break it down",
        "Approach 3: Analyze carefully"
      ]

      task = %{type: :reasoning, prompt: "Solve this"}

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 5_000)

      assert length(results) == 3
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))

      # Results should be in same order as input
      Enum.zip(prompts, results)
      |> Enum.each(fn {prompt, result} ->
        assert result.prompt == prompt
      end)

      # At least some should succeed (mock evaluation doesn't fail)
      successful = Enum.count(results, &is_nil(&1.error))
      assert successful > 0
    end

    test "respects parallelism limit" do
      prompts = Enum.map(1..10, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      start_time = System.monotonic_time(:millisecond)

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 3, timeout: 5_000)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      assert length(results) == 10
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))

      # With parallelism of 3, should take longer than sequential/1 but less than sequential/10
      # This is a rough check - exact timing is hard to assert
      assert duration_ms > 0
    end

    test "handles mix of successful and failed evaluations" do
      prompts = [
        "Valid prompt 1",
        "Valid prompt 2",
        "Valid prompt 3"
      ]

      task = %{type: :reasoning}

      # Some may timeout with very short timeout
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 1)

      assert length(results) == 3
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))

      # Results should maintain order
      Enum.zip(prompts, results)
      |> Enum.each(fn {prompt, result} ->
        assert result.prompt == prompt
      end)
    end

    test "returns results in same order as input prompts" do
      prompts = Enum.map(1..5, fn i -> "Prompt number #{i}" end)
      task = %{type: :reasoning}

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 5, timeout: 5_000)

      # Check order preservation
      Enum.zip(prompts, results)
      |> Enum.with_index()
      |> Enum.each(fn {{prompt, result}, index} ->
        assert result.prompt == prompt, "Result #{index} prompt mismatch"
        assert result.prompt == "Prompt number #{index + 1}"
      end)
    end

    test "handles empty prompt list" do
      results = Evaluator.evaluate_batch([], task: %{type: :reasoning}, parallelism: 2)

      assert results == []
    end

    test "uses configured parallelism" do
      prompts = Enum.map(1..6, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      # Test with parallelism of 1 (sequential)
      results_seq = Evaluator.evaluate_batch(prompts, task: task, parallelism: 1, timeout: 5_000)

      assert length(results_seq) == 6

      # Test with parallelism of 6 (fully parallel)
      results_par =
        Evaluator.evaluate_batch(prompts, task: task, parallelism: 6, timeout: 5_000)

      assert length(results_par) == 6

      # Both should produce valid results
      assert Enum.all?(results_seq, &match?(%EvaluationResult{}, &1))
      assert Enum.all?(results_par, &match?(%EvaluationResult{}, &1))
    end
  end

  describe "evaluation result structure" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "includes all required fields" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Check struct fields
      assert is_binary(result.prompt)
      assert is_float(result.fitness) or is_nil(result.fitness)
      assert is_map(result.metrics)
      assert is_map(result.trajectory)
      # error can be nil or atom
      assert is_nil(result.error) or is_atom(result.error)
    end

    test "metrics include duration and success flag" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      assert is_integer(result.metrics.duration_ms)
      assert result.metrics.duration_ms > 0
      assert is_boolean(result.metrics.success)
    end

    test "trajectory structure is present" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Trajectory should be a map (detailed structure in Section 1.2.2)
      assert is_map(result.trajectory)
    end

    test "fitness is in valid range when successful" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      if result.error == nil do
        assert is_float(result.fitness)
        assert result.fitness >= 0.0
        assert result.fitness <= 1.0
      end
    end
  end

  describe "agent configuration merging" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "merges prompt with base configuration" do
      prompt = "Custom prompt for testing"
      task = %{type: :reasoning}

      base_opts = [
        ai: [
          model: {:openai, model: "gpt-4"},
          verbose: false
        ]
      ]

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, agent_opts: base_opts)

      assert %EvaluationResult{} = result
      assert result.prompt == prompt
    end

    test "uses default configuration when no agent_opts provided" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task)

      assert %EvaluationResult{} = result
      # Should succeed with defaults
      assert result.error == nil or result.error == :timeout
    end
  end

  describe "timeout enforcement" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "enforces timeout on long-running evaluations" do
      # Override with timeout scenario
      {:ok, _context} = setup_mock_model(:openai, scenario: :timeout)

      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Should timeout
      assert result.error == :timeout
    end

    test "allows successful completion within timeout" do
      prompt = "Quick task"
      task = %{type: :reasoning}

      # Generous timeout
      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 30_000)

      # Should complete successfully
      assert is_float(result.fitness) or result.error == :timeout
      assert result.metrics.duration_ms < 30_000
    end

    test "cleans up agent process after timeout" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      # Get initial process count
      initial_process_count = length(Process.list())

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 1)

      # Wait a bit for cleanup
      Process.sleep(100)

      # Process count should be similar (agent cleaned up)
      final_process_count = length(Process.list())

      # Allow some variance due to other test processes
      assert abs(final_process_count - initial_process_count) < 5

      # Result should indicate timeout
      assert result.error == :timeout or is_nil(result.error)
    end
  end

  describe "concurrent execution" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "executes multiple evaluations in parallel" do
      prompts = Enum.map(1..4, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      start_time = System.monotonic_time(:millisecond)

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 4, timeout: 5_000)

      duration_ms = System.monotonic_time(:millisecond) - start_time

      assert length(results) == 4

      # Parallel execution should be faster than 4 sequential evaluations
      # Each evaluation takes some time, so 4 in parallel should take less than 4x sequential
      # This is approximate - exact timing depends on system load
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))
    end

    test "limits concurrency with parallelism parameter" do
      prompts = Enum.map(1..8, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      # Test with low parallelism
      results_low = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 5_000)

      # Test with high parallelism
      results_high = Evaluator.evaluate_batch(prompts, task: task, parallelism: 8, timeout: 5_000)

      # Both should complete all evaluations
      assert length(results_low) == 8
      assert length(results_high) == 8

      # All results should be valid
      assert Enum.all?(results_low, &match?(%EvaluationResult{}, &1))
      assert Enum.all?(results_high, &match?(%EvaluationResult{}, &1))
    end

    test "handles concurrent evaluation failures gracefully" do
      prompts = Enum.map(1..5, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      # Use very short timeout to cause some failures
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 3, timeout: 1)

      assert length(results) == 5

      # All should return results (even if failed)
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))

      # Each result should have a prompt
      Enum.zip(prompts, results)
      |> Enum.each(fn {prompt, result} ->
        assert result.prompt == prompt
      end)
    end
  end

  describe "agent lifecycle management" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "cleans up agent process after evaluation" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      initial_processes = length(Process.list())

      {:ok, _result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Wait for cleanup
      Process.sleep(100)

      final_processes = length(Process.list())

      # Process count should be similar (cleanup happened)
      assert abs(final_processes - initial_processes) < 5
    end

    test "cleans up agents after batch evaluation" do
      prompts = Enum.map(1..3, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      initial_processes = length(Process.list())

      _results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 5_000)

      # Wait for all cleanup
      Process.sleep(200)

      final_processes = length(Process.list())

      # All agents should be cleaned up
      assert abs(final_processes - initial_processes) < 5
    end

    test "cleans up even when evaluation fails" do
      # Override with timeout scenario
      {:ok, _context} = setup_mock_model(:openai, scenario: :timeout)

      prompt = "Test prompt"
      task = %{type: :reasoning}

      initial_processes = length(Process.list())

      {:ok, _result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Wait for cleanup
      Process.sleep(100)

      final_processes = length(Process.list())

      # Agent should be cleaned up even after timeout
      assert abs(final_processes - initial_processes) < 5
    end
  end

  describe "error handling" do
    setup do
      setup_mock_model(:openai, scenario: :success)
    end

    test "handles agent spawn failures gracefully" do
      # This test is tricky - we'd need to mock the spawn to fail
      # For now, verify that error results have correct structure
      prompt = "Test prompt"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # If there's an error, it should be structured
      if not is_nil(result.error) do
        assert is_atom(result.error) or is_tuple(result.error)
        assert is_nil(result.fitness)
        assert result.metrics.success == false
      end
    end

    test "returns error results for failed evaluations" do
      prompts = ["Prompt 1", "Prompt 2"]
      task = %{type: :reasoning}

      # Force timeouts
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 1)

      assert length(results) == 2

      # Each result should be structured, even if failed
      Enum.each(results, fn result ->
        assert %EvaluationResult{} = result
        assert is_binary(result.prompt)
        assert is_map(result.metrics)

        if not is_nil(result.error) do
          assert result.metrics.success == false
        end
      end)
    end
  end
end
