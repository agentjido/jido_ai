defmodule Depot do
  @external_resource "README.md"
  @moduledoc @external_resource
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)

  alias Depot.Errors

  @type adapter :: module()
  @type filesystem :: {module(), Depot.Adapter.config()}

  defp convert_path_error({:path, :traversal}, path),
    do: Errors.PathTraversal.exception(attempted_path: path)

  defp convert_path_error({:path, :absolute}, path),
    do: Errors.AbsolutePath.exception(absolute_path: path)

  defp convert_path_error(:enotdir, path), do: Errors.NotDirectory.exception(not_dir_path: path)

  @doc """
  Write to a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.write(filesystem, "test.txt", "Hello World")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.write("test.txt", "Hello World")

  """
  @spec write(filesystem, Path.t(), iodata(), keyword()) :: :ok | {:error, term}
  def write({adapter, config}, path, contents, opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.write(config, normalized_path, contents, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Returns a `Stream` for writing to the given `path`.

  ## Options

  The following stream options apply to all adapters:

    * `:chunk_size` - When reading, the amount to read,
      usually expressed as a number of bytes.

  ## Examples

  > Note: The shape of the returned stream will
  > necessarily depend on the adapter in use. In the
  > following examples the [`Local`](`Depot.Adapter.Local`)
  > adapter is invoked, which returns a `File.Stream`.

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, %File.Stream{}} = Depot.write_stream(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, %File.Stream{}} = LocalFileSystem.write_stream("test.txt")

  """
  def write_stream({adapter, config}, path, opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.write_stream(config, normalized_path, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Read from a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, "Hello World"} = LocalFileSystem.read("test.txt")

  """
  @spec read(filesystem, Path.t(), keyword()) :: {:ok, binary} | {:error, term}
  def read({adapter, config}, path, _opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.read(config, normalized_path)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Returns a `Stream` for reading the given `path`.

  ## Options

  The following stream options apply to all adapters:

    * `:chunk_size` - When reading, the amount to read,
      usually expressed as a number of bytes.

  ## Examples

  > Note: The shape of the returned stream will
  > necessarily depend on the adapter in use. In the
  > following examples the [`Local`](`Depot.Adapter.Local`)
  > adapter is invoked, which returns a `File.Stream`.

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, %File.Stream{}} = Depot.read_stream(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, %File.Stream{}} = LocalFileSystem.read_stream("test.txt")

  """
  def read_stream({adapter, config}, path, opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.read_stream(config, normalized_path, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Delete a file from a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.delete(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.delete("test.txt")

  """
  @spec delete(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def delete({adapter, config}, path, _opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.delete(config, normalized_path)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Move a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.move(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.move("test.txt", "other-test.txt")

  """
  @spec move(filesystem, Path.t(), Path.t(), keyword()) :: :ok | {:error, term}
  def move({adapter, config}, source, destination, opts \\ []) do
    with {:ok, normalized_source} <- Depot.RelativePath.normalize(source),
         {:ok, normalized_destination} <- Depot.RelativePath.normalize(destination) do
      adapter.move(config, normalized_source, normalized_destination, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, source)}
    end
  end

  @doc """
  Copy a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.copy(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.copy("test.txt", "other-test.txt")

  """
  @spec copy(filesystem, Path.t(), Path.t(), keyword()) :: :ok | {:error, term}
  def copy({adapter, config}, source, destination, opts \\ []) do
    with {:ok, normalized_source} <- Depot.RelativePath.normalize(source),
         {:ok, normalized_destination} <- Depot.RelativePath.normalize(destination) do
      adapter.copy(config, normalized_source, normalized_destination, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, source)}
    end
  end

  @doc """
  Copy a file from source to destination on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.copy(filesystem, "test.txt", "other-test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.copy("test.txt", "other-test.txt")

  """
  @spec file_exists(filesystem, Path.t(), keyword()) :: {:ok, :exists | :missing} | {:error, term}
  def file_exists({adapter, config}, path, _opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.file_exists(config, normalized_path)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  List the contents of a folder on a filesystem

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, contents} = Depot.list_contents(filesystem, ".")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, contents} = LocalFileSystem.list_contents(".")

  """
  @spec list_contents(filesystem, Path.t(), keyword()) ::
          {:ok, [%Depot.Stat.Dir{} | %Depot.Stat.File{}]} | {:error, term}
  def list_contents({adapter, config}, path, _opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.list_contents(config, normalized_path)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Create a directory

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.create_directory(filesystem, "test/")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.create_directory("test/")

  """
  @spec create_directory(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def create_directory({adapter, config}, path, opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path),
         {:ok, normalized_path} <- Depot.RelativePath.assert_directory(normalized_path) do
      adapter.create_directory(config, normalized_path, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Delete a directory.

  ## Options

    * `:recursive` - Recursively delete contents. Defaults to `false`.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.delete_directory(filesystem, "test/")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.delete_directory("test/")

  """
  @spec delete_directory(filesystem, Path.t(), keyword()) :: :ok | {:error, term}
  def delete_directory({adapter, config}, path, opts \\ []) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path),
         {:ok, normalized_path} <- Depot.RelativePath.assert_directory(normalized_path) do
      adapter.delete_directory(config, normalized_path, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Clear the filesystem.

  This is always recursive.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.clear(filesystem)

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      LocalFileSystem.clear()

  """
  @spec clear(filesystem, keyword()) :: :ok | {:error, term}
  def clear({adapter, config}, _opts \\ []) do
    adapter.clear(config)
  end

  @spec set_visibility(filesystem, Path.t(), Depot.Visibility.t()) :: :ok | {:error, term}
  def set_visibility({adapter, config}, path, visibility) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.set_visibility(config, normalized_path, visibility)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @spec visibility(filesystem, Path.t()) :: {:ok, Depot.Visibility.t()} | {:error, term}
  def visibility({adapter, config}, path) do
    with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      adapter.visibility(config, normalized_path)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
    end
  end

  @doc """
  Get file or directory metadata (stat information)

  Returns detailed metadata about a file or directory including size, modification time, and visibility.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      {:ok, %Depot.Stat.File{}} = Depot.stat(filesystem, "test.txt")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      {:ok, %Depot.Stat.File{}} = LocalFileSystem.stat("test.txt")

  """
  @spec stat(filesystem, Path.t()) ::
          {:ok, %Depot.Stat.File{} | %Depot.Stat.Dir{}} | {:error, term}
  def stat({adapter, config}, path) do
    if function_exported?(adapter, :stat, 2) do
      with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
        adapter.stat(config, normalized_path)
      else
        {:error, reason} -> {:error, convert_path_error(reason, path)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc """
  Check file access permissions

  Checks whether the given file or directory can be accessed with the specified modes.

  ## Modes

    * `:read` - Check read access
    * `:write` - Check write access

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.access(filesystem, "test.txt", [:read, :write])

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.access("test.txt", [:read])

  """
  @spec access(filesystem, Path.t(), [:read | :write]) :: :ok | {:error, term}
  def access({adapter, config}, path, modes) do
    if function_exported?(adapter, :access, 3) do
      with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
        adapter.access(config, normalized_path, modes)
      else
        {:error, reason} -> {:error, convert_path_error(reason, path)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc """
  Append content to a file

  If the file exists, the content is appended to the end. If it doesn't exist,
  a new file is created with the given content.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.append(filesystem, "test.txt", "Additional content")

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.append("test.txt", "More data")

  """
  @spec append(filesystem, Path.t(), iodata(), keyword()) :: :ok | {:error, term}
  def append({adapter, config}, path, contents, opts \\ []) do
    if function_exported?(adapter, :append, 4) do
      with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
        adapter.append(config, normalized_path, contents, opts)
      else
        {:error, reason} -> {:error, convert_path_error(reason, path)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc """
  Truncate a file to a specific size

  Resizes the file to the specified number of bytes. If the new size is larger than
  the current size, the file is padded with null bytes. If smaller, the file is truncated.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.truncate(filesystem, "test.txt", 100)

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.truncate("test.txt", 0)  # Empty the file

  """
  @spec truncate(filesystem, Path.t(), non_neg_integer()) :: :ok | {:error, term}
  def truncate({adapter, config}, path, new_size) do
    if function_exported?(adapter, :truncate, 3) do
      with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
        adapter.truncate(config, normalized_path, new_size)
      else
        {:error, reason} -> {:error, convert_path_error(reason, path)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc """
  Update file modification time

  Changes the modification time of a file or directory.

  ## Examples

  ### Direct filesystem

      filesystem = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      :ok = Depot.utime(filesystem, "test.txt", DateTime.utc_now())

  ### Module-based filesystem

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      :ok = LocalFileSystem.utime("test.txt", ~U[2023-01-01 00:00:00Z])

  """
  @spec utime(filesystem, Path.t(), DateTime.t()) :: :ok | {:error, term}
  def utime({adapter, config}, path, mtime) do
    if function_exported?(adapter, :utime, 3) do
      with {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
        adapter.utime(config, normalized_path, mtime)
      else
        {:error, reason} -> {:error, convert_path_error(reason, path)}
      end
    else
      {:error, :unsupported}
    end
  end

  @doc """
  Copy a file from one filesystem to the other

  This can either be done natively if the same adapter is used for both filesystems
  or by streaming/read-write cycle the file from the source to the local system
  and back to the destination.

  ## Examples

  ### Direct filesystem

      filesystem_source = Depot.Adapter.Local.configure(prefix: "/home/user/storage")
      filesystem_destination = Depot.Adapter.Local.configure(prefix: "/home/user/storage2")
      :ok = Depot.copy_between_filesystem({filesystem_source, "test.txt"}, {filesystem_destination, "copy.txt"})

  ### Module-based filesystem

      defmodule LocalSourceFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage"
      end

      defmodule LocalDestinationFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: "/home/user/storage2"
      end

      :ok = Depot.copy_between_filesystem(
        {LocalSourceFileSystem.__filesystem__(), "test.txt"},
        {LocalDestinationFileSystem.__filesystem__(), "copy.txt"}
      )

  """
  @spec copy_between_filesystem(
          source :: {filesystem, Path.t()},
          destination :: {filesystem, Path.t()},
          keyword()
        ) :: :ok | {:error, term}
  def copy_between_filesystem(source, destination, opts \\ [])

  # Same adapter, same config -> just do a plain copy
  def copy_between_filesystem({filesystem, source}, {filesystem, destination}, opts) do
    copy(filesystem, source, destination, opts)
  end

  # Same adapter -> try direct copy if supported
  def copy_between_filesystem(
        {{adapter, config_source}, path_source} = source,
        {{adapter, config_destination}, path_destination} = destination,
        opts
      ) do
    with :ok <-
           adapter.copy(config_source, path_source, config_destination, path_destination, opts) do
      :ok
    else
      {:error, :unsupported} -> copy_via_local_memory(source, destination, opts)
      {:error, reason} -> {:error, Errors.to_error(reason)}
    end
  end

  # different adapter
  def copy_between_filesystem(source, destination, opts) do
    copy_via_local_memory(source, destination, opts)
  end

  defp copy_via_local_memory(
         {{source_adapter, _} = source_filesystem, source_path},
         {{destination_adapter, _} = destination_filesystem, destination_path},
         opts
       ) do
    case {Depot.read_stream(source_filesystem, source_path, opts),
          Depot.write_stream(destination_filesystem, destination_path, opts)} do
      # A and B support streaming -> Stream data
      {{:ok, read_stream}, {:ok, write_stream}} ->
        read_stream
        |> Stream.into(write_stream)
        |> Stream.run()

      # Only A support streaming -> Stream to memory and write when done
      {{:ok, read_stream}, {:error, ^destination_adapter}} ->
        Depot.write(destination_filesystem, destination_path, Enum.into(read_stream, []))

      # Only B support streaming -> Load into memory and stream to B
      {{:error, ^source_adapter}, {:ok, write_stream}} ->
        with {:ok, contents} <- Depot.read(source_filesystem, source_path) do
          contents
          |> chunk(Keyword.get(opts, :chunk_size, 5 * 1024))
          |> Enum.into(write_stream)
        end

      # Neither support streaming
      {{:error, ^source_adapter}, {:error, ^destination_adapter}} ->
        with {:ok, contents} <- Depot.read(source_filesystem, source_path) do
          Depot.write(destination_filesystem, destination_path, contents)
        end
    end
  rescue
    e -> {:error, Errors.to_error(e)}
  end

  @doc false
  # Also used by the InMemory adapter and therefore not private
  def chunk("", _size), do: []

  def chunk(binary, size) when byte_size(binary) >= size do
    {chunk, rest} = :erlang.split_binary(binary, size)
    [chunk | chunk(rest, size)]
  end

  def chunk(binary, _size), do: [binary]

  # Helper function to map adapters to their versioning modules
  @spec get_versioning_module(module()) :: module() | nil
  defp get_versioning_module(Depot.Adapter.Git), do: Depot.Adapter.Git
  defp get_versioning_module(Depot.Adapter.ETS), do: Depot.Adapter.ETS.Versioning
  defp get_versioning_module(Depot.Adapter.InMemory), do: Depot.Adapter.InMemory.Versioning
  defp get_versioning_module(_), do: nil

  @doc """
  Commit changes to a version-controlled filesystem.

  Uses the polymorphic versioning interface to support any adapter that implements
  versioning functionality (Git, ETS, InMemory).

  ## Examples

      # Git adapter
      filesystem = Depot.Adapter.Git.configure(path: "/repo", mode: :manual)
      Depot.write(filesystem, "file.txt", "content")
      :ok = Depot.commit(filesystem, "Add new file")

      # ETS adapter (uses versioning wrapper)
      filesystem = Depot.Adapter.ETS.configure(name: :test_ets)
      :ok = Depot.commit(filesystem, "Snapshot")

  """
  @spec commit(filesystem, String.t() | nil, keyword()) :: :ok | {:error, term}
  def commit({adapter, config}, message \\ nil, opts \\ []) do
    with versioning_module when not is_nil(versioning_module) <- get_versioning_module(adapter),
         true <- function_exported?(versioning_module, :commit, 3) do
      versioning_module.commit(config, message, opts)
    else
      _ -> {:error, :unsupported}
    end
  end

  @doc """
  List revisions/commits for a path in a version-controlled filesystem.

  Uses the polymorphic versioning interface to support any adapter that implements
  versioning functionality. Returns a list of revision maps with standardized format.

  ## Options

    * `:limit` - Maximum number of revisions to return
    * `:since` - Only revisions after this datetime
    * `:until` - Only revisions before this datetime
    * `:author` - Only revisions by this author

  ## Examples

      # Git adapter
      filesystem = Depot.Adapter.Git.configure(path: "/repo")
      {:ok, revisions} = Depot.revisions(filesystem, "file.txt", limit: 10)

      # ETS adapter
      filesystem = Depot.Adapter.ETS.configure(name: :test_ets)
      {:ok, revisions} = Depot.revisions(filesystem, "file.txt")

  """
  @spec revisions(filesystem, Path.t(), keyword()) ::
          {:ok, [map() | Depot.Revision.t()]} | {:error, term}
  def revisions({adapter, config}, path \\ ".", opts \\ []) do
    with versioning_module when not is_nil(versioning_module) <- get_versioning_module(adapter),
         true <- function_exported?(versioning_module, :revisions, 3),
         {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      versioning_module.revisions(config, normalized_path, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
      _ -> {:error, :unsupported}
    end
  end

  @doc """
  Read a file as it existed at a specific revision.

  Uses the polymorphic versioning interface to support any adapter that implements
  versioning functionality.

  ## Examples

      # Git adapter
      filesystem = Depot.Adapter.Git.configure(path: "/repo")
      {:ok, content} = Depot.read_revision(filesystem, "file.txt", "abc123")

      # ETS adapter
      filesystem = Depot.Adapter.ETS.configure(name: :test_ets)
      {:ok, content} = Depot.read_revision(filesystem, "file.txt", "version_id")

  """
  @spec read_revision(filesystem, Path.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term}
  def read_revision({adapter, config}, path, revision, opts \\ []) do
    with versioning_module when not is_nil(versioning_module) <- get_versioning_module(adapter),
         true <- function_exported?(versioning_module, :read_revision, 4),
         {:ok, normalized_path} <- Depot.RelativePath.normalize(path) do
      versioning_module.read_revision(config, normalized_path, revision, opts)
    else
      {:error, reason} -> {:error, convert_path_error(reason, path)}
      _ -> {:error, :unsupported}
    end
  end

  @doc """
  Rollback the filesystem to a previous revision.

  Uses the polymorphic versioning interface to support any adapter that implements
  versioning functionality.

  ## Options

    * `:path` - Only rollback changes to a specific path (if supported)

  ## Examples

      # Git adapter - full rollback
      filesystem = Depot.Adapter.Git.configure(path: "/repo")
      :ok = Depot.rollback(filesystem, "abc123")

      # ETS adapter - single file rollback
      filesystem = Depot.Adapter.ETS.configure(name: :test_ets)
      :ok = Depot.rollback(filesystem, "version_id", path: "file.txt")

  """
  @spec rollback(filesystem, String.t(), keyword()) :: :ok | {:error, term}
  def rollback({adapter, config}, revision, opts \\ []) do
    with versioning_module when not is_nil(versioning_module) <- get_versioning_module(adapter),
         true <- function_exported?(versioning_module, :rollback, 3) do
      versioning_module.rollback(config, revision, opts)
    else
      _ -> {:error, :unsupported}
    end
  end
end
