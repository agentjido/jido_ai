defmodule Kodo.Core.Jobs.JobTest do
  use Kodo.Case, async: true

  alias Kodo.Core.Jobs.Job

  describe "job creation and management" do
    test "new/4 creates a job with default values" do
      job = Job.new(1, "echo hello", "session123")

      assert job.id == 1
      assert job.command == "echo hello"
      assert job.session_id == "session123"
      assert job.background? == false
      assert job.status == :running
      assert job.pid == nil
      assert job.exit_status == nil
      assert job.completed_at == nil
      assert %DateTime{} = job.started_at
    end

    test "new/4 creates a background job when specified" do
      job = Job.new(2, "sleep 10", "session456", true)

      assert job.background? == true
      assert job.status == :running
    end

    test "set_pid/2 updates the job's PID" do
      job = Job.new(1, "test", "session123")
      pid = spawn(fn -> :ok end)

      updated_job = Job.set_pid(job, pid)
      assert updated_job.pid == pid
    end

    test "complete/2 marks job as completed with exit code 0" do
      job = Job.new(1, "test", "session123")
      completed_job = Job.complete(job, 0)

      assert completed_job.status == :completed
      assert completed_job.exit_status == 0
      assert %DateTime{} = completed_job.completed_at
    end

    test "complete/2 marks job as failed with non-zero exit code" do
      job = Job.new(1, "test", "session123")
      failed_job = Job.complete(job, 1)

      assert failed_job.status == :failed
      assert failed_job.exit_status == 1
      assert %DateTime{} = failed_job.completed_at
    end

    test "stop/1 marks job as stopped" do
      job = Job.new(1, "test", "session123")
      stopped_job = Job.stop(job)

      assert stopped_job.status == :stopped
    end

    test "resume/1 marks job as running" do
      job = Job.new(1, "test", "session123") |> Job.stop()
      resumed_job = Job.resume(job)

      assert resumed_job.status == :running
    end
  end

  describe "job status queries" do
    test "active?/1 returns true for running jobs" do
      job = Job.new(1, "test", "session123")
      assert Job.active?(job) == true
    end

    test "active?/1 returns true for stopped jobs" do
      job = Job.new(1, "test", "session123") |> Job.stop()
      assert Job.active?(job) == true
    end

    test "active?/1 returns false for completed jobs" do
      job = Job.new(1, "test", "session123") |> Job.complete(0)
      assert Job.active?(job) == false
    end

    test "active?/1 returns false for failed jobs" do
      job = Job.new(1, "test", "session123") |> Job.complete(1)
      assert Job.active?(job) == false
    end

    test "finished?/1 returns false for running jobs" do
      job = Job.new(1, "test", "session123")
      assert Job.finished?(job) == false
    end

    test "finished?/1 returns false for stopped jobs" do
      job = Job.new(1, "test", "session123") |> Job.stop()
      assert Job.finished?(job) == false
    end

    test "finished?/1 returns true for completed jobs" do
      job = Job.new(1, "test", "session123") |> Job.complete(0)
      assert Job.finished?(job) == true
    end

    test "finished?/1 returns true for failed jobs" do
      job = Job.new(1, "test", "session123") |> Job.complete(1)
      assert Job.finished?(job) == true
    end
  end

  describe "job status strings and formatting" do
    test "status_string/1 returns correct strings for each status" do
      base_job = Job.new(1, "test", "session123")

      # Running foreground
      assert Job.status_string(base_job) == "Foreground"

      # Running background
      bg_job = Job.new(1, "test", "session123", true)
      assert Job.status_string(bg_job) == "Running"

      # Stopped
      stopped_job = Job.stop(base_job)
      assert Job.status_string(stopped_job) == "Stopped"

      # Completed
      completed_job = Job.complete(base_job, 0)
      assert Job.status_string(completed_job) == "Done"

      # Failed
      failed_job = Job.complete(base_job, 1)
      assert Job.status_string(failed_job) == "Failed"
    end

    test "format/1 returns formatted job string for foreground job" do
      job = Job.new(5, "echo hello", "session123")
      formatted = Job.format(job)

      assert formatted =~ "[5]"
      assert formatted =~ "Foreground"
      assert formatted =~ "echo hello"
      refute formatted =~ "&"
    end

    test "format/1 returns formatted job string for background job" do
      job = Job.new(3, "sleep 10", "session456", true)
      formatted = Job.format(job)

      assert formatted =~ "[3]&"
      assert formatted =~ "Running"
      assert formatted =~ "sleep 10"
    end
  end
end
