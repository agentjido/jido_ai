defmodule Kodo.VFS.Demo do
  @moduledoc """
  Demonstrates the Virtual Filesystem functionality with multiple mounted filesystems
  and transparent path-based routing using the new terse API.
  """
  require Logger

  @doc """
  Runs a comprehensive demo of the VFS functionality.

  ## Example
      iex> Kodo.VFS.Demo.run()
      :ok
  """
  def run do
    IO.puts("\n=== Starting VFS Demo with New Terse API ===\n")

    # Start a demo instance
    instance = :vfs_demo_instance
    {:ok, _} = Kodo.start(instance)

    # Create a temporary directory for local filesystem
    tmp_dir = Path.join(System.tmp_dir!(), "kodo_vfs_demo_#{:rand.uniform(1000)}")
    File.mkdir_p!(tmp_dir)

    # Mount local filesystem with both root and prefix options
    :ok = Kodo.VFS.mount(instance, "/local", Depot.Adapter.Local,
      root: tmp_dir,
      prefix: tmp_dir
    )

    # Mount a second in-memory filesystem for projects
    :ok = Kodo.VFS.mount(instance, "/projects", Depot.Adapter.InMemory, name: :ProjectFS)

    demonstrate_basic_operations(instance)
    demonstrate_cross_fs_operations(instance)
    demonstrate_nested_directories(instance)
    demonstrate_search(instance)
    demonstrate_terse_api(instance)

    # Cleanup
    :ok = Kodo.VFS.unmount(instance, "/local")
    :ok = Kodo.VFS.unmount(instance, "/projects")
    File.rm_rf!(tmp_dir)
    Kodo.stop(instance)

    :ok
  rescue
    e ->
      Logger.error("Demo failed", error: inspect(e, pretty: true))
      :error
  end

  defp demonstrate_basic_operations(instance) do
    IO.puts("\n--- Basic Operations ---")

    # Write to different filesystems
    :ok = Kodo.VFS.write(instance, "/root.txt", "Root filesystem content")
    :ok = Kodo.VFS.write(instance, "/local/local.txt", "Local filesystem content")
    :ok = Kodo.VFS.write(instance, "/projects/project.txt", "Project content")

    # Read from different filesystems
    {:ok, root_content} = Kodo.VFS.read(instance, "/root.txt")
    {:ok, local_content} = Kodo.VFS.read(instance, "/local/local.txt")
    {:ok, project_content} = Kodo.VFS.read(instance, "/projects/project.txt")

    IO.puts("Root content: #{root_content}")
    IO.puts("Local content: #{local_content}")
    IO.puts("Project content: #{project_content}")
  end

  defp demonstrate_cross_fs_operations(instance) do
    IO.puts("\n--- Cross-Filesystem Operations ---")

    # Copy between filesystems
    :ok = Kodo.VFS.write(instance, "/source.txt", "Content to copy")
    :ok = Kodo.VFS.copy(instance, "/source.txt", "/local/copied.txt")
    :ok = Kodo.VFS.copy(instance, "/source.txt", "/projects/copied.txt")

    # Move between filesystems
    :ok = Kodo.VFS.write(instance, "/to_move.txt", "Content to move")
    :ok = Kodo.VFS.move(instance, "/to_move.txt", "/local/moved.txt")

    # Verify using terse API
    {:ok, files} = Kodo.VFS.ls(instance, "/local")
    IO.puts("\nLocal files after copy/move:")
    Enum.each(files, &IO.puts("  #{&1.name}"))
  end

  defp demonstrate_nested_directories(instance) do
    IO.puts("\n--- Nested Directory Operations ---")

    # Create nested structure in projects
    :ok = Kodo.VFS.write(instance, "/projects/app/src/main.ex", "defmodule Main do\nend")
    :ok = Kodo.VFS.write(instance, "/projects/app/test/main_test.ex", "defmodule MainTest do\nend")

    # List contents recursively
    print_directory_tree(instance, "/projects/app")
  end

  defp demonstrate_search(instance) do
    IO.puts("\n--- Search Operations ---")

    # Search for content across filesystems using new API
    {:ok, matches} = Kodo.VFS.search(instance, "defmodule")
    IO.puts("\nFiles containing 'defmodule':")
    Enum.each(matches, &IO.puts("  #{&1}"))
  end

  defp demonstrate_terse_api(instance) do
    IO.puts("\n--- Terse API Demonstration ---")

    # Demonstrate all the terse operations
    :ok = Kodo.VFS.write(instance, "/demo/file1.txt", "content1")
    :ok = Kodo.VFS.write(instance, "/demo/file2.log", "content2")

    # List using short form
    {:ok, files} = Kodo.VFS.ls(instance, "/demo")
    IO.puts("Files in /demo (using ls):")
    Enum.each(files, &IO.puts("  #{&1.name}"))

    # Check existence using short form
    exists = Kodo.VFS.exists?(instance, "/demo/file1.txt")
    IO.puts("File exists: #{exists}")

    # Get filesystem stats
    {:ok, stats} = Kodo.VFS.stats(instance, "/demo")
    IO.puts("Filesystem stats: #{inspect(stats)}")

    # Demonstrate batch rename
    {:ok, results} = Kodo.VFS.batch_rename(instance, "/demo", ~r/\.txt$/, ".bak")
    IO.puts("Batch rename results: #{inspect(results)}")
  end

  defp print_directory_tree(instance, path, indent \\ "") do
    case Kodo.VFS.ls(instance, path) do
      {:ok, files} ->
        Enum.each(files, fn file ->
          full_path = Path.join(path, file.name)
          IO.puts("#{indent}#{file.name}")

          # Try to read to determine if it's a directory
          case Kodo.VFS.read(instance, full_path) do
            {:error, _} -> print_directory_tree(instance, full_path, indent <> "  ")
            _ -> :ok
          end
        end)

      _ ->
        :ok
    end
  end
end
