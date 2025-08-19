defmodule Kodo.Core.Jobs.JobManagerTest do
  use Kodo.Case, async: true

  alias Kodo.Core.Jobs.{JobManager, Job}
  alias Kodo.Core.Parsing.ExecutionPlan

  setup context do
    # Register basic commands for the execution to work
    Kodo.Case.register_basic_commands(context.command_registry)

    # Also register commands in the instance registry (used by jobs)
    {:ok, inst_reg} = Kodo.Instance.commands(context.instance)
    Kodo.Case.register_basic_commands(inst_reg)

    # Create a unique JobManager instance for test isolation
    job_manager_name = Kodo.Case.unique_atom("job_manager")

    # Use proper child specification
    {:ok, job_manager_pid} =
      start_supervised({
        JobManager,
        [name: job_manager_name, instance: context.instance]
      })

    # Setup telemetry handler for testing events
    test_pid = self()
    handler_id = Kodo.Case.unique_atom("telemetry_handler")

    :telemetry.attach_many(
      handler_id,
      [[:kodo, :job, :started], [:kodo, :job, :completed]],
      fn event, measurements, metadata, _config ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end,
      nil
    )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    # Create simple test execution plan
    command = %ExecutionPlan.Command{
      name: "echo",
      args: ["hello"],
      redirections: [],
      env: nil
    }

    pipeline = %ExecutionPlan.Pipeline{
      commands: [command],
      background?: false
    }

    execution_plan = %ExecutionPlan{
      pipelines: [pipeline],
      control_ops: []
    }

    {:ok,
     job_manager: job_manager_pid,
     job_manager_name: job_manager_name,
     execution_plan: execution_plan,
     telemetry_handler: handler_id}
  end

  describe "start_job/4" do
    test "starts a job and returns id=1 with correct state", %{
      job_manager: jm,
      execution_plan: plan
    } do
      assert {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Should return id=1 for first job
      assert job_id == 1

      # Get the job to verify correct fields
      assert {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert %Job{} = job
      assert job.id == 1
      assert job.command == "echo hello"
      assert job.session_id == "session123"
      assert job.background? == false
      assert job.status == :running
      assert is_pid(job.pid)
      assert %DateTime{} = job.started_at
      assert job.completed_at == nil
      assert job.exit_status == nil

      # Verify next_id is now 2
      assert GenServer.call(jm, :next_job_id) == 2
    end

    test "background job has correct background? flag", %{job_manager: jm, execution_plan: plan} do
      assert {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", true)
      assert {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.background? == true
    end

    test "sequential jobs get incremental IDs", %{job_manager: jm, execution_plan: plan} do
      assert {:ok, job_id1} = JobManager.start_job(jm, plan, "echo 1", "session123", false)
      assert {:ok, job_id2} = JobManager.start_job(jm, plan, "echo 2", "session123", false)
      assert {:ok, job_id3} = JobManager.start_job(jm, plan, "echo 3", "session123", false)

      assert job_id1 == 1
      assert job_id2 == 2
      assert job_id3 == 3
    end

    test "emits telemetry started event", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", true)

      assert_receive {:telemetry, [:kodo, :job, :started], %{count: 1}, metadata}
      assert metadata.job_id == job_id
      assert metadata.command == "echo hello"
      assert metadata.background == true
    end
  end

  describe "bring_to_foreground/1" do
    test "brings background job to foreground", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", true)

      assert :ok = GenServer.call(jm, {:bring_to_foreground, job_id})

      {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.background? == false
    end

    test "returns :not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:bring_to_foreground, 9999})
    end

    test "returns :not_background for foreground job", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      assert {:error, :not_background} = GenServer.call(jm, {:bring_to_foreground, job_id})
    end
  end

  describe "send_to_background/1" do
    test "sends foreground job to background", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      assert :ok = GenServer.call(jm, {:send_to_background, job_id})

      {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.background? == true
    end

    test "returns :not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:send_to_background, 9999})
    end

    test "returns :already_background for background job", %{
      job_manager: jm,
      execution_plan: plan
    } do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", true)

      assert {:error, :already_background} = GenServer.call(jm, {:send_to_background, job_id})
    end
  end

  describe "list_jobs/1" do
    test "filters by session_id", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id1} = JobManager.start_job(jm, plan, "echo 1", "session1", false)
      {:ok, job_id2} = JobManager.start_job(jm, plan, "echo 2", "session1", false)
      {:ok, _job_id3} = JobManager.start_job(jm, plan, "echo 3", "session2", false)

      jobs = JobManager.list_jobs(jm, "session1")

      assert length(jobs) == 2
      assert Enum.any?(jobs, fn job -> job.id == job_id1 end)
      assert Enum.any?(jobs, fn job -> job.id == job_id2 end)
    end

    test "returns all jobs when session_id is nil", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id1} = JobManager.start_job(jm, plan, "echo 1", "session1", false)
      {:ok, job_id2} = JobManager.start_job(jm, plan, "echo 2", "session2", false)

      jobs = JobManager.list_jobs(jm, nil)

      assert length(jobs) >= 2
      assert Enum.any?(jobs, fn job -> job.id == job_id1 end)
      assert Enum.any?(jobs, fn job -> job.id == job_id2 end)
    end
  end

  describe "wait_for_job/2" do
    test "finished job returns immediately", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Complete the job first
      GenServer.cast(jm, {:job_completed, job_id, 0})

      # Should return immediately
      assert {:ok, job} = GenServer.call(jm, {:wait_for_job, job_id}, 100)
      assert job.status == :completed
      assert job.exit_status == 0
    end

    test "unfinished job suspends caller until completion", %{
      job_manager: jm,
      execution_plan: plan
    } do
      {:ok, job_id} = JobManager.start_job(jm, plan, "sleep 2", "session123", false)

      # This should block until the job completes naturally
      start_time = System.monotonic_time(:millisecond)
      assert {:ok, job} = GenServer.call(jm, {:wait_for_job, job_id}, 10000)
      end_time = System.monotonic_time(:millisecond)

      assert job.status == :completed
      assert job.exit_status == 0
      # Should have waited at least 1800ms (sleep 2 = 2000ms, allowing for timing variations)
      assert end_time - start_time >= 1800
    end

    test "returns :not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:wait_for_job, 9999}, 100)
    end
  end

  describe "kill_job/2" do
    test "kills job with :sigterm", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "sleep 10", "session123", false)

      # Give job a moment to start
      Process.sleep(10)

      assert :ok = GenServer.call(jm, {:kill_job, job_id, :sigterm})
    end

    test "kills job with :sigkill", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "sleep 10", "session123", false)

      # Give job a moment to start
      Process.sleep(10)

      assert :ok = GenServer.call(jm, {:kill_job, job_id, :sigkill})
    end

    test "returns :not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:kill_job, 9999, :sigterm})
    end

    test "returns :no_process when job has no pid", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Complete the job so it no longer has an active process
      GenServer.cast(jm, {:job_completed, job_id, 0})

      # Manually set pid to nil to simulate the condition
      GenServer.call(jm, {:test_set_job_pid, job_id, nil})

      assert {:error, :no_process} = GenServer.call(jm, {:kill_job, job_id, :sigterm})
    end
  end

  describe "process exit handling" do
    test "handles EXIT message and updates job status", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Create a dummy task that will exit
      dummy_task =
        Task.async(fn ->
          Process.sleep(50)
          :normal_exit
        end)

      # Inject the dummy task's PID into the job
      GenServer.call(jm, {:test_set_job_pid, job_id, dummy_task.pid})

      # Link the dummy task to the job manager so it receives EXIT messages
      GenServer.cast(jm, {:link_process, dummy_task.pid})

      # Wait for the task to complete naturally
      Task.await(dummy_task)

      # Give the JobManager time to process the EXIT message
      Process.sleep(50)

      # Check that the job was marked as completed
      {:ok, updated_job} = GenServer.call(jm, {:get_job, job_id})
      assert updated_job.status == :completed
      assert updated_job.exit_status == 0
      assert %DateTime{} = updated_job.completed_at
    end

    test "handles different exit reasons correctly", %{job_manager: jm, execution_plan: plan} do
      test_cases = [
        {:normal, 0},
        {:killed, 128 + 9},
        {:interrupt, 128 + 2},
        {:other_reason, 1}
      ]

      for {reason, expected_exit_status} <- test_cases do
        {:ok, job_id} = JobManager.start_job(jm, plan, "test #{reason}", "session123", false)

        # Create a dummy task that will exit with the specified reason
        dummy_task =
          Task.async(fn ->
            Process.sleep(10)
            exit(reason)
          end)

        # Inject the dummy task's PID into the job
        GenServer.call(jm, {:test_set_job_pid, job_id, dummy_task.pid})

        # Link the dummy task to the job manager so it receives EXIT messages
        GenServer.cast(jm, {:link_process, dummy_task.pid})

        # Wait for the task to exit and the JobManager to process it
        catch_exit(Task.await(dummy_task))
        Process.sleep(50)

        # Check that the job was marked with the correct exit status
        {:ok, updated_job} = GenServer.call(jm, {:get_job, job_id})
        assert updated_job.exit_status == expected_exit_status
      end
    end

    test "notifies waiters when job exits", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Start waiting for the job in a separate process
      waiter_task =
        Task.async(fn ->
          GenServer.call(jm, {:wait_for_job, job_id}, 5000)
        end)

      # Give the waiter time to register
      Process.sleep(10)

      # Get the job and inject a dummy task PID
      dummy_task =
        Task.async(fn ->
          Process.sleep(30)
          :normal
        end)

      GenServer.call(jm, {:test_set_job_pid, job_id, dummy_task.pid})

      # Link the dummy task to the job manager so it receives EXIT messages
      GenServer.cast(jm, {:link_process, dummy_task.pid})

      # Wait for the dummy task to complete
      Task.await(dummy_task)

      # The waiter should be notified
      assert {:ok, job} = Task.await(waiter_task)
      assert job.status == :completed
    end

    test "emits telemetry completed event on exit", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Create and inject dummy task
      dummy_task =
        Task.async(fn ->
          Process.sleep(20)
          :normal
        end)

      GenServer.call(jm, {:test_set_job_pid, job_id, dummy_task.pid})

      # Link the dummy task to the job manager so it receives EXIT messages
      GenServer.cast(jm, {:link_process, dummy_task.pid})

      # Wait for completion
      Task.await(dummy_task)
      Process.sleep(50)

      assert_receive {:telemetry, [:kodo, :job, :completed], measurements, metadata}
      assert metadata.job_id == job_id
      assert metadata.exit_status == 0
      assert is_number(measurements.duration)
    end
  end

  describe "cleanup timer" do
    test "removes completed job after cleanup timeout", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      # Complete the job
      GenServer.cast(jm, {:job_completed, job_id, 0})

      # Job should still be accessible immediately after completion
      assert {:ok, _job} = GenServer.call(jm, {:get_job, job_id})

      # Force immediate cleanup by sending the cleanup message
      send(jm, {:cleanup_job, job_id})
      Process.sleep(10)

      # Job should now be removed
      assert {:error, :not_found} = GenServer.call(jm, {:get_job, job_id})
    end

    test "does not remove active jobs during cleanup", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "sleep 2", "session123", false)

      # Try to cleanup an active job (should not be removed)
      send(jm, {:cleanup_job, job_id})
      Process.sleep(10)

      # Job should still be accessible
      assert {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.status == :running
    end
  end

  describe "telemetry" do
    test "emits job started event with correct metadata", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo test", "session123", true)

      assert_receive {:telemetry, [:kodo, :job, :started], %{count: 1}, metadata}
      assert metadata.job_id == job_id
      assert metadata.command == "echo test"
      assert metadata.background == true
    end

    test "emits job completed event with duration", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo test", "session123", false)

      # Complete the job manually
      GenServer.cast(jm, {:job_completed, job_id, 42})

      assert_receive {:telemetry, [:kodo, :job, :completed], measurements, metadata}
      assert metadata.job_id == job_id
      assert metadata.exit_status == 42
      assert is_number(measurements.duration)
      assert measurements.duration >= 0
    end
  end

  describe "other GenServer calls" do
    test "get_job returns job when found", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      assert {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.id == job_id
      assert job.command == "echo hello"
    end

    test "get_job returns not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:get_job, 9999})
    end

    test "stop_job stops running job", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "sleep 10", "session123", false)

      assert :ok = GenServer.call(jm, {:stop_job, job_id})
    end

    test "stop_job returns not_found for non-existent job", %{job_manager: jm} do
      assert {:error, :not_found} = GenServer.call(jm, {:stop_job, 9999})
    end

    test "job_stopped updates job status", %{job_manager: jm, execution_plan: plan} do
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)

      GenServer.cast(jm, {:job_stopped, job_id})

      {:ok, job} = GenServer.call(jm, {:get_job, job_id})
      assert job.status == :stopped
    end

    test "next_job_id returns the next available ID", %{job_manager: jm, execution_plan: plan} do
      next_id = GenServer.call(jm, :next_job_id)
      assert is_integer(next_id)
      assert next_id > 0

      # Start a job and verify next_id increments
      {:ok, job_id} = JobManager.start_job(jm, plan, "echo hello", "session123", false)
      assert job_id == next_id
      assert GenServer.call(jm, :next_job_id) == next_id + 1
    end
  end
end

# Add test helper functions to JobManager for testing
defmodule Kodo.Core.Jobs.JobManager.TestHelpers do
  @moduledoc false

  # This module extension allows us to add test-specific functionality
  # without modifying the main JobManager module

  def inject_test_pid(job_manager_pid, job_id, new_pid) do
    GenServer.call(job_manager_pid, {:test_set_job_pid, job_id, new_pid})
  end
end
