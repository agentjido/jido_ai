defmodule Kodo.VFS do
  @moduledoc """
  Virtual File System - Main API for filesystem operations across multiple mount points.

  Provides a unified interface over different Depot filesystem adapters with support
  for mounting multiple filesystems at different paths.
  """

  alias Kodo.VFS.Manager

  # Mount Operations
  @doc "Mount a filesystem adapter at the given mount point"
  def mount(instance, mount_point, adapter, opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.mount(vfs_manager, mount_point, adapter, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Unmount filesystem at the given mount point"
  def unmount(instance, mount_point) do
    vfs_manager = get_manager(instance)

    try do
      Manager.unmount(vfs_manager, mount_point)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "List all mount points and their filesystems"
  def mounts(instance) do
    vfs_manager = get_manager(instance)

    try do
      Manager.mounts(vfs_manager)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  # File Operations - terse API
  @doc "Write content to a file"
  def write(instance, path, content, opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.write(vfs_manager, path, content, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Read content from a file"
  def read(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.read(vfs_manager, path, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Delete a file"
  def delete(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.delete(vfs_manager, path, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Copy a file from source to destination"
  def copy(instance, source, destination, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.copy(vfs_manager, source, destination, opts)
  end

  @doc "Move a file from source to destination"
  def move(instance, source, destination, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.move(vfs_manager, source, destination, opts)
  end

  # Directory Operations - terse API
  @doc "List contents of a directory"
  def ls(instance, path \\ ".", opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.ls(vfs_manager, path, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Check if a file or directory exists"
  def exists?(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.exists?(vfs_manager, path, opts)
  end

  @doc "Create a directory"
  def mkdir(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)

    try do
      Manager.mkdir(vfs_manager, path, opts)
    catch
      :exit, {:noproc, _} -> {:error, :not_found}
    end
  end

  @doc "Remove a directory"
  def rmdir(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.rmdir(vfs_manager, path, opts)
  end

  @doc "Clear all filesystems (root and mounted)"
  def clear(instance, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.clear(vfs_manager, opts)
  end

  # Revision Operations - for version-controlled filesystems
  @doc "Commit changes to a mounted filesystem"
  def commit(instance, mount_point, message \\ nil, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.commit(vfs_manager, mount_point, message, opts)
  end

  @doc "List revisions/commits for a path"
  def revisions(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.revisions(vfs_manager, path, opts)
  end

  @doc "Read a file as it existed at a specific revision"
  def read_revision(instance, path, sha, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.read_revision(vfs_manager, path, sha, opts)
  end

  @doc "Rollback a mounted filesystem to a previous revision"
  def rollback(instance, mount_point, sha, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.rollback(vfs_manager, mount_point, sha, opts)
  end

  # Advanced Filesystem Operations
  @doc "Get file/directory metadata (size, mtime, visibility)"
  def stat(instance, path, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.stat(vfs_manager, path, opts)
  end

  @doc "Check read/write permissions for a path"
  def access(instance, path, mode, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.access(vfs_manager, path, mode, opts)
  end

  @doc "Append content to a file"
  def append(instance, path, content, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.append(vfs_manager, path, content, opts)
  end

  @doc "Resize a file to a specific byte count"
  def truncate(instance, path, size, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.truncate(vfs_manager, path, size, opts)
  end

  @doc "Update file modification time"
  def utime(instance, path, time, opts \\ []) do
    vfs_manager = get_manager(instance)
    Manager.utime(vfs_manager, path, time, opts)
  end

  # Advanced Operations
  @doc "Search for content across all mounted filesystems"
  def search(instance, pattern, path \\ "/", opts \\ []) do
    vfs_manager = get_manager(instance)
    do_search(vfs_manager, path, pattern, opts)
  end

  @doc "Get filesystem statistics"
  def stats(instance, path \\ "/", opts \\ []) do
    vfs_manager = get_manager(instance)

    with {:ok, files} <- collect_all_files(vfs_manager, path, opts) do
      total_size = Enum.reduce(files, 0, &(&1.size + &2))
      file_count = length(files)

      by_extension =
        files
        |> Enum.group_by(&Path.extname(&1.name))
        |> Enum.map(fn {ext, files} -> {ext, length(files)} end)
        |> Enum.sort()

      {:ok,
       %{
         total_files: file_count,
         total_size: total_size,
         extensions: by_extension
       }}
    end
  end

  @doc "Batch rename files matching a pattern"
  def batch_rename(instance, dir, pattern, replacement, opts \\ []) do
    with {:ok, files} <- ls(instance, dir, opts) do
      results =
        Enum.map(files, fn file ->
          if String.match?(file.name, pattern) do
            old_path = Path.join(dir, file.name)
            new_name = String.replace(file.name, pattern, replacement)
            new_path = Path.join(dir, new_name)

            case move(instance, old_path, new_path, opts) do
              :ok -> {:ok, {old_path, new_path}}
              error -> {:error, {old_path, error}}
            end
          else
            :skipped
          end
        end)

      {:ok, results}
    end
  end

  # Aliases for compatibility
  def list_contents(instance, path, opts \\ []), do: ls(instance, path, opts)
  def file_exists?(instance, path, opts \\ []), do: exists?(instance, path, opts)
  def create_directory(instance, path, opts \\ []), do: mkdir(instance, path, opts)
  def delete_directory(instance, path, opts \\ []), do: rmdir(instance, path, opts)
  def get_mounts(instance), do: mounts(instance)

  # Private Functions
  defp get_manager(instance) do
    {:via, Registry, {Kodo.InstanceRegistry, {:vfs_manager, instance}}}
  end

  defp do_search(manager, path, pattern, opts) do
    with {:ok, files} <- Manager.ls(manager, path, opts) do
      matches =
        Enum.flat_map(files, fn file ->
          full_path = Path.join(path, file.name)
          # Normalize path to return consistent absolute paths
          normalized_path = Path.expand(full_path, "/")

          case Manager.read(manager, full_path, opts) do
            {:ok, content} ->
              if String.contains?(content, pattern), do: [normalized_path], else: []

            {:error, _} ->
              # Likely a directory, recurse
              case do_search(manager, full_path, pattern, opts) do
                {:ok, nested_matches} -> nested_matches
                _ -> []
              end
          end
        end)

      {:ok, matches}
    else
      {:error, _} = error -> error
    end
  end

  defp collect_all_files(manager, path, opts) do
    with {:ok, files} <- Manager.ls(manager, path, opts) do
      files_with_nested =
        Enum.flat_map(files, fn file ->
          full_path = Path.join(path, file.name)

          case Manager.read(manager, full_path, opts) do
            {:ok, _} ->
              [file]

            {:error, _} ->
              case collect_all_files(manager, full_path, opts) do
                {:ok, nested_files} -> nested_files
                _ -> []
              end
          end
        end)

      {:ok, files_with_nested}
    end
  end
end
