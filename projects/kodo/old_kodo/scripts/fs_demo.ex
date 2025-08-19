defmodule Kodo.FsDemo do
  @moduledoc """
  Demonstrates usage of Depot with InMemory adapter.
  Run these functions in IEx to explore Depot functionality.
  """

  require Logger

  @doc """
  Sets up a new InMemory filesystem and demonstrates basic operations.

  ## Example
      iex> {:ok, fs} = Kodo.Demo.run()
      iex> Depot.read(fs, "hello.txt")
      {:ok, "Hello World"}
  """
  def run do
    # Configure and start the filesystem
    filesystem = Depot.Adapter.InMemory.configure(name: DemoFS)

    case start_filesystem(filesystem) do
      {:ok, fs} ->
        demonstrate_operations(fs)
        {:ok, fs}

      error ->
        Logger.warning("Failed to start filesystem", error: inspect(error))
        error
    end
  end

  @doc """
  Demonstrates nested directory operations.

  ## Example
      iex> {:ok, fs} = Kodo.Demo.run()
      iex> Kodo.Demo.nested_example(fs)
      :ok
      iex> Depot.read(fs, "nested/deep/file.txt")
      {:ok, "I'm deep inside!"}
  """
  def nested_example(filesystem) do
    # Create nested directories with content
    :ok = Depot.write(filesystem, "nested/file1.txt", "First level")
    :ok = Depot.write(filesystem, "nested/deep/file.txt", "I'm deep inside!")
    :ok = Depot.write(filesystem, "nested/deep/deeper/file.txt", "Even deeper!")

    # List directory contents
    {:ok, files} = Depot.list_contents(filesystem, "nested")
    IO.puts("\nNested directory contents:")
    print_directory_tree(files)

    :ok
  end

  @doc """
  Demonstrates file operations and error handling.

  ## Example
      iex> {:ok, fs} = Kodo.Demo.run()
      iex> Kodo.Demo.operations_example(fs)
      :ok
  """
  def operations_example(filesystem) do
    # Write and read
    :ok = Depot.write(filesystem, "test.txt", "Original content")
    {:ok, content} = Depot.read(filesystem, "test.txt")
    IO.puts("Read content: #{content}")

    # Overwrite
    :ok = Depot.write(filesystem, "test.txt", "New content")
    {:ok, new_content} = Depot.read(filesystem, "test.txt")
    IO.puts("Updated content: #{new_content}")

    # Copy
    :ok = Depot.copy(filesystem, "test.txt", "test_copy.txt")

    # Move/Rename
    :ok = Depot.move(filesystem, "test_copy.txt", "moved.txt")

    # Delete
    :ok = Depot.delete(filesystem, "test.txt")

    # Demonstrate error handling
    case Depot.read(filesystem, "test.txt") do
      {:error, reason} ->
        IO.puts("Expected error after deletion: #{inspect(reason)}")

      _ ->
        IO.puts("Unexpected success reading deleted file")
    end

    :ok
  end

  @doc """
  Inspect all fields available in a Depot.Stat.File struct
  """
  def inspect_file_struct(filesystem, path) do
    {:ok, files} = Depot.list_contents(filesystem, path)
    IO.inspect(files, label: "File struct details")
  end

  # Private helper functions

  defp start_filesystem(filesystem) do
    # Start the filesystem directly
    case Depot.Adapter.InMemory.start_link(filesystem) do
      {:ok, _pid} ->
        # Do some initial setup
        :ok = Depot.write(filesystem, "hello.txt", "Hello World")
        {:ok, filesystem}

      error ->
        error
    end
  end

  defp demonstrate_operations(filesystem) do
    IO.puts("\nDemonstrating basic operations:")

    # Basic write/read
    {:ok, content} = Depot.read(filesystem, "hello.txt")
    IO.puts("Read from hello.txt: #{content}")

    # List root contents
    {:ok, files} = Depot.list_contents(filesystem, ".")
    IO.puts("\nRoot directory contents:")
    print_directory_tree(files)
  end

  defp print_directory_tree(files, indent \\ "") do
    Enum.each(files, fn file ->
      IO.puts("#{indent}#{file.name} (#{format_file_info(file)})")
    end)
  end

  defp format_file_info(file) do
    size_str = "#{file.size} bytes"
    visibility_str = "#{file.visibility}"
    "size: #{size_str}, visibility: #{visibility_str}"
  end

  @doc """
  Lists all files recursively in the filesystem.
  """
  def list_all(filesystem, path \\ ".") do
    case Depot.list_contents(filesystem, path) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          full_path = Path.join(path, file.name)
          # Try to read the file to determine if it's a directory
          case Depot.read(filesystem, full_path) do
            {:error, _} ->
              # Likely a directory, try to list contents
              case Depot.list_contents(filesystem, full_path) do
                {:ok, _} ->
                  IO.puts(full_path <> "/")
                  list_all(filesystem, full_path)

                _ ->
                  IO.puts(full_path)
              end

            _ ->
              IO.puts(full_path)
          end
        end)

      error ->
        Logger.warning("Failed to list contents", path: path, error: inspect(error))
        error
    end
  end

  @doc """
  Runs a comprehensive demo script showing multiple filesystems and operations.
  """
  def script do
    IO.puts("\n=== Starting Multi-Filesystem Demo ===\n")

    # Start two separate filesystems
    {:ok, fs1} = start_demo_filesystem("ProjectA")
    {:ok, fs2} = start_demo_filesystem("ProjectB")

    IO.puts("\n--- Setting up initial content ---")

    # Setup filesystem 1 with some source code files
    :ok = Depot.write(fs1, "src/main.ex", "defmodule Main do\n  def hello, do: :world\nend")
    :ok = Depot.write(fs1, "src/utils.ex", "defmodule Utils do\n  def add(a, b), do: a + b\nend")
    :ok = Depot.write(fs1, "test/main_test.ex", "defmodule MainTest do\n  use ExUnit.Case\nend")

    # Setup filesystem 2 with some config and data files
    :ok = Depot.write(fs2, "config/dev.json", ~s({"port": 4000, "env": "dev"}))
    :ok = Depot.write(fs2, "config/prod.json", ~s({"port": 80, "env": "prod"}))
    :ok = Depot.write(fs2, "data/users.csv", "id,name\n1,Alice\n2,Bob")

    IO.puts("\n--- Initial State ---")
    IO.puts("\nProjectA Contents:")
    list_all(fs1)
    IO.puts("\nProjectB Contents:")
    list_all(fs2)

    IO.puts("\n--- Demonstrating File Operations ---")

    # Copy operations
    :ok = Depot.copy(fs1, "src/main.ex", "src/main.ex.backup")
    IO.puts("\nCreated backup in ProjectA")

    # Create a shared config by copying between filesystems
    {:ok, config} = Depot.read(fs2, "config/dev.json")
    :ok = Depot.write(fs1, "config/dev.json", config)
    IO.puts("\nShared config from ProjectB to ProjectA")

    # Demonstrate search functionality
    IO.puts("\n--- Searching Files ---")
    search_files(fs1, "defmodule")
    search_files(fs2, "Alice")

    # Demonstrate file stats
    IO.puts("\n--- File Statistics ---")
    print_filesystem_stats(fs1, "ProjectA")
    print_filesystem_stats(fs2, "ProjectB")

    # Demonstrate batch operations
    IO.puts("\n--- Batch Operations ---")
    batch_rename_files(fs2, "config/", ".json", ".config")

    IO.puts("\n--- Final State ---")
    IO.puts("\nProjectA Contents:")
    list_all(fs1)
    IO.puts("\nProjectB Contents:")
    list_all(fs2)

    {:ok, %{project_a: fs1, project_b: fs2}}
  end

  @doc """
  Searches for content across files in a filesystem.
  """
  def search_files(filesystem, pattern) do
    search_in_path(filesystem, ".", pattern)
  end

  defp search_in_path(filesystem, path, pattern) do
    case Depot.list_contents(filesystem, path) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          full_path = Path.join(path, file.name)

          case Depot.read(filesystem, full_path) do
            {:ok, content} ->
              if String.contains?(content, pattern) do
                IO.puts("Found '#{pattern}' in #{full_path}")
              end

            {:error, _} ->
              # Likely a directory, recurse
              search_in_path(filesystem, full_path, pattern)
          end
        end)

      _ ->
        :ok
    end
  end

  @doc """
  Prints statistics about files in the filesystem.
  """
  def print_filesystem_stats(filesystem, name) do
    {:ok, all_files} = collect_all_files(filesystem, ".")

    total_size = Enum.reduce(all_files, 0, &(&1.size + &2))
    file_count = length(all_files)

    IO.puts("\n#{name} Statistics:")
    IO.puts("Total files: #{file_count}")
    IO.puts("Total size: #{total_size} bytes")

    # Group by extension
    by_extension =
      all_files
      |> Enum.group_by(&Path.extname(&1.name))
      |> Enum.map(fn {ext, files} -> {ext, length(files)} end)
      |> Enum.sort()

    IO.puts("\nFiles by extension:")

    Enum.each(by_extension, fn {ext, count} ->
      IO.puts("  #{if ext == "", do: "(no extension)", else: ext}: #{count}")
    end)
  end

  @doc """
  Batch renames files in a directory by replacing extensions.
  """
  def batch_rename_files(filesystem, dir, old_ext, new_ext) do
    case Depot.list_contents(filesystem, dir) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          if String.ends_with?(file.name, old_ext) do
            old_path = Path.join(dir, file.name)
            new_name = String.replace(file.name, old_ext, new_ext)
            new_path = Path.join(dir, new_name)

            case Depot.move(filesystem, old_path, new_path) do
              :ok ->
                IO.puts("Renamed #{old_path} to #{new_path}")

              {:error, reason} ->
                IO.puts("Failed to rename #{old_path}: #{inspect(reason)}")
            end
          end
        end)

      _ ->
        :ok
    end
  end

  # Helper functions

  defp start_demo_filesystem(name) do
    filesystem = Depot.Adapter.InMemory.configure(name: String.to_atom(name))

    case Depot.Adapter.InMemory.start_link(filesystem) do
      {:ok, _pid} -> {:ok, filesystem}
      error -> error
    end
  end

  defp collect_all_files(filesystem, path) do
    case Depot.list_contents(filesystem, path) do
      {:ok, files} ->
        files_with_nested =
          Enum.flat_map(files, fn file ->
            full_path = Path.join(path, file.name)

            case Depot.read(filesystem, full_path) do
              {:ok, _} ->
                [file]

              {:error, _} ->
                case collect_all_files(filesystem, full_path) do
                  {:ok, nested_files} -> nested_files
                  _ -> []
                end
            end
          end)

        {:ok, files_with_nested}

      error ->
        error
    end
  end
end
