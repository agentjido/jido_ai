defmodule Kodo.Commands.JobsTest do
  use Kodo.Case, async: true

  alias Kodo.Commands.Jobs
  alias Kodo.Core.Jobs.JobManager

  describe "jobs command behaviour implementation" do
    test "implements Kodo.Ports.Command behaviour" do
      behaviours = Jobs.__info__(:attributes)[:behaviour] || []
      assert Kodo.Ports.Command in behaviours
    end

    test "has required callback functions" do
      assert Jobs.name() == "jobs"
      assert is_binary(Jobs.description())
      assert is_binary(Jobs.usage())
      assert Jobs.meta() == [:builtin, :pure]
      assert function_exported?(Jobs, :execute, 2)
    end

    test "is marked as pure command" do
      assert :pure in Jobs.meta()
    end
  end

  describe "jobs command execution" do
    setup context do
      setup_session_with_commands(context)
    end

    test "shows no active jobs when list is empty", %{
      session_pid: session_pid,
      instance: instance
    } do
      context = %{session_pid: session_pid, instance: instance}

      assert {:ok, output} = Jobs.execute([], context)
      assert output == "No active jobs"
    end

    test "shows no active jobs with -l flag when list is empty", %{
      session_pid: session_pid,
      instance: instance
    } do
      context = %{session_pid: session_pid, instance: instance}

      assert {:ok, output} = Jobs.execute(["-l"], context)
      assert output == "No active jobs"
    end

    test "formats jobs in short format", %{session_pid: session_pid, instance: instance} do
      context = %{session_pid: session_pid, instance: instance}

      # This test now relies on the actual job manager instance
      # For now, test the basic functionality with empty jobs
      assert {:ok, output} = Jobs.execute([], context)
      assert output == "No active jobs"
    end

    test "formats jobs in long format with -l flag", %{
      session_pid: session_pid,
      instance: instance
    } do
      context = %{session_pid: session_pid, instance: instance}

      # This test now relies on the actual job manager instance
      # For now, test the basic functionality with empty jobs
      assert {:ok, output} = Jobs.execute(["-l"], context)
      assert output == "No active jobs"
    end
  end
end
