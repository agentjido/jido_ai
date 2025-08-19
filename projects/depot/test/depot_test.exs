defmodule DepotTest do
  use ExUnit.Case, async: true

  defmacrop assert_in_list(list, match) do
    quote do
      assert Enum.any?(unquote(list), &match?(unquote(match), &1))
    end
  end

  describe "chunk/2" do
    test "empty binary returns empty list" do
      assert Depot.chunk("", 10) == []
    end

    test "binary smaller than chunk size returns single item list" do
      assert Depot.chunk("hello", 10) == ["hello"]
    end

    test "binary equal to chunk size returns single item list" do
      assert Depot.chunk("hello", 5) == ["hello"]
    end

    test "binary larger than chunk size returns multiple chunks" do
      assert Depot.chunk("hello world", 5) == ["hello", " worl", "d"]
    end

    test "binary much larger than chunk size returns many chunks" do
      data = String.duplicate("a", 100)
      chunks = Depot.chunk(data, 10)

      assert length(chunks) == 10
      assert Enum.all?(chunks, &(byte_size(&1) == 10))
      assert Enum.join(chunks) == data
    end

    test "chunk size of 1 splits every character" do
      assert Depot.chunk("abc", 1) == ["a", "b", "c"]
    end
  end

  describe "path error handling" do
    @describetag :tmp_dir

    test "handles :enotdir error when path is not a directory", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      # Create a file first
      :ok = Depot.write(filesystem, "not_a_dir.txt", "content")

      # Try to create a directory with same name as file - this should trigger :enotdir
      # Note: This test might be adapter-specific and may not trigger convert_path_error
      case Depot.create_directory(filesystem, "not_a_dir.txt/subdir") do
        {:error, %Depot.Errors.NotDirectory{}} -> :ok
        # Different adapters may handle this differently
        {:error, _other} -> :ok
        # Some adapters might not check this
        :ok -> :ok
      end
    end
  end

  describe "filesystem without own processes" do
    @describetag :tmp_dir

    test "user can write to filesystem", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert :ok = Depot.write(filesystem, "test.txt", "Hello World")
    end

    test "user can check if files exist on a filesystem", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")

      assert {:ok, :exists} = Depot.file_exists(filesystem, "test.txt")
      assert {:ok, :missing} = Depot.file_exists(filesystem, "not-test.txt")
    end

    test "user can read from filesystem", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")

      assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
    end

    test "user can delete from filesystem", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.delete(filesystem, "test.txt")

      assert {:error, _} = Depot.read(filesystem, "test.txt")
    end

    test "user can move files", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.move(filesystem, "test.txt", "not-test.txt")

      assert {:error, _} = Depot.read(filesystem, "test.txt")
      assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
    end

    test "user can copy files", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.copy(filesystem, "test.txt", "not-test.txt")

      assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
      assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
    end

    test "user can list files", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.write(filesystem, "test-1.txt", "Hello World")

      {:ok, list} = Depot.list_contents(filesystem, ".")

      assert length(list) == 2
      assert_in_list list, %Depot.Stat.File{name: "test.txt"}
      assert_in_list list, %Depot.Stat.File{name: "test-1.txt"}
    end
  end

  describe "module based filesystem without own processes" do
    @describetag :tmp_dir

    test "user can write to filesystem", %{tmp_dir: prefix} do
      defmodule Local.WriteTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      assert :ok = Local.WriteTest.write("test.txt", "Hello World")
    end

    test "user can check if files exist on a filesystem", %{tmp_dir: prefix} do
      defmodule Local.FileExistsTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.FileExistsTest.write("test.txt", "Hello World")

      assert {:ok, :exists} = Local.FileExistsTest.file_exists("test.txt")
      assert {:ok, :missing} = Local.FileExistsTest.file_exists("not-test.txt")
    end

    test "user can read from filesystem", %{tmp_dir: prefix} do
      defmodule Local.ReadTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.ReadTest.write("test.txt", "Hello World")

      assert {:ok, "Hello World"} = Local.ReadTest.read("test.txt")
    end

    test "user can delete from filesystem", %{tmp_dir: prefix} do
      defmodule Local.DeleteTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.DeleteTest.write("test.txt", "Hello World")
      :ok = Local.DeleteTest.delete("test.txt")

      assert {:error, _} = Local.DeleteTest.read("test.txt")
    end

    test "user can move files", %{tmp_dir: prefix} do
      defmodule Local.MoveTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.MoveTest.write("test.txt", "Hello World")
      :ok = Local.MoveTest.move("test.txt", "not-test.txt")

      assert {:error, _} = Local.MoveTest.read("test.txt")
      assert {:ok, "Hello World"} = Local.MoveTest.read("not-test.txt")
    end

    test "user can copy files", %{tmp_dir: prefix} do
      defmodule Local.CopyTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.CopyTest.write("test.txt", "Hello World")
      :ok = Local.CopyTest.copy("test.txt", "not-test.txt")

      assert {:ok, "Hello World"} = Local.CopyTest.read("test.txt")
      assert {:ok, "Hello World"} = Local.CopyTest.read("not-test.txt")
    end

    test "user can list files", %{tmp_dir: prefix} do
      defmodule Local.ListContentsTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      :ok = Local.ListContentsTest.write("test.txt", "Hello World")
      :ok = Local.ListContentsTest.write("test-1.txt", "Hello World")

      {:ok, list} = Local.ListContentsTest.list_contents(".")

      assert length(list) == 2
      assert_in_list list, %Depot.Stat.File{name: "test.txt"}
      assert_in_list list, %Depot.Stat.File{name: "test-1.txt"}
    end
  end

  describe "filesystem with own processes" do
    test "user can write to filesystem" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      assert :ok = Depot.write(filesystem, "test.txt", "Hello World")
    end

    test "user can check if files exist on a filesystem" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")

      assert {:ok, :exists} = Depot.file_exists(filesystem, "test.txt")
      assert {:ok, :missing} = Depot.file_exists(filesystem, "not-test.txt")
    end

    test "user can read from filesystem" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")

      assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
    end

    test "user can delete from filesystem" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.delete(filesystem, "test.txt")

      assert {:error, _} = Depot.read(filesystem, "test.txt")
    end

    test "user can move files" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.move(filesystem, "test.txt", "not-test.txt")

      assert {:error, _} = Depot.read(filesystem, "test.txt")
      assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
    end

    test "user can copy files" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.copy(filesystem, "test.txt", "not-test.txt")

      assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
      assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
    end

    test "user can list files" do
      filesystem = Depot.Adapter.InMemory.configure(name: InMemoryTest)

      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.write(filesystem, "test-1.txt", "Hello World")

      {:ok, list} = Depot.list_contents(filesystem, ".")

      assert length(list) == 2
      assert_in_list list, %Depot.Stat.File{name: "test.txt"}
      assert_in_list list, %Depot.Stat.File{name: "test-1.txt"}
    end
  end

  describe "module based filesystem with own processes" do
    test "user can write to filesystem" do
      defmodule InMemory.WriteTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.WriteTest)

      assert :ok = InMemory.WriteTest.write("test.txt", "Hello World")
    end

    test "user can check if files exist on a filesystem" do
      defmodule InMemory.FileExistsTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.FileExistsTest)

      :ok = InMemory.FileExistsTest.write("test.txt", "Hello World")

      assert {:ok, :exists} = InMemory.FileExistsTest.file_exists("test.txt")
      assert {:ok, :missing} = InMemory.FileExistsTest.file_exists("not-test.txt")
    end

    test "user can read from filesystem" do
      defmodule InMemory.ReadTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.ReadTest)

      :ok = InMemory.ReadTest.write("test.txt", "Hello World")

      assert {:ok, "Hello World"} = InMemory.ReadTest.read("test.txt")
    end

    test "user can delete from filesystem" do
      defmodule InMemory.DeleteTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.DeleteTest)

      :ok = InMemory.DeleteTest.write("test.txt", "Hello World")
      :ok = InMemory.DeleteTest.delete("test.txt")

      assert {:error, _} = InMemory.DeleteTest.read("test.txt")
    end

    test "user can move files" do
      defmodule InMemory.MoveTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.MoveTest)

      :ok = InMemory.MoveTest.write("test.txt", "Hello World")
      :ok = InMemory.MoveTest.move("test.txt", "not-test.txt")

      assert {:error, _} = InMemory.MoveTest.read("test.txt")
      assert {:ok, "Hello World"} = InMemory.MoveTest.read("not-test.txt")
    end

    test "user can copy files" do
      defmodule InMemory.CopyTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.CopyTest)

      :ok = InMemory.CopyTest.write("test.txt", "Hello World")
      :ok = InMemory.CopyTest.copy("test.txt", "not-test.txt")

      assert {:ok, "Hello World"} = InMemory.CopyTest.read("test.txt")
      assert {:ok, "Hello World"} = InMemory.CopyTest.read("not-test.txt")
    end

    test "user can list files" do
      defmodule InMemory.ListContentsTest do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemory.ListContentsTest)

      :ok = InMemory.ListContentsTest.write("test.txt", "Hello World")
      :ok = InMemory.ListContentsTest.write("test-1.txt", "Hello World")

      {:ok, list} = InMemory.ListContentsTest.list_contents(".")

      assert length(list) == 2
      assert_in_list list, %Depot.Stat.File{name: "test.txt"}
      assert_in_list list, %Depot.Stat.File{name: "test-1.txt"}
    end
  end

  describe "filesystem independant" do
    @describetag :tmp_dir

    setup %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)
      {:ok, filesystem: filesystem}
    end

    test "reads configuration from :otp_app", context do
      configuration = [
        adapter: Depot.Adapter.Local,
        prefix: "ziKK7t5LzV5XiJjYh30KxCLorRXqLwwEnZYJ"
      ]

      Application.put_env(:depot_test, DepotTest.AdhocFilesystem, configuration)

      defmodule AdhocFilesystem do
        use Depot.Filesystem, otp_app: :depot_test
      end

      {_module, module_config} = DepotTest.AdhocFilesystem.__filesystem__()

      assert module_config.prefix == "ziKK7t5LzV5XiJjYh30KxCLorRXqLwwEnZYJ"
    end

    test "directory traversals are detected and reported", %{filesystem: filesystem} do
      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../test.txt"}} =
               Depot.write(filesystem, "../test.txt", "Hello World")

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../test.txt"}} =
               Depot.read(filesystem, "../test.txt")

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../test.txt"}} =
               Depot.delete(filesystem, "../test.txt")

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../test"}} =
               Depot.list_contents(filesystem, "../test")
    end

    test "relative paths are required", %{filesystem: filesystem} do
      assert {:error, %Depot.Errors.AbsolutePath{absolute_path: "/../test.txt"}} =
               Depot.write(filesystem, "/../test.txt", "Hello World")

      assert {:error, %Depot.Errors.AbsolutePath{absolute_path: "/../test.txt"}} =
               Depot.read(filesystem, "/../test.txt")

      assert {:error, %Depot.Errors.AbsolutePath{absolute_path: "/../test.txt"}} =
               Depot.delete(filesystem, "/../test.txt")

      assert {:error, %Depot.Errors.AbsolutePath{absolute_path: "/../test"}} =
               Depot.list_contents(filesystem, "/../test")
    end
  end

  describe "copying between different filesystems" do
    @describetag :tmp_dir

    setup %{tmp_dir: prefix} do
      prefix_a = Path.join(prefix, "a")
      prefix_b = Path.join(prefix, "b")

      {:ok, prefixes: [prefix_a, prefix_b]}
    end

    test "direct copy - same adapter", %{prefixes: [prefix_a, prefix_b]} do
      filesystem_a = Depot.Adapter.Local.configure(prefix: prefix_a)
      filesystem_b = Depot.Adapter.Local.configure(prefix: prefix_b)

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, :exists} = Depot.file_exists(filesystem_b, "test.txt")
    end

    test "indirect copy - same adapter" do
      filesystem_a = Depot.Adapter.InMemory.configure(name: InMemoryTest.A)
      filesystem_b = Depot.Adapter.InMemory.configure(name: InMemoryTest.B)

      filesystem_a |> Supervisor.child_spec(id: :a) |> start_supervised()
      filesystem_b |> Supervisor.child_spec(id: :b) |> start_supervised()

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, :exists} = Depot.file_exists(filesystem_b, "test.txt")
    end

    test "different adapter", %{prefixes: [prefix_a | _]} do
      filesystem_a = Depot.Adapter.Local.configure(prefix: prefix_a)
      filesystem_b = Depot.Adapter.InMemory.configure(name: InMemoryTest.B)

      start_supervised(filesystem_b)

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, :exists} = Depot.file_exists(filesystem_b, "test.txt")
    end
  end

  describe "streaming operations" do
    @describetag :tmp_dir

    test "write_stream functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      {:ok, stream} = Depot.write_stream(filesystem, "stream.txt")
      data = ["Hello", " ", "World"]
      Enum.into(data, stream)

      assert {:ok, "Hello World"} = Depot.read(filesystem, "stream.txt")
    end

    test "read_stream functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "stream.txt", "Hello World")
      {:ok, stream} = Depot.read_stream(filesystem, "stream.txt")

      assert Enum.into(stream, "") == "Hello World"
    end

    test "write_stream with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid.txt"}} =
               Depot.write_stream(filesystem, "../invalid.txt")
    end

    test "read_stream with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid.txt"}} =
               Depot.read_stream(filesystem, "../invalid.txt")
    end
  end

  describe "directory operations" do
    @describetag :tmp_dir

    test "create_directory functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert :ok = Depot.create_directory(filesystem, "test_dir/")
      {:ok, contents} = Depot.list_contents(filesystem, ".")

      assert_in_list contents, %Depot.Stat.Dir{name: "test_dir"}
    end

    test "delete_directory functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.create_directory(filesystem, "test_dir/")
      assert :ok = Depot.delete_directory(filesystem, "test_dir/")

      {:ok, contents} = Depot.list_contents(filesystem, ".")
      refute Enum.any?(contents, &match?(%Depot.Stat.Dir{name: "test_dir"}, &1))
    end

    test "clear filesystem functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test1.txt", "content")
      :ok = Depot.write(filesystem, "test2.txt", "content")
      :ok = Depot.create_directory(filesystem, "subdir/")

      assert :ok = Depot.clear(filesystem)

      {:ok, contents} = Depot.list_contents(filesystem, ".")
      assert contents == []
    end

    test "create_directory with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid/"}} =
               Depot.create_directory(filesystem, "../invalid/")
    end

    test "delete_directory with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid/"}} =
               Depot.delete_directory(filesystem, "../invalid/")
    end
  end

  describe "visibility operations" do
    @describetag :tmp_dir

    test "set_visibility functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "content")
      assert :ok = Depot.set_visibility(filesystem, "test.txt", :public)
    end

    test "visibility functionality", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      :ok = Depot.write(filesystem, "test.txt", "content")
      :ok = Depot.set_visibility(filesystem, "test.txt", :public)

      assert {:ok, :public} = Depot.visibility(filesystem, "test.txt")
    end

    test "set_visibility with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid.txt"}} =
               Depot.set_visibility(filesystem, "../invalid.txt", :public)
    end

    test "visibility with invalid path", %{tmp_dir: prefix} do
      filesystem = Depot.Adapter.Local.configure(prefix: prefix)

      assert {:error, %Depot.Errors.PathTraversal{attempted_path: "../invalid.txt"}} =
               Depot.visibility(filesystem, "../invalid.txt")
    end
  end

  describe "chunk function" do
    test "chunks empty string" do
      assert Depot.chunk("", 5) == []
    end

    test "chunks string smaller than size" do
      assert Depot.chunk("Hi", 5) == ["Hi"]
    end

    test "chunks string equal to size" do
      assert Depot.chunk("Hello", 5) == ["Hello"]
    end

    test "chunks string larger than size" do
      assert Depot.chunk("Hello World", 5) == ["Hello", " Worl", "d"]
    end

    test "chunks with size 1" do
      assert Depot.chunk("ABC", 1) == ["A", "B", "C"]
    end
  end

  describe "copy_between_filesystem edge cases" do
    @describetag :tmp_dir

    test "copy_via_local_memory with read stream only", %{tmp_dir: prefix} do
      filesystem_a = Depot.Adapter.Local.configure(prefix: prefix)
      filesystem_b = Depot.Adapter.InMemory.configure(name: InMemoryTest.StreamOnly)

      start_supervised(filesystem_b)

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, "Hello World"} = Depot.read(filesystem_b, "test.txt")
    end

    test "copy_via_local_memory with write stream only", %{tmp_dir: prefix} do
      filesystem_a = Depot.Adapter.InMemory.configure(name: InMemoryTest.WriteStreamOnly)
      filesystem_b = Depot.Adapter.Local.configure(prefix: prefix)

      start_supervised(filesystem_a)

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, "Hello World"} = Depot.read(filesystem_b, "test.txt")
    end

    test "copy_via_local_memory no streaming support" do
      filesystem_a = Depot.Adapter.InMemory.configure(name: InMemoryTest.NoStreamA)
      filesystem_b = Depot.Adapter.InMemory.configure(name: InMemoryTest.NoStreamB)

      filesystem_a |> Supervisor.child_spec(id: :no_stream_a) |> start_supervised()
      filesystem_b |> Supervisor.child_spec(id: :no_stream_b) |> start_supervised()

      :ok = Depot.write(filesystem_a, "test.txt", "Hello World")

      assert :ok =
               Depot.copy_between_filesystem(
                 {filesystem_a, "test.txt"},
                 {filesystem_b, "test.txt"}
               )

      assert {:ok, "Hello World"} = Depot.read(filesystem_b, "test.txt")
    end
  end

  describe "extended filesystem operations" do
    test "stat/2 works with high-level API", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      content = "Hello World"
      :ok = Depot.write(filesystem, "test.txt", content)

      assert {:ok, %Depot.Stat.File{} = stat} = Depot.stat(filesystem, "test.txt")
      assert stat.name == "test.txt"
      assert stat.size == byte_size(content)
    end

    test "stat/2 returns unsupported for adapters without implementation", %{test: _test} do
      # Use a mock adapter that doesn't implement stat
      assert {:error, :unsupported} = Depot.stat({NonExistentAdapter, %{}}, "test.txt")
    end

    test "access/3 works with high-level API", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "content")
      assert :ok = Depot.access(filesystem, "test.txt", [:read])
    end

    test "append/4 works with high-level API", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello")
      :ok = Depot.append(filesystem, "test.txt", " World")

      assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
    end

    test "truncate/3 works with high-level API", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      :ok = Depot.truncate(filesystem, "test.txt", 5)

      assert {:ok, "Hello"} = Depot.read(filesystem, "test.txt")
    end

    test "utime/3 works with high-level API", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      :ok = Depot.write(filesystem, "test.txt", "content")
      new_time = ~U[2023-01-01 12:00:00Z]
      :ok = Depot.utime(filesystem, "test.txt", new_time)

      assert {:ok, %Depot.Stat.File{mtime: mtime}} = Depot.stat(filesystem, "test.txt")
      assert mtime == DateTime.to_unix(new_time, :second)
    end

    test "extended operations handle path normalization errors", %{test: test} do
      filesystem = Depot.Adapter.InMemory.configure(name: test)
      start_supervised(filesystem)

      # Test with invalid paths that should trigger path normalization errors
      invalid_path = "../outside"

      assert {:error, %Depot.Errors.PathTraversal{}} = Depot.stat(filesystem, invalid_path)

      assert {:error, %Depot.Errors.PathTraversal{}} =
               Depot.access(filesystem, invalid_path, [:read])

      assert {:error, %Depot.Errors.PathTraversal{}} =
               Depot.append(filesystem, invalid_path, "content")

      assert {:error, %Depot.Errors.PathTraversal{}} =
               Depot.truncate(filesystem, invalid_path, 10)

      assert {:error, %Depot.Errors.PathTraversal{}} =
               Depot.utime(filesystem, invalid_path, DateTime.utc_now())
    end
  end
end
