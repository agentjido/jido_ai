defmodule Kodo.VFS do
  @moduledoc """
  Virtual File System API for Kodo instances.

  This module provides a unified interface for file operations across multiple
  mounted filesystems within a Kodo instance. Each instance has its own VFS
  that can mount different Depot adapters at various paths.

  ## Architecture

  This VFS uses a router-based architecture that eliminates GenServer bottlenecks:
  - Mount information is stored in ETS tables for O(1) lookups
  - Operations are executed in the caller's process for maximum parallelism
  - Cross-filesystem operations use streaming to avoid memory issues
  - All return types are normalized to `{:ok, result} | {:error, reason}` tuples
  """

  alias Kodo.VFS.Executor

  # Mount operations

  @doc """
  Mounts a filesystem at the specified path within the instance.

  ## Examples
      
      iex> Kodo.VFS.mount(instance, "/data", Depot.Adapter.Local, prefix: "/tmp/data")
      {:ok, filesystem}
      
      iex> Kodo.VFS.mount(instance, "/cache", Depot.Adapter.InMemory, [])
      {:ok, filesystem}
  """
  @spec mount(
          instance :: term(),
          mount_path :: String.t(),
          filesystem_module :: module(),
          opts :: keyword()
        ) ::
          {:ok, term()} | {:error, term()}
  def mount(instance, mount_path, filesystem_module, opts \\ []) do
    Executor.execute(instance, :mount, {mount_path, filesystem_module, opts})
  end

  @doc """
  Unmounts the filesystem at the specified path.

  ## Examples
      
      iex> Kodo.VFS.unmount(instance, "/data")
      :ok
  """
  @spec unmount(instance :: term(), mount_path :: String.t()) :: :ok | {:error, term()}
  def unmount(instance, mount_path) do
    Executor.execute(instance, :unmount, {mount_path})
  end

  @doc """
  Lists all mounted filesystems for the instance.

  ## Examples
      
      iex> Kodo.VFS.list_mounts(instance)
      {:ok, [{"/", root_filesystem}, {"/data", data_filesystem}]}
  """
  @spec list_mounts(instance :: term()) :: {:ok, list()} | {:error, term()}
  def list_mounts(instance) do
    Executor.execute(instance, :list_mounts, {})
  end

  # Basic file operations - all return {:ok, result} | {:error, reason}

  @doc """
  Writes content to a file.

  ## Examples
      
      iex> Kodo.VFS.write(instance, "/data/file.txt", "Hello World", [])
      :ok
  """
  @spec write(instance :: term(), path :: String.t(), content :: iodata(), opts :: keyword()) ::
          :ok | {:error, term()}
  def write(instance, path, content, opts \\ []) do
    Executor.execute(instance, :write, {path, content, opts})
  end

  @doc """
  Reads content from a file.

  ## Examples
      
      iex> Kodo.VFS.read(instance, "/data/file.txt")
      {:ok, "Hello World"}
  """
  @spec read(instance :: term(), path :: String.t()) :: {:ok, binary()} | {:error, term()}
  def read(instance, path) do
    Executor.execute(instance, :read, {path})
  end

  @doc """
  Checks if a file exists. Always returns a boolean.

  ## Examples
      
      iex> Kodo.VFS.file_exists?(instance, "/data/file.txt")
      true
  """
  @spec file_exists?(instance :: term(), path :: String.t()) :: boolean()
  def file_exists?(instance, path) do
    case Executor.execute(instance, :file_exists, {path}) do
      {:ok, exists} -> exists
      {:error, _} -> false
    end
  end

  @doc """
  Lists the contents of a directory.

  ## Examples
      
      iex> Kodo.VFS.list_contents(instance, "/data")
      {:ok, [%Depot.Stat.File{name: "file.txt"}, %Depot.Stat.Dir{name: "subdir"}]}
  """
  @spec list_contents(instance :: term(), path :: String.t()) ::
          {:ok, [Depot.Stat.File.t() | Depot.Stat.Dir.t()]} | {:error, term()}
  def list_contents(instance, path) do
    Executor.execute(instance, :list_contents, {path})
  end

  @doc """
  Creates a directory.

  ## Examples
      
      iex> Kodo.VFS.mkdir(instance, "/data/new_dir", [])
      :ok
  """
  @spec mkdir(instance :: term(), path :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  def mkdir(instance, path, opts \\ []) do
    Executor.execute(instance, :create_directory, {path, opts})
  end

  @doc """
  Removes a directory.

  ## Examples
      
      iex> Kodo.VFS.rmdir(instance, "/data/old_dir", [])
      :ok
  """
  @spec rmdir(instance :: term(), path :: String.t(), opts :: keyword()) :: :ok | {:error, term()}
  def rmdir(instance, path, opts \\ []) do
    Executor.execute(instance, :delete_directory, {path, opts})
  end

  @doc """
  Deletes a file.

  ## Examples
      
      iex> Kodo.VFS.delete(instance, "/data/file.txt")
      :ok
  """
  @spec delete(instance :: term(), path :: String.t()) :: :ok | {:error, term()}
  def delete(instance, path) do
    Executor.execute(instance, :delete, {path})
  end

  @doc """
  Copies a file from source to destination using streaming for cross-filesystem operations.

  ## Examples
      
      iex> Kodo.VFS.copy(instance, "/data/source.txt", "/data/dest.txt", [])
      :ok
  """
  @spec copy(
          instance :: term(),
          source_path :: String.t(),
          dest_path :: String.t(),
          opts :: keyword()
        ) ::
          :ok | {:error, term()}
  def copy(instance, source_path, dest_path, opts \\ []) do
    Executor.execute(instance, :copy, {source_path, dest_path, opts})
  end

  @doc """
  Moves a file from source to destination using streaming for cross-filesystem operations.

  ## Examples
      
      iex> Kodo.VFS.move(instance, "/data/source.txt", "/data/dest.txt", [])
      :ok
  """
  @spec move(
          instance :: term(),
          source_path :: String.t(),
          dest_path :: String.t(),
          opts :: keyword()
        ) ::
          :ok | {:error, term()}
  def move(instance, source_path, dest_path, opts \\ []) do
    Executor.execute(instance, :move, {source_path, dest_path, opts})
  end

  @doc """
  Sets the visibility of a file or directory.

  ## Examples
      
      iex> Kodo.VFS.set_visibility(instance, "/data/file.txt", :private)
      :ok
  """
  @spec set_visibility(instance :: term(), path :: String.t(), visibility :: Depot.Visibility.t()) ::
          :ok | {:error, term()}
  def set_visibility(instance, path, visibility) do
    Executor.execute(instance, :set_visibility, {path, visibility})
  end

  @doc """
  Gets the visibility of a file or directory.

  ## Examples
      
      iex> Kodo.VFS.visibility(instance, "/data/file.txt")
      {:ok, :private}
  """
  @spec visibility(instance :: term(), path :: String.t()) ::
          {:ok, Depot.Visibility.t()} | {:error, term()}
  def visibility(instance, path) do
    Executor.execute(instance, :visibility, {path})
  end

  @doc """
  Clears all files in all mounted filesystems.

  ## Examples
      
      iex> Kodo.VFS.clear(instance)
      :ok
  """
  @spec clear(instance :: term()) :: :ok | {:error, term()}
  def clear(instance) do
    Executor.execute(instance, :clear, {})
  end

  # Extended filesystem operations - all return {:ok, result} | {:error, reason}

  @doc """
  Gets file or directory statistics.

  ## Examples
      
      iex> Kodo.VFS.stat(instance, "/data/file.txt")
      {:ok, %Depot.Stat.File{name: "file.txt", size: 1024, mtime: ~U[2024-01-01 00:00:00Z]}}
  """
  @spec stat(instance :: term(), path :: String.t()) ::
          {:ok, Depot.Stat.File.t() | Depot.Stat.Dir.t()} | {:error, term()}
  def stat(instance, path) do
    Executor.execute(instance, :stat, {path})
  end

  @doc """
  Checks file access permissions.

  ## Examples
      
      iex> Kodo.VFS.access(instance, "/data/file.txt", [:read, :write])
      :ok
  """
  @spec access(instance :: term(), path :: String.t(), modes :: [:read | :write]) ::
          :ok | {:error, term()}
  def access(instance, path, modes) do
    Executor.execute(instance, :access, {path, modes})
  end

  @doc """
  Appends content to a file.

  ## Examples
      
      iex> Kodo.VFS.append(instance, "/data/file.txt", "Additional content", [])
      :ok
  """
  @spec append(instance :: term(), path :: String.t(), content :: iodata(), opts :: keyword()) ::
          :ok | {:error, term()}
  def append(instance, path, content, opts \\ []) do
    Executor.execute(instance, :append, {path, content, opts})
  end

  @doc """
  Truncates a file to the specified size.

  ## Examples
      
      iex> Kodo.VFS.truncate(instance, "/data/file.txt", 100)
      :ok
  """
  @spec truncate(instance :: term(), path :: String.t(), new_size :: non_neg_integer()) ::
          :ok | {:error, term()}
  def truncate(instance, path, new_size) do
    Executor.execute(instance, :truncate, {path, new_size})
  end

  @doc """
  Updates the modification time of a file.

  ## Examples
      
      iex> Kodo.VFS.utime(instance, "/data/file.txt", ~U[2024-01-01 12:00:00Z])
      :ok
  """
  @spec utime(instance :: term(), path :: String.t(), mtime :: DateTime.t()) ::
          :ok | {:error, term()}
  def utime(instance, path, mtime) do
    Executor.execute(instance, :utime, {path, mtime})
  end

  # Streaming operations

  @doc """
  Creates a readable stream for a file.

  ## Examples
      
      iex> {:ok, stream} = Kodo.VFS.read_stream(instance, "/data/large_file.txt")
      iex> Enum.take(stream, 3)
      ["chunk1", "chunk2", "chunk3"]
  """
  @spec read_stream(instance :: term(), path :: String.t(), opts :: keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def read_stream(instance, path, opts \\ []) do
    Executor.execute(instance, :read_stream, {path, opts})
  end

  @doc """
  Creates a writable stream for a file.

  ## Examples
      
      iex> {:ok, stream} = Kodo.VFS.write_stream(instance, "/data/output.txt")
      iex> ["chunk1", "chunk2"] |> Enum.into(stream)
      :ok
  """
  @spec write_stream(instance :: term(), path :: String.t(), opts :: keyword()) ::
          {:ok, Collectable.t()} | {:error, term()}
  def write_stream(instance, path, opts \\ []) do
    Executor.execute(instance, :write_stream, {path, opts})
  end

  # Convenience and compatibility functions

  @doc """
  Alias for file_exists?/2 - used by some tests.
  """
  @spec exists?(instance :: term(), path :: String.t()) :: boolean()
  def exists?(instance, path), do: file_exists?(instance, path)

  @doc """
  Alias for list_contents/2 - lists directory contents.
  """
  @spec ls(instance :: term(), path :: String.t()) ::
          {:ok, [Depot.Stat.File.t() | Depot.Stat.Dir.t()]} | {:error, term()}
  def ls(instance, path \\ "/"), do: list_contents(instance, path)

  @doc """
  Returns root filesystem and all mounts - compatibility function.
  """
  @spec mounts(instance :: term()) :: {term(), map()} | {:error, term()}
  def mounts(instance) do
    case list_mounts(instance) do
      {:ok, mount_list} ->
        # Return root and other mounts separately for compatibility
        {root, other_mounts} = Enum.split_with(mount_list, fn {path, _, _} -> path == "/" end)

        root_fs =
          case root do
            [{_, filesystem, _}] -> filesystem
            [] -> nil
          end

        # Convert mount list to map: mount_path -> {filesystem, config}
        mount_map =
          Enum.into(other_mounts, %{}, fn {path, filesystem, config} ->
            {path, {filesystem, config}}
          end)

        {root_fs, mount_map}

      error ->
        error
    end
  end

  @doc """
  Alias for mounts/1 - compatibility function.
  """
  @spec get_mounts(instance :: term()) :: {term(), [term()]} | {:error, term()}
  def get_mounts(instance), do: mounts(instance)

  @doc """
  Alias for mkdir/3 - compatibility function.
  """
  @spec create_directory(instance :: term(), path :: String.t(), opts :: keyword()) ::
          :ok | {:error, term()}
  def create_directory(instance, path, opts \\ []), do: mkdir(instance, path, opts)

  @doc """
  Alias for rmdir/3 - compatibility function.
  """
  @spec delete_directory(instance :: term(), path :: String.t(), opts :: keyword()) ::
          :ok | {:error, term()}
  def delete_directory(instance, path, opts \\ []), do: rmdir(instance, path, opts)

  @doc """
  Returns filesystem statistics - placeholder for compatibility.
  """
  @spec stats(instance :: term()) :: {:ok, map()} | {:error, term()}
  def stats(instance) do
    case list_mounts(instance) do
      {:ok, mounts} ->
        # Count files across all mounts and gather stats
        {total_files, total_size, all_extensions} =
          Enum.reduce(mounts, {0, 0, []}, fn {_mount_path, filesystem, config},
                                             {files_acc, size_acc, ext_acc} ->
            {file_count, size, extensions} = gather_filesystem_stats({filesystem, config}, "")
            {files_acc + file_count, size_acc + size, ext_acc ++ extensions}
          end)

        # Group extensions and count them
        extension_counts =
          all_extensions
          |> Enum.frequencies()
          |> Enum.to_list()

        stats = %{
          total_mounts: length(mounts),
          total_files: total_files,
          total_size: total_size,
          extensions: extension_counts,
          mount_points: Enum.map(mounts, fn {path, _, _} -> path end)
        }

        {:ok, stats}

      error ->
        error
    end
  end

  @doc """
  Searches for files matching a pattern across all mounted filesystems.

  ## Examples
      
      iex> Kodo.VFS.search(instance, "*.txt")
      {:ok, ["/data/file.txt", "/config/settings.txt"]}
  """
  @spec search(instance :: term(), pattern :: String.t()) ::
          {:ok, [String.t()]} | {:error, term()}
  def search(instance, pattern) do
    with {:ok, mounts} <- list_mounts(instance) do
      matches =
        mounts
        |> Enum.flat_map(fn {mount_path, _filesystem, _config} ->
          search_in_mount(instance, mount_path, pattern)
        end)

      {:ok, matches}
    end
  end

  # Private helper functions

  defp gather_filesystem_stats(depot_adapter, path) do
    case Depot.list_contents(depot_adapter, path) do
      {:ok, entries} ->
        Enum.reduce(entries, {0, 0, []}, fn entry, {file_count, total_size, extensions} ->
          # Handle both string entries and stat structs
          entry_name =
            case entry do
              %{name: name} -> name
              name when is_binary(name) -> name
              _ -> nil
            end

          if entry_name do
            full_path = Path.join(path, entry_name)

            case Depot.stat(depot_adapter, full_path) do
              {:ok, %Depot.Stat.File{name: name, size: size}} ->
                extension = Path.extname(name) |> String.downcase()
                extension = if extension == "", do: "no_extension", else: extension
                {file_count + 1, total_size + size, [extension | extensions]}

              {:ok, %Depot.Stat.Dir{}} ->
                {sub_files, sub_size, sub_extensions} =
                  gather_filesystem_stats(depot_adapter, full_path)

                {file_count + sub_files, total_size + sub_size, extensions ++ sub_extensions}

              _ ->
                {file_count, total_size, extensions}
            end
          else
            {file_count, total_size, extensions}
          end
        end)

      {:error, _} ->
        {0, 0, []}
    end
  end

  defp search_in_mount(instance, mount_path, pattern) do
    case list_contents(instance, mount_path) do
      {:ok, entries} ->
        entries
        |> Enum.map(fn
          # Extract name from Depot.Stat struct
          %{name: name} -> name
          # Handle string entries
          entry when is_binary(entry) -> entry
          _ -> nil
        end)
        |> Enum.filter(fn entry ->
          entry &&
            (path_matches_pattern?(entry, pattern) ||
               content_matches_pattern?(instance, mount_path, entry, pattern))
        end)
        |> Enum.map(fn entry -> Path.join(mount_path, entry) end)

      {:error, _} ->
        []
    end
  end

  defp path_matches_pattern?(path, pattern) do
    basename = Path.basename(path)

    # Check if pattern is a simple string (substring search)
    # or a glob pattern (with * or ?)
    if String.contains?(pattern, "*") or String.contains?(pattern, "?") do
      # Glob pattern matching
      regex_pattern =
        pattern
        |> String.replace("*", ".*")
        |> String.replace("?", ".")
        |> (&"^#{&1}$").()

      Regex.match?(~r/#{regex_pattern}/, basename)
    else
      # Simple substring search
      String.contains?(basename, pattern)
    end
  end

  defp content_matches_pattern?(instance, mount_path, entry, pattern) do
    file_path = Path.join(mount_path, entry)

    case read(instance, file_path) do
      {:ok, content} -> String.contains?(content, pattern)
      {:error, _} -> false
    end
  end

  # TODO: Implement versioning operations in future iterations
  # These require more complex logic and can be added later
end
