defmodule Depot.Adapter.ETS do
  @moduledoc """
  Depot Adapter using ETS (Erlang Term Storage) for in-memory storage.

  ## Direct usage

      iex> filesystem = Depot.Adapter.ETS.configure(name: ETSFileSystem)
      iex> start_supervised(filesystem)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Direct usage with eternal tables

      iex> filesystem = Depot.Adapter.ETS.configure(name: ETSFileSystem, eternal: true)
      iex> start_supervised(filesystem)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule ETSFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.ETS
      end

      start_supervised(ETSFileSystem)

      ETSFileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = ETSFileSystem.read("test.txt")

  ## Configuration Options

  - `:name` - Required. The name of the ETS table
  - `:eternal` - Optional. When `true`, uses the Eternal library to make the ETS table
    survive process crashes. Defaults to `false`.
  """

  use GenServer

  alias Depot.Errors

  # Constants for default values and common options
  @default_visibility :private
  @default_chunk_size 1024

  defmodule Config do
    @moduledoc false
    defstruct name: nil, table: nil, eternal: false, versions_table: nil
  end

  defmodule ETSStream do
    defstruct [:config, :path]

    defimpl Collectable do
      def into(%{config: config, path: path} = stream) do
        collector_fn = fn
          acc, {:cont, elem} ->
            GenServer.call(
              Depot.Registry.via(Depot.Adapter.ETS, config.name),
              {:append_stream, path, elem}
            )

            acc

          _acc, :done ->
            stream

          _acc, :halt ->
            :ok
        end

        {[], collector_fn}
      end
    end
  end

  @behaviour Depot.Adapter

  @impl Depot.Adapter
  def starts_processes, do: true

  # Consolidated start_link functions using pattern matching
  def start_link({{__MODULE__, %Config{} = config}, _opts}), do: do_start_link(config)
  def start_link({__MODULE__, %Config{} = config}), do: do_start_link(config)
  def start_link(%Config{} = config), do: do_start_link(config)

  defp do_start_link(config) do
    GenServer.start_link(__MODULE__, config, name: Depot.Registry.via(__MODULE__, config.name))
  end

  @impl GenServer
  def init(%Config{} = config) do
    table =
      if config.eternal do
        case Eternal.start_link(config.name, [:set, :protected]) do
          {:ok, _pid} -> config.name
          {:error, {:already_started, _pid}} -> config.name
        end
      else
        :ets.new(config.name, [:set, :protected])
      end

    # Create versions table for versioning support
    versions_table_name = String.to_atom("#{config.name}_versions")

    versions_table =
      if config.eternal do
        case Eternal.start_link(versions_table_name, [:set, :protected]) do
          {:ok, _pid} -> versions_table_name
          {:error, {:already_started, _pid}} -> versions_table_name
        end
      else
        :ets.new(versions_table_name, [:set, :protected])
      end

    {:ok, %Config{config | table: table} |> Map.put(:versions_table, versions_table)}
  end

  @impl Depot.Adapter
  def configure(opts) do
    config = %Config{
      name: Keyword.fetch!(opts, :name),
      eternal: Keyword.get(opts, :eternal, false)
    }

    {__MODULE__, config}
  end

  # File Operations
  @impl Depot.Adapter
  def write(config, path, contents, opts) do
    call_server(config, {:write, path, contents, opts})
  end

  @impl Depot.Adapter
  def read(config, path) do
    call_server(config, {:read, path})
  end

  @impl Depot.Adapter
  def read_stream(config, path, opts) do
    chunk_size = Keyword.get(opts, :chunk_size, @default_chunk_size)
    call_server(config, {:read_stream, path, chunk_size})
  end

  @impl Depot.Adapter
  def delete(config, path) do
    call_server(config, {:delete, path})
  end

  @impl Depot.Adapter
  def move(config, source, destination, opts) do
    call_server(config, {:move, source, destination, opts})
  end

  @impl Depot.Adapter
  def copy(config, source, destination, opts) do
    call_server(config, {:copy, source, destination, opts})
  end

  @impl Depot.Adapter
  def copy(config, source, source_opts, destination, destination_opts) do
    call_server(config, {:copy, source, source_opts, destination, destination_opts})
  end

  # File Status Operations
  @impl Depot.Adapter
  def file_exists(config, path) do
    call_server(config, {:file_exists, path})
  end

  @impl Depot.Adapter
  def list_contents(config, path) do
    call_server(config, {:list_contents, path})
  end

  # Directory Operations
  @impl Depot.Adapter
  def create_directory(config, path, opts) do
    call_server(config, {:create_directory, path, opts})
  end

  @impl Depot.Adapter
  def delete_directory(config, path, opts) do
    call_server(config, {:delete_directory, path, opts})
  end

  @impl Depot.Adapter
  def clear(config) do
    call_server(config, :clear)
  end

  # Visibility Operations
  @impl Depot.Adapter
  def set_visibility(config, path, visibility) do
    call_server(config, {:set_visibility, path, visibility})
  end

  @impl Depot.Adapter
  def visibility(config, path) do
    call_server(config, {:visibility, path})
  end

  @impl Depot.Adapter
  def write_stream(config, path, opts) do
    call_server(config, {:write_stream, path, opts})
  end

  # Helper function to normalize paths and handle GenServer calls
  defp call_server(config, message) do
    GenServer.call(Depot.Registry.via(__MODULE__, config.name), message)
  end

  # Handle Calls Implementation
  @impl GenServer
  def handle_call({:write, path, contents, opts}, _from, %Config{table: table} = state) do
    visibility = Keyword.get(opts, :visibility, @default_visibility)
    directory_visibility = Keyword.get(opts, :directory_visibility, @default_visibility)

    file = {IO.iodata_to_binary(contents), %{visibility: visibility}}
    :ets.insert(table, {path, file})

    create_parent_directories(table, path, directory_visibility)

    {:reply, :ok, state}
  end

  def handle_call({:read, path}, _from, %Config{table: table} = state) do
    reply =
      case lookup_file(table, path) do
        {:ok, binary} -> {:ok, binary}
        :error -> {:error, Errors.FileNotFound.exception(file_path: path)}
      end

    {:reply, reply, state}
  end

  def handle_call({:read_stream, path, chunk_size}, _from, %Config{table: table} = state) do
    reply =
      case lookup_file(table, path) do
        {:ok, binary} ->
          stream =
            Stream.unfold(binary, fn
              <<chunk::binary-size(chunk_size), rest::binary>> -> {chunk, rest}
              <<>> -> nil
              rest -> {rest, <<>>}
            end)

          {:ok, stream}

        :error ->
          {:error, Errors.FileNotFound.exception(file_path: path)}
      end

    {:reply, reply, state}
  end

  def handle_call({:delete, path}, _from, %Config{table: table} = state) do
    :ets.delete(table, path)
    {:reply, :ok, state}
  end

  def handle_call({:move, source, destination, opts}, _from, %Config{table: table} = state) do
    reply =
      case lookup_file(table, source) do
        {:ok, binary} ->
          visibility = Keyword.get(opts, :visibility, @default_visibility)
          file = {binary, %{visibility: visibility}}
          :ets.insert(table, {destination, file})
          :ets.delete(table, source)
          :ok

        :error ->
          {:error, Errors.FileNotFound.exception(file_path: source)}
      end

    {:reply, reply, state}
  end

  def handle_call({:copy, source, destination, opts}, _from, state) do
    handle_copy(source, nil, destination, opts, state)
  end

  def handle_call({:copy, source, _source_opts, destination, destination_opts}, _from, state) do
    handle_copy(source, nil, destination, destination_opts, state)
  end

  def handle_call({:file_exists, path}, _from, %Config{table: table} = state) do
    normalized_path = normalize_path(path)

    exists =
      case :ets.lookup(table, normalized_path) do
        [{^normalized_path, {_content, _meta}}] -> :exists
        [] -> :missing
      end

    {:reply, {:ok, exists}, state}
  end

  def handle_call({:list_contents, path}, _from, %Config{table: table} = state) do
    normalized_path = normalize_path(path)
    contents = list_directory_contents(table, normalized_path)
    {:reply, {:ok, contents}, state}
  end

  def handle_call({:create_directory, path, opts}, _from, %Config{table: table} = state) do
    directory_visibility = Keyword.get(opts, :directory_visibility, @default_visibility)
    normalized_path = normalize_path(path)

    # Always store directory entry with empty map as content
    :ets.insert(table, {normalized_path, {%{}, %{visibility: directory_visibility}}})
    create_directory_tree(table, Path.dirname(normalized_path), directory_visibility)

    {:reply, :ok, state}
  end

  def handle_call({:delete_directory, path, opts}, _from, %Config{table: table} = state) do
    recursive? = Keyword.get(opts, :recursive, false)
    normalized_path = normalize_path(path)

    reply = do_delete_directory(table, normalized_path, recursive?)
    {:reply, reply, state}
  end

  def handle_call(:clear, _from, %Config{table: table} = state) do
    :ets.delete_all_objects(table)
    {:reply, :ok, state}
  end

  def handle_call({:set_visibility, path, visibility}, _from, %Config{table: table} = state) do
    normalized_path = normalize_path(path)
    reply = update_visibility(table, normalized_path, visibility)
    {:reply, reply, state}
  end

  def handle_call({:visibility, path}, _from, %Config{table: table} = state) do
    normalized_path = normalize_path(path)
    reply = get_visibility(table, normalized_path)
    {:reply, reply, state}
  end

  def handle_call({:write_stream, path, _opts}, _from, state) do
    {:reply, {:ok, %ETSStream{config: state, path: path}}, state}
  end

  def handle_call({:append_stream, path, content}, _from, %Config{table: table} = state) do
    append_to_stream(table, path, content)
    {:reply, :ok, state}
  end

  # Versioning handle_call functions

  def handle_call(
        {:write_version, path, contents, opts},
        _from,
        %Config{table: table, versions_table: versions_table} = state
      ) do
    visibility = Keyword.get(opts, :visibility, @default_visibility)
    directory_visibility = Keyword.get(opts, :directory_visibility, @default_visibility)

    version_id = generate_version_id()
    timestamp = System.system_time(:second)

    # Store the version
    version_key = {path, version_id}

    version_data =
      {IO.iodata_to_binary(contents), %{visibility: visibility, timestamp: timestamp}}

    :ets.insert(versions_table, {version_key, version_data})

    # Update the current file
    file = {IO.iodata_to_binary(contents), %{visibility: visibility}}
    :ets.insert(table, {path, file})
    create_parent_directories(table, path, directory_visibility)

    # Store version metadata for the path
    path_versions =
      case :ets.lookup(versions_table, path) do
        [{^path, existing_versions}] -> existing_versions
        [] -> []
      end

    version_info = %{version_id: version_id, timestamp: timestamp}
    :ets.insert(versions_table, {path, [version_info | path_versions]})

    {:reply, {:ok, version_id}, state}
  end

  def handle_call(
        {:read_version, path, version_id},
        _from,
        %Config{versions_table: versions_table} = state
      ) do
    reply =
      case :ets.lookup(versions_table, {path, version_id}) do
        [{{^path, ^version_id}, {binary, _meta}}] when is_binary(binary) -> {:ok, binary}
        [] -> {:error, Errors.FileNotFound.exception(file_path: "#{path}@#{version_id}")}
      end

    {:reply, reply, state}
  end

  def handle_call({:list_versions, path}, _from, %Config{versions_table: versions_table} = state) do
    reply =
      case :ets.lookup(versions_table, path) do
        [{^path, version_list}] -> {:ok, Enum.reverse(version_list)}
        [] -> {:ok, []}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:delete_version, path, version_id},
        _from,
        %Config{versions_table: versions_table} = state
      ) do
    # Remove the version data
    :ets.delete(versions_table, {path, version_id})

    # Remove from version list for the path
    case :ets.lookup(versions_table, path) do
      [{^path, version_list}] ->
        updated_versions = Enum.reject(version_list, &(&1.version_id == version_id))
        :ets.insert(versions_table, {path, updated_versions})

      [] ->
        :ok
    end

    {:reply, :ok, state}
  end

  def handle_call(
        {:get_latest_version, path},
        _from,
        %Config{versions_table: versions_table} = state
      ) do
    reply =
      case :ets.lookup(versions_table, path) do
        [{^path, [latest | _]}] -> {:ok, latest.version_id}
        [{^path, []}] -> {:error, Errors.FileNotFound.exception(file_path: path)}
        [] -> {:error, Errors.FileNotFound.exception(file_path: path)}
      end

    {:reply, reply, state}
  end

  def handle_call(
        {:restore_version, path, version_id},
        _from,
        %Config{table: table, versions_table: versions_table} = state
      ) do
    reply =
      case :ets.lookup(versions_table, {path, version_id}) do
        [{{^path, ^version_id}, {binary, meta}}] when is_binary(binary) ->
          # Restore the file to current
          file = {binary, %{visibility: meta.visibility}}
          :ets.insert(table, {path, file})
          :ok

        [] ->
          {:error, Errors.FileNotFound.exception(file_path: "#{path}@#{version_id}")}
      end

    {:reply, reply, state}
  end

  # Private Helper Functions

  defp normalize_path(path), do: String.trim_trailing(path, "/")

  defp lookup_file(table, path) do
    case :ets.lookup(table, path) do
      [{^path, {binary, _meta}}] when is_binary(binary) -> {:ok, binary}
      _ -> :error
    end
  end

  defp create_parent_directories(table, path, visibility) do
    path
    |> Path.dirname()
    |> Path.split()
    |> Enum.reduce("", fn segment, acc ->
      dir_path = Path.join([acc, segment])
      :ets.insert_new(table, {dir_path, {%{}, %{visibility: visibility}}})
      dir_path
    end)
  end

  defp handle_copy(
         source,
         _source_opts,
         destination,
         destination_opts,
         %Config{table: table} = state
       ) do
    reply =
      case lookup_file(table, source) do
        {:ok, binary} ->
          visibility = Keyword.get(destination_opts, :visibility, @default_visibility)
          file = {binary, %{visibility: visibility}}
          :ets.insert(table, {destination, file})
          :ok

        :error ->
          {:error, Errors.FileNotFound.exception(file_path: source)}
      end

    {:reply, reply, state}
  end

  defp list_directory_contents(table, path) do
    normalized_path = normalize_path(path)

    table
    |> :ets.tab2list()
    |> Enum.reduce(%{}, fn {file_path, {content, meta}}, acc ->
      case check_path_in_directory(file_path, normalized_path) do
        {:direct_child, name} when name not in [".", ".."] ->
          if Map.has_key?(acc, name) do
            if match?(%Depot.Stat.Dir{}, acc[name]) do
              acc
            else
              case content do
                map when is_map(map) ->
                  Map.put(acc, name, create_stat_struct(name, content, meta))

                _ ->
                  acc
              end
            end
          else
            Map.put(acc, name, create_stat_struct(name, content, meta))
          end

        _ ->
          acc
      end
    end)
    |> Map.values()
  end

  defp check_path_in_directory(file_path, parent_path) do
    normalized_file = normalize_path(file_path)

    cond do
      # Root directory case
      parent_path in ["", "."] ->
        case Path.split(normalized_file) do
          [single_part] -> {:direct_child, single_part}
          [first_part | _] -> {:direct_child, first_part}
          _ -> :not_child
        end

      # Regular directory case - only exact children
      Path.dirname(normalized_file) == parent_path ->
        {:direct_child, Path.basename(normalized_file)}

      true ->
        :not_child
    end
  end

  defp create_stat_struct(name, content, meta) do
    case content do
      map when is_map(map) ->
        %Depot.Stat.Dir{
          name: name,
          size: 0,
          mtime: 0,
          visibility: meta.visibility
        }

      bin when is_binary(bin) ->
        %Depot.Stat.File{
          name: name,
          size: byte_size(bin),
          mtime: 0,
          visibility: meta.visibility
        }
    end
  end

  defp create_directory_tree(table, path, visibility) do
    if path in ["", ".", "/"] do
      :ok
    else
      path
      |> Path.split()
      |> Enum.reduce({"", visibility}, fn segment, {acc, vis} ->
        dir_path = if acc == "", do: segment, else: Path.join(acc, segment)

        # Always store directories with a map as content
        :ets.insert_new(table, {dir_path, {%{}, %{visibility: vis}}})
        {dir_path, vis}
      end)
    end
  end

  defp do_delete_directory(table, path, recursive?) do
    has_contents? = directory_has_contents?(table, path)

    cond do
      not match?([{_, {%{}, _}}], :ets.lookup(table, path)) ->
        {:error, Errors.DirectoryNotFound.exception(dir_path: path)}

      has_contents? and not recursive? ->
        {:error, Errors.DirectoryNotEmpty.exception(dir_path: path)}

      true ->
        if recursive? do
          delete_directory_recursive(table, path)
        else
          :ets.delete(table, path)
        end

        :ok
    end
  end

  defp directory_has_contents?(table, path) do
    :ets.foldl(
      fn {key, _value}, acc ->
        acc or (String.starts_with?(key, path <> "/") and key != path)
      end,
      false,
      table
    )
  end

  defp delete_directory_recursive(table, path) do
    :ets.foldl(
      fn {key, _}, :ok ->
        if String.starts_with?(key, path) do
          :ets.delete(table, key)
        end

        :ok
      end,
      :ok,
      table
    )
  end

  defp update_visibility(table, path, visibility) do
    case :ets.lookup(table, path) do
      [{^path, {contents, meta}}] ->
        :ets.insert(table, {path, {contents, Map.put(meta, :visibility, visibility)}})
        update_children_visibility(table, path, visibility, is_map(contents))
        :ok

      [] ->
        {:error, Errors.FileNotFound.exception(file_path: path)}
    end
  end

  defp update_children_visibility(table, path, visibility, true) do
    :ets.foldl(
      fn {key, {content, sub_meta}}, :ok ->
        if String.starts_with?(key, path <> "/") do
          :ets.insert(table, {key, {content, Map.put(sub_meta, :visibility, visibility)}})
        end

        :ok
      end,
      :ok,
      table
    )
  end

  defp update_children_visibility(_table, _path, _visibility, false), do: :ok

  defp get_visibility(table, path) do
    case :ets.lookup(table, path) do
      [{_, {_, %{visibility: visibility}}}] ->
        {:ok, visibility}

      [] ->
        if path in [".", ""] do
          {:ok, :public}
        else
          {:error, Errors.FileNotFound.exception(file_path: path)}
        end
    end
  end

  defp append_to_stream(table, path, content) do
    case :ets.lookup(table, path) do
      [{^path, {existing, meta}}] when is_binary(existing) ->
        new_content = existing <> IO.iodata_to_binary(content)
        :ets.insert(table, {path, {new_content, meta}})

      [] ->
        :ets.insert(
          table,
          {path, {IO.iodata_to_binary(content), %{visibility: @default_visibility}}}
        )
    end
  end

  # Versioning adapter implementation

  @impl Depot.Adapter
  def write_version(config, path, contents, opts) do
    call_server(config, {:write_version, path, contents, opts})
  end

  @impl Depot.Adapter
  def read_version(config, path, version_id) do
    call_server(config, {:read_version, path, version_id})
  end

  @impl Depot.Adapter
  def list_versions(config, path) do
    call_server(config, {:list_versions, path})
  end

  @impl Depot.Adapter
  def delete_version(config, path, version_id) do
    call_server(config, {:delete_version, path, version_id})
  end

  @impl Depot.Adapter
  def get_latest_version(config, path) do
    call_server(config, {:get_latest_version, path})
  end

  @impl Depot.Adapter
  def restore_version(config, path, version_id) do
    call_server(config, {:restore_version, path, version_id})
  end

  defp generate_version_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
