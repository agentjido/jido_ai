defmodule Kodo.VFSIntegrationTest do
  use ExUnit.Case, async: false

  setup do
    # Create a unique instance for each test
    instance = :"test_integration_#{System.system_time(:nanosecond)}_#{:rand.uniform(1_000_000)}"

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

  describe "top-level VFS API" do
    test "mount/4, mounts/1, and unmount/2 work from Kodo module", %{instance: instance} do
      # Mount a filesystem
      assert :ok = Kodo.mount(instance, "/test", Depot.Adapter.InMemory, name: :TestFS)

      # List mounts and verify our mount is there
      {_root_fs, mounts} = Kodo.mounts(instance)
      assert Map.has_key?(mounts, "/test")

      # Unmount the filesystem
      assert :ok = Kodo.unmount(instance, "/test")

      # Verify it's been removed
      {_root_fs, mounts_after} = Kodo.mounts(instance)
      refute Map.has_key?(mounts_after, "/test")
    end

    test "VFS operations work across mounted filesystems", %{instance: instance} do
      # Mount a filesystem
      :ok = Kodo.mount(instance, "/data", Depot.Adapter.InMemory, name: :DataFS)

      # Write to root filesystem
      assert :ok = Kodo.write(instance, "/root.txt", "root content")

      # Write to mounted filesystem
      assert :ok = Kodo.write(instance, "/data/data.txt", "data content")

      # Read from both
      assert {:ok, "root content"} = Kodo.read(instance, "/root.txt")
      assert {:ok, "data content"} = Kodo.read(instance, "/data/data.txt")

      # List files in root
      {:ok, root_files} = Kodo.ls(instance, "/")
      root_file_names = Enum.map(root_files, & &1.name)
      assert "root.txt" in root_file_names

      # List files in mounted filesystem
      {:ok, data_files} = Kodo.ls(instance, "/data")
      data_file_names = Enum.map(data_files, & &1.name)
      assert "data.txt" in data_file_names

      # Check existence
      assert Kodo.exists?(instance, "/root.txt")
      assert Kodo.exists?(instance, "/data/data.txt")
      refute Kodo.exists?(instance, "/nonexistent.txt")

      # Delete a file
      assert :ok = Kodo.delete(instance, "/root.txt")
      refute Kodo.exists?(instance, "/root.txt")
    end

    test "error handling for invalid mount operations", %{instance: instance} do
      # Try to unmount non-existent mount
      assert {:error, :not_mounted} = Kodo.unmount(instance, "/nonexistent")

      # Mount should succeed
      assert :ok = Kodo.mount(instance, "/valid", Depot.Adapter.InMemory, name: :ValidFS)

      # Unmount should succeed
      assert :ok = Kodo.unmount(instance, "/valid")
    end
  end
end
