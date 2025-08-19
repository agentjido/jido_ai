defmodule Kodo.Errors.Routing do
  use Splode.ErrorClass, class: :routing
end

defmodule Kodo.Errors.Filesystem do
  use Splode.ErrorClass, class: :filesystem
end

defmodule Kodo.Errors.Validation do
  use Splode.ErrorClass, class: :validation
end

defmodule Kodo.Errors.Unknown do
  use Splode.ErrorClass, class: :unknown
end

defmodule Kodo.Errors.Unknown.Unknown do
  use Splode.Error, class: :unknown, fields: [:error]

  def message(%{error: error}) do
    if is_binary(error) do
      to_string(error)
    else
      inspect(error)
    end
  end
end

# Specific error types
defmodule Kodo.Errors.MountNotFound do
  use Splode.Error, class: :routing, fields: [:instance]

  def message(%{path: path}) do
    "No filesystem mounted for path: #{path}"
  end
end

defmodule Kodo.Errors.OperationFailed do
  use Splode.Error, class: :filesystem, fields: [:operation, :reason]

  def message(%{operation: operation, path: path, reason: reason}) do
    "#{operation} operation failed for #{path}: #{inspect(reason)}"
  end
end

defmodule Kodo.Errors.InvalidPath do
  use Splode.Error, class: :validation, fields: [:reason]

  def message(%{path: path, reason: reason}) do
    "Invalid path #{path}: #{reason}"
  end
end

defmodule Kodo.Errors.CrossFilesystemError do
  use Splode.Error, class: :filesystem, fields: [:source_path, :destination_path, :reason]

  def message(%{source_path: source, destination_path: dest, reason: reason}) do
    "Cross-filesystem operation failed from #{source} to #{dest}: #{inspect(reason)}"
  end
end

defmodule Kodo.Errors do
  @moduledoc """
  Error definitions for Kodo operations using Splode.
  """

  use Splode,
    error_classes: [
      routing: Kodo.Errors.Routing,
      filesystem: Kodo.Errors.Filesystem,
      validation: Kodo.Errors.Validation,
      unknown: Kodo.Errors.Unknown
    ],
    unknown_error: Kodo.Errors.Unknown.Unknown

  @doc """
  Wraps Depot errors with additional VFS context.
  """
  def wrap_depot_error(depot_error, operation, path, _instance \\ nil) do
    case depot_error do
      :enoent ->
        Kodo.Errors.InvalidPath.exception(path: path, reason: "File or directory not found")

      :enotdir ->
        Kodo.Errors.InvalidPath.exception(path: path, reason: "Not a directory")

      :eisdir ->
        Kodo.Errors.InvalidPath.exception(path: path, reason: "Is a directory")

      :eexist ->
        Kodo.Errors.InvalidPath.exception(
          path: path,
          reason: "File or directory already exists"
        )

      :enotempty ->
        Kodo.Errors.InvalidPath.exception(path: path, reason: "Directory not empty")

      {:error, reason} ->
        Kodo.Errors.OperationFailed.exception(
          operation: operation,
          path: path,
          reason: reason
        )

      reason ->
        Kodo.Errors.OperationFailed.exception(
          operation: operation,
          path: path,
          reason: reason
        )
    end
  end

  @doc """
  Creates a routing error when no mount is found.
  """
  def no_mount_for_path(path, instance \\ nil) do
    Kodo.Errors.MountNotFound.exception(path: path, instance: instance)
  end

  @doc """
  Creates an error for cross-filesystem operations.
  """
  def cross_filesystem_operation_failed(source_path, dest_path, reason, _instance \\ nil) do
    Kodo.Errors.CrossFilesystemError.exception(
      source_path: source_path,
      destination_path: dest_path,
      reason: reason
    )
  end
end
