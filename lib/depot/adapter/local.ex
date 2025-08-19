defmodule Depot.Adapter.Local do
  @moduledoc """
  Depot Adapter for the local filesystem.

  ## Direct usage

      iex> prefix = System.tmp_dir!()
      iex> filesystem = Depot.Adapter.Local.configure(prefix: prefix)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule LocalFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.Local,
          prefix: prefix
      end

      LocalFileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = LocalFileSystem.read("test.txt")

  ## Usage with Streams

  The following options are available for streams:

    * `:chunk_size` - When reading, the amount to read,
      by `:line` (default) or by a given number of bytes.

    * `:modes` - A list of modes to use when opening the file
      for reading. For more information, see the docs for
      `File.stream!/3`.

  ### Examples

      {:ok, %File.Stream{}} = Depot.read_stream(filesystem, "test.txt")

      # with custom read chunk size
      {:ok, %File.Stream{line_or_bytes: 1_024, ...}} = Depot.read_stream(filesystem, "test.txt", chunk_size: 1_024)

      # with custom file read modes
      {:ok, %File.Stream{mode: [{:encoding, :utf8}, :binary], ...}} = Depot.read_stream(filesystem, "test.txt", modes: [encoding: :utf8])

  """
  import Bitwise
  alias Depot.Visibility.UnixVisibilityConverter
  alias Depot.Visibility.PortableUnixVisibilityConverter, as: DefaultVisibilityConverter
  alias Depot.Errors

  defmodule Config do
    @moduledoc false

    @type t :: %__MODULE__{
            prefix: Path.t(),
            converter: UnixVisibilityConverter.t(),
            visibility: UnixVisibilityConverter.config()
          }

    defstruct prefix: nil, converter: nil, visibility: nil
  end

  @behaviour Depot.Adapter

  @impl Depot.Adapter
  def starts_processes, do: false

  @impl Depot.Adapter
  def configure(opts) do
    visibility_config = Keyword.get(opts, :visibility, [])
    converter = Keyword.get(visibility_config, :converter, DefaultVisibilityConverter)
    visibility = visibility_config |> Keyword.drop([:converter]) |> converter.config()

    config = %Config{
      prefix: Keyword.fetch!(opts, :prefix),
      converter: converter,
      visibility: visibility
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(%Config{} = config, path, contents, opts) do
    path = full_path(config, path)

    mode =
      with {:ok, visibility} <- Keyword.fetch(opts, :visibility) do
        mode = config.converter.for_file(config.visibility, visibility)
        {:ok, mode}
      end

    with :ok <- ensure_directory(config, Path.dirname(path), opts),
         :ok <- File.write(path, contents),
         :ok <- maybe_chmod(path, mode) do
      :ok
    end
  end

  @impl Depot.Adapter
  def write_stream(%Config{} = config, path, opts) do
    modes = opts[:modes] || []
    line_or_bytes = opts[:chunk_size] || :line
    {:ok, File.stream!(full_path(config, path), modes, line_or_bytes)}
  rescue
    e -> {:error, convert_exception_error(e, full_path(config, path))}
  end

  @impl Depot.Adapter
  def read(%Config{} = config, path) do
    case File.read(full_path(config, path)) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, convert_file_error(reason, full_path(config, path))}
    end
  end

  @impl Depot.Adapter
  def read_stream(%Config{} = config, path, opts) do
    modes = opts[:modes] || []
    line_or_bytes = opts[:chunk_size] || :line
    {:ok, File.stream!(full_path(config, path), modes, line_or_bytes)}
  rescue
    e -> {:error, convert_exception_error(e, full_path(config, path))}
  end

  @impl Depot.Adapter
  def delete(%Config{} = config, path) do
    case File.rm(full_path(config, path)) do
      :ok -> :ok
      {:error, :enoent} -> :ok
      {:error, reason} -> {:error, convert_file_error(reason, full_path(config, path))}
    end
  end

  @impl Depot.Adapter
  def move(%Config{} = config, source, destination, opts) do
    source = full_path(config, source)
    destination = full_path(config, destination)

    with :ok <- ensure_directory(config, Path.dirname(destination), opts),
         result <- File.rename(source, destination) do
      case result do
        :ok -> :ok
        {:error, reason} -> {:error, convert_file_error(reason, source)}
      end
    end
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination, opts) do
    source = full_path(config, source)
    destination = full_path(config, destination)

    with :ok <- ensure_directory(config, Path.dirname(destination), opts),
         result <- File.cp(source, destination) do
      case result do
        :ok -> :ok
        {:error, reason} -> {:error, convert_file_error(reason, source)}
      end
    end
  end

  @impl Depot.Adapter
  def copy(
        %Config{} = source_config,
        source,
        %Config{} = destination_config,
        destination,
        opts
      ) do
    source = full_path(source_config, source)
    destination = full_path(destination_config, destination)

    with :ok <- ensure_directory(destination_config, Path.dirname(destination), opts),
         result <- File.cp(source, destination) do
      case result do
        :ok -> :ok
        {:error, reason} -> {:error, convert_file_error(reason, source)}
      end
    end
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    case File.exists?(full_path(config, path)) do
      true -> {:ok, :exists}
      false -> {:ok, :missing}
    end
  end

  @impl Depot.Adapter
  def list_contents(%Config{} = config, path) do
    full_path = full_path(config, path)

    case File.ls(full_path) do
      {:ok, files} ->
        contents =
          for file <- files,
              {:ok, stat} = File.stat(Path.join(full_path, file), time: :posix),
              stat.type in [:directory, :regular] do
            struct =
              case stat.type do
                :directory -> Depot.Stat.Dir
                :regular -> Depot.Stat.File
              end

            struct!(struct,
              name: file,
              size: stat.size,
              mtime: stat.mtime,
              visibility: visibility_for_mode(config, stat.type, stat.mode)
            )
          end

        {:ok, contents}

      {:error, reason} ->
        {:error, convert_file_error(reason, full_path)}
    end
  end

  @impl Depot.Adapter
  def create_directory(%Config{} = config, path, opts) do
    path = full_path(config, path)
    ensure_directory(config, path, opts)
  end

  @impl Depot.Adapter
  def delete_directory(%Config{} = config, path, opts) do
    path = full_path(config, path)

    if Keyword.get(opts, :recursive, false) do
      case File.rm_rf(path) do
        {:ok, _} -> :ok
        {:error, reason, _} -> {:error, convert_file_error(reason, path)}
      end
    else
      case File.rmdir(path) do
        :ok -> :ok
        {:error, reason} -> {:error, convert_file_error(reason, path)}
      end
    end
  end

  @impl Depot.Adapter
  def clear(%Config{} = config) do
    with {:ok, contents} <- list_contents(%Config{} = config, ".") do
      Enum.reduce_while(contents, :ok, fn dir_or_file, :ok ->
        case clear_dir_or_file(config, dir_or_file) do
          :ok -> {:cont, :ok}
          err -> {:halt, err}
        end
      end)
    end
  end

  @impl Depot.Adapter
  def set_visibility(%Config{} = config, path, visibility) do
    path = full_path(config, path)

    mode =
      if File.dir?(path) do
        config.converter.for_directory(config.visibility, visibility)
      else
        config.converter.for_file(config.visibility, visibility)
      end

    case File.chmod(path, mode) do
      :ok -> :ok
      {:error, reason} -> {:error, convert_file_error(reason, path)}
    end
  end

  @impl Depot.Adapter
  def visibility(%Config{} = config, path) do
    path = full_path(config, path)

    case File.stat(path) do
      {:ok, %{mode: mode, type: type}} ->
        {:ok, visibility_for_mode(config, type, mode)}

      {:error, reason} ->
        {:error, convert_file_error(reason, path)}
    end
  end

  defp visibility_for_mode(config, type, mode) do
    mode = mode &&& 0o777

    case type do
      :directory -> config.converter.from_directory(config.visibility, mode)
      _ -> config.converter.from_file(config.visibility, mode)
    end
  end

  defp clear_dir_or_file(config, %Depot.Stat.Dir{name: dir}),
    do: delete_directory(config, dir, recursive: true)

  defp clear_dir_or_file(config, %Depot.Stat.File{name: name}),
    do: delete(config, name)

  defp full_path(config, path) do
    Depot.RelativePath.join_prefix(config.prefix, path)
  end

  defp ensure_directory(config, path, opts) do
    mode =
      with {:ok, visibility} <- Keyword.fetch(opts, :directory_visibility) do
        mode = config.converter.for_directory(config.visibility, visibility)
        {:ok, mode}
      end

    path
    |> IO.chardata_to_string()
    |> Path.join("/")
    |> do_mkdir_p(mode)
  end

  defp do_mkdir_p(path, mode) do
    with :missing <- existing_directory(path),
         parent = Path.dirname(path),
         :ok <- infinite_loop_protect(path),
         :ok <- do_mkdir_p(parent, mode),
         :ok <- :file.make_dir(path) do
      maybe_chmod(path, mode)
    end
  end

  def existing_directory(path) do
    if File.dir?(path), do: :ok, else: :missing
  end

  defp infinite_loop_protect(path) do
    if Path.dirname(path) != path do
      :ok
    else
      {:error, Errors.InvalidPath.exception(path: path, reason: "infinite loop detected")}
    end
  end

  defp maybe_chmod(path, {:ok, mode}), do: File.chmod(path, mode)
  defp maybe_chmod(_path, :error), do: :ok

  defp convert_file_error(:enoent, path) do
    if File.dir?(Path.dirname(path)) do
      Errors.FileNotFound.exception(file_path: path)
    else
      Errors.DirectoryNotFound.exception(dir_path: path)
    end
  end

  defp convert_file_error(:enotdir, path) do
    Errors.DirectoryNotFound.exception(dir_path: path)
  end

  defp convert_file_error(:eexist, path) do
    Errors.DirectoryNotEmpty.exception(dir_path: path)
  end

  defp convert_file_error(:einval, path) do
    Errors.InvalidPath.exception(path: path, reason: "invalid path")
  end

  defp convert_file_error(:eacces, path) do
    Errors.PermissionDenied.exception(target_path: path, operation: "access")
  end

  defp convert_file_error(:eperm, path) do
    Errors.PermissionDenied.exception(target_path: path, operation: "permission")
  end

  defp convert_file_error(reason, path) do
    Errors.AdapterError.exception(
      adapter: __MODULE__,
      reason: "File operation failed on #{path}: #{inspect(reason)}"
    )
  end

  defp convert_exception_error(%{__exception__: true} = exception, _path) do
    exception
  end

  # Extended filesystem operations

  @impl Depot.Adapter
  def stat(%Config{} = config, path) do
    path = full_path(config, path)

    case File.stat(path, time: :posix) do
      {:ok, stat} ->
        struct_module =
          case stat.type do
            :regular -> Depot.Stat.File
            :directory -> Depot.Stat.Dir
            # fallback for special files
            _ -> Depot.Stat.File
          end

        {:ok,
         struct!(struct_module,
           name: Path.basename(path),
           size: stat.size,
           mtime: stat.mtime,
           visibility: visibility_for_mode(config, stat.type, stat.mode)
         )}

      {:error, reason} ->
        {:error, convert_file_error(reason, path)}
    end
  end

  @impl Depot.Adapter
  def access(%Config{} = config, path, modes) do
    path = full_path(config, path)

    # Convert our modes to Erlang file access modes
    erlang_modes =
      modes
      |> Enum.flat_map(fn
        :read -> [:read]
        :write -> [:write]
      end)
      |> Enum.uniq()

    case :file.read_file_info(String.to_charlist(path), [{:time, :posix}]) do
      {:ok, _} ->
        # File exists, now check access
        case :file.read_file_info(String.to_charlist(path), [:read | erlang_modes]) do
          {:ok, _} ->
            :ok

          {:error, :eacces} ->
            {:error, Errors.PermissionDenied.exception(target_path: path, operation: "access")}

          {:error, reason} ->
            {:error, convert_file_error(reason, path)}
        end

      {:error, reason} ->
        {:error, convert_file_error(reason, path)}
    end
  end

  @impl Depot.Adapter
  def append(%Config{} = config, path, contents, opts) do
    path = full_path(config, path)

    mode =
      with {:ok, visibility} <- Keyword.fetch(opts, :visibility) do
        mode = config.converter.for_file(config.visibility, visibility)
        {:ok, mode}
      end

    with :ok <- ensure_directory(config, Path.dirname(path), opts),
         {:ok, file} <- File.open(path, [:append, :binary]),
         :ok <- IO.binwrite(file, contents),
         :ok <- File.close(file),
         :ok <- maybe_chmod(path, mode) do
      :ok
    else
      {:error, reason} -> {:error, convert_file_error(reason, path)}
    end
  end

  @impl Depot.Adapter
  def truncate(%Config{} = config, path, new_size) do
    path = full_path(config, path)

    case File.stat(path) do
      {:ok, _} ->
        case :file.open(String.to_charlist(path), [:write, :binary]) do
          {:ok, device} ->
            result =
              case :file.position(device, new_size) do
                {:ok, _} ->
                  case :file.truncate(device) do
                    :ok -> :ok
                    {:error, reason} -> {:error, convert_file_error(reason, path)}
                  end

                {:error, reason} ->
                  {:error, convert_file_error(reason, path)}
              end

            :file.close(device)
            result

          {:error, reason} ->
            {:error, convert_file_error(reason, path)}
        end

      {:error, reason} ->
        {:error, convert_file_error(reason, path)}
    end
  end

  @impl Depot.Adapter
  def utime(%Config{} = config, path, mtime) do
    path = full_path(config, path)

    # Convert DateTime to the format expected by :file.change_time 
    {{year, month, day}, {hour, minute, second}} =
      mtime
      |> DateTime.to_naive()
      |> NaiveDateTime.to_erl()

    datetime_tuple = {{year, month, day}, {hour, minute, second}}

    case :file.change_time(String.to_charlist(path), datetime_tuple, datetime_tuple) do
      :ok -> :ok
      {:error, reason} -> {:error, convert_file_error(reason, path)}
    end
  end
end
