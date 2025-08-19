defmodule Depot.Adapter do
  @moduledoc """
  Behaviour for how `Depot` adapters work.
  """
  @type path :: Path.t()
  @type write_opts :: keyword
  @type stream_opts :: keyword
  @type directory_delete_opts :: keyword
  @type config :: struct

  @callback starts_processes() :: boolean
  @callback configure(keyword) :: {module(), config}
  @callback write(config, path, contents :: iodata(), write_opts) :: :ok | {:error, term}
  @callback write_stream(config, path, stream_opts) :: {:ok, Collectable.t()} | {:error, term}
  @callback read(config, path) :: {:ok, binary} | {:error, term}
  @callback read_stream(config, path, stream_opts) :: {:ok, Enumerable.t()} | {:error, term}
  @callback delete(config, path) :: :ok | {:error, term}
  @callback move(config, source :: path, destination :: path, write_opts) :: :ok | {:error, term}
  @callback copy(config, source :: path, destination :: path, write_opts) :: :ok | {:error, term}
  @callback copy(
              source_config :: config,
              source :: path,
              destination_config :: config,
              destination :: path,
              write_opts
            ) :: :ok | {:error, term}
  @callback file_exists(config, path) :: {:ok, :exists | :missing} | {:error, term}
  @callback list_contents(config, path) ::
              {:ok, [%Depot.Stat.Dir{} | %Depot.Stat.File{}]} | {:error, term}
  @callback create_directory(config, path, write_opts) :: :ok | {:error, term}
  @callback delete_directory(config, path, directory_delete_opts) :: :ok | {:error, term}
  @callback clear(config) :: :ok | {:error, term}
  @callback set_visibility(config, path, Depot.Visibility.t()) :: :ok | {:error, term}
  @callback visibility(config, path) :: {:ok, Depot.Visibility.t()} | {:error, term}

  # Extended filesystem operations (optional - adapters can choose to implement these)
  @optional_callbacks stat: 2,
                      access: 3,
                      append: 4,
                      truncate: 3,
                      utime: 3

  @callback stat(config, path) ::
              {:ok, %Depot.Stat.File{} | %Depot.Stat.Dir{}} | {:error, term}
  @callback access(config, path, modes :: [:read | :write]) :: :ok | {:error, term}
  @callback append(config, path, contents :: iodata(), write_opts) :: :ok | {:error, term}
  @callback truncate(config, path, new_size :: non_neg_integer()) :: :ok | {:error, term}
  @callback utime(config, path, mtime :: DateTime.t()) :: :ok | {:error, term}

  # Versioning callbacks (optional - adapters can choose to implement these)
  @optional_callbacks write_version: 4,
                      read_version: 3,
                      list_versions: 2,
                      delete_version: 3,
                      get_latest_version: 2,
                      restore_version: 3

  @callback write_version(config, path, contents :: iodata(), write_opts) ::
              {:ok, version_id :: binary} | {:error, term}
  @callback read_version(config, path, version_id :: binary) :: {:ok, binary} | {:error, term}
  @callback list_versions(config, path) ::
              {:ok, [%{version_id: binary, timestamp: integer}]} | {:error, term}
  @callback delete_version(config, path, version_id :: binary) :: :ok | {:error, term}
  @callback get_latest_version(config, path) :: {:ok, version_id :: binary} | {:error, term}
  @callback restore_version(config, path, version_id :: binary) :: :ok | {:error, term}
end
