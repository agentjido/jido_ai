defmodule Jido.AI.Runner.GEPA.SchedulerTest do
  use ExUnit.Case, async: true

  alias Jido.AI.Runner.GEPA.Scheduler

  describe "start_link/1" do
    test "starts scheduler with valid configuration" do
      opts = [max_concurrent: 3, max_queue_size: 10]

      assert {:ok, pid} = Scheduler.start_link(opts)
      assert Process.alive?(pid)

      Scheduler.stop(pid)
    end

    test "starts scheduler with named process" do
      opts = [name: :test_scheduler]

      assert {:ok, pid} = Scheduler.start_link(opts)
      assert Process.whereis(:test_scheduler) == pid

      Scheduler.stop(pid)
    end

    test "uses default configuration values" do
      assert {:ok, pid} = Scheduler.start_link([])

      {:ok, status} = Scheduler.status(pid)
      assert status.max_concurrent == 5
      assert status.running == 0
      assert status.pending == 0

      Scheduler.stop(pid)
    end

    test "accepts custom max_concurrent" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 10)

      {:ok, status} = Scheduler.status(pid)
      assert status.max_concurrent == 10

      Scheduler.stop(pid)
    end

    test "accepts priorities configuration" do
      {:ok, pid} = Scheduler.start_link(enable_priorities: false)
      assert Process.alive?(pid)

      Scheduler.stop(pid)
    end
  end

  describe "submit_task/2" do
    test "submits task successfully" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_123",
        evaluator: fn -> {:ok, 42} end
      }

      assert {:ok, task_id} = Scheduler.submit_task(pid, task_spec)
      assert is_binary(task_id)

      Scheduler.stop(pid)
    end

    test "submits task with priority" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_123",
        priority: :high,
        evaluator: fn -> {:ok, 42} end
      }

      assert {:ok, task_id} = Scheduler.submit_task(pid, task_spec)
      assert is_binary(task_id)

      Scheduler.stop(pid)
    end

    test "submits task with metadata" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_123",
        evaluator: fn -> {:ok, 42} end,
        metadata: %{generation: 5, score: 0.8}
      }

      assert {:ok, task_id} = Scheduler.submit_task(pid, task_spec)
      assert is_binary(task_id)

      Scheduler.stop(pid)
    end

    test "returns error when missing candidate_id" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        evaluator: fn -> {:ok, 42} end
      }

      assert {:error, :missing_candidate_id} = Scheduler.submit_task(pid, task_spec)

      Scheduler.stop(pid)
    end

    test "returns error when missing evaluator" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_123"
      }

      assert {:error, :missing_evaluator} = Scheduler.submit_task(pid, task_spec)

      Scheduler.stop(pid)
    end

    test "returns error when evaluator is not a function" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_123",
        evaluator: "not a function"
      }

      assert {:error, :invalid_evaluator} = Scheduler.submit_task(pid, task_spec)

      Scheduler.stop(pid)
    end

    test "returns error when queue is full" do
      {:ok, pid} = Scheduler.start_link(max_queue_size: 2, max_concurrent: 1)

      # Fill the queue and running slots
      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(1000) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Wait for task to start running
      Process.sleep(50)

      # Try to submit one more (should fill queue)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # This should exceed queue size
      assert {:error, :queue_full} = Scheduler.submit_task(pid, slow_task)

      Scheduler.stop(pid)
    end
  end

  describe "status/1" do
    test "returns initial status" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 5)

      {:ok, status} = Scheduler.status(pid)

      assert status.running == 0
      assert status.pending == 0
      assert status.completed == 0
      assert status.capacity == 0.0
      assert status.max_concurrent == 5
      assert is_float(status.throughput)
      assert is_integer(status.uptime_ms)
      assert status.uptime_ms >= 0
      assert is_map(status.stats)

      Scheduler.stop(pid)
    end

    test "tracks running tasks" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2)

      # Submit slow tasks
      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Wait for tasks to start
      Process.sleep(50)

      {:ok, status} = Scheduler.status(pid)
      assert status.running == 2

      Scheduler.stop(pid)
    end

    test "tracks pending tasks" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      # Submit multiple slow tasks
      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Wait for first task to start
      Process.sleep(50)

      {:ok, status} = Scheduler.status(pid)
      assert status.running == 1
      assert status.pending == 2

      Scheduler.stop(pid)
    end

    test "tracks completed tasks" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_1",
        evaluator: fn -> {:ok, 42} end
      }

      {:ok, _} = Scheduler.submit_task(pid, task_spec)

      # Wait for task to complete
      Process.sleep(100)

      {:ok, status} = Scheduler.status(pid)
      assert status.completed == 1

      Scheduler.stop(pid)
    end

    test "calculates capacity correctly" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 4)

      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Wait for tasks to start
      Process.sleep(50)

      {:ok, status} = Scheduler.status(pid)
      assert status.capacity == 0.5

      Scheduler.stop(pid)
    end

    test "tracks uptime" do
      {:ok, pid} = Scheduler.start_link([])

      {:ok, status1} = Scheduler.status(pid)
      Process.sleep(50)
      {:ok, status2} = Scheduler.status(pid)

      assert status2.uptime_ms > status1.uptime_ms

      Scheduler.stop(pid)
    end

    test "includes statistics" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_1",
        evaluator: fn -> {:ok, 42} end
      }

      {:ok, _} = Scheduler.submit_task(pid, task_spec)
      Process.sleep(100)

      {:ok, status} = Scheduler.status(pid)
      assert status.stats.submitted == 1
      assert status.stats.completed == 1

      Scheduler.stop(pid)
    end
  end

  describe "get_result/2" do
    test "returns result for completed task" do
      {:ok, pid} = Scheduler.start_link([])

      task_spec = %{
        candidate_id: "cand_1",
        evaluator: fn -> {:ok, 42} end
      }

      {:ok, task_id} = Scheduler.submit_task(pid, task_spec)

      # Wait for task to complete
      Process.sleep(100)

      assert {:ok, {:ok, 42}} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end

    test "returns error for running task" do
      {:ok, pid} = Scheduler.start_link([])

      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, task_id} = Scheduler.submit_task(pid, slow_task)

      # Wait for task to start
      Process.sleep(50)

      assert {:error, :task_running} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end

    test "returns error for pending task" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      # Submit first slow task to occupy the slot
      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Submit second task that will be pending
      {:ok, task_id} = Scheduler.submit_task(pid, slow_task)

      # Wait for first task to start
      Process.sleep(50)

      assert {:error, :task_pending} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end

    test "returns error for nonexistent task" do
      {:ok, pid} = Scheduler.start_link([])

      assert {:error, :not_found} = Scheduler.get_result(pid, "nonexistent_task")

      Scheduler.stop(pid)
    end

    test "handles task failure" do
      {:ok, pid} = Scheduler.start_link([])

      failing_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> raise "test error" end
      }

      {:ok, task_id} = Scheduler.submit_task(pid, failing_task)

      # Wait for task to fail
      Process.sleep(100)

      assert {:ok, {:error, %RuntimeError{message: "test error"}}} =
               Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end
  end

  describe "cancel_task/2" do
    test "cancels pending task" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      # Submit first slow task to occupy the slot
      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Submit second task that will be pending
      {:ok, task_id} = Scheduler.submit_task(pid, slow_task)

      # Wait for first task to start
      Process.sleep(50)

      # Cancel the pending task
      assert :ok = Scheduler.cancel_task(pid, task_id)

      # Verify task was removed
      assert {:error, :not_found} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end

    test "returns error for nonexistent task" do
      {:ok, pid} = Scheduler.start_link([])

      assert {:error, :not_found} = Scheduler.cancel_task(pid, "nonexistent")

      Scheduler.stop(pid)
    end

    test "updates statistics after cancellation" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, task_id} = Scheduler.submit_task(pid, slow_task)

      Process.sleep(50)

      :ok = Scheduler.cancel_task(pid, task_id)
      Process.sleep(50)

      {:ok, status} = Scheduler.status(pid)
      assert status.stats.cancelled == 1

      Scheduler.stop(pid)
    end
  end

  describe "priority scheduling" do
    test "executes critical tasks first" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      # Results tracker
      test_pid = self()

      # Submit normal task first
      normal_task = %{
        candidate_id: "normal",
        priority: :normal,
        evaluator: fn ->
          send(test_pid, {:executed, :normal})
          {:ok, :normal}
        end
      }

      # Submit critical task after
      critical_task = %{
        candidate_id: "critical",
        priority: :critical,
        evaluator: fn ->
          send(test_pid, {:executed, :critical})
          {:ok, :critical}
        end
      }

      {:ok, _} = Scheduler.submit_task(pid, normal_task)
      {:ok, _} = Scheduler.submit_task(pid, critical_task)

      # First task (normal) should start immediately
      assert_receive {:executed, :normal}, 200

      # Critical task should execute before any other normal tasks
      assert_receive {:executed, :critical}, 200

      Scheduler.stop(pid)
    end

    test "respects priority levels: critical > high > normal > low" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      test_pid = self()

      # Create slow first task to block execution
      blocking_task = %{
        candidate_id: "blocking",
        evaluator: fn -> Process.sleep(100) end
      }

      {:ok, _} = Scheduler.submit_task(pid, blocking_task)

      # Submit tasks in reverse priority order
      for priority <- [:low, :normal, :high, :critical] do
        task = %{
          candidate_id: "task_#{priority}",
          priority: priority,
          evaluator: fn ->
            send(test_pid, {:executed, priority})
            {:ok, priority}
          end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      # Wait for blocking task to complete
      Process.sleep(150)

      # Tasks should execute in priority order
      assert_receive {:executed, :critical}, 200
      assert_receive {:executed, :high}, 200
      assert_receive {:executed, :normal}, 200
      assert_receive {:executed, :low}, 200

      Scheduler.stop(pid)
    end

    test "works when priorities are disabled" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1, enable_priorities: false)

      test_pid = self()

      # Submit tasks with different priorities
      for priority <- [:critical, :high, :normal, :low] do
        task = %{
          candidate_id: "task_#{priority}",
          priority: priority,
          evaluator: fn ->
            send(test_pid, {:executed, priority})
            {:ok, priority}
          end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      # All tasks should execute in FIFO order (priorities ignored)
      assert_receive {:executed, :critical}, 200
      assert_receive {:executed, :high}, 200
      assert_receive {:executed, :normal}, 200
      assert_receive {:executed, :low}, 200

      Scheduler.stop(pid)
    end
  end

  describe "concurrency control" do
    test "respects max_concurrent limit" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2)

      slow_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> Process.sleep(500) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      # Wait for tasks to start
      Process.sleep(50)

      {:ok, status} = Scheduler.status(pid)
      assert status.running == 2
      assert status.pending == 1

      Scheduler.stop(pid)
    end

    test "dispatches pending tasks when slots become available" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 1)

      # Submit first slow task
      first_task = %{
        candidate_id: "first",
        evaluator: fn -> Process.sleep(100) end
      }

      # Submit second slow task
      second_task = %{
        candidate_id: "second",
        evaluator: fn ->
          Process.sleep(100)
          {:ok, :done}
        end
      }

      {:ok, _} = Scheduler.submit_task(pid, first_task)
      {:ok, task_id} = Scheduler.submit_task(pid, second_task)

      # Wait for first task to start
      Process.sleep(50)

      {:ok, status1} = Scheduler.status(pid)
      assert status1.running == 1
      assert status1.pending == 1

      # Wait for first task to complete and second to start
      Process.sleep(100)

      {:ok, status2} = Scheduler.status(pid)
      assert status2.running == 1
      assert status2.pending == 0

      # Verify second task completed
      Process.sleep(150)
      assert {:ok, {:ok, :done}} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end

    test "handles multiple concurrent task submissions" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 5)

      # Submit many tasks concurrently
      tasks =
        for i <- 1..20 do
          Elixir.Task.async(fn ->
            task_spec = %{
              candidate_id: "cand_#{i}",
              evaluator: fn -> {:ok, i} end
            }

            Scheduler.submit_task(pid, task_spec)
          end)
        end

      results = Elixir.Task.await_many(tasks)

      # All submissions should succeed
      assert Enum.all?(results, fn result ->
               match?({:ok, _task_id}, result)
             end)

      # Wait for all tasks to complete
      Process.sleep(200)

      {:ok, status} = Scheduler.status(pid)
      assert status.completed == 20

      Scheduler.stop(pid)
    end
  end

  describe "dynamic scheduling" do
    test "adapts to varying task completion times" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 3)

      # Submit tasks with different completion times
      for i <- 1..10 do
        delay = rem(i, 3) * 50

        task = %{
          candidate_id: "cand_#{i}",
          evaluator: fn ->
            Process.sleep(delay)
            {:ok, i}
          end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      # Wait for some tasks to complete
      Process.sleep(200)

      {:ok, status} = Scheduler.status(pid)
      assert status.completed > 0
      assert status.running <= 3

      Scheduler.stop(pid)
    end

    test "maintains throughput with continuous task submission" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 5)

      # Submit initial batch
      for i <- 1..10 do
        task = %{
          candidate_id: "cand_#{i}",
          evaluator: fn -> {:ok, i} end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      Process.sleep(100)

      # Submit second batch while first is processing
      for i <- 11..20 do
        task = %{
          candidate_id: "cand_#{i}",
          evaluator: fn -> {:ok, i} end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      # Wait for all to complete
      Process.sleep(200)

      {:ok, status} = Scheduler.status(pid)
      assert status.completed == 20
      assert status.throughput > 0

      Scheduler.stop(pid)
    end
  end

  describe "resource allocation" do
    test "balances load across available capacity" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 4)

      # Submit tasks continuously
      for i <- 1..8 do
        task = %{
          candidate_id: "cand_#{i}",
          evaluator: fn ->
            Process.sleep(100)
            {:ok, i}
          end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      # Check capacity utilization
      Process.sleep(50)
      {:ok, status1} = Scheduler.status(pid)
      assert status1.capacity == 1.0
      assert status1.running == 4

      # After first batch completes, second batch should start
      Process.sleep(100)
      {:ok, status2} = Scheduler.status(pid)
      assert status2.running == 4
      assert status2.completed == 4

      Scheduler.stop(pid)
    end

    test "tracks resource usage statistics" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 3)

      for i <- 1..5 do
        task = %{
          candidate_id: "cand_#{i}",
          evaluator: fn -> {:ok, i} end
        }

        {:ok, _} = Scheduler.submit_task(pid, task)
      end

      Process.sleep(100)

      {:ok, status} = Scheduler.status(pid)
      assert status.stats.submitted == 5
      assert status.stats.completed == 5
      assert status.stats.failed == 0

      Scheduler.stop(pid)
    end
  end

  describe "stop/1" do
    test "stops scheduler gracefully" do
      {:ok, pid} = Scheduler.start_link([])
      assert Process.alive?(pid)

      assert :ok = Scheduler.stop(pid)

      Process.sleep(50)
      refute Process.alive?(pid)
    end

    test "stops with custom timeout" do
      {:ok, pid} = Scheduler.start_link([])

      assert :ok = Scheduler.stop(pid, timeout: 10_000)

      Process.sleep(50)
      refute Process.alive?(pid)
    end
  end

  describe "error handling" do
    test "handles task exceptions gracefully" do
      {:ok, pid} = Scheduler.start_link([])

      failing_task = %{
        candidate_id: "cand_1",
        evaluator: fn -> raise "intentional error" end
      }

      {:ok, task_id} = Scheduler.submit_task(pid, failing_task)

      # Wait for task to fail
      Process.sleep(100)

      {:ok, status} = Scheduler.status(pid)
      assert status.stats.failed == 1

      # Result should contain error
      {:ok, result} = Scheduler.get_result(pid, task_id)
      assert match?({:error, _}, result)

      Scheduler.stop(pid)
    end

    test "continues operation after task failure" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2)

      failing_task = %{
        candidate_id: "fail",
        evaluator: fn -> raise "error" end
      }

      success_task = %{
        candidate_id: "success",
        evaluator: fn -> {:ok, 42} end
      }

      {:ok, _} = Scheduler.submit_task(pid, failing_task)
      {:ok, task_id} = Scheduler.submit_task(pid, success_task)

      # Wait for both tasks to complete
      Process.sleep(100)

      {:ok, status} = Scheduler.status(pid)
      assert status.completed == 2
      assert status.stats.failed == 1
      assert status.stats.completed == 1

      # Success task should have result
      assert {:ok, {:ok, 42}} = Scheduler.get_result(pid, task_id)

      Scheduler.stop(pid)
    end
  end

  describe "concurrent operations" do
    test "handles concurrent status queries" do
      {:ok, pid} = Scheduler.start_link([])

      tasks =
        for _ <- 1..10 do
          Elixir.Task.async(fn -> Scheduler.status(pid) end)
        end

      results = Elixir.Task.await_many(tasks)

      assert Enum.all?(results, fn result ->
               match?({:ok, %{running: _, pending: _, completed: _}}, result)
             end)

      Scheduler.stop(pid)
    end

    test "handles concurrent task submissions and cancellations" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2)

      slow_task = %{
        candidate_id: "slow",
        evaluator: fn -> Process.sleep(500) end
      }

      # Submit tasks
      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, task_id1} = Scheduler.submit_task(pid, slow_task)
      {:ok, task_id2} = Scheduler.submit_task(pid, slow_task)

      Process.sleep(50)

      # Cancel pending tasks concurrently
      cancel_tasks =
        for task_id <- [task_id1, task_id2] do
          Elixir.Task.async(fn -> Scheduler.cancel_task(pid, task_id) end)
        end

      results = Elixir.Task.await_many(cancel_tasks)

      # At least one cancellation should succeed
      assert Enum.any?(results, fn result -> result == :ok end)

      Scheduler.stop(pid)
    end
  end

  describe "fault tolerance" do
    test "handles scheduler process termination gracefully" do
      # Trap exits so we can observe the process dying without crashing the test
      Process.flag(:trap_exit, true)

      {:ok, pid} = Scheduler.start_link(max_concurrent: 3)

      # Verify scheduler is running
      assert Process.alive?(pid)
      {:ok, status} = Scheduler.status(pid)
      assert status.running == 0

      # Terminate the process
      Process.exit(pid, :kill)
      Process.sleep(50)

      # Process should be terminated
      refute Process.alive?(pid)

      # Reset trap_exit to default
      Process.flag(:trap_exit, false)
    end

    test "rejects operations after scheduler termination" do
      {:ok, pid} = Scheduler.start_link([])

      # Terminate the scheduler
      Scheduler.stop(pid)
      Process.sleep(100)

      task_spec = %{
        candidate_id: "test",
        evaluator: fn -> {:ok, 1} end
      }

      # Operations should fail gracefully
      catch_exit(Scheduler.submit_task(pid, task_spec))
      catch_exit(Scheduler.status(pid))
      catch_exit(Scheduler.get_result(pid, "task_123"))
    end

    test "maintains queue integrity under rapid submissions" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2, max_queue_size: 50)

      # Rapidly submit many tasks
      task_ids =
        for i <- 1..30 do
          task = %{
            candidate_id: "cand_#{i}",
            evaluator: fn ->
              Process.sleep(10)
              {:ok, i}
            end
          }

          {:ok, task_id} = Scheduler.submit_task(pid, task)
          task_id
        end

      # All tasks should be submitted successfully
      assert length(task_ids) == 30

      # Wait for processing
      Process.sleep(200)

      {:ok, status} = Scheduler.status(pid)
      # Most or all tasks should have started processing
      assert status.completed > 0

      Scheduler.stop(pid)
    end

    test "handles linked process crash without affecting scheduler" do
      {:ok, pid} = Scheduler.start_link([])

      # Submit a task that will crash
      crashing_task = %{
        candidate_id: "crash",
        evaluator: fn ->
          raise "intentional crash"
        end
      }

      {:ok, task_id} = Scheduler.submit_task(pid, crashing_task)

      # Wait for task to crash
      Process.sleep(100)

      # Scheduler should still be alive
      assert Process.alive?(pid)

      # Can still get task result (error)
      {:ok, result} = Scheduler.get_result(pid, task_id)
      assert match?({:error, _}, result)

      # Can still submit new tasks
      success_task = %{
        candidate_id: "success",
        evaluator: fn -> {:ok, 42} end
      }

      {:ok, _new_task_id} = Scheduler.submit_task(pid, success_task)

      Scheduler.stop(pid)
    end

    test "maintains state consistency under task failures" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 3)

      # Mix of successful and failing tasks
      _task_ids =
        for i <- 1..10 do
          task = %{
            candidate_id: "task_#{i}",
            evaluator: fn ->
              if rem(i, 3) == 0 do
                raise "error #{i}"
              else
                {:ok, i}
              end
            end
          }

          {:ok, task_id} = Scheduler.submit_task(pid, task)
          task_id
        end

      # Wait for all tasks to complete
      Process.sleep(300)

      {:ok, status} = Scheduler.status(pid)

      # All tasks should be accounted for
      total_processed = status.stats.completed + status.stats.failed
      assert total_processed == 10

      # Should have some failures and some successes
      assert status.stats.failed > 0
      assert status.stats.completed > 0

      Scheduler.stop(pid)
    end

    test "handles monitor down messages correctly" do
      {:ok, pid} = Scheduler.start_link([])

      # Create a monitor
      ref = Process.monitor(pid)

      # Stop the scheduler
      Scheduler.stop(pid)

      # Should receive DOWN message
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000
    end

    test "recovers capacity after task completion" do
      {:ok, pid} = Scheduler.start_link(max_concurrent: 2)

      # Submit tasks that will consume all capacity
      slow_task = %{
        candidate_id: "slow",
        evaluator: fn -> Process.sleep(100) end
      }

      {:ok, _} = Scheduler.submit_task(pid, slow_task)
      {:ok, _} = Scheduler.submit_task(pid, slow_task)

      Process.sleep(50)

      # Capacity should be full
      {:ok, status1} = Scheduler.status(pid)
      assert status1.capacity == 1.0

      # Wait for tasks to complete
      Process.sleep(100)

      # Capacity should be freed
      {:ok, status2} = Scheduler.status(pid)
      assert status2.capacity == 0.0

      Scheduler.stop(pid)
    end
  end
end
