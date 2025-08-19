defmodule Kodo.AdvancedFilesystemTest do
  use ExUnit.Case, async: false

  setup do
    # Create a unique instance for each test
    instance = :"test_advanced_fs_#{System.system_time(:nanosecond)}_#{:rand.uniform(1_000_000)}"

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

  describe "stat/2 operation" do
    test "stat returns file metadata for InMemory adapter", %{instance: instance} do
      # Write a test file first
      :ok = Kodo.write(instance, "test.txt", "test content")

      result = Kodo.VFS.stat(instance, "test.txt")
      assert {:ok, stat} = result
      assert %Depot.Stat.File{} = stat
      assert stat.name == "test.txt"
      assert stat.size == 12
    end

    test "stat via top-level API delegates to VFS", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      result = Kodo.stat(instance, "test.txt")
      assert {:ok, stat} = result
      assert %Depot.Stat.File{} = stat
    end
  end

  describe "access/3 operation" do
    test "access works for InMemory adapter", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      result = Kodo.VFS.access(instance, "test.txt", [:read])
      assert :ok = result
    end

    test "access with different modes", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      # Test different access modes
      assert :ok = Kodo.VFS.access(instance, "test.txt", [:read])
      assert :ok = Kodo.VFS.access(instance, "test.txt", [:write])
      assert :ok = Kodo.VFS.access(instance, "test.txt", [:read, :write])
    end

    test "access via top-level API delegates to VFS", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      result = Kodo.access(instance, "test.txt", [:read])
      assert :ok = result
    end
  end

  describe "append/3 operation" do
    test "append works for InMemory adapter", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "initial content")

      result = Kodo.VFS.append(instance, "test.txt", "\nappended content")
      assert :ok = result

      # Verify content was appended
      {:ok, content} = Kodo.read(instance, "test.txt")
      assert content == "initial content\nappended content"
    end

    test "append via top-level API delegates to VFS", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "initial content")

      result = Kodo.append(instance, "test.txt", "\nappended content")
      assert :ok = result
    end
  end

  describe "truncate/3 operation" do
    test "truncate works for InMemory adapter", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "this is a long file content")

      result = Kodo.VFS.truncate(instance, "test.txt", 10)
      assert :ok = result

      # Verify content was truncated
      {:ok, content} = Kodo.read(instance, "test.txt")
      assert content == "this is a "
    end

    test "truncate via top-level API delegates to VFS", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "this is a long file content")

      result = Kodo.truncate(instance, "test.txt", 10)
      assert :ok = result
    end
  end

  describe "utime/3 operation" do
    test "utime works for InMemory adapter", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      now = DateTime.utc_now()
      result = Kodo.VFS.utime(instance, "test.txt", now)
      assert :ok = result
    end

    test "utime with DateTime", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      # Use DateTime instead of raw timestamp
      datetime = DateTime.from_unix!(System.system_time(:second), :second)
      result = Kodo.VFS.utime(instance, "test.txt", datetime)
      assert :ok = result
    end

    test "utime via top-level API delegates to VFS", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      now = DateTime.utc_now()
      result = Kodo.utime(instance, "test.txt", now)
      assert :ok = result
    end
  end

  describe "advanced operations with Local adapter" do
    test "operations work with Local adapter", %{instance: instance} do
      # Mount a local adapter 
      local_path = System.tmp_dir!() |> Path.join("test_advanced_#{:rand.uniform(10000)}")
      File.mkdir_p!(local_path)
      on_exit(fn -> File.rm_rf!(local_path) end)

      :ok = Kodo.VFS.mount(instance, "/local", Depot.Adapter.Local, prefix: local_path)

      # Write a test file
      :ok = Kodo.write(instance, "/local/test.txt", "test content")

      # Test all advanced operations work with Local adapter
      assert {:ok, stat} = Kodo.VFS.stat(instance, "/local/test.txt")
      assert %Depot.Stat.File{} = stat
      assert :ok = Kodo.VFS.access(instance, "/local/test.txt", [:read])
      assert :ok = Kodo.VFS.append(instance, "/local/test.txt", " more")
      assert :ok = Kodo.VFS.truncate(instance, "/local/test.txt", 5)
      assert :ok = Kodo.VFS.utime(instance, "/local/test.txt", DateTime.utc_now())
    end
  end

  describe "error handling" do
    test "operations with non-existent files", %{instance: instance} do
      # Test operations on files that don't exist
      assert {:error, _} = Kodo.VFS.stat(instance, "nonexistent.txt")
      assert {:error, _} = Kodo.VFS.access(instance, "nonexistent.txt", [:read])
      # append creates the file if it doesn't exist (like write)
      assert :ok = Kodo.VFS.append(instance, "nonexistent.txt", "content")
      assert {:error, _} = Kodo.VFS.truncate(instance, "nonexistent2.txt", 0)
      assert {:error, _} = Kodo.VFS.utime(instance, "nonexistent3.txt", DateTime.utc_now())
    end

    test "operations with invalid parameters", %{instance: instance} do
      :ok = Kodo.write(instance, "test.txt", "test content")

      # Test truncate with negative size - this should cause an exception
      # We'll catch the exit from the GenServer crash
      catch_exit do
        Kodo.VFS.truncate(instance, "test.txt", -1)
      end
    end
  end

  describe "integration with supported adapters" do
    @describetag :flaky
    test "advanced operations would work with supporting adapters", %{instance: _instance} do
      # This is a conceptual test showing how the operations would work
      # with adapters that actually support these advanced operations

      # For example, if we had a fully-featured Local adapter:
      # :ok = Kodo.VFS.mount(instance, "/advanced", SomeAdvancedAdapter, config: %{})
      # :ok = Kodo.write(instance, "/advanced/test.txt", "content")
      # {:ok, stat} = Kodo.VFS.stat(instance, "/advanced/test.txt")
      # assert is_map(stat)
      # assert Map.has_key?(stat, :size)
      # assert Map.has_key?(stat, :mtime)

      # For now, just verify the plumbing works
      assert function_exported?(Kodo.VFS, :stat, 2)
      assert function_exported?(Kodo.VFS, :access, 3)
      assert function_exported?(Kodo.VFS, :append, 3)
      assert function_exported?(Kodo.VFS, :truncate, 3)
      assert function_exported?(Kodo.VFS, :utime, 3)

      # And top-level API
      assert function_exported?(Kodo, :stat, 2)
      assert function_exported?(Kodo, :access, 3)
      assert function_exported?(Kodo, :append, 3)
      assert function_exported?(Kodo, :truncate, 3)
      assert function_exported?(Kodo, :utime, 3)
    end
  end
end
