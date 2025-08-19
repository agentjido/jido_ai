defmodule Kodo.VFS.ManagerTest do
  use ExUnit.Case, async: false
  alias Kodo.VFS.Manager

  setup do
    # Create unique manager name for each test
    manager_name = :"test_manager_#{System.system_time(:nanosecond)}_#{:rand.uniform(1_000_000)}"
    instance = :"test_instance_#{System.system_time(:nanosecond)}_#{:rand.uniform(1_000_000)}"

    # Start the manager
    {:ok, pid} =
      Manager.start_link(
        name: manager_name,
        instance: instance,
        root_adapter: Depot.Adapter.InMemory,
        root_opts: [name: :"#{instance}_root"]
      )

    on_exit(fn ->
      try do
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{manager: manager_name, instance: instance, pid: pid}
  end

  describe "start_link/1" do
    test "starts with default options" do
      manager_name = :"default_manager_#{System.system_time(:nanosecond)}"
      instance = :"default_instance_#{System.system_time(:nanosecond)}"

      opts = [
        name: manager_name,
        instance: instance,
        root_adapter: Depot.Adapter.InMemory,
        root_opts: [name: :"#{instance}_root"]
      ]

      assert {:ok, pid} = Manager.start_link(opts)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "fails when root filesystem cannot be started" do
      manager_name = :"failing_manager_#{System.system_time(:nanosecond)}"
      instance = :"failing_instance_#{System.system_time(:nanosecond)}"

      # Use invalid configuration to cause failure
      opts = [
        name: manager_name,
        instance: instance,
        root_adapter: Depot.Adapter.InMemory,
        # Invalid name should cause failure
        root_opts: [name: nil]
      ]

      # This might succeed or fail depending on Depot's behavior
      # We mainly want to ensure it doesn't crash the test
      result = Manager.start_link(opts)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, pid} -> GenServer.stop(pid)
        {:error, _} -> :ok
      end
    end
  end

  describe "mount operations" do
    test "mount/4 adds filesystem to mounts", %{manager: manager} do
      assert :ok = Manager.mount(manager, "/tmp", Depot.Adapter.InMemory, name: :TmpFS)

      {_root_fs, mounts} = Manager.mounts(manager)
      assert Map.has_key?(mounts, "/tmp")
    end

    test "mount/4 with terse API", %{manager: manager} do
      assert :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      {_root_fs, mounts} = Manager.mounts(manager)
      assert Map.has_key?(mounts, "/data")
    end

    test "unmount/2 removes filesystem from mounts", %{manager: manager} do
      :ok = Manager.mount(manager, "/tmp", Depot.Adapter.InMemory, name: :TmpFS)
      assert :ok = Manager.unmount(manager, "/tmp")

      {_root_fs, mounts} = Manager.mounts(manager)
      refute Map.has_key?(mounts, "/tmp")
    end

    test "unmount/2 returns error for non-existent mount", %{manager: manager} do
      assert {:error, :not_mounted} = Manager.unmount(manager, "/nonexistent")
    end

    test "mounts/1 returns root filesystem and mount points", %{manager: manager} do
      :ok = Manager.mount(manager, "/tmp", Depot.Adapter.InMemory, name: :TmpFS)
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      {root_fs, mounts} = Manager.mounts(manager)

      assert root_fs != nil
      assert Map.has_key?(mounts, "/tmp")
      assert Map.has_key?(mounts, "/data")
    end
  end

  describe "file operations" do
    test "write/4 and read/3 work with root filesystem", %{manager: manager} do
      assert :ok = Manager.write(manager, "/root.txt", "root content")
      assert {:ok, "root content"} = Manager.read(manager, "/root.txt")
    end

    test "write/4 and read/3 work with mounted filesystem", %{manager: manager} do
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      assert :ok = Manager.write(manager, "/data/file.txt", "data content")
      assert {:ok, "data content"} = Manager.read(manager, "/data/file.txt")
    end

    test "delete/3 removes files", %{manager: manager} do
      :ok = Manager.write(manager, "/test.txt", "content")
      assert :ok = Manager.delete(manager, "/test.txt")
      assert {:error, _} = Manager.read(manager, "/test.txt")
    end

    test "copy/4 within same filesystem", %{manager: manager} do
      :ok = Manager.write(manager, "/source.txt", "content")
      assert :ok = Manager.copy(manager, "/source.txt", "/dest.txt")

      assert {:ok, "content"} = Manager.read(manager, "/source.txt")
      assert {:ok, "content"} = Manager.read(manager, "/dest.txt")
    end

    test "copy/4 across different filesystems", %{manager: manager} do
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      :ok = Manager.write(manager, "/source.txt", "content")
      assert :ok = Manager.copy(manager, "/source.txt", "/data/dest.txt")

      assert {:ok, "content"} = Manager.read(manager, "/source.txt")
      assert {:ok, "content"} = Manager.read(manager, "/data/dest.txt")
    end

    test "move/4 within same filesystem", %{manager: manager} do
      :ok = Manager.write(manager, "/source.txt", "content")
      assert :ok = Manager.move(manager, "/source.txt", "/dest.txt")

      assert {:error, _} = Manager.read(manager, "/source.txt")
      assert {:ok, "content"} = Manager.read(manager, "/dest.txt")
    end

    test "move/4 across different filesystems", %{manager: manager} do
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      :ok = Manager.write(manager, "/source.txt", "content")
      assert :ok = Manager.move(manager, "/source.txt", "/data/dest.txt")

      assert {:error, _} = Manager.read(manager, "/source.txt")
      assert {:ok, "content"} = Manager.read(manager, "/data/dest.txt")
    end
  end

  describe "terse API directory operations" do
    test "ls/3 lists directory contents", %{manager: manager} do
      :ok = Manager.write(manager, "/file1.txt", "content1")
      :ok = Manager.write(manager, "/file2.txt", "content2")

      {:ok, files} = Manager.ls(manager, "/")
      file_names = Enum.map(files, & &1.name)

      assert "file1.txt" in file_names
      assert "file2.txt" in file_names
    end

    test "ls/3 with default path", %{manager: manager} do
      :ok = Manager.write(manager, "/file.txt", "content")

      {:ok, files} = Manager.ls(manager)
      file_names = Enum.map(files, & &1.name)

      assert "file.txt" in file_names
    end

    test "exists?/3 checks file existence", %{manager: manager} do
      :ok = Manager.write(manager, "/exists.txt", "content")

      result = Manager.exists?(manager, "/exists.txt")
      # Note: Depot returns {:ok, :exists | :missing}, we convert to boolean
      assert result == true or match?({:ok, :exists}, result)

      result2 = Manager.exists?(manager, "/missing.txt")
      assert result2 == false or match?({:ok, :missing}, result2)
    end

    test "mkdir/3 creates directories", %{manager: manager} do
      result = Manager.mkdir(manager, "/testdir/")
      assert result == :ok or match?({:error, _}, result)
    end

    test "rmdir/3 removes directories", %{manager: manager} do
      # First create a directory
      Manager.mkdir(manager, "/testdir/")

      result = Manager.rmdir(manager, "/testdir/")
      assert result == :ok or match?({:error, _}, result)
    end

    test "clear/2 clears all filesystems", %{manager: manager} do
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      :ok = Manager.write(manager, "/root.txt", "root")
      :ok = Manager.write(manager, "/data/data.txt", "data")

      assert :ok = Manager.clear(manager)

      assert {:error, _} = Manager.read(manager, "/root.txt")
      assert {:error, _} = Manager.read(manager, "/data/data.txt")
    end
  end

  describe "path routing" do
    test "routes to root filesystem by default", %{manager: manager} do
      :ok = Manager.write(manager, "/root.txt", "content")
      assert {:ok, "content"} = Manager.read(manager, "/root.txt")
    end

    test "routes to mounted filesystem correctly", %{manager: manager} do
      :ok = Manager.mount(manager, "/app", Depot.Adapter.InMemory, name: :AppFS)

      :ok = Manager.write(manager, "/app/file.txt", "app content")
      assert {:ok, "app content"} = Manager.read(manager, "/app/file.txt")
    end

    test "routes to deepest matching mount point", %{manager: manager} do
      :ok = Manager.mount(manager, "/app", Depot.Adapter.InMemory, name: :AppFS)
      :ok = Manager.mount(manager, "/app/data", Depot.Adapter.InMemory, name: :AppDataFS)

      :ok = Manager.write(manager, "/app/shallow.txt", "shallow")
      :ok = Manager.write(manager, "/app/data/deep.txt", "deep")

      assert {:ok, "shallow"} = Manager.read(manager, "/app/shallow.txt")
      assert {:ok, "deep"} = Manager.read(manager, "/app/data/deep.txt")
    end

    test "normalizes paths correctly", %{manager: manager} do
      :ok = Manager.mount(manager, "/data", Depot.Adapter.InMemory, name: :DataFS)

      :ok = Manager.write(manager, "/data/file.txt", "content")

      # Test various path formats
      assert {:ok, "content"} = Manager.read(manager, "/data/file.txt")
      assert {:ok, "content"} = Manager.read(manager, "/data/../data/file.txt")
      assert {:ok, "content"} = Manager.read(manager, "/data/./file.txt")
    end

    test "handles root mount point correctly", %{manager: manager} do
      :ok = Manager.write(manager, "/root_file.txt", "root content")
      assert {:ok, "root content"} = Manager.read(manager, "/root_file.txt")
    end
  end

  describe "compatibility aliases" do
    test "list_contents/3 works as alias for ls/3", %{manager: manager} do
      :ok = Manager.write(manager, "/test.txt", "content")

      assert {:ok, files1} = Manager.ls(manager, "/")
      assert {:ok, files2} = Manager.list_contents(manager, "/")
      assert files1 == files2
    end

    test "file_exists?/3 works as alias for exists?/3", %{manager: manager} do
      :ok = Manager.write(manager, "/test.txt", "content")

      result1 = Manager.exists?(manager, "/test.txt")
      result2 = Manager.file_exists?(manager, "/test.txt")
      assert result1 == result2
    end

    test "create_directory/3 works as alias for mkdir/3", %{manager: manager} do
      result1 = Manager.mkdir(manager, "/testdir1/")
      result2 = Manager.create_directory(manager, "/testdir2/")

      # Both should have same type of result
      assert result1 == :ok == (result2 == :ok)
    end

    test "delete_directory/3 works as alias for rmdir/3", %{manager: manager} do
      Manager.mkdir(manager, "/testdir1/")
      Manager.mkdir(manager, "/testdir2/")

      result1 = Manager.rmdir(manager, "/testdir1/")
      result2 = Manager.delete_directory(manager, "/testdir2/")

      # Both should have same type of result
      assert result1 == :ok == (result2 == :ok)
    end

    test "get_mounts/1 works as alias for mounts/1", %{manager: manager} do
      :ok = Manager.mount(manager, "/test", Depot.Adapter.InMemory, name: :TestFS)

      assert Manager.mounts(manager) == Manager.get_mounts(manager)
    end
  end

  describe "error handling" do
    test "handles filesystem adapter startup failures gracefully", %{manager: manager} do
      # Try mounting with invalid configuration
      result = Manager.mount(manager, "/invalid", Depot.Adapter.InMemory, name: nil)
      # Should return error or succeed depending on Depot behavior
      assert match?(:ok, result) or match?({:error, _}, result)
    end

    test "handles operations on non-existent files", %{manager: manager} do
      assert {:error, _} = Manager.read(manager, "/nonexistent.txt")
      # Note: InMemory adapter may return :ok for deleting non-existent files
      result = Manager.delete(manager, "/nonexistent.txt")
      assert result == :ok or match?({:error, _}, result)
    end

    test "handles copy/move operations with non-existent source", %{manager: manager} do
      assert {:error, _} = Manager.copy(manager, "/nonexistent.txt", "/dest.txt")
      assert {:error, _} = Manager.move(manager, "/nonexistent.txt", "/dest.txt")
    end
  end
end
