defmodule Kodo.RevisionSupportTest do
  use ExUnit.Case, async: false

  setup do
    # Create a unique instance for each test
    instance = :"test_revisions_#{System.system_time(:nanosecond)}_#{:rand.uniform(1_000_000)}"

    # Start the instance
    {:ok, _} = Kodo.start(instance)

    on_exit(fn ->
      try do
        Kodo.stop(instance)
      catch
        :exit, _ -> :ok
      end
    end)

    %{instance: instance}
  end

  describe "revision operations with unsupported adapters" do
    test "commit returns unsupported error for InMemory adapter", %{instance: instance} do
      result = Kodo.VFS.commit(instance, "/", "Test commit")
      assert {:error, :unsupported} = result
    end

    test "revisions returns unsupported error for InMemory adapter", %{instance: instance} do
      result = Kodo.VFS.revisions(instance, ".")
      assert {:error, :unsupported} = result
    end

    test "read_revision returns unsupported error for InMemory adapter", %{instance: instance} do
      result = Kodo.VFS.read_revision(instance, "test.txt", "abc123")
      assert {:error, :unsupported} = result
    end

    test "rollback returns unsupported error for InMemory adapter", %{instance: instance} do
      result = Kodo.VFS.rollback(instance, "/", "abc123")
      assert {:error, :unsupported} = result
    end
  end

  describe "revision operations with Local adapter (unsupported)" do
    test "commit returns unsupported for Local adapter", %{instance: instance} do
      # Mount a local adapter 
      local_path = System.tmp_dir!() |> Path.join("test_local")
      File.mkdir_p!(local_path)
      on_exit(fn -> File.rm_rf!(local_path) end)

      :ok = Kodo.VFS.mount(instance, "/local", Depot.Adapter.Local, prefix: local_path)

      result = Kodo.VFS.commit(instance, "/local", "Test commit")
      assert {:error, :unsupported} = result
    end
  end

  describe "revision operations error handling" do
    test "commit with non-existent mount point", %{instance: instance} do
      result = Kodo.VFS.commit(instance, "/nonexistent", "Test commit")
      assert {:error, :mount_not_found} = result
    end

    test "rollback with non-existent mount point", %{instance: instance} do
      result = Kodo.VFS.rollback(instance, "/nonexistent", "abc123")
      assert {:error, :mount_not_found} = result
    end
  end

  describe "top-level API revision methods" do
    test "commit delegates to VFS module", %{instance: instance} do
      result = Kodo.commit(instance, "/", "Test commit")
      assert {:error, :unsupported} = result
    end

    test "revisions delegates to VFS module", %{instance: instance} do
      result = Kodo.revisions(instance, ".")
      assert {:error, :unsupported} = result
    end

    test "read_revision delegates to VFS module", %{instance: instance} do
      result = Kodo.read_revision(instance, "test.txt", "abc123")
      assert {:error, :unsupported} = result
    end

    test "rollback delegates to VFS module", %{instance: instance} do
      result = Kodo.rollback(instance, "/", "abc123")
      assert {:error, :unsupported} = result
    end
  end

  describe "Git adapter integration" do
    @describetag :flaky
    test "Git adapter can be mounted", %{instance: instance} do
      # Create a temporary git repo
      git_path = System.tmp_dir!() |> Path.join("test_git_#{:rand.uniform(10000)}")
      File.mkdir_p!(git_path)
      on_exit(fn -> File.rm_rf!(git_path) end)

      # Initialize git repo
      System.cmd("git", ["init"], cd: git_path)
      System.cmd("git", ["config", "user.name", "Test User"], cd: git_path)
      System.cmd("git", ["config", "user.email", "test@example.com"], cd: git_path)

      # Create initial commit
      test_file = Path.join(git_path, "test.txt")
      File.write!(test_file, "initial content")
      System.cmd("git", ["add", "."], cd: git_path)
      System.cmd("git", ["commit", "-m", "Initial commit"], cd: git_path)

      # Mount the git repo
      result = Kodo.VFS.mount(instance, "/git", Depot.Adapter.Git, path: git_path, mode: :manual)
      assert :ok = result

      # Test revision operations should now work (though we can't test exact behavior without git setup)
      assert {:ok, _} = Kodo.VFS.mounts(instance)
    end
  end
end
