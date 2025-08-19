defmodule KodoTest do
  use ExUnit.Case, async: false
  doctest Kodo

  setup do
    # Clean up any test instances
    test_instances = [:api_test_1, :api_test_2, :api_test_3, :session_test, :component_test]

    for instance <- test_instances do
      if Kodo.exists?(instance) do
        Kodo.stop(instance)
      end
    end

    :ok
  end

  describe "instance management" do
    test "start/1 creates a new instance" do
      instance_name = :api_test_1

      assert {:ok, pid} = Kodo.start(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
      assert Kodo.exists?(instance_name)
    end

    test "start/1 returns existing PID for already started instance" do
      instance_name = :api_test_2

      assert {:ok, pid1} = Kodo.start(instance_name)
      assert {:ok, pid2} = Kodo.start(instance_name)
      assert pid1 == pid2
    end

    test "stop/1 stops an existing instance" do
      instance_name = :api_test_3

      assert {:ok, pid} = Kodo.start(instance_name)
      assert Kodo.exists?(instance_name)

      assert :ok = Kodo.stop(instance_name)
      refute Kodo.exists?(instance_name)

      # Wait for process to actually terminate
      Process.sleep(10)
      refute Process.alive?(pid)
    end

    test "stop/1 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.stop(:non_existent_instance)
    end

    test "list/0 returns all active instances" do
      instances_before = Kodo.list()

      assert {:ok, _} = Kodo.start(:list_test_1)
      assert {:ok, _} = Kodo.start(:list_test_2)

      instances_after = Kodo.list()

      assert :list_test_1 in instances_after
      assert :list_test_2 in instances_after
      assert length(instances_after) == length(instances_before) + 2

      # Clean up
      Kodo.stop(:list_test_1)
      Kodo.stop(:list_test_2)
    end

    test "exists?/1 returns true for existing instances" do
      instance_name = :exists_test

      refute Kodo.exists?(instance_name)

      assert {:ok, _} = Kodo.start(instance_name)
      assert Kodo.exists?(instance_name)

      assert :ok = Kodo.stop(instance_name)
      refute Kodo.exists?(instance_name)
    end

    test "default instance exists on startup" do
      assert Kodo.exists?(:default)
      assert :default in Kodo.list()
    end
  end

  describe "session management (placeholders)" do
    setup do
      instance_name = :session_test
      {:ok, _} = Kodo.start(instance_name)

      on_exit(fn -> Kodo.stop(instance_name) end)

      %{instance_name: instance_name}
    end

    test "session/1 returns placeholder session", %{instance_name: instance_name} do
      assert {:ok, session_id, session_pid} = Kodo.session(instance_name)

      assert is_binary(session_id)
      assert byte_size(session_id) == 8
      assert is_pid(session_pid)
      assert Process.alive?(session_pid)
    end

    test "session/1 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.session(:non_existent_instance)
    end

    test "eval/3 returns placeholder result", %{instance_name: instance_name} do
      assert {:ok, session_id, _pid} = Kodo.session(instance_name)

      expression = "1 + 1"
      assert {:ok, result} = Kodo.eval(instance_name, session_id, expression)
      assert result == {:placeholder_eval, instance_name, session_id, expression}
    end

    test "eval/3 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.eval(:non_existent_instance, "session_id", "1 + 1")
    end
  end

  describe "component access" do
    setup do
      instance_name = :component_test
      {:ok, _} = Kodo.start(instance_name)

      # Give the instance time to start its components
      Process.sleep(10)

      on_exit(fn -> Kodo.stop(instance_name) end)

      %{instance_name: instance_name}
    end

    test "commands/1 returns command registry PID", %{instance_name: instance_name} do
      assert {:ok, pid} = Kodo.commands(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "commands/1 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.commands(:non_existent_instance)
    end

    test "jobs/1 returns job manager PID", %{instance_name: instance_name} do
      assert {:ok, pid} = Kodo.jobs(instance_name)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "jobs/1 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.jobs(:non_existent_instance)
    end


  end

  describe "command and job management (placeholders)" do
    setup do
      instance_name = :placeholder_test
      {:ok, _} = Kodo.start(instance_name)

      # Give the instance time to start its components
      Process.sleep(10)

      on_exit(fn -> Kodo.stop(instance_name) end)

      %{instance_name: instance_name}
    end

    test "add_command/2 returns placeholder success", %{instance_name: instance_name} do
      assert :ok = Kodo.add_command(instance_name, SomeCommandModule)
    end

    test "add_command/2 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.add_command(:non_existent_instance, SomeCommandModule)
    end

    test "job/5 returns placeholder job ID", %{instance_name: instance_name} do
      execution_plan = %{command: "echo", args: ["hello"]}
      command_string = "echo hello"
      session_id = "test_session"

      assert {:ok, job_id} = Kodo.job(instance_name, execution_plan, command_string, session_id)
      assert is_integer(job_id)
      assert job_id > 0
    end

    test "job/5 with background flag returns placeholder job ID", %{instance_name: instance_name} do
      execution_plan = %{command: "sleep", args: ["5"]}
      command_string = "sleep 5"
      session_id = "test_session"

      assert {:ok, job_id} =
               Kodo.job(instance_name, execution_plan, command_string, session_id, true)

      assert is_integer(job_id)
      assert job_id > 0
    end

    test "job/5 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.job(:non_existent_instance, %{}, "cmd", "session", false)
    end

    test "list_jobs/2 returns empty list placeholder", %{instance_name: instance_name} do
      assert {:ok, jobs} = Kodo.list_jobs(instance_name)
      assert jobs == []
    end

    test "list_jobs/2 with session filter returns empty list placeholder", %{
      instance_name: instance_name
    } do
      assert {:ok, jobs} = Kodo.list_jobs(instance_name, "session_id")
      assert jobs == []
    end

    test "list_jobs/2 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.list_jobs(:non_existent_instance)
    end
  end

  describe "VFS operations (placeholders)" do
    setup do
      instance_name = :vfs_test
      {:ok, _} = Kodo.start(instance_name)

      # Give the instance time to start its components
      Process.sleep(10)

      on_exit(fn -> Kodo.stop(instance_name) end)

      %{instance_name: instance_name}
    end

    test "mount/4 returns placeholder success", %{instance_name: instance_name} do
      assert :ok = Kodo.mount(instance_name, "/data", Depot.Adapter.InMemory, name: :DataFS)
    end

    test "mount/4 returns error for non-existent instance" do
      assert {:error, :not_found} =
               Kodo.mount(:non_existent_instance, "/data", Depot.Adapter.InMemory, name: :TestFS)
    end

    test "unmount/2 returns placeholder success", %{instance_name: instance_name} do
      # First mount something to unmount
      assert :ok = Kodo.mount(instance_name, "/data", Depot.Adapter.InMemory, name: :TestFS)
      assert :ok = Kodo.unmount(instance_name, "/data")
    end

    test "unmount/2 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.unmount(:non_existent_instance, "/data")
    end

    test "mounts/1 returns root mount", %{instance_name: instance_name} do
      assert {:ok, mounts} = Kodo.mounts(instance_name)
      assert length(mounts) == 1
      assert {"/", Depot.Adapter.InMemory, _config} = hd(mounts)
    end

    test "mounts/1 returns error for non-existent instance" do
      assert {:error, :not_found} = Kodo.mounts(:non_existent_instance)
    end

    test "VFS file operations work with root filesystem", %{instance_name: instance_name} do
      # The VFS starts with a root InMemory filesystem, so operations should work
      assert :ok = Kodo.write(instance_name, "/test.txt", "content")
      assert {:ok, "content"} = Kodo.read(instance_name, "/test.txt")
      assert {:ok, [%Depot.Stat.File{name: "test.txt"}]} = Kodo.ls(instance_name, "/")
      assert :ok = Kodo.delete(instance_name, "/test.txt")
      # Check that file no longer exists
      assert false == Kodo.file_exists?(instance_name, "/test.txt")
    end

    test "VFS file operations return error for non-existent instance" do
      instance = :non_existent_instance

      assert {:error, :not_found} = Kodo.read(instance, "/test.txt")
      assert {:error, :not_found} = Kodo.write(instance, "/test.txt", "content")
      assert {:error, :not_found} = Kodo.delete(instance, "/test.txt")
      assert {:error, :not_found} = Kodo.ls(instance, "/")
      assert {:error, :not_found} = Kodo.mkdir(instance, "/new_dir")
      assert {:error, :not_found} = Kodo.rm(instance, "/test.txt")
    end

    test "file_exists?/3 returns false placeholder", %{instance_name: instance_name} do
      assert Kodo.file_exists?(instance_name, "/test.txt") == false
    end

    test "file_exists?/3 returns false for non-existent instance" do
      assert Kodo.file_exists?(:non_existent_instance, "/test.txt") == false
    end
  end

  describe "API consistency" do
    test "all functions handle non-existent instances gracefully" do
      instance = :non_existent_instance

      # Instance management
      assert {:error, :not_found} = Kodo.stop(instance)
      assert Kodo.exists?(instance) == false

      # Session management
      assert {:error, :not_found} = Kodo.session(instance)
      assert {:error, :not_found} = Kodo.eval(instance, "session", "expression")

      # Component access
      assert {:error, :not_found} = Kodo.commands(instance)
      assert {:error, :not_found} = Kodo.jobs(instance)

      # Command and job management
      assert {:error, :not_found} = Kodo.add_command(instance, SomeModule)
      assert {:error, :not_found} = Kodo.job(instance, %{}, "cmd", "session", false)
      assert {:error, :not_found} = Kodo.list_jobs(instance)

      # VFS operations
      assert {:error, :not_found} =
               Kodo.mount(instance, "/path", Depot.Adapter.InMemory, name: :TestFS)

      assert {:error, :not_found} = Kodo.unmount(instance, "/path")
    end

    test "session IDs are unique" do
      instance_name = :unique_session_test
      assert {:ok, _} = Kodo.start(instance_name)

      # Give the instance time to start
      Process.sleep(10)

      assert {:ok, session_id1, _} = Kodo.session(instance_name)
      assert {:ok, session_id2, _} = Kodo.session(instance_name)

      assert session_id1 != session_id2
      assert is_binary(session_id1)
      assert is_binary(session_id2)

      Kodo.stop(instance_name)
    end
  end
end
