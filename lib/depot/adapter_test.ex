defmodule Depot.AdapterTest do
  defmacro in_list(list, match) do
    quote do
      Enum.any?(unquote(list), &match?(unquote(match), &1))
    end
  end

  defp tests do
    quote do
      test "user can write to filesystem", %{filesystem: filesystem} do
        assert :ok = Depot.write(filesystem, "test.txt", "Hello World")
      end

      test "user can overwrite a file on the filesystem", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Old text")
        assert :ok = Depot.write(filesystem, "test.txt", "Hello World")
        assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
      end

      test "user can stream to a filesystem", %{filesystem: {adapter, _} = filesystem} do
        case Depot.write_stream(filesystem, "test.txt") do
          {:ok, stream} ->
            Enum.into(["Hello", " ", "World"], stream)

            assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

          {:error, ^adapter} ->
            :ok
        end
      end

      test "user can check if files exist on a filesystem", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")

        assert {:ok, :exists} = Depot.file_exists(filesystem, "test.txt")
        assert {:ok, :missing} = Depot.file_exists(filesystem, "not-test.txt")
      end

      test "user can read from filesystem", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")

        assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
      end

      test "user can stream from filesystem", %{filesystem: {adapter, _} = filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")

        case Depot.read_stream(filesystem, "test.txt") do
          {:ok, stream} ->
            assert Enum.into(stream, <<>>) == "Hello World"

          {:error, ^adapter} ->
            :ok
        end
      end

      test "user can stream in a certain chunk size", %{filesystem: {adapter, _} = filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")

        case Depot.read_stream(filesystem, "test.txt", chunk_size: 2) do
          {:ok, stream} ->
            assert ["He" | _] = Enum.into(stream, [])

          {:error, ^adapter} ->
            :ok
        end
      end

      test "user can try to read a non-existing file from filesystem", %{filesystem: filesystem} do
        assert {:error, %Depot.Errors.FileNotFound{}} = Depot.read(filesystem, "test.txt")
      end

      test "user can delete from filesystem", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")
        :ok = Depot.delete(filesystem, "test.txt")

        assert {:error, _} = Depot.read(filesystem, "test.txt")
      end

      test "user can delete a non-existing file from filesystem", %{filesystem: filesystem} do
        assert :ok = Depot.delete(filesystem, "test.txt")
      end

      test "user can move files", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")
        :ok = Depot.move(filesystem, "test.txt", "not-test.txt")

        assert {:error, _} = Depot.read(filesystem, "test.txt")
        assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
      end

      test "user can try to move a non-existing file", %{filesystem: filesystem} do
        assert {:error, %Depot.Errors.FileNotFound{}} =
                 Depot.move(filesystem, "test.txt", "not-test.txt")
      end

      test "user can copy files", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")
        :ok = Depot.copy(filesystem, "test.txt", "not-test.txt")

        assert {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")
        assert {:ok, "Hello World"} = Depot.read(filesystem, "not-test.txt")
      end

      test "user can try to copy a non-existing file", %{filesystem: filesystem} do
        assert {:error, %Depot.Errors.FileNotFound{}} =
                 Depot.copy(filesystem, "test.txt", "not-test.txt")
      end

      test "user can list files and folders", %{filesystem: filesystem} do
        :ok = Depot.create_directory(filesystem, "test/")
        :ok = Depot.write(filesystem, "test.txt", "Hello World")
        :ok = Depot.write(filesystem, "test-1.txt", "Hello World")
        :ok = Depot.write(filesystem, "folder/test-1.txt", "Hello World")

        {:ok, list} = Depot.list_contents(filesystem, ".")

        assert in_list(list, %Depot.Stat.Dir{name: "test"})
        assert in_list(list, %Depot.Stat.Dir{name: "folder"})
        assert in_list(list, %Depot.Stat.File{name: "test.txt"})
        assert in_list(list, %Depot.Stat.File{name: "test-1.txt"})

        refute in_list(list, %Depot.Stat.File{name: "folder/test-1.txt"})

        assert length(list) == 4
      end

      test "directory listings include visibility", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "visible.txt", "Hello World", visibility: :public)
        :ok = Depot.write(filesystem, "invisible.txt", "Hello World", visibility: :private)
        :ok = Depot.create_directory(filesystem, "visible-dir/", directory_visibility: :public)
        :ok = Depot.create_directory(filesystem, "invisible-dir/", directory_visibility: :private)

        {:ok, list} = Depot.list_contents(filesystem, ".")

        assert in_list(list, %Depot.Stat.Dir{name: "visible-dir", visibility: :public})
        assert in_list(list, %Depot.Stat.Dir{name: "invisible-dir", visibility: :private})
        assert in_list(list, %Depot.Stat.File{name: "visible.txt", visibility: :public})
        assert in_list(list, %Depot.Stat.File{name: "invisible.txt", visibility: :private})

        assert length(list) == 4
      end

      test "user can create directories", %{filesystem: filesystem} do
        assert :ok = Depot.create_directory(filesystem, "test/")
        assert :ok = Depot.create_directory(filesystem, "test/nested/folder/")
      end

      test "user can delete directories", %{filesystem: filesystem} do
        :ok = Depot.create_directory(filesystem, "test/")
        assert :ok = Depot.delete_directory(filesystem, "test/")
      end

      test "non empty directories are not deleted by default", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test/test.txt", "Hello World")
        assert {:error, _} = Depot.delete_directory(filesystem, "test/")
      end

      test "non empty directories are deleted with the recursive flag set", %{
        filesystem: filesystem
      } do
        :ok = Depot.write(filesystem, "test/test.txt", "Hello World")
        assert :ok = Depot.delete_directory(filesystem, "test/", recursive: true)

        :ok = Depot.create_directory(filesystem, "test/nested/folder/")
        assert :ok = Depot.delete_directory(filesystem, "test/", recursive: true)
      end

      test "files in deleted directories are no longer available", %{filesystem: filesystem} do
        :ok = Depot.write(filesystem, "test/test.txt", "Hello World")
        assert :ok = Depot.delete_directory(filesystem, "test/", recursive: true)
        assert {:ok, :missing} = Depot.file_exists(filesystem, "not-test.txt")
      end

      test "non filesystem can be cleared", %{
        filesystem: filesystem
      } do
        :ok = Depot.write(filesystem, "test.txt", "Hello World")
        :ok = Depot.write(filesystem, "test/test.txt", "Hello World")
        :ok = Depot.create_directory(filesystem, "test/nested/folder/")

        assert :ok = Depot.clear(filesystem)

        assert {:ok, :missing} = Depot.file_exists(filesystem, "test.txt")
        assert {:ok, :missing} = Depot.file_exists(filesystem, "test/test.txt")
        assert {:ok, :missing} = Depot.file_exists(filesystem, "test/")
      end

      test "set visibility", %{filesystem: filesystem} do
        :ok =
          Depot.write(filesystem, "folder/file.txt", "Hello World",
            visibility: :public,
            directory_visibility: :public
          )

        assert :ok = Depot.set_visibility(filesystem, "folder/", :private)
        assert {:ok, :private} = Depot.visibility(filesystem, "folder/")

        assert :ok = Depot.set_visibility(filesystem, "folder/file.txt", :private)
        assert {:ok, :private} = Depot.visibility(filesystem, "folder/file.txt")
      end

      test "visibility", %{filesystem: filesystem} do
        :ok =
          Depot.write(filesystem, "public/file.txt", "Hello World",
            visibility: :private,
            directory_visibility: :public
          )

        :ok =
          Depot.write(filesystem, "private/file.txt", "Hello World",
            visibility: :public,
            directory_visibility: :private
          )

        assert {:ok, :public} = Depot.visibility(filesystem, ".")
        assert {:ok, :public} = Depot.visibility(filesystem, "public/")
        assert {:ok, :private} = Depot.visibility(filesystem, "public/file.txt")
        assert {:ok, :private} = Depot.visibility(filesystem, "private/")
        assert {:ok, :public} = Depot.visibility(filesystem, "private/file.txt")
      end
    end
  end

  defmacro adapter_test(block) do
    quote do
      describe "common adapter tests" do
        setup unquote(block)

        import Depot.AdapterTest, only: [in_list: 2]
        unquote(tests())
      end
    end
  end

  defmacro adapter_test(context, block) do
    quote do
      describe "common adapter tests" do
        setup unquote(context), unquote(block)

        import Depot.AdapterTest, only: [in_list: 2]
        unquote(tests())
      end
    end
  end
end
