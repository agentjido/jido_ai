defmodule Jido.AI.Runner.GEPA.ResultCollectorTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Evaluator.EvaluationResult
  alias Jido.AI.Runner.GEPA.ResultCollector

  describe "start_link/1" do
    test "starts collector with default configuration" do
      assert {:ok, collector} = ResultCollector.start_link()
      assert Process.alive?(collector)

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 0
      assert stats.completed_count == 0
      assert stats.batch_count == 0
    end

    test "starts collector with custom configuration" do
      assert {:ok, collector} =
               ResultCollector.start_link(
                 batch_size: 5,
                 batch_timeout: 1_000,
                 expected_count: 10,
                 timeout: 30_000
               )

      assert Process.alive?(collector)
    end

    test "starts collector with batch callback" do
      test_pid = self()

      callback = fn batch ->
        send(test_pid, {:batch_callback, length(batch)})
      end

      assert {:ok, _collector} = ResultCollector.start_link(on_batch: callback)
    end

    test "starts collector with name" do
      assert {:ok, _collector} =
               ResultCollector.start_link(name: :named_collector)

      assert Process.whereis(:named_collector) != nil
    end
  end

  describe "register_evaluation/3 and submit_result/3" do
    test "registers evaluation and submits result successfully" do
      {:ok, collector} = ResultCollector.start_link()

      # Spawn a dummy process
      pid = spawn(fn -> Process.sleep(:infinity) end)
      ref = make_ref()

      # Register
      :ok = ResultCollector.register_evaluation(collector, ref, pid)

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 1

      # Submit result
      result = build_result("test prompt", 0.85)
      :ok = ResultCollector.submit_result(collector, ref, result)

      # Check result was collected
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1
      assert hd(results).fitness == 0.85

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 0
      assert stats.completed_count == 1

      # Cleanup
      Process.exit(pid, :kill)
    end

    test "accepts multiple result submissions" do
      {:ok, collector} = ResultCollector.start_link()

      results_data = [
        {"prompt1", 0.9},
        {"prompt2", 0.8},
        {"prompt3", 0.7}
      ]

      refs =
        for {prompt, fitness} <- results_data do
          pid = spawn(fn -> Process.sleep(:infinity) end)
          ref = make_ref()
          ResultCollector.register_evaluation(collector, ref, pid)

          result = build_result(prompt, fitness)
          ResultCollector.submit_result(collector, ref, result)

          {ref, pid}
        end

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 3

      fitnesses = Enum.map(results, & &1.fitness) |> Enum.sort()
      assert fitnesses == [0.7, 0.8, 0.9]

      # Cleanup
      for {_ref, pid} <- refs, do: Process.exit(pid, :kill)
    end

    test "handles duplicate result submission" do
      {:ok, collector} = ResultCollector.start_link()

      pid = spawn(fn -> Process.sleep(:infinity) end)
      ref = make_ref()

      ResultCollector.register_evaluation(collector, ref, pid)

      result1 = build_result("prompt", 0.8)
      result2 = build_result("prompt", 0.9)

      # Submit same ref twice
      :ok = ResultCollector.submit_result(collector, ref, result1)
      :ok = ResultCollector.submit_result(collector, ref, result2)

      # Should only have first result
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1
      assert hd(results).fitness == 0.8

      Process.exit(pid, :kill)
    end

    test "accepts results for unregistered evaluations with warning" do
      {:ok, collector} = ResultCollector.start_link()

      ref = make_ref()
      result = build_result("unregistered", 0.5)

      # Submit without registration
      :ok = ResultCollector.submit_result(collector, ref, result)

      # Should still accept the result
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1
      assert hd(results).fitness == 0.5
    end
  end

  describe "result batching (1.2.4.2)" do
    test "flushes batch when batch size reached" do
      test_pid = self()

      callback = fn batch ->
        send(test_pid, {:batch_flushed, length(batch)})
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 3,
          on_batch: callback
        )

      # Submit 3 results to trigger batch flush
      for i <- 1..3 do
        ref = make_ref()
        result = build_result("prompt#{i}", 0.8)
        ResultCollector.submit_result(collector, ref, result)
      end

      # Should receive batch callback
      assert_receive {:batch_flushed, 3}, 1_000
    end

    test "flushes batch on timeout" do
      test_pid = self()

      callback = fn batch ->
        send(test_pid, {:batch_flushed, length(batch)})
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 10,
          batch_timeout: 100,
          on_batch: callback
        )

      # Submit only 2 results (below batch size)
      ref1 = make_ref()
      result1 = build_result("prompt1", 0.8)
      ResultCollector.submit_result(collector, ref1, result1)

      ref2 = make_ref()
      result2 = build_result("prompt2", 0.9)
      ResultCollector.submit_result(collector, ref2, result2)

      # Should flush after timeout
      assert_receive {:batch_flushed, 2}, 500
    end

    test "manual batch flush" do
      test_pid = self()

      callback = fn batch ->
        send(test_pid, {:batch_flushed, length(batch)})
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 10,
          batch_timeout: 10_000,
          on_batch: callback
        )

      # Submit 2 results
      ref1 = make_ref()
      ResultCollector.submit_result(collector, ref1, build_result("p1", 0.8))

      ref2 = make_ref()
      ResultCollector.submit_result(collector, ref2, build_result("p2", 0.9))

      # Manually flush
      :ok = ResultCollector.flush_batch(collector)

      # Should receive callback immediately
      assert_receive {:batch_flushed, 2}, 100
    end

    test "multiple batch flushes" do
      test_pid = self()

      callback = fn batch ->
        send(test_pid, {:batch_flushed, length(batch)})
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 2,
          on_batch: callback
        )

      # Submit 5 results - should trigger 2 batches (2, 2) and leave 1 pending
      for i <- 1..5 do
        ref = make_ref()
        ResultCollector.submit_result(collector, ref, build_result("p#{i}", 0.8))
      end

      assert_receive {:batch_flushed, 2}, 1_000
      assert_receive {:batch_flushed, 2}, 1_000
      refute_receive {:batch_flushed, _}, 100

      # Flush remaining
      ResultCollector.flush_batch(collector)
      assert_receive {:batch_flushed, 1}, 100
    end

    test "batch callback error does not crash collector" do
      callback = fn _batch ->
        raise "Intentional error"
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 1,
          on_batch: callback
        )

      # Submit result - should trigger error in callback
      ref = make_ref()
      ResultCollector.submit_result(collector, ref, build_result("test", 0.8))

      # Collector should still be alive
      Process.sleep(50)
      assert Process.alive?(collector)

      # Should still be able to query results
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1
    end
  end

  describe "failure handling (1.2.4.3)" do
    test "detects process crash and creates error result" do
      {:ok, collector} = ResultCollector.start_link()

      # Spawn process that will crash
      pid =
        spawn(fn ->
          Process.sleep(10)
          :ok
        end)

      ref = make_ref()

      ResultCollector.register_evaluation(collector, ref, pid)

      # Wait for process to exit
      Process.sleep(100)

      # Check that error result was created
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1

      result = hd(results)
      assert result.fitness == nil
      # Can be either :normal or :noproc depending on timing
      assert match?({:agent_crashed, _}, result.error)
      assert result.metrics.crashed == true

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 0
      assert stats.completed_count == 1
    end

    test "handles multiple process crashes" do
      {:ok, collector} = ResultCollector.start_link()

      # Spawn multiple processes that crash
      refs =
        for _i <- 1..3 do
          pid = spawn(fn -> :ok end)
          ref = make_ref()
          ResultCollector.register_evaluation(collector, ref, pid)
          ref
        end

      # Wait for all to exit
      Process.sleep(100)

      # Should have error results for all
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 3

      for result <- results do
        assert result.error != nil
        assert result.metrics.crashed == true
      end

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 0
      assert stats.completed_count == 3
    end

    test "creates error result with crash reason" do
      {:ok, collector} = ResultCollector.start_link()

      # Spawn process that exits with specific reason
      pid =
        spawn(fn ->
          Process.sleep(10)
          exit(:test_reason)
        end)

      ref = make_ref()
      ResultCollector.register_evaluation(collector, ref, pid)

      # Wait for crash
      Process.sleep(100)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 1

      result = hd(results)
      assert result.error == {:agent_crashed, :test_reason}
    end

    test "ignores crashes from unmonitored processes" do
      {:ok, collector} = ResultCollector.start_link()

      # Spawn and crash an unregistered process
      pid = spawn(fn -> :ok end)
      Process.sleep(50)

      # Should not create any results
      {:ok, results} = ResultCollector.get_results(collector)
      assert results == []
    end

    test "handles mix of successful submissions and crashes" do
      {:ok, collector} = ResultCollector.start_link()

      # Register one that will succeed
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)
      ResultCollector.submit_result(collector, ref1, build_result("success", 0.9))

      # Register one that will crash
      pid2 = spawn(fn -> :ok end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      # Wait for crash
      Process.sleep(100)

      # Should have both results
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 2

      successful = Enum.find(results, &(&1.fitness == 0.9))
      crashed = Enum.find(results, &(&1.error != nil))

      assert successful != nil
      assert crashed != nil
      assert crashed.metrics.crashed == true

      Process.exit(pid1, :kill)
    end
  end

  describe "partial result collection (1.2.4.4)" do
    test "global timeout creates timeout results for pending evaluations" do
      {:ok, collector} =
        ResultCollector.start_link(
          timeout: 100,
          expected_count: 3
        )

      # Register 3 evaluations but only submit 1
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)
      ResultCollector.submit_result(collector, ref1, build_result("completed", 0.9))

      pid2 = spawn(fn -> Process.sleep(:infinity) end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      pid3 = spawn(fn -> Process.sleep(:infinity) end)
      ref3 = make_ref()
      ResultCollector.register_evaluation(collector, ref3, pid3)

      # Wait for timeout
      Process.sleep(200)

      # Should have timeout results for pending evaluations
      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 3

      completed = Enum.find(results, &(&1.fitness == 0.9))
      timed_out = Enum.filter(results, &(&1.error == :timeout))

      assert completed != nil
      assert length(timed_out) == 2

      for result <- timed_out do
        assert result.metrics.timeout == true
      end

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
      Process.exit(pid3, :kill)
    end

    test "await_completion returns partial results on timeout" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 3)

      # Register and submit only 1 result
      ref1 = make_ref()
      ResultCollector.submit_result(collector, ref1, build_result("only", 0.8))

      # Register 2 more but don't submit
      pid2 = spawn(fn -> Process.sleep(:infinity) end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      pid3 = spawn(fn -> Process.sleep(:infinity) end)
      ref3 = make_ref()
      ResultCollector.register_evaluation(collector, ref3, pid3)

      # Await with short timeout - should return partial
      assert {:partial, results} = ResultCollector.await_completion(collector, timeout: 100)

      assert length(results) == 1
      assert hd(results).fitness == 0.8

      Process.exit(pid2, :kill)
      Process.exit(pid3, :kill)
    end

    test "await_completion returns ok when all results collected" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 2)

      # Submit both expected results
      ref1 = make_ref()
      ResultCollector.submit_result(collector, ref1, build_result("first", 0.8))

      ref2 = make_ref()
      ResultCollector.submit_result(collector, ref2, build_result("second", 0.9))

      # Should complete immediately
      assert {:ok, results} = ResultCollector.await_completion(collector, timeout: 1_000)

      assert length(results) == 2
      fitnesses = Enum.map(results, & &1.fitness) |> Enum.sort()
      assert fitnesses == [0.8, 0.9]
    end

    test "multiple waiters notified on completion" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 1)

      # Spawn multiple waiters
      waiter1 =
        Task.async(fn ->
          ResultCollector.await_completion(collector, timeout: 5_000)
        end)

      waiter2 =
        Task.async(fn ->
          ResultCollector.await_completion(collector, timeout: 5_000)
        end)

      # Give waiters time to register
      Process.sleep(50)

      # Submit result
      ref = make_ref()
      ResultCollector.submit_result(collector, ref, build_result("test", 0.85))

      # Both should complete
      assert {:ok, results1} = Task.await(waiter1)
      assert {:ok, results2} = Task.await(waiter2)

      assert length(results1) == 1
      assert length(results2) == 1
      assert hd(results1).fitness == 0.85
      assert hd(results2).fitness == 0.85
    end

    test "await_completion works when already complete" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 1)

      # Submit result first
      ref = make_ref()
      ResultCollector.submit_result(collector, ref, build_result("test", 0.9))

      # Then await - should return immediately
      assert {:ok, results} = ResultCollector.await_completion(collector, timeout: 100)
      assert length(results) == 1
    end
  end

  describe "get_results/2" do
    test "returns empty list when no results" do
      {:ok, collector} = ResultCollector.start_link()

      assert {:ok, []} = ResultCollector.get_results(collector)
    end

    test "returns all collected results" do
      {:ok, collector} = ResultCollector.start_link()

      refs =
        for i <- 1..5 do
          ref = make_ref()
          ResultCollector.submit_result(collector, ref, build_result("p#{i}", 0.5 + i * 0.1))
          ref
        end

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 5

      fitnesses = Enum.map(results, & &1.fitness) |> Enum.sort()
      assert fitnesses == [0.6, 0.7, 0.8, 0.9, 1.0]
    end

    test "returns results immediately without blocking" do
      {:ok, collector} = ResultCollector.start_link()

      ref = make_ref()
      ResultCollector.submit_result(collector, ref, build_result("test", 0.8))

      # Should return immediately even if more results expected
      start_time = System.monotonic_time(:millisecond)
      {:ok, results} = ResultCollector.get_results(collector)
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert length(results) == 1
      assert elapsed < 100
    end
  end

  describe "get_stats/1" do
    test "returns accurate statistics" do
      {:ok, collector} =
        ResultCollector.start_link(expected_count: 5)

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 0
      assert stats.completed_count == 0
      assert stats.batch_count == 0
      assert stats.expected_count == 5
      assert stats.uptime_ms >= 0

      # Register some evaluations
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)

      pid2 = spawn(fn -> Process.sleep(:infinity) end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 2
      assert stats.completed_count == 0

      # Submit one result
      ResultCollector.submit_result(collector, ref1, build_result("test", 0.8))

      stats = ResultCollector.get_stats(collector)
      assert stats.pending_count == 1
      assert stats.completed_count == 1
      assert stats.batch_count == 1

      Process.exit(pid1, :kill)
      Process.exit(pid2, :kill)
    end

    test "tracks uptime correctly" do
      {:ok, collector} = ResultCollector.start_link()

      stats1 = ResultCollector.get_stats(collector)
      Process.sleep(100)
      stats2 = ResultCollector.get_stats(collector)

      assert stats2.uptime_ms > stats1.uptime_ms
      assert stats2.uptime_ms >= 100
    end
  end

  describe "integration scenarios" do
    test "complete workflow: register, submit, crash, timeout" do
      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 2,
          timeout: 200,
          expected_count: 4
        )

      # Successful submission
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      ref1 = make_ref()
      ResultCollector.register_evaluation(collector, ref1, pid1)
      ResultCollector.submit_result(collector, ref1, build_result("success", 0.9))

      # Process crash
      pid2 = spawn(fn -> :ok end)
      ref2 = make_ref()
      ResultCollector.register_evaluation(collector, ref2, pid2)

      # Pending (will timeout)
      pid3 = spawn(fn -> Process.sleep(:infinity) end)
      ref3 = make_ref()
      ResultCollector.register_evaluation(collector, ref3, pid3)

      pid4 = spawn(fn -> Process.sleep(:infinity) end)
      ref4 = make_ref()
      ResultCollector.register_evaluation(collector, ref4, pid4)

      # Wait for timeout
      Process.sleep(300)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 4

      successful = Enum.find(results, &(&1.fitness == 0.9))
      crashed = Enum.find(results, &(&1.metrics[:crashed] == true))
      timed_out = Enum.filter(results, &(&1.error == :timeout))

      assert successful != nil
      assert crashed != nil
      assert length(timed_out) == 2

      # Cleanup
      Process.exit(pid1, :kill)
      Process.exit(pid3, :kill)
      Process.exit(pid4, :kill)
    end

    test "high concurrency with many results" do
      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 10,
          expected_count: 50
        )

      # Submit 50 results concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            ref = make_ref()
            result = build_result("prompt#{i}", :rand.uniform())
            ResultCollector.submit_result(collector, ref, result)
          end)
        end

      Task.await_many(tasks)

      {:ok, results} = ResultCollector.get_results(collector)
      assert length(results) == 50
    end

    test "batch callback receives all results" do
      test_pid = self()
      all_results = []

      callback = fn batch ->
        send(test_pid, {:batch, batch})
      end

      {:ok, collector} =
        ResultCollector.start_link(
          batch_size: 3,
          on_batch: callback
        )

      # Submit 10 results
      for i <- 1..10 do
        ref = make_ref()
        ResultCollector.submit_result(collector, ref, build_result("p#{i}", 0.8))
      end

      # Should receive 3 batches (3, 3, 3) + manual flush for 1
      assert_receive {:batch, batch1}, 1_000
      assert length(batch1) == 3

      assert_receive {:batch, batch2}, 1_000
      assert length(batch2) == 3

      assert_receive {:batch, batch3}, 1_000
      assert length(batch3) == 3

      # Flush remaining
      ResultCollector.flush_batch(collector)
      assert_receive {:batch, batch4}, 1_000
      assert length(batch4) == 1

      # Total should be 10
      total = length(batch1) + length(batch2) + length(batch3) + length(batch4)
      assert total == 10
    end
  end

  # Helper Functions

  defp build_result(prompt, fitness) do
    %EvaluationResult{
      prompt: prompt,
      fitness: fitness,
      metrics: %{success: true},
      trajectory: nil,
      error: nil
    }
  end
end
