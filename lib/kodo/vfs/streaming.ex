defmodule Kodo.VFS.Streaming do
  @moduledoc """
  Streaming operations for VFS to handle large files and cross-filesystem operations
  without loading entire contents into memory.
  """

  alias Kodo.VFS.Router
  alias Kodo.Errors
  require Logger

  # 64KB chunks
  @chunk_size 64 * 1024

  @doc """
  Streams a file copy from source to destination, optionally across different filesystems.
  This avoids loading the entire file into memory.
  """
  @spec stream_copy(
          instance :: term(),
          source_path :: String.t(),
          dest_path :: String.t(),
          opts :: keyword()
        ) ::
          :ok | {:error, term()}
  def stream_copy(instance, source_path, dest_path, opts \\ []) do
    with {:ok, source_fs, source_config, source_rel_path} <- Router.route(instance, source_path),
         {:ok, dest_fs, dest_config, dest_rel_path} <- Router.route(instance, dest_path) do
      if same_filesystem?(source_fs, source_config, dest_fs, dest_config) do
        # Same filesystem - use native copy
        Depot.copy({source_fs, source_config}, source_rel_path, dest_rel_path, opts)
      else
        # Cross-filesystem - stream the data
        Logger.warning("Performing cross-filesystem copy via streaming",
          source: source_path,
          destination: dest_path,
          instance: instance
        )

        stream_cross_filesystem_copy(
          {source_fs, source_config, source_rel_path},
          {dest_fs, dest_config, dest_rel_path},
          opts
        )
      end
    else
      {:error, :mount_not_found} ->
        {:error, Errors.no_mount_for_path(source_path, instance)}

      error ->
        {:error, Errors.wrap_depot_error(error, :copy, source_path, instance)}
    end
  end

  @doc """
  Streams a file move from source to destination, optionally across different filesystems.
  """
  @spec stream_move(
          instance :: term(),
          source_path :: String.t(),
          dest_path :: String.t(),
          opts :: keyword()
        ) ::
          :ok | {:error, term()}
  def stream_move(instance, source_path, dest_path, opts \\ []) do
    with {:ok, source_fs, source_config, source_rel_path} <- Router.route(instance, source_path),
         {:ok, dest_fs, dest_config, dest_rel_path} <- Router.route(instance, dest_path) do
      if same_filesystem?(source_fs, source_config, dest_fs, dest_config) do
        # Same filesystem - use native move
        Depot.move({source_fs, source_config}, source_rel_path, dest_rel_path, opts)
      else
        # Cross-filesystem - stream copy then delete
        Logger.warning("Performing cross-filesystem move via streaming",
          source: source_path,
          destination: dest_path,
          instance: instance
        )

        with :ok <-
               stream_cross_filesystem_copy(
                 {source_fs, source_config, source_rel_path},
                 {dest_fs, dest_config, dest_rel_path},
                 opts
               ),
             :ok <- Depot.delete({source_fs, source_config}, source_rel_path) do
          :ok
        end
      end
    else
      {:error, :mount_not_found} ->
        {:error, Errors.no_mount_for_path(source_path, instance)}

      error ->
        {:error, Errors.wrap_depot_error(error, :move, source_path, instance)}
    end
  end

  @doc """
  Creates a readable stream for a file.
  """
  @spec read_stream(instance :: term(), path :: String.t(), opts :: keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def read_stream(instance, path, opts \\ []) do
    case Router.route(instance, path) do
      {:ok, filesystem, config, relative_path} ->
        case Depot.read_stream({filesystem, config}, relative_path, opts) do
          {:ok, stream} ->
            {:ok, stream}

          {:error, :not_implemented} ->
            # Fallback to chunked reading
            create_chunked_read_stream(filesystem, config, relative_path, opts)

          error ->
            {:error, Errors.wrap_depot_error(error, :read_stream, path, instance)}
        end

      {:error, :mount_not_found} ->
        {:error, Errors.no_mount_for_path(path, instance)}
    end
  end

  @doc """
  Creates a writable stream for a file.
  """
  @spec write_stream(instance :: term(), path :: String.t(), opts :: keyword()) ::
          {:ok, Collectable.t()} | {:error, term()}
  def write_stream(instance, path, opts \\ []) do
    case Router.route(instance, path) do
      {:ok, filesystem, config, relative_path} ->
        case Depot.write_stream({filesystem, config}, relative_path, opts) do
          {:ok, stream} ->
            {:ok, stream}

          {:error, :not_implemented} ->
            # Fallback to buffered writing
            create_buffered_write_stream(filesystem, config, relative_path, opts)

          error ->
            {:error, Errors.wrap_depot_error(error, :write_stream, path, instance)}
        end

      {:error, :mount_not_found} ->
        {:error, Errors.no_mount_for_path(path, instance)}
    end
  end

  # Private functions

  defp same_filesystem?(fs1, config1, fs2, config2) do
    fs1 == fs2 and config1 == config2
  end

  defp stream_cross_filesystem_copy(
         {source_fs, source_config, source_path},
         {dest_fs, dest_config, dest_path},
         opts
       ) do
    case Depot.read_stream({source_fs, source_config}, source_path, []) do
      {:ok, read_stream} ->
        case Depot.write_stream({dest_fs, dest_config}, dest_path, opts) do
          {:ok, write_stream} ->
            try do
              read_stream
              |> Stream.into(write_stream)
              |> Stream.run()

              :ok
            rescue
              error ->
                {:error, Errors.cross_filesystem_operation_failed(source_path, dest_path, error)}
            end

          {:error, :not_implemented} ->
            # Fallback to chunked copy
            chunked_cross_filesystem_copy(
              {source_fs, source_config, source_path},
              {dest_fs, dest_config, dest_path},
              opts
            )

          error ->
            {:error, error}
        end

      {:error, :not_implemented} ->
        # Fallback to chunked copy
        chunked_cross_filesystem_copy(
          {source_fs, source_config, source_path},
          {dest_fs, dest_config, dest_path},
          opts
        )

      error ->
        {:error, error}
    end
  end

  defp chunked_cross_filesystem_copy(
         {source_fs, source_config, source_path},
         {dest_fs, dest_config, dest_path},
         opts
       ) do
    # Read file in chunks and write incrementally
    case Depot.read({source_fs, source_config}, source_path) do
      {:ok, content} ->
        if byte_size(content) > @chunk_size * 10 do
          Logger.warning("Large file copy without streaming support - may use significant memory",
            source: source_path,
            destination: dest_path,
            size: byte_size(content)
          )
        end

        Depot.write({dest_fs, dest_config}, dest_path, content, opts)

      error ->
        {:error, error}
    end
  end

  defp create_chunked_read_stream(filesystem, config, path, _opts) do
    # Create a stream that reads the file in chunks
    stream =
      Stream.resource(
        fn ->
          case Depot.read({filesystem, config}, path) do
            {:ok, content} -> {content, 0}
            error -> error
          end
        end,
        fn
          {content, offset} when offset < byte_size(content) ->
            chunk_size = min(@chunk_size, byte_size(content) - offset)
            chunk = binary_part(content, offset, chunk_size)
            {[chunk], {content, offset + chunk_size}}

          {_content, _offset} ->
            {:halt, nil}

          error ->
            {:halt, error}
        end,
        fn _acc -> :ok end
      )

    {:ok, stream}
  end

  defp create_buffered_write_stream(filesystem, config, path, opts) do
    # Create a collector that buffers writes
    collector = %{
      filesystem: filesystem,
      config: config,
      path: path,
      opts: opts,
      buffer: []
    }

    stream =
      {collector,
       fn
         %{buffer: buffer} = acc, {:cont, data} ->
           %{acc | buffer: [data | buffer]}

         %{filesystem: fs, config: cfg, path: p, opts: o, buffer: buffer}, :done ->
           content = buffer |> Enum.reverse() |> IO.iodata_to_binary()

           case Depot.write({fs, cfg}, p, content, o) do
             :ok -> :ok
             error -> {:error, error}
           end

         _acc, :halt ->
           :ok
       end}

    {:ok, stream}
  end
end
