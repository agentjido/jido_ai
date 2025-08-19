defmodule Kodo.Commands.BgTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Bg
  alias Kodo.Core.Jobs.JobManager

  describe "bg command behaviour implementation" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Bg.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Bg.name() == "bg"
      assert is_binary(Bg.description())
      assert is_binary(Bg.usage())
      assert Bg.meta() == [:builtin]
      assert function_exported?(Bg, :execute, 2)
    end

    test "is marked as builtin command" do
      assert :builtin in Bg.meta()
    end
  end

  describe "bg command execution" do
    setup context do
      setup_session_with_commands(context)
    end

    test "returns error when no foreground jobs available", %{
      session_pid: session_pid,
      instance: instance
    } do
      context = %{session_pid: session_pid, instance: instance}

      assert {:error, error} = Bg.execute([], context)
      assert error == "No foreground jobs available"
    end

    test "returns error for invalid job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Bg.execute(["invalid"], context)
      assert error == "Invalid job ID: invalid"
    end

    test "returns error for non-existent job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Bg.execute(["999"], context)
      assert error == "Job 999 not found"
    end

    test "returns usage error for too many arguments", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Bg.execute(["1", "2"], context)
      assert String.contains?(error, "Usage:")
    end

    test "successfully backgrounds a foreground job with specific job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}
      session_id = "session_#{:erlang.phash2(session_pid)}"

      # Create a foreground job
      execution_plan = %Kodo.Core.Parsing.ExecutionPlan{
        pipelines: [
          %Kodo.Core.Parsing.ExecutionPlan.Pipeline{
            commands: [%Kodo.Core.Parsing.ExecutionPlan.Command{name: "sleep", args: ["10"]}]
          }
        ]
      }

      {:ok, job_id} = JobManager.start_job(jm, execution_plan, "sleep 10", session_id, false)

      # Give it a moment to start
      Process.sleep(10)

      # Background the specific job
      assert {:ok, output} = Bg.execute([Integer.to_string(job_id)], context)
      assert String.contains?(output, "sleep 10")
    end
  end
end
