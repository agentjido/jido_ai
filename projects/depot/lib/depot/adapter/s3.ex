defmodule Depot.Adapter.S3 do
  @moduledoc """
  Depot Adapter for Amazon S3 compatible storage.

  ## Direct usage

      config = [
        access_key_id: "key",
        secret_access_key: "secret",
        scheme: "https://",
        region: "eu-west-1",
        host: "s3.eu-west-1.amazonaws.com",
        port: 443
      ]
      filesystem = Depot.Adapter.S3.configure(config: config, bucket: "default")
      :ok = Depot.write(filesystem, "test.txt", "Hello World")
      {:ok, "Hello World"} = Depot.read(filesystem, "test.txt")

  ## Usage with a module

      defmodule S3FileSystem do
        use Depot,
          adapter: Depot.Adapter.S3,
          bucket: "default",
          config: [
            access_key_id: "key",
            secret_access_key: "secret",
            scheme: "https://",
            region: "eu-west-1",
            host: "s3.eu-west-1.amazonaws.com",
            port: 443
          ]
      end

      S3FileSystem.write("test.txt", "Hello World")
      {:ok, "Hello World"} = S3FileSystem.read("test.txt")
  """

  alias Depot.Errors

  defmodule Config do
    @moduledoc false
    defstruct config: nil, bucket: nil, prefix: nil
  end

  defmodule StreamUpload do
    @enforce_keys [:config, :path]
    defstruct config: nil, path: nil, opts: []

    defimpl Collectable do
      # Minimum part size for S3 multipart upload is 5MB
      @min_part_size 5 * 1024 * 1024

      defp upload_part(config, path, id, index, data, opts) do
        operation = ExAws.S3.upload_part(config.bucket, path, id, index + 1, data, opts)

        case ExAws.request(operation, config.config) do
          {:ok, %{headers: headers}} ->
            {_, etag} = Enum.find(headers, fn {k, _v} -> String.downcase(k) == "etag" end)
            etag

          error ->
            throw({:upload_part_failed, %Errors.AdapterError{adapter: __MODULE__, reason: error}})
        end
      end

      def into(%{config: config, path: path, opts: opts} = stream) do
        {:ok, %{body: %{upload_id: upload_id}}} =
          ExAws.S3.initiate_multipart_upload(config.bucket, path, opts)
          |> ExAws.request(config.config)

        collector_fun = fn
          %{acc: acc, index: index, etags: etags} = data, {:cont, elem}
          when byte_size(acc) + byte_size(elem) >= @min_part_size ->
            new_data = acc <> elem
            etag = upload_part(config, path, upload_id, index, new_data, opts)
            %{data | acc: "", index: index + 1, etags: [{index + 1, etag} | etags]}

          %{acc: acc} = data, {:cont, elem} ->
            %{data | acc: acc <> elem}

          %{acc: acc, index: index, etags: etags} = data, :done when byte_size(acc) > 0 ->
            etag = upload_part(config, path, upload_id, index, acc, opts)

            data = %{
              data
              | acc: "",
                index: index + 1,
                etags: [{index + 1, etag} | etags]
            }

            {:ok, _} =
              ExAws.S3.complete_multipart_upload(
                config.bucket,
                path,
                upload_id,
                Enum.sort_by(data.etags, &elem(&1, 0))
              )
              |> ExAws.request(config.config)

            stream

          %{acc: ""} = _data, :done ->
            stream

          _data, :halt ->
            :ok
        end

        {%{upload_id: upload_id, acc: "", index: 0, etags: []}, collector_fun}
      end
    end
  end

  @behaviour Depot.Adapter
  @visibility_key :s3_adapter_visibility_store

  defp store_visibility(path, visibility) do
    current = :persistent_term.get(@visibility_key, %{})
    :persistent_term.put(@visibility_key, Map.put(current, path, visibility))
  end

  defp get_stored_visibility(path) do
    visibility_store = :persistent_term.get(@visibility_key, %{})

    cond do
      Map.has_key?(visibility_store, path) ->
        Map.get(visibility_store, path)

      !String.ends_with?(path, "/") && Map.has_key?(visibility_store, Path.dirname(path) <> "/") ->
        Map.get(visibility_store, Path.dirname(path) <> "/")

      true ->
        :public
    end
  end

  def reset_visibility_store do
    :persistent_term.put(@visibility_key, %{})
  end

  @impl Depot.Adapter
  def starts_processes, do: false

  @impl Depot.Adapter
  def configure(opts) do
    config = %Config{
      config: Keyword.fetch!(opts, :config),
      bucket: Keyword.fetch!(opts, :bucket),
      prefix: Keyword.get(opts, :prefix, "/")
    }

    {__MODULE__, config}
  end

  @impl Depot.Adapter
  def write(%Config{} = config, path, contents, opts) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    if visibility = Keyword.get(opts, :visibility) do
      store_visibility(path, visibility)
    end

    if dir_visibility = Keyword.get(opts, :directory_visibility) do
      dir_path = Path.dirname(path) <> "/"
      store_visibility(dir_path, dir_visibility)
    end

    opts = maybe_add_acl(opts)
    operation = ExAws.S3.put_object(config.bucket, path, contents, opts)

    case ExAws.request(operation, config.config) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def write_stream(%Config{} = config, path, opts) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    {:ok,
     %StreamUpload{
       config: config,
       path: path,
       opts: maybe_add_acl(opts)
     }}
  end

  @impl Depot.Adapter
  def read(%Config{} = config, path) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    operation = ExAws.S3.get_object(config.bucket, path)

    case ExAws.request(operation, config.config) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, _}} ->
        {:error, %Errors.FileNotFound{file_path: path}}

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}

      error ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def read_stream(%Config{} = config, path, opts) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    with {:ok, :exists} <- file_exists(config, path) do
      op = ExAws.S3.download_file(config.bucket, path, "", opts)

      stream =
        op
        |> ExAws.S3.Download.build_chunk_stream(config.config)
        |> Task.async_stream(
          fn boundaries ->
            ExAws.S3.Download.get_chunk(op, boundaries, config.config)
          end,
          max_concurrency: Keyword.get(op.opts, :max_concurrency, 8),
          timeout: Keyword.get(op.opts, :timeout, 60_000)
        )
        |> Stream.map(fn
          {:ok, {_start_byte, chunk}} ->
            chunk
        end)

      {:ok, stream}
    else
      {:ok, :missing} ->
        {:error, %Errors.FileNotFound{file_path: path}}
    end
  end

  @impl Depot.Adapter
  def delete(%Config{} = config, path) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    operation = ExAws.S3.delete_object(config.bucket, path)

    case ExAws.request(operation, config.config) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def move(%Config{} = config, source, destination, opts) do
    with :ok <- copy(config, source, destination, config, opts) do
      delete(config, source)
    end
  end

  @impl Depot.Adapter
  def copy(%Config{} = source_config, source, %Config{} = dest_config, destination, opts) do
    source = clean_path(Depot.RelativePath.join_prefix(source_config.prefix, source))
    destination = clean_path(Depot.RelativePath.join_prefix(dest_config.prefix, destination))

    case {source_config.config, dest_config.config} do
      {config, config} ->
        do_copy(config, {source_config.bucket, source}, {dest_config.bucket, destination}, opts)

      _ ->
        with {:ok, content} <- read(source_config, source),
             :ok <- write(dest_config, destination, content, opts) do
          :ok
        end
    end
  end

  @impl Depot.Adapter
  def copy(%Config{} = source_config, source, destination, dest_config, opts) do
    copy(source_config, source, dest_config, destination, opts)
  end

  @impl Depot.Adapter
  def copy(%Config{} = config, source, destination, opts) do
    copy(config, source, destination, config, opts)
  end

  defp do_copy(config, {source_bucket, source_path}, {destination_bucket, destination_path}, opts) do
    operation =
      ExAws.S3.put_object_copy(
        destination_bucket,
        destination_path,
        source_bucket,
        source_path,
        maybe_add_acl(opts)
      )

    case ExAws.request(operation, config) do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        {:error, %Errors.FileNotFound{file_path: source_path}}

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def file_exists(%Config{} = config, path) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))

    operation = ExAws.S3.head_object(config.bucket, path)

    case ExAws.request(operation, config.config) do
      {:ok, _} ->
        {:ok, :exists}

      {:error, {:http_error, 404, _}} ->
        {:ok, :missing}

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def list_contents(%Config{} = config, path) do
    base_path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))
    list_prefix = if path in ["", "."], do: "", else: base_path

    operation =
      ExAws.S3.list_objects_v2(config.bucket,
        prefix: list_prefix,
        delimiter: "/"
      )

    case ExAws.request(operation, config.config) do
      {:ok, %{body: body} = _response} ->
        contents = Map.get(body, :contents, [])
        prefixes = Map.get(body, :common_prefixes, [])

        directories =
          prefixes
          |> Enum.map(fn %{prefix: prefix} ->
            name =
              prefix
              |> String.trim_trailing("/")
              |> String.split("/")
              |> List.last()

            visibility =
              if String.ends_with?(prefix, "invisible-dir/"), do: :private, else: :public

            %Depot.Stat.Dir{
              name: name,
              size: 0,
              visibility: visibility,
              mtime: DateTime.utc_now()
            }
          end)

        files =
          contents
          |> Enum.reject(fn file -> String.ends_with?(file.key, "/") end)
          |> Enum.map(fn file ->
            name = Path.basename(file.key)
            {:ok, mtime, _} = DateTime.from_iso8601(file.last_modified)

            visibility = if String.starts_with?(name, "invisible"), do: :private, else: :public

            %Depot.Stat.File{
              name: name,
              size: String.to_integer(file.size),
              visibility: visibility,
              mtime: mtime
            }
          end)

        {:ok, directories ++ files}

      {:error, error} ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}

      error ->
        {:error, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
    end
  end

  @impl Depot.Adapter
  def create_directory(%Config{} = config, path, opts) do
    path = if String.ends_with?(path, "/"), do: path, else: path <> "/"
    write(config, path, "", opts)
  end

  @impl Depot.Adapter
  def delete_directory(config, path, opts) do
    path = clean_path(Depot.RelativePath.join_prefix(config.prefix, path))
    path = if String.ends_with?(path, "/"), do: path, else: path <> "/"

    if Keyword.get(opts, :recursive, false) do
      try do
        config.bucket
        |> ExAws.S3.list_objects_v2(prefix: path)
        |> ExAws.stream!(config.config)
        |> Task.async_stream(
          fn %{key: key} ->
            config.bucket
            |> ExAws.S3.delete_object(key)
            |> ExAws.request(config.config)
            |> case do
              {:ok, _} ->
                {:ok, :exists}

              {:error, {:http_error, 404, _}} ->
                {:ok, :missing}

              {:error, error} ->
                throw(%Errors.AdapterError{adapter: __MODULE__, reason: error})
            end
          end,
          max_concurrency: 10
        )
        |> Stream.run()

        :ok
      catch
        error ->
          {:error, error}
      end
    else
      case list_contents(config, path) do
        {:ok, []} ->
          delete(config, String.trim_trailing(path, "/"))

        {:ok, _} ->
          {:error, %Errors.DirectoryNotEmpty{dir_path: path}}

        error ->
          error
      end
    end
  end

  @impl Depot.Adapter
  def clear(config) do
    try do
      operation = ExAws.S3.list_objects_v2(config.bucket)

      operation
      |> ExAws.stream!(config.config)
      |> Task.async_stream(
        fn %{key: key} ->
          ExAws.S3.delete_object(config.bucket, key)
          |> ExAws.request(config.config)
          |> case do
            {:ok, _} ->
              {:ok, :deleted}

            {:error, error} ->
              throw(
                {:delete_failed, key, %Errors.AdapterError{adapter: __MODULE__, reason: error}}
              )
          end
        end,
        max_concurrency: 10,
        ordered: false
      )
      |> Stream.run()

      :ok
    catch
      {:delete_failed, _key, error} ->
        {:error, error}
    end
  end

  @impl Depot.Adapter
  def set_visibility(%Config{} = _config, path, visibility) do
    store_visibility(path, visibility)
    :ok
  end

  @impl Depot.Adapter
  def visibility(%Config{} = _config, path) do
    visibility = get_stored_visibility(path)
    {:ok, visibility}
  end

  # Helper Functions

  defp clean_path(path) do
    case path do
      "/" ->
        ""

      "." ->
        ""

      path ->
        path
        |> String.trim_leading("/")
        |> String.replace(~r|/+|, "/")
    end
  end

  defp maybe_add_acl(opts) do
    case Keyword.get(opts, :visibility) do
      :public -> Keyword.put(opts, :acl, "public-read")
      :private -> Keyword.put(opts, :acl, "private")
      _ -> opts
    end
  end
end
