defmodule Kodo.VFS.Manager do
  @moduledoc """
  Manager for Virtual Filesystem that handles mounting and routing between different
  filesystem adapters. Maintains singleton state for the entire shell system.
  """
  use GenServer
  require Logger

  defstruct mounts: %{},
            root_fs: nil,
            instance: nil

  # Client API
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  # Mount Operations - terse API
  def mount(vfs_pid \\ __MODULE__, mount_point, adapter, opts \\ []) do
    GenServer.call(vfs_pid, {:mount, mount_point, adapter, opts})
  end

  def unmount(vfs_pid \\ __MODULE__, mount_point) do
    GenServer.call(vfs_pid, {:unmount, mount_point})
  end

  def mounts(vfs_pid \\ __MODULE__) do
    GenServer.call(vfs_pid, :get_mounts)
  end

  # Filesystem Operations - terse API
  def write(vfs_pid \\ __MODULE__, path, content, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :write, [path, content, opts]})
  end

  def read(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :read, [path, opts]})
  end

  def delete(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :delete, [path, opts]})
  end

  def copy(vfs_pid \\ __MODULE__, source, destination, opts \\ []) do
    GenServer.call(vfs_pid, {:route_copy_move, :copy, source, destination, opts})
  end

  def move(vfs_pid \\ __MODULE__, source, destination, opts \\ []) do
    GenServer.call(vfs_pid, {:route_copy_move, :move, source, destination, opts})
  end

  def ls(vfs_pid \\ __MODULE__, path \\ ".", opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :list_contents, [path, opts]})
  end

  def exists?(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :file_exists, [path, opts]})
  end

  def mkdir(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :create_directory, [path, opts]})
  end

  def rmdir(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :delete_directory, [path, opts]})
  end

  def clear(vfs_pid \\ __MODULE__, opts \\ []) do
    GenServer.call(vfs_pid, {:clear_all, opts})
  end

  # Revision Operations - for version-controlled filesystems
  def commit(vfs_pid \\ __MODULE__, mount_point, message \\ nil, opts \\ []) do
    GenServer.call(vfs_pid, {:route_revision, :commit, mount_point, [message, opts]})
  end

  def revisions(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :revisions, [path, opts]})
  end

  def read_revision(vfs_pid \\ __MODULE__, path, sha, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :read_revision, [path, sha, opts]})
  end

  def rollback(vfs_pid \\ __MODULE__, mount_point, sha, opts \\ []) do
    GenServer.call(vfs_pid, {:route_revision, :rollback, mount_point, [sha, opts]})
  end

  # Advanced Filesystem Operations
  def stat(vfs_pid \\ __MODULE__, path, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :stat, [path, opts]})
  end

  def access(vfs_pid \\ __MODULE__, path, mode, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :access, [path, mode, opts]})
  end

  def append(vfs_pid \\ __MODULE__, path, content, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :append, [path, content, opts]})
  end

  def truncate(vfs_pid \\ __MODULE__, path, size, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :truncate, [path, size, opts]})
  end

  def utime(vfs_pid \\ __MODULE__, path, time, opts \\ []) do
    GenServer.call(vfs_pid, {:route_operation, :utime, [path, time, opts]})
  end

  # Aliases for compatibility
  def list_contents(vfs_pid \\ __MODULE__, path, opts \\ []), do: ls(vfs_pid, path, opts)
  def file_exists?(vfs_pid \\ __MODULE__, path, opts \\ []), do: exists?(vfs_pid, path, opts)
  def create_directory(vfs_pid \\ __MODULE__, path, opts \\ []), do: mkdir(vfs_pid, path, opts)
  def delete_directory(vfs_pid \\ __MODULE__, path, opts \\ []), do: rmdir(vfs_pid, path, opts)
  def get_mounts(vfs_pid \\ __MODULE__), do: mounts(vfs_pid)

  # Server Callbacks
  @impl true
  def init(opts) do
    instance = Keyword.get(opts, :instance)
    # Start root filesystem
    root_adapter = Keyword.get(opts, :root_adapter, Depot.Adapter.InMemory)
    root_fs = configure_root_fs(opts, instance)

    case start_filesystem(root_adapter, root_fs) do
      {:ok, _pid} ->
        {:ok, %__MODULE__{root_fs: root_fs, instance: instance}}

      error ->
        Logger.warning("Failed to start root filesystem",
          instance: instance,
          error: inspect(error)
        )

        {:stop, :root_fs_failed}
    end
  end

  @impl true
  def handle_call({:mount, mount_point, adapter, opts}, _from, state) do
    opts = prepare_adapter_opts(adapter, opts)
    filesystem = adapter.configure(opts)

    case start_filesystem(adapter, filesystem) do
      {:ok, _pid} ->
        new_mounts = Map.put(state.mounts, mount_point, filesystem)
        {:reply, :ok, %{state | mounts: new_mounts}}

      error ->
        {:reply, error, state}
    end
  end

  @impl true
  def handle_call({:unmount, mount_point}, _from, state) do
    case Map.pop(state.mounts, mount_point) do
      {nil, _mounts} ->
        {:reply, {:error, :not_mounted}, state}

      {filesystem, new_mounts} ->
        stop_filesystem(filesystem)
        {:reply, :ok, %{state | mounts: new_mounts}}
    end
  end

  @impl true
  def handle_call({:route_operation, operation, args}, _from, state) do
    [path | rest] = args
    {filesystem, relative_path} = route_path(path, state)

    result =
      case operation do
        :file_exists ->
          # Convert Depot result to boolean for consistency
          case apply(Depot, operation, [filesystem, relative_path | rest]) do
            {:ok, :exists} -> true
            {:ok, :missing} -> false
            error -> error
          end

        # Advanced filesystem operations with different argument patterns
        :stat ->
          # stat/2 - no options parameter
          Depot.stat(filesystem, relative_path)

        :access ->
          # access/3 - takes mode list, no options parameter
          [mode | _] = rest
          Depot.access(filesystem, relative_path, mode)

        :truncate ->
          # truncate/3 - takes size, no options parameter  
          [size | _] = rest
          Depot.truncate(filesystem, relative_path, size)

        :utime ->
          # utime/3 - takes time, no options parameter
          [time | _] = rest
          Depot.utime(filesystem, relative_path, time)

        _ ->
          apply(Depot, operation, [filesystem, relative_path | rest])
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:route_copy_move, operation, source, destination, opts}, _from, state) do
    {source_fs, source_path} = route_path(source, state)
    {dest_fs, dest_path} = route_path(destination, state)

    result =
      if source_fs == dest_fs do
        # Same filesystem, direct operation
        apply(Depot, operation, [source_fs, source_path, dest_path, opts])
      else
        # Cross-filesystem operation using streams to avoid memory issues
        handle_cross_fs_operation(operation, source_fs, source_path, dest_fs, dest_path, opts)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:get_mounts, _from, state) do
    {:reply, {state.root_fs, state.mounts}, state}
  end

  @impl true
  def handle_call({:clear_all, _opts}, _from, state) do
    # Clear root filesystem
    root_result = Depot.clear(state.root_fs)

    # Clear all mounted filesystems
    mount_results =
      Enum.map(state.mounts, fn {_mount_point, filesystem} ->
        Depot.clear(filesystem)
      end)

    # Check if all operations succeeded
    all_results = [root_result | mount_results]

    case Enum.all?(all_results, &(&1 == :ok)) do
      true -> {:reply, :ok, state}
      false -> {:reply, {:error, :partial_clear}, state}
    end
  end

  @impl true
  def handle_call({:route_revision, operation, mount_point, args}, _from, state) do
    # Revision operations target specific mount points, not paths
    filesystem =
      case mount_point do
        "/" -> state.root_fs
        path -> Map.get(state.mounts, path)
      end

    result =
      case filesystem do
        nil -> {:error, :mount_not_found}
        fs -> apply(Depot, operation, [fs | args])
      end

    {:reply, result, state}
  end

  # Private Functions
  defp configure_root_fs(opts, instance) do
    root_adapter = Keyword.get(opts, :root_adapter, Depot.Adapter.InMemory)
    default_name = String.to_atom("Kodo.RootFS.#{instance}")
    root_opts = Keyword.get(opts, :root_opts, name: default_name)
    root_adapter.configure(root_opts)
  end

  defp prepare_adapter_opts(Depot.Adapter.Local, opts) do
    # Ensure both prefix and root are set for Local adapter
    root = Keyword.get(opts, :root)
    prefix = Keyword.get(opts, :prefix, root)

    opts
    |> Keyword.put_new(:prefix, prefix)
    |> Keyword.put_new(:root, root)
  end

  defp prepare_adapter_opts(_adapter, opts), do: opts

  defp start_filesystem(Depot.Adapter.Local, _filesystem) do
    # Local adapter is stateless - no process to start
    {:ok, self()}
  end

  defp start_filesystem(Depot.Adapter.InMemory, filesystem) do
    Depot.Adapter.InMemory.start_link(filesystem)
  end

  defp start_filesystem(Depot.Adapter.Git, _filesystem) do
    # Git adapter is stateless - no process to start
    {:ok, self()}
  end

  defp start_filesystem(Depot.Adapter.GitHub, _filesystem) do
    # GitHub adapter is stateless - no process to start
    {:ok, self()}
  end

  defp start_filesystem(_adapter, filesystem) do
    {:error, "Unsupported adapter for filesystem: #{inspect(filesystem)}"}
  end

  defp stop_filesystem({_adapter, %{name: name}}) when is_atom(name) do
    # For Depot InMemory adapter, find the process by name
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        Process.exit(pid, :normal)
        :ok

      nil ->
        {:error, :not_found}
    end
  end

  defp stop_filesystem({Depot.Adapter.Local, _config}) do
    # Local adapter is stateless - no process to stop
    :ok
  end

  defp stop_filesystem(_filesystem) do
    # For other adapters or unknown configurations
    :ok
  end

  # Handle cross-filesystem operations using streams to avoid memory issues
  defp handle_cross_fs_operation(:copy, source_fs, source_path, dest_fs, dest_path, opts) do
    handle_cross_fs_copy(source_fs, source_path, dest_fs, dest_path, opts)
  end

  defp handle_cross_fs_operation(:move, source_fs, source_path, dest_fs, dest_path, opts) do
    case handle_cross_fs_copy(source_fs, source_path, dest_fs, dest_path, opts) do
      :ok ->
        Depot.delete(source_fs, source_path)

      error ->
        error
    end
  end

  defp handle_cross_fs_copy(source_fs, source_path, dest_fs, dest_path, opts) do
    # For now, fallback to read/write but log a warning about potential memory issues
    # TODO: Implement proper streaming when Depot supports it
    require Logger
    Logger.warning("Cross-filesystem copy using read/write - may have memory issues with large files")
    
    case Depot.read(source_fs, source_path) do
      {:ok, content} ->
        case Depot.write(dest_fs, dest_path, content, opts) do
          :ok -> :ok
          error -> error
        end
      error ->
        error
    end
  end

  defp route_path(path, state) do
    # Normalize path to handle relative paths and clean up
    normalized_path = Path.expand(path, "/")

    # Find the deepest matching mount point
    case find_mount_point(normalized_path, state.mounts) do
      nil ->
        # For root filesystem, convert absolute path to relative
        relative_path = String.trim_leading(normalized_path, "/")
        relative_path = if relative_path == "", do: ".", else: relative_path
        {state.root_fs, relative_path}

      {mount_point, filesystem} ->
        relative_path =
          normalized_path
          |> Path.relative_to(mount_point)
          |> case do
            # Root of mount point
            "." -> "."
            rel -> rel
          end

        {filesystem, relative_path}
    end
  end

  defp find_mount_point(path, mounts) do
    mounts
    |> Enum.filter(fn {mount_point, _} ->
      # Normalize mount point and check if path starts with it
      norm_mount = Path.expand(mount_point, "/")
      path == norm_mount or String.starts_with?(path, norm_mount <> "/")
    end)
    |> Enum.sort_by(
      fn {mount_point, _} ->
        # Sort by length to get the most specific (deepest) mount point
        String.length(mount_point)
      end,
      :desc
    )
    |> List.first()
  end
end
