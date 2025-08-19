defmodule Kodo.Commands.FgTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Fg
  alias Kodo.Core.Jobs.JobManager

  describe "fg command behaviour implementation" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Fg.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Fg.name() == "fg"
      assert is_binary(Fg.description())
      assert is_binary(Fg.usage())
      assert Fg.meta() == [:builtin]
      assert function_exported?(Fg, :execute, 2)
    end

    test "is marked as builtin command" do
      assert :builtin in Fg.meta()
    end
  end

  describe "fg command execution" do
    setup context do
      setup_session_with_commands(context)
    end

    test "returns error when no background jobs available", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Fg.execute([], context)
      assert error == "No background jobs available"
    end

    test "returns error for invalid job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Fg.execute(["invalid"], context)
      assert error == "Invalid job ID: invalid"
    end

    test "returns error for non-existent job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Fg.execute(["999"], context)
      assert error == "Job 999 not found"
    end

    test "returns usage error for too many arguments", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}

      assert {:error, error} = Fg.execute(["1", "2"], context)
      assert String.contains?(error, "Usage:")
    end

    test "successfully foregrounds a background job with specific job ID", %{
      session_pid: session_pid,
      instance: instance,
      job_manager: jm
    } do
      context = %{session_pid: session_pid, instance: instance, job_manager: jm}
      session_id = "session_#{:erlang.phash2(session_pid)}"

      # Create a background job
      execution_plan = %Kodo.Core.Parsing.ExecutionPlan{
        pipelines: [
          %Kodo.Core.Parsing.ExecutionPlan.Pipeline{
            commands: [%Kodo.Core.Parsing.ExecutionPlan.Command{name: "echo", args: ["test"]}]
          }
        ]
      }

      {:ok, job_id} = JobManager.start_job(jm, execution_plan, "echo test", session_id, true)

      # Give it a moment to start
      Process.sleep(10)

      # Foreground the specific job - this should wait for completion
      assert {:ok, output} = Fg.execute([Integer.to_string(job_id)], context)
      # Successful completion returns empty string
      assert output == ""
    end
  end
end
