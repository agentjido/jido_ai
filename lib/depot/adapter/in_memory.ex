defmodule Depot.Adapter.InMemory do
  @moduledoc """
  Depot Adapter using an `Agent` for in memory storage.

  ## Direct usage

      iex> filesystem = Depot.Adapter.InMemory.configure(name: InMemoryFileSystem)
      iex> start_supervised(filesystem)
      iex> :ok = Depot.write(filesystem, "test.txt", "Hello World")
      iex> {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule InMemoryFileSystem do
        use Depot.Filesystem,
          adapter: Depot.Adapter.InMemory
      end

      start_supervised(InMemoryFileSystem)

      InMemoryFileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = InMemoryFileSystem.read("test.txt")
  """

  alias Depot.Errors

  defmodule AgentStream do
    @enforce_keys [:config, :path]
    defstruct config: nil, path: nil, chunk_size: 1024

    defimpl Enumerable do
      def reduce(%{config: config, path: path, chunk_size: chunk_size}, a, b) do
        case Depot.Adapter.InMemory.read(config, path) do
          {:ok, contents} ->
            contents
            |> Depot.chunk(chunk_size)
            |> reduce(a, b)

          _ ->
            {:halted, []}
        end
      end

      def reduce(_list, {:halt, acc}, _fun), do: {:halted, acc}
      def reduce(list, {:suspend, acc}, fun), do: {:suspended, acc, &reduce(list, &1, fun)}
      def reduce([], {:cont, acc}, _fun), do: {:done, acc}
      def reduce([head | tail], {:cont, acc}, fun), do: reduce(tail, fun.(head, acc), fun)

      def count(_), do: {:error, __MODULE__}
      def slice(_), do: {:error, __MODULE__}
      def member?(_, _), do: {:error, __MODULE__}
    end

    defimpl Collectable do
      def into(%{config: config, path: path} = stream) do
        original =
          case Depot.Adapter.InMemory.read(config, path) do
            {:ok, contents} -> contents
            _ -> ""
          end

        fun = fn
          list, {:cont, x} ->
            [x | list]

          list, :done ->
            contents = original <> IO.iodata_to_binary(:lists.reverse(list))
            Depot.Adapter.InMemory.write(config, path, contents, [])
            stream

          _, :halt ->
            :ok
        end

        {[], fun}
      end
    end
  end

  use Agent

  defmodule Config do
    @moduledoc false
    defstruct name: nil
  end

  @behaviour Depot.Adapter

  @impl Depot.Adapter
  def starts_processes, do: true

  def start_link({__MODULE__, %Config{} = config}) do
    start_link(config)
  end

  def start_link(%Config{} = config) do
    Agent.start_link(fn -> {%{}, %{}, %{}} end, name: Depot.Registry.via(__MODULE__, config.name))
  end

  @impl Depot.Adapter
  def configure(opts) do
    config = %Config{
      name: Keyword.fetch!(opts, :name)
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(config, path, contents, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      file = {IO.iodata_to_binary(contents), %{visibility: visibility}}
      directory = {%{}, %{visibility: directory_visibility}}
      put_in(state, accessor(path, directory), file)
    end)
  end

  @impl Depot.Adapter
  def write_stream(config, path, opts) do
    {:ok,
     %AgentStream{
       config: config,
       path: path,
       chunk_size: Keyword.get(opts, :chunk_size, 1024)
     }}
  end

  @impl Depot.Adapter
  def read(config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {binary, _meta} when is_binary(binary) -> {:ok, binary}
        _ -> {:error, Errors.FileNotFound.exception(file_path: path)}
      end
    end)
  end

  @impl Depot.Adapter
  def read_stream(config, path, opts) do
    {:ok,
     %AgentStream{
       config: config,
       path: path,
       chunk_size: Keyword.get(opts, :chunk_size, 1024)
     }}
  end

  @impl Depot.Adapter
  def delete(%Config{} = config, path) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      {_, state} = pop_in(state, accessor(path))
      state
    end)

    :ok
  end

  @impl Depot.Adapter
  def move(%Config{} = config, source, destination, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        {binary, _meta} when is_binary(binary) ->
          file = {binary, %{visibility: visibility}}
          directory = {%{}, %{visibility: directory_visibility}}

          {_, state} =
            state |> put_in(accessor(destination, directory), file) |> pop_in(accessor(source))

          {:ok, state}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: source)}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(source)) do
        {binary, _meta} when is_binary(binary) ->
          file = {binary, %{visibility: visibility}}
          directory = {%{}, %{visibility: directory_visibility}}
          {:ok, put_in(state, accessor(destination, directory), file)}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: source)}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def copy(
        %Config{} = _source_config,
        _source,
        %Config{} = _destination_config,
        _destination,
        _opts
      ) do
    {:error, :unsupported}
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {binary, _meta} when is_binary(binary) -> {:ok, :exists}
        _ -> {:ok, :missing}
      end
    end)
  end

  @impl Depot.Adapter
  def list_contents(%Config{} = config, path) do
    contents =
      Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
        paths =
          case get_in(state, accessor(path)) do
            {%{} = map, _meta} -> map
            _ -> %{}
          end

        for {path, {content, meta}} <- paths do
          struct =
            case content do
              %{} -> %Depot.Stat.Dir{size: 0}
              bin when is_binary(bin) -> %Depot.Stat.File{size: byte_size(bin)}
            end

          struct!(struct, name: path, mtime: 0, visibility: meta.visibility)
        end
      end)

    {:ok, contents}
  end

  @impl Depot.Adapter
  def create_directory(%Config{} = config, path, opts) do
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)
    directory = {%{}, %{visibility: directory_visibility}}

    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      put_in(state, accessor(path, directory), directory)
    end)

    :ok
  end

  @impl Depot.Adapter
  def delete_directory(%Config{} = config, path, opts) do
    recursive? = Keyword.get(opts, :recursive, false)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case {recursive?, get_in(state, accessor(path))} do
        {_, nil} ->
          {:ok, state}

        {recursive?, {map, _meta}} when is_map(map) and (map_size(map) == 0 or recursive?) ->
          {_, state} = pop_in(state, accessor(path))
          {:ok, state}

        _ ->
          {{:error, Errors.DirectoryNotEmpty.exception(dir_path: path)}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def clear(%Config{} = config) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn _ -> {%{}, %{}, %{}} end)
  end

  @impl Depot.Adapter
  def set_visibility(%Config{} = config, path, visibility) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {_, _} ->
          state =
            update_in(state, accessor(path), fn {contents, meta} ->
              {contents, Map.put(meta, :visibility, visibility)}
            end)

          {:ok, state}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: path)}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def visibility(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {_, %{visibility: visibility}} -> {:ok, visibility}
        _ -> {:error, Errors.FileNotFound.exception(file_path: path)}
      end
    end)
  end

  defp accessor(path, default \\ nil) when is_binary(path) do
    path
    |> Path.absname("/")
    |> Path.split()
    |> do_accessor([], default)
    |> Enum.reverse()
  end

  defp do_accessor([segment], acc, default) do
    [Access.key(segment, default), Access.elem(0) | acc]
  end

  defp do_accessor([segment | rest], acc, default) do
    intermediate_default = default || {%{}, %{}}
    do_accessor(rest, [Access.key(segment, intermediate_default), Access.elem(0) | acc], default)
  end

  # Versioning implementation

  @impl Depot.Adapter
  def write_version(%Config{} = config, path, contents, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn {files, dirs, versions} ->
      version_id = generate_version_id()
      timestamp = System.system_time(:second)

      # Store the version
      version_key = {path, version_id}

      version_data =
        {IO.iodata_to_binary(contents), %{visibility: visibility, timestamp: timestamp}}

      new_versions = Map.put(versions, version_key, version_data)

      # Store version metadata for the path
      path_versions = Map.get(versions, path, [])
      version_info = %{version_id: version_id, timestamp: timestamp}
      final_versions = Map.put(new_versions, path, [version_info | path_versions])

      # Update the current file
      file = {IO.iodata_to_binary(contents), %{visibility: visibility}}
      directory = {%{}, %{visibility: directory_visibility}}

      # Use the same logic as the regular write function 
      updated_files =
        try do
          put_in(files, accessor(path, directory), file)
        rescue
          # If the path doesn't exist, start with an empty file structure
          _ ->
            put_in({%{}, %{}}, accessor(path, directory), file) |> elem(0)
        end

      {{:ok, version_id}, {updated_files, dirs, final_versions}}
    end)
  end

  @impl Depot.Adapter
  def read_version(%Config{} = config, path, version_id) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn {_files, _dirs, versions} ->
      case Map.get(versions, {path, version_id}) do
        {binary, _meta} when is_binary(binary) -> {:ok, binary}
        _ -> {:error, Errors.FileNotFound.exception(file_path: "#{path}@#{version_id}")}
      end
    end)
  end

  @impl Depot.Adapter
  def list_versions(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn {_files, _dirs, versions} ->
      case Map.get(versions, path) do
        nil -> {:ok, []}
        version_list -> {:ok, Enum.reverse(version_list)}
      end
    end)
  end

  @impl Depot.Adapter
  def delete_version(%Config{} = config, path, version_id) do
    Agent.update(Depot.Registry.via(__MODULE__, config.name), fn {files, dirs, versions} ->
      # Remove the version data
      versions = Map.delete(versions, {path, version_id})

      # Remove from version list for the path
      path_versions = Map.get(versions, path, [])
      updated_versions = Enum.reject(path_versions, &(&1.version_id == version_id))
      versions = Map.put(versions, path, updated_versions)

      {files, dirs, versions}
    end)

    :ok
  end

  @impl Depot.Adapter
  def get_latest_version(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn {_files, _dirs, versions} ->
      case Map.get(versions, path) do
        [latest | _] -> {:ok, latest.version_id}
        [] -> {:error, Errors.FileNotFound.exception(file_path: path)}
        nil -> {:error, Errors.FileNotFound.exception(file_path: path)}
      end
    end)
  end

  @impl Depot.Adapter
  def restore_version(%Config{} = config, path, version_id) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn {files, dirs, versions} ->
      case Map.get(versions, {path, version_id}) do
        {binary, meta} when is_binary(binary) ->
          # Restore the file to current
          file = {binary, %{visibility: meta.visibility}}
          directory = {%{}, %{visibility: :private}}

          updated_files =
            try do
              put_in(files, accessor(path, directory), file)
            rescue
              _ ->
                put_in({%{}, %{}}, accessor(path, directory), file) |> elem(0)
            end

          {:ok, {updated_files, dirs, versions}}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: "#{path}@#{version_id}")},
           {files, dirs, versions}}
      end
    end)
  end

  # Extended filesystem operations

  @impl Depot.Adapter
  def stat(%Config{} = config, path) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {binary, meta} when is_binary(binary) ->
          {:ok,
           %Depot.Stat.File{
             name: Path.basename(path),
             size: byte_size(binary),
             mtime: Map.get(meta, :mtime, 0),
             visibility: meta.visibility
           }}

        {%{}, meta} ->
          {:ok,
           %Depot.Stat.Dir{
             name: Path.basename(path),
             size: 0,
             mtime: Map.get(meta, :mtime, 0),
             visibility: meta.visibility
           }}

        _ ->
          {:error, Errors.FileNotFound.exception(file_path: path)}
      end
    end)
  end

  @impl Depot.Adapter
  def access(%Config{} = config, path, modes) do
    Agent.get(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {_, meta} ->
          # InMemory adapter supports all access modes
          # Could check visibility for :read/:write permissions if needed
          case {Enum.member?(modes, :read), Enum.member?(modes, :write), meta.visibility} do
            # read access always allowed
            {true, false, _} -> :ok
            # write access always allowed  
            {false, true, _} -> :ok
            # read-write access always allowed
            {true, true, _} -> :ok
            _ -> :ok
          end

        _ ->
          {:error, Errors.FileNotFound.exception(file_path: path)}
      end
    end)
  end

  @impl Depot.Adapter
  def append(%Config{} = config, path, contents, opts) do
    visibility = Keyword.get(opts, :visibility, :private)
    directory_visibility = Keyword.get(opts, :directory_visibility, :private)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {existing_binary, _meta} when is_binary(existing_binary) ->
          # File exists, append to it
          new_contents = existing_binary <> IO.iodata_to_binary(contents)
          file = {new_contents, %{visibility: visibility, mtime: System.system_time(:second)}}
          {:ok, put_in(state, accessor(path), file)}

        _ ->
          # File doesn't exist, create it with the contents
          file =
            {IO.iodata_to_binary(contents),
             %{visibility: visibility, mtime: System.system_time(:second)}}

          directory = {%{}, %{visibility: directory_visibility}}
          {:ok, put_in(state, accessor(path, directory), file)}
      end
    end)
  end

  @impl Depot.Adapter
  def truncate(%Config{} = config, path, new_size) do
    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {binary, meta} when is_binary(binary) ->
          current_size = byte_size(binary)

          new_binary =
            cond do
              new_size >= current_size ->
                # Pad with zeros if growing
                binary <> :binary.copy(<<0>>, new_size - current_size)

              new_size == 0 ->
                # Truncate to empty
                ""

              true ->
                # Truncate to smaller size
                binary_part(binary, 0, new_size)
            end

          updated_meta = Map.put(meta, :mtime, System.system_time(:second))
          file = {new_binary, updated_meta}
          {:ok, put_in(state, accessor(path), file)}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: path)}, state}
      end
    end)
  end

  @impl Depot.Adapter
  def utime(%Config{} = config, path, mtime) do
    mtime_seconds = DateTime.to_unix(mtime, :second)

    Agent.get_and_update(Depot.Registry.via(__MODULE__, config.name), fn state ->
      case get_in(state, accessor(path)) do
        {contents, meta} ->
          updated_meta = Map.put(meta, :mtime, mtime_seconds)
          updated_entry = {contents, updated_meta}
          {:ok, put_in(state, accessor(path), updated_entry)}

        _ ->
          {{:error, Errors.FileNotFound.exception(file_path: path)}, state}
      end
    end)
  end

  defp generate_version_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
