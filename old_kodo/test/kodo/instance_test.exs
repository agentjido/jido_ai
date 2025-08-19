defmodule Kodo.InstanceTest do
  use ExUnit.Case, async: false

  alias Kodo.{InstanceManager, Instance}

  setup do
    # Ensure InstanceManager is running
    case GenServer.whereis(InstanceManager) do
      nil ->
        {:ok, _pid} = InstanceManager.start_link([])
        :ok

      _pid ->
        :ok
    end

    # Clean up any test instances
    on_exit(fn ->
      for instance <- InstanceManager.list() do
        if instance != :default do
          InstanceManager.stop(instance)
        end
      end
    end)

    # Start a test instance (handle case where it's already started)
    case InstanceManager.start(:test_instance) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    {:ok, instance: :test_instance}
  end

  describe "child/2" do
    test "returns child process for valid module", %{instance: instance} do
      assert {:ok, pid} = Instance.child(instance, Kodo.Core.Sessions.SessionSupervisor)
      assert is_pid(pid)
    end

    test "returns error for invalid module", %{instance: instance} do
      assert {:error, :not_found} = Instance.child(instance, NonExistentModule)
    end
  end

  describe "sessions/1" do
    test "returns session supervisor", %{instance: instance} do
      assert {:ok, pid} = Instance.sessions(instance)
      assert is_pid(pid)
    end
  end

  describe "commands/1" do
    test "returns command registry", %{instance: instance} do
      assert {:ok, pid} = Instance.commands(instance)
      assert is_pid(pid)
    end
  end

  describe "jobs/1" do
    test "returns job manager", %{instance: instance} do
      assert {:ok, pid} = Instance.jobs(instance)
      assert is_pid(pid)
    end
  end

  describe "vfs/1" do
    test "returns vfs manager", %{instance: instance} do
      assert {:ok, pid} = Instance.vfs(instance)
      assert is_pid(pid)
    end
  end

  describe "new_session/1" do
    test "creates a new session", %{instance: instance} do
      assert {:ok, session_id, session_pid} = Instance.new_session(instance)
      assert is_binary(session_id)
      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end

    test "creates multiple sessions", %{instance: instance} do
      {:ok, session_id1, session_pid1} = Instance.new_session(instance)
      {:ok, session_id2, session_pid2} = Instance.new_session(instance)

      assert session_id1 != session_id2
      assert session_pid1 != session_pid2
      assert Process.alive?(session_pid1)
      assert Process.alive?(session_pid2)
    end
  end

  describe "add_command/2" do
    test "registers a command module", %{instance: instance} do
      defmodule TestCommand do
        @behaviour Kodo.Ports.Command

        def name, do: "test_cmd"
        def description, do: "Test command"
        def usage, do: "test_cmd"
        def meta, do: %{}
        def execute(_args, _context), do: {:ok, "test output"}
      end

      assert :ok = Instance.add_command(instance, TestCommand)
    end

    test "returns error for invalid command module", %{instance: instance} do
      defmodule InvalidCommand do
        # Missing required functions
      end

      assert {:error, _reason} = Instance.add_command(instance, InvalidCommand)
    end
  end

  describe "new_job/5" do
    test "starts a new job", %{instance: instance} do
      execution_plan = %Kodo.Core.Parsing.ExecutionPlan.Command{
        name: "echo",
        args: ["hello"],
        redirections: []
      }

      assert {:ok, job_id} =
               Instance.new_job(instance, execution_plan, "echo hello", "test_session", false)

      assert is_integer(job_id)
    end

    test "starts background job", %{instance: instance} do
      execution_plan = %Kodo.Core.Parsing.ExecutionPlan.Command{
        name: "sleep",
        args: ["1"],
        redirections: []
      }

      assert {:ok, job_id} =
               Instance.new_job(instance, execution_plan, "sleep 1", "test_session", true)

      assert is_integer(job_id)
    end
  end

  describe "error handling" do
    test "handles non-existent instance gracefully" do
      assert {:error, :not_found} = Instance.sessions(:non_existent)
      assert {:error, :not_found} = Instance.commands(:non_existent)
      assert {:error, :not_found} = Instance.jobs(:non_existent)
      assert {:error, :not_found} = Instance.vfs(:non_existent)
    end
  end
end
