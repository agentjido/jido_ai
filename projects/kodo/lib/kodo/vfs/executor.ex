defmodule Kodo.VFS.Executor do
  @moduledoc """
  VFS operation executor that routes operations and executes them in the caller's process.
  This replaces the GenServer-based manager to eliminate serialization bottlenecks.
  """

  alias Kodo.VFS.{Router, Streaming}
  alias Kodo.Errors

  @doc """
  Executes a filesystem operation after routing to the appropriate filesystem.

  Operations are performed in the caller's process for maximum parallelism.
  """
  def execute(instance, operation, args) do
    case operation do
      :mount -> apply_mount(instance, args)
      :unmount -> apply_unmount(instance, args)
      :list_mounts -> Router.list_mounts(instance)
      :clear -> apply_clear_all(instance)
      _ -> execute_routed_operation(instance, operation, args)
    end
  end

  # Mount/unmount operations
  defp apply_mount(instance, {mount_path, filesystem_module, opts}) do
    case filesystem_module.configure(opts) do
      {filesystem, config} ->
        # Start the filesystem process if needed
        start_result =
          if filesystem_module.starts_processes() do
            try do
              DynamicSupervisor.start_child(
                {:via, Registry, {Kodo.InstanceRegistry, {:vfs_supervisor, instance}}},
                {filesystem, config}
              )
            catch
              :exit, {:noproc, _} -> {:error, :not_found}
              :exit, {:normal, _} -> {:error, :not_found}
            end
          else
            {:ok, :no_process}
          end

        case start_result do
          {:ok, :no_process} ->
            case Router.add_mount(instance, mount_path, filesystem, config) do
              :ok -> :ok
              error -> error
            end

          {:ok, _pid} ->
            case Router.add_mount(instance, mount_path, filesystem, config) do
              :ok -> :ok
              error -> error
            end

          {:error, :not_found} ->
            {:error, :not_found}

          error ->
            {:error,
             Errors.OperationFailed.exception(
               operation: :start_filesystem,
               path: mount_path,
               reason: error
             )}
        end

      error ->
        {:error,
         Errors.OperationFailed.exception(operation: :configure, path: "/", reason: error)}
    end
  end

  defp apply_unmount(instance, {mount_path}) do
    Router.remove_mount(instance, mount_path)
  end

  defp apply_clear_all(instance) do
    case Router.list_mounts(instance) do
      {:ok, mounts} ->
        Enum.each(mounts, fn {_mount_path, filesystem, config} ->
          Depot.clear({filesystem, config})
        end)

        :ok

      error ->
        error
    end
  end

  # Routed operations - operations that require path resolution
  defp execute_routed_operation(instance, operation, args) do
    {path, remaining_args} = extract_path_from_args(operation, args)

    case Router.route(instance, path) do
      {:ok, filesystem, config, relative_path} ->
        execute_depot_operation(
          filesystem,
          config,
          operation,
          relative_path,
          remaining_args,
          instance,
          path
        )

      {:error, :instance_not_found} ->
        {:error, :not_found}

      {:error, :mount_not_found} ->
        {:error, Errors.no_mount_for_path(path, instance)}
    end
  end

  defp execute_depot_operation(
         filesystem,
         config,
         operation,
         relative_path,
         args,
         instance,
         original_path
       ) do
    try do
      depot_fs = {filesystem, config}

      result =
        case operation do
          :read ->
            Depot.read(depot_fs, relative_path)

          :write ->
            {content, opts} = args
            Depot.write(depot_fs, relative_path, content, opts)

          :delete ->
            Depot.delete(depot_fs, relative_path)

          :file_exists ->
            case Depot.file_exists(depot_fs, relative_path) do
              {:ok, :exists} -> {:ok, true}
              {:ok, :missing} -> {:ok, false}
              error -> error
            end

          :list_contents ->
            Depot.list_contents(depot_fs, relative_path)

          :create_directory ->
            {opts} = args
            Depot.create_directory(depot_fs, relative_path, opts)

          :delete_directory ->
            {opts} = args
            Depot.delete_directory(depot_fs, relative_path, opts)

          :set_visibility ->
            {visibility} = args
            Depot.set_visibility(depot_fs, relative_path, visibility)

          :visibility ->
            Depot.visibility(depot_fs, relative_path)

          :stat ->
            apply_if_available(filesystem, :stat, [config, relative_path])

          :access ->
            {modes} = args
            apply_if_available(filesystem, :access, [config, relative_path, modes])

          :append ->
            {content, opts} = args
            apply_if_available(filesystem, :append, [config, relative_path, content, opts])

          :truncate ->
            {size} = args
            apply_if_available(filesystem, :truncate, [config, relative_path, size])

          :utime ->
            {mtime} = args
            apply_if_available(filesystem, :utime, [config, relative_path, mtime])

          # Streaming operations
          :copy ->
            {dest_path, opts} = args
            Streaming.stream_copy(instance, original_path, dest_path, opts)

          :move ->
            {dest_path, opts} = args
            Streaming.stream_move(instance, original_path, dest_path, opts)

          :read_stream ->
            {opts} = args
            Streaming.read_stream(instance, original_path, opts)

          :write_stream ->
            {opts} = args
            Streaming.write_stream(instance, original_path, opts)

          _ ->
            {:error, :unsupported_operation}
        end

      case result do
        {:error, reason} ->
          {:error, Errors.wrap_depot_error(reason, operation, original_path, instance)}

        other ->
          other
      end
    rescue
      error ->
        {:error,
         Errors.OperationFailed.exception(
           operation: operation,
           path: original_path,
           reason: error
         )}
    end
  end

  defp apply_if_available(filesystem, function, args) do
    if function_exported?(filesystem, function, length(args)) do
      apply(filesystem, function, args)
    else
      {:error, :not_implemented}
    end
  end

  # Extract the path from operation arguments
  defp extract_path_from_args(:read, {path}), do: {path, {}}
  defp extract_path_from_args(:write, {path, content, opts}), do: {path, {content, opts}}
  defp extract_path_from_args(:delete, {path}), do: {path, {}}
  defp extract_path_from_args(:file_exists, {path}), do: {path, {}}
  defp extract_path_from_args(:list_contents, {path}), do: {path, {}}
  defp extract_path_from_args(:create_directory, {path, opts}), do: {path, {opts}}
  defp extract_path_from_args(:delete_directory, {path, opts}), do: {path, {opts}}
  defp extract_path_from_args(:set_visibility, {path, visibility}), do: {path, {visibility}}
  defp extract_path_from_args(:visibility, {path}), do: {path, {}}
  defp extract_path_from_args(:clear, {}), do: {"/", {}}
  defp extract_path_from_args(:stat, {path}), do: {path, {}}
  defp extract_path_from_args(:access, {path, modes}), do: {path, {modes}}
  defp extract_path_from_args(:append, {path, content, opts}), do: {path, {content, opts}}
  defp extract_path_from_args(:truncate, {path, size}), do: {path, {size}}
  defp extract_path_from_args(:utime, {path, mtime}), do: {path, {mtime}}

  defp extract_path_from_args(:copy, {source_path, dest_path, opts}),
    do: {source_path, {dest_path, opts}}

  defp extract_path_from_args(:move, {source_path, dest_path, opts}),
    do: {source_path, {dest_path, opts}}

  defp extract_path_from_args(:read_stream, {path, opts}), do: {path, {opts}}
  defp extract_path_from_args(:write_stream, {path, opts}), do: {path, {opts}}
end
