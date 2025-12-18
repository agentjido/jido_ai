defmodule Jido.AI.Runner.GEPA.EvaluationSystemIntegrationTest do
  @moduledoc """
  Integration tests for Section 1.2 - Prompt Evaluation System.

  Tests the complete evaluation pipeline integrating:
  - Evaluator (1.2.1): Agent spawning and evaluation
  - Trajectory (1.2.2): Execution path collection
  - Metrics (1.2.3): Statistical aggregation
  - ResultCollector (1.2.4): Async result synchronization

  These tests validate that all components work together correctly in realistic
  evaluation scenarios with various configurations, concurrency levels, and
  failure conditions.

  ## Requirements

  These integration tests require:
  - OpenAI API key configured in environment (`OPENAI_API_KEY`)
  - Network connectivity to OpenAI API
  - Sufficient API rate limits

  To run these tests:
  ```
  OPENAI_API_KEY=your_key mix test --include integration
  ```

  To skip these tests (default):
  ```
  mix test --exclude integration
  ```
  """

  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluator
  alias Jido.AI.Runner.GEPA.Evaluator.EvaluationResult
  alias Jido.AI.Runner.GEPA.Metrics
  alias Jido.AI.Runner.GEPA.ResultCollector
  alias Jido.AI.Runner.GEPA.Trajectory

  # Tag integration tests to allow skipping when API is not configured
  @moduletag :integration
  @moduletag :requires_api

  describe "agent spawning with various configurations (1.2 Unit Test: Agent Spawning)" do
    test "evaluates prompts with default configuration" do
      prompt = "Solve this step by step"
      task = %{type: :reasoning, prompt: "What is 2+2?"}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      assert %EvaluationResult{} = result
      assert result.prompt == prompt
      assert is_float(result.fitness) or is_nil(result.fitness)
      assert result.metrics.success == true or result.metrics.timeout == true
      assert %Trajectory{} = result.trajectory
    end

    test "evaluates prompts with custom parallelism" do
      prompts = Enum.map(1..6, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      # Low parallelism
      results_low = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 5_000)
      assert length(results_low) == 6
      assert Enum.all?(results_low, &match?(%EvaluationResult{}, &1))

      # High parallelism
      results_high = Evaluator.evaluate_batch(prompts, task: task, parallelism: 6, timeout: 5_000)
      assert length(results_high) == 6
      assert Enum.all?(results_high, &match?(%EvaluationResult{}, &1))

      # Both should produce valid trajectories
      assert Enum.all?(results_low, fn r -> match?(%Trajectory{}, r.trajectory) end)
      assert Enum.all?(results_high, fn r -> match?(%Trajectory{}, r.trajectory) end)
    end

    test "evaluates prompts with custom timeout values" do
      prompt = "Test prompt"
      task = %{type: :reasoning}

      # Short timeout
      {:ok, result_short} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 100)
      assert %EvaluationResult{} = result_short
      assert %Trajectory{} = result_short.trajectory

      # Long timeout
      {:ok, result_long} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 10_000)
      assert %EvaluationResult{} = result_long
      assert %Trajectory{} = result_long.trajectory

      # Both should have trajectory with timing data
      if result_short.trajectory.completed_at do
        assert is_integer(result_short.trajectory.duration_ms)
      end

      if result_long.trajectory.completed_at do
        assert is_integer(result_long.trajectory.duration_ms)
      end
    end

    test "evaluates prompts with custom agent configuration" do
      prompt = "Custom config test"
      task = %{type: :reasoning}

      custom_opts = [
        ai: [
          model: {:openai, model: "gpt-4"},
          verbose: false
        ]
      ]

      {:ok, result} =
        Evaluator.evaluate_prompt(prompt, task: task, agent_opts: custom_opts, timeout: 5_000)

      assert %EvaluationResult{} = result
      assert result.prompt == prompt
      assert %Trajectory{} = result.trajectory
      assert result.trajectory.metadata[:prompt] == prompt
    end

    test "handles agent configuration variations" do
      prompt = "Config variation test"
      task = %{type: :reasoning}

      configs = [
        [],
        [ai: [verbose: true]],
        [ai: [model: {:openai, model: "gpt-4"}]]
      ]

      results =
        for config <- configs do
          {:ok, result} =
            Evaluator.evaluate_prompt(prompt, task: task, agent_opts: config, timeout: 5_000)

          result
        end

      assert length(results) == 3
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))
      assert Enum.all?(results, fn r -> match?(%Trajectory{}, r.trajectory) end)
    end
  end

  describe "trajectory collection completeness (1.2 Unit Test: Trajectory Collection)" do
    test "captures all trajectory steps during evaluation" do
      prompt = "Test trajectory capture"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      assert %EvaluationResult{} = result
      assert %Trajectory{} = result.trajectory

      trajectory = result.trajectory

      # Should have steps recorded
      assert is_list(trajectory.steps)
      assert length(trajectory.steps) > 0

      # Each step should have required fields
      for step <- trajectory.steps do
        assert %Trajectory.Step{} = step
        assert is_binary(step.id)
        assert step.type in [:reasoning, :action, :observation, :tool_call, :state_change]
        assert step.content != nil
        assert %DateTime{} = step.timestamp
        assert step.importance in [:low, :medium, :high, :critical]
      end
    end

    test "captures state snapshots during evaluation" do
      prompt = "Test snapshot capture"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory
      assert is_list(trajectory.state_snapshots)

      # Should have at least one snapshot (final state)
      if length(trajectory.state_snapshots) > 0 do
        for snapshot <- trajectory.state_snapshots do
          assert %Trajectory.StateSnapshot{} = snapshot
          assert is_binary(snapshot.id)
          assert %DateTime{} = snapshot.timestamp
          assert is_map(snapshot.state)
          assert is_atom(snapshot.reason)
        end
      end
    end

    test "records complete timing data in trajectory" do
      prompt = "Test timing data"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory

      # Trajectory timing
      assert %DateTime{} = trajectory.started_at

      if trajectory.completed_at do
        assert %DateTime{} = trajectory.completed_at
        assert is_integer(trajectory.duration_ms)
        assert trajectory.duration_ms >= 0

        # Duration should match the time difference
        calculated_duration =
          DateTime.diff(trajectory.completed_at, trajectory.started_at, :millisecond)

        # Allow small variance due to timing precision
        assert abs(calculated_duration - trajectory.duration_ms) < 10
      end
    end

    test "preserves trajectory metadata throughout evaluation" do
      prompt = "Metadata preservation test"
      task = %{type: :reasoning, id: "test_task_123"}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory

      # Metadata should be preserved
      assert is_map(trajectory.metadata)
      assert trajectory.metadata[:prompt] == prompt
      assert trajectory.metadata[:task_type] == :reasoning
    end

    test "records outcome correctly in trajectory" do
      prompt = "Outcome test"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory

      # Outcome should be set
      assert trajectory.outcome in [:success, :failure, :timeout, :error, :partial, nil]

      # Outcome should match result error state
      if is_nil(result.error) do
        assert trajectory.outcome == :success
      end
    end

    test "maintains trajectory step ordering" do
      prompt = "Step ordering test"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory

      if length(trajectory.steps) > 1 do
        # Steps should be chronologically ordered
        timestamps =
          trajectory.steps
          |> Enum.map(& &1.timestamp)
          |> Enum.map(&DateTime.to_unix(&1, :microsecond))

        sorted_timestamps = Enum.sort(timestamps)
        assert timestamps == sorted_timestamps
      end
    end

    test "trajectory statistics are accurate" do
      prompt = "Statistics test"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      trajectory = result.trajectory
      stats = Trajectory.statistics(trajectory)

      # Statistics should match actual trajectory data
      assert stats.total_steps == length(trajectory.steps)
      assert stats.total_snapshots == length(trajectory.state_snapshots)
      assert stats.duration_ms == trajectory.duration_ms
      assert stats.outcome == trajectory.outcome
      assert is_map(stats.step_types)
      assert is_map(stats.importance_distribution)
    end
  end

  describe "metrics aggregation accuracy (1.2 Unit Test: Metrics Aggregation)" do
    test "aggregates metrics from single evaluation correctly" do
      prompt = "Single evaluation metrics"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      # Result should contain aggregated metrics
      assert is_map(result.metrics)
      assert is_boolean(result.metrics.success)

      if result.error == nil do
        assert result.metrics.success == true
        assert is_float(result.fitness)
        assert result.fitness >= 0.0 and result.fitness <= 1.0
      end
    end

    test "calculates fitness from trajectory metrics" do
      prompt = "Fitness calculation test"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)

      if result.error == nil do
        # Fitness should be calculated from metrics
        assert is_float(result.fitness)

        # Should have aggregated metrics
        assert is_map(result.metrics.aggregated)

        # Aggregated metrics should include statistical measures
        for {_metric_type, stats} <- result.metrics.aggregated do
          assert is_float(stats.mean)
          assert is_float(stats.median)
          assert is_float(stats.variance)
          assert is_float(stats.std_dev)
          assert is_number(stats.min)
          assert is_number(stats.max)
          assert is_integer(stats.count)
        end
      end
    end

    test "aggregates metrics across multiple evaluations" do
      prompts = Enum.map(1..5, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 3, timeout: 5_000)

      # Collect all metrics into one collection
      all_metrics = Metrics.new()

      all_metrics =
        Enum.reduce(results, all_metrics, fn result, acc ->
          if result.error == nil and result.metrics.aggregated do
            # Add each metric from the result
            Enum.reduce(result.metrics.aggregated, acc, fn {metric_type, stats}, acc2 ->
              Metrics.add_metric(acc2, metric_type, stats.mean)
            end)
          else
            acc
          end
        end)

      # Should have collected metrics
      aggregated = Metrics.aggregate(all_metrics)

      # Verify aggregation
      for {_metric_type, stats} <- aggregated do
        if stats.count > 0 do
          assert is_float(stats.mean)
          assert is_float(stats.median)
          assert is_float(stats.variance)
          assert stats.count > 0
        end
      end
    end

    test "calculates confidence intervals correctly" do
      # Create metrics collection with known values
      metrics = Metrics.new()

      # Add multiple samples
      values = [0.8, 0.85, 0.9, 0.75, 0.95]

      metrics =
        Enum.reduce(values, metrics, fn val, acc ->
          Metrics.add_metric(acc, :success_rate, val)
        end)

      # Calculate confidence interval
      ci = Metrics.confidence_interval(metrics, :success_rate, confidence_level: 0.95)

      assert is_map(ci)
      assert is_float(ci.lower)
      assert is_float(ci.upper)
      assert is_float(ci.mean)
      assert ci.confidence == 0.95
      assert ci.sample_size == 5

      # Mean should be within interval
      assert ci.mean >= ci.lower
      assert ci.mean <= ci.upper

      # Interval should be reasonable
      assert ci.lower >= 0.0
      assert ci.upper <= 1.0
    end

    test "handles metrics from successful and failed evaluations" do
      prompts = ["Prompt 1", "Prompt 2", "Prompt 3"]
      task = %{type: :reasoning}

      # Mix of timeouts and successes
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 100)

      # Should have mix of results
      successful = Enum.filter(results, &is_nil(&1.error))
      failed = Enum.filter(results, &(not is_nil(&1.error)))

      # Each should have metrics
      for result <- results do
        assert is_map(result.metrics)
        assert is_boolean(result.metrics.success)
      end

      # Successful results should have fitness
      for result <- successful do
        assert is_float(result.fitness) or is_nil(result.fitness)
      end

      # Failed results should not have fitness
      for result <- failed do
        assert is_nil(result.fitness)
      end
    end
  end

  describe "concurrent evaluation handling (1.2 Unit Test: Concurrent Evaluation)" do
    test "handles concurrent evaluations with ResultCollector" do
      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 5,
          expected_count: 10,
          timeout: 30_000
        )

      prompts = Enum.map(1..10, fn i -> "Concurrent prompt #{i}" end)
      task = %{type: :reasoning}

      # Spawn evaluation tasks
      tasks =
        for prompt <- prompts do
          Task.async(fn ->
            {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)
            result
          end)
        end

      # Register with collector and collect results
      tasks_with_refs =
        Enum.map(tasks, fn task ->
          ResultCollector.register_evaluation(collector, task.ref, task.pid)
          task
        end)

      # Await all evaluations
      results = Task.await_many(tasks_with_refs, 10_000)

      # Submit to collector
      Enum.zip(tasks_with_refs, results)
      |> Enum.each(fn {task, result} ->
        ResultCollector.submit_result(collector, task.ref, result)
      end)

      # Get collected results
      {:ok, collected_results} = ResultCollector.get_results(collector)

      assert length(collected_results) == 10
      assert Enum.all?(collected_results, &match?(%EvaluationResult{}, &1))
    end

    test "maintains result ordering with concurrent evaluation" do
      prompts = Enum.map(1..8, fn i -> "Ordered prompt #{i}" end)
      task = %{type: :reasoning}

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 4, timeout: 5_000)

      # Results should be in same order as prompts
      assert length(results) == length(prompts)

      Enum.zip(prompts, results)
      |> Enum.each(fn {prompt, result} ->
        assert result.prompt == prompt
      end)
    end

    test "handles high concurrency without errors" do
      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 20,
          expected_count: 50,
          timeout: 60_000
        )

      prompts = Enum.map(1..50, fn i -> "High concurrency #{i}" end)
      task = %{type: :reasoning}

      # Spawn many concurrent evaluations
      tasks =
        for prompt <- prompts do
          Task.async(fn ->
            {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)
            result
          end)
        end

      # Register all
      for task <- tasks do
        ResultCollector.register_evaluation(collector, task.ref, task.pid)
      end

      # Collect results
      results = Task.await_many(tasks, 30_000)

      # Submit all
      Enum.zip(tasks, results)
      |> Enum.each(fn {task, result} ->
        ResultCollector.submit_result(collector, task.ref, result)
      end)

      {:ok, collected} = ResultCollector.get_results(collector)
      assert length(collected) == 50
    end

    test "result collector batching works with concurrent submissions" do
      test_pid = self()
      batch_count = :atomics.new(1, [])

      callback = fn _batch ->
        :atomics.add(batch_count, 1, 1)
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 5,
          on_batch: callback
        )

      # Submit 15 results concurrently
      tasks =
        for i <- 1..15 do
          Task.async(fn ->
            ref = make_ref()
            result = build_test_result("prompt#{i}", 0.8)
            ResultCollector.submit_result(collector, ref, result)
          end)
        end

      Task.await_many(tasks)

      # Flush remaining
      ResultCollector.flush_batch(collector)

      # Wait for callbacks
      Process.sleep(100)

      # Should have triggered 4 batches (5, 5, 5, and 0 or partial)
      batches = :atomics.get(batch_count, 1)
      assert batches >= 3
    end
  end

  describe "timeout enforcement (1.2 Unit Test: Timeout Enforcement)" do
    test "enforces per-evaluation timeout" do
      prompt = "Timeout test"
      task = %{type: :reasoning}

      # Very short timeout
      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 1)

      assert %EvaluationResult{} = result

      # Should timeout or complete very quickly
      if result.error == :timeout do
        assert result.metrics.timeout == true
        assert is_nil(result.fitness)
        assert result.trajectory.outcome == :timeout
      else
        # Completed very quickly
        assert result.metrics.duration_ms < 100
      end
    end

    test "enforces global timeout with ResultCollector" do
      {:ok, collector} =
        ResultCollector.start_link(
          timeout: 200,
          expected_count: 5
        )

      # Register evaluations but only submit some
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)
      ResultCollector.submit_result(collector, ref1, build_test_result("completed", 0.9))

      # These will timeout
      for _i <- 1..4 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Wait for timeout
      Process.sleep(300)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 5

      # Should have timeout results
      timed_out = Enum.filter(results, &(&1.error == :timeout))
      assert length(timed_out) == 4

      # Cleanup
      Process.exit(pid1, :kill)
    end

    test "partial results returned on timeout" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 10)

      # Submit only 3 results
      for i <- 1..3 do
        ref = make_ref()
        ResultCollector.submit_result(collector, ref, build_test_result("prompt#{i}", 0.8))
      end

      # Register 7 more that won't complete
      for _i <- 1..7 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Await with short timeout
      assert {:partial, results} = ResultCollector.await_completion(collector, timeout: 100)
      assert length(results) == 3
    end

    test "timeout does not prevent trajectory collection" do
      prompt = "Timeout trajectory test"
      task = %{type: :reasoning}

      {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 1)

      # Even with timeout, should have trajectory
      assert %Trajectory{} = result.trajectory
      assert result.trajectory.outcome in [:timeout, :success, :error]

      # Trajectory should have at least some steps
      if result.error == :timeout do
        # Should have error recorded in trajectory
        assert result.trajectory.outcome == :timeout
        assert result.trajectory.error == :timeout
      end
    end
  end

  describe "result synchronization under failures (1.2 Unit Test: Result Synchronization)" do
    test "handles agent crashes during evaluation" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 3)

      # Successful evaluation
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)
      ResultCollector.submit_result(collector, ref1, build_test_result("success", 0.9))

      # Crashing evaluation
      pid2 = spawn(fn -> :ok end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      # Another crash with specific reason
      pid3 =
        spawn(fn ->
          Process.sleep(10)
          exit(:test_failure)
        end)

      ref3 = make_ref()
      ResultCollector.register_evaluation(collector, ref3, pid3)

      # Wait for crashes
      Process.sleep(100)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 3

      successful = Enum.find(results, &(&1.fitness == 0.9))
      crashed = Enum.filter(results, &(&1.metrics[:crashed] == true))

      assert successful != nil
      assert length(crashed) == 2

      # Cleanup
      Process.exit(pid1, :kill)
    end

    test "creates error results for crashed agents" do
      {:ok, collector} = ResultCollector.start_link()

      pid = spawn(fn -> exit(:custom_error) end)
      ref = make_ref()

      ResultCollector.register_evaluation(collector, ref, pid)

      Process.sleep(100)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1

      result = hd(results)
      assert result.error == {:agent_crashed, :custom_error}
      assert result.metrics.crashed == true
      assert is_nil(result.fitness)
    end

    test "handles mixed success, timeout, and crash scenarios" do
      {:ok, collector} =
        ResultCollector.start_link(
          timeout: 200,
          expected_count: 6
        )

      # Two successful
      for i <- 1..2 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
        ResultCollector.submit_result(collector, ref, build_test_result("success#{i}", 0.9))
      end

      # Two crashes
      for _i <- 1..2 do
        pid = spawn(fn -> :ok end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Two timeouts (registered but won't submit)
      for _i <- 1..2 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Wait for timeout and crashes
      Process.sleep(300)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 6

      successful = Enum.filter(results, &(&1.fitness == 0.9))
      crashed = Enum.filter(results, &(&1.metrics[:crashed] == true))
      timed_out = Enum.filter(results, &(&1.error == :timeout))

      assert length(successful) == 2
      assert length(crashed) == 2
      assert length(timed_out) == 2
    end

    test "batch evaluation handles individual failures gracefully" do
      prompts = Enum.map(1..5, fn i -> "Prompt #{i}" end)
      task = %{type: :reasoning}

      # Use very short timeout to cause some failures
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 3, timeout: 1)

      assert length(results) == 5

      # All should return results
      assert Enum.all?(results, &match?(%EvaluationResult{}, &1))

      # Order should be preserved
      Enum.zip(prompts, results)
      |> Enum.each(fn {prompt, result} ->
        assert result.prompt == prompt
      end)

      # Each should have trajectory even if failed
      assert Enum.all?(results, fn r -> match?(%Trajectory{}, r.trajectory) end)
    end

    test "partial results include all completed evaluations" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 10)

      # Complete 4 evaluations
      completed_refs =
        for i <- 1..4 do
          ref = make_ref()
          ResultCollector.submit_result(collector, ref, build_test_result("done#{i}", 0.85))
          ref
        end

      # Crash 3 evaluations
      for _i <- 1..3 do
        pid = spawn(fn -> :ok end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Leave 3 pending
      for _i <- 1..3 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        ref = make_ref()
        ResultCollector.register_evaluation(collector, ref, pid)
      end

      # Wait for crashes
      Process.sleep(100)

      # Get partial results
      {:ok, results} = ResultCollector.get_results(collector)

      # Should have completed + crashed
      assert length(results) >= 7

      successful = Enum.filter(results, &(&1.fitness == 0.85))
      crashed = Enum.filter(results, &(&1.metrics[:crashed] == true))

      assert length(successful) == 4
      assert length(crashed) == 3
    end
  end

  describe "complete integration workflow" do
    test "full evaluation pipeline with all components" do
      # Setup
      prompts = [
        "Analyze this problem step by step",
        "Consider multiple approaches",
        "Evaluate the trade-offs"
      ]

      task = %{type: :reasoning, id: "integration_test"}

      # Execute batch evaluation
      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 2, timeout: 5_000)

      # Validate results
      assert length(results) == 3

      for {prompt, result} <- Enum.zip(prompts, results) do
        # Basic result validation
        assert %EvaluationResult{} = result
        assert result.prompt == prompt

        # Trajectory validation
        assert %Trajectory{} = result.trajectory
        assert result.trajectory.metadata[:prompt] == prompt
        assert is_list(result.trajectory.steps)
        assert length(result.trajectory.steps) > 0

        # Metrics validation
        assert is_map(result.metrics)
        assert is_boolean(result.metrics.success)

        # Fitness validation (if successful)
        if result.error == nil do
          assert is_float(result.fitness)
          assert result.fitness >= 0.0 and result.fitness <= 1.0
        end
      end
    end

    test "aggregates metrics across multiple evaluations in batch" do
      prompts = Enum.map(1..10, fn i -> "Evaluation #{i}" end)
      task = %{type: :reasoning}

      results = Evaluator.evaluate_batch(prompts, task: task, parallelism: 5, timeout: 5_000)

      # Collect all metrics
      all_metrics = Metrics.new()

      all_metrics =
        Enum.reduce(results, all_metrics, fn result, acc ->
          if result.error == nil do
            Metrics.add_metric(acc, :success_rate, 1.0)
          else
            Metrics.add_metric(acc, :success_rate, 0.0)
          end
        end)

      # Calculate aggregate statistics
      aggregated = Metrics.aggregate(all_metrics)
      assert is_map(aggregated)

      if Map.has_key?(aggregated, :success_rate) do
        stats = aggregated.success_rate
        assert stats.count == 10
        assert is_float(stats.mean)
        assert stats.mean >= 0.0 and stats.mean <= 1.0
      end
    end

    test "concurrent evaluation with result collector and metrics aggregation" do
      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 5,
          expected_count: 8,
          timeout: 30_000
        )

      prompts = Enum.map(1..8, fn i -> "Complete workflow #{i}" end)
      task = %{type: :reasoning}

      # Spawn evaluations
      tasks =
        for prompt <- prompts do
          Task.async(fn ->
            {:ok, result} = Evaluator.evaluate_prompt(prompt, task: task, timeout: 5_000)
            result
          end)
        end

      # Register with collector
      for task <- tasks do
        ResultCollector.register_evaluation(collector, task.ref, task.pid)
      end

      # Await and submit
      results = Task.await_many(tasks, 10_000)

      Enum.zip(tasks, results)
      |> Enum.each(fn {task, result} ->
        ResultCollector.submit_result(collector, task.ref, result)
      end)

      # Get results
      {:ok, collected} = ResultCollector.get_results(collector)
      assert length(collected) == 8

      # Aggregate metrics
      metrics = Metrics.new()

      metrics =
        Enum.reduce(collected, metrics, fn result, acc ->
          if result.error == nil and is_float(result.fitness) do
            Metrics.add_metric(acc, :quality_score, result.fitness)
          else
            acc
          end
        end)

      # Validate aggregation
      if Metrics.count(metrics, :quality_score) > 0 do
        stats = Metrics.get_stats(metrics, :quality_score)
        assert is_map(stats)
        assert is_float(stats.mean)
        assert stats.count > 0
      end
    end
  end

  # Helper Functions

  defp build_test_result(prompt, fitness) do
    %EvaluationResult{
      prompt: prompt,
      fitness: fitness,
      metrics: %{success: true},
      trajectory: Trajectory.new(metadata: %{prompt: prompt}),
      error: nil
    }
  end
end
