defmodule Kodo.VFS.Router do
  @moduledoc """
  Fast path routing for VFS operations using ETS for O(1) mount lookups.

  This module separates routing logic from execution, allowing filesystem operations
  to be executed in the caller's process rather than being serialized through a GenServer.
  """

  alias Kodo.InstanceRegistry

  @type mount_entry :: {mount_path :: String.t(), filesystem :: term(), config :: term()}
  @type route_result ::
          {:ok, filesystem :: term(), config :: term(), relative_path :: String.t()}
          | {:error, :mount_not_found}

  @doc """
  Routes a path to the appropriate filesystem and returns the relative path.

  Returns `{:ok, filesystem, config, relative_path}` if a mount is found,
  or `{:error, :mount_not_found}` if no mount matches the path.
  """
  @spec route(instance :: term(), path :: String.t()) :: route_result()
  def route(instance, path) do
    normalized_path = normalize_path(path)

    case InstanceRegistry.lookup(instance, :vfs_mounts) do
      {:ok, mounts_table} ->
        find_best_mount(mounts_table, normalized_path)

      {:error, :not_found} ->
        {:error, :instance_not_found}

      {:error, _} ->
        {:error, :mount_not_found}
    end
  end

  @doc """
  Lists all mounted filesystems for an instance.
  """
  @spec list_mounts(instance :: term()) :: {:ok, [mount_entry()]} | {:error, term()}
  def list_mounts(instance) do
    case InstanceRegistry.lookup(instance, :vfs_mounts) do
      {:ok, mounts_table} ->
        mounts = :ets.tab2list(mounts_table)
        {:ok, mounts}

      error ->
        error
    end
  end

  @doc """
  Adds a mount to the routing table.
  """
  @spec add_mount(
          instance :: term(),
          mount_path :: String.t(),
          filesystem :: term(),
          config :: term()
        ) :: :ok | {:error, term()}
  def add_mount(instance, mount_path, filesystem, config) do
    normalized_mount = normalize_path(mount_path)

    case InstanceRegistry.lookup(instance, :vfs_mounts) do
      {:ok, mounts_table} ->
        :ets.insert(mounts_table, {normalized_mount, filesystem, config})
        :ok

      error ->
        error
    end
  end

  @doc """
  Removes a mount from the routing table.
  """
  @spec remove_mount(instance :: term(), mount_path :: String.t()) :: :ok | {:error, term()}
  def remove_mount(instance, mount_path) do
    normalized_mount = normalize_path(mount_path)

    case InstanceRegistry.lookup(instance, :vfs_mounts) do
      {:ok, mounts_table} ->
        case :ets.lookup(mounts_table, normalized_mount) do
          [] ->
            {:error, :not_mounted}

          _ ->
            :ets.delete(mounts_table, normalized_mount)
            :ok
        end

      error ->
        error
    end
  end

  @doc """
  Creates the ETS table for mounts and registers it with the instance.
  """
  @spec initialize_mounts_table(instance :: term()) :: :ok | {:error, term()}
  def initialize_mounts_table(instance) do
    table_name = :"vfs_mounts_#{instance}"
    mounts_table = :ets.new(table_name, [:set, :public, {:read_concurrency, true}])
    InstanceRegistry.register(instance, :vfs_mounts, mounts_table)
  end

  @doc """
  Cleans up the ETS table for an instance.
  """
  @spec cleanup_mounts_table(instance :: term()) :: :ok
  def cleanup_mounts_table(instance) do
    case InstanceRegistry.lookup(instance, :vfs_mounts) do
      {:ok, mounts_table} ->
        :ets.delete(mounts_table)
        InstanceRegistry.unregister(instance, :vfs_mounts)

      {:error, _} ->
        :ok
    end
  end

  # Private functions

  defp find_best_mount(mounts_table, path) do
    # Get all mounts and find the longest matching prefix
    :ets.tab2list(mounts_table)
    |> Enum.filter(fn {mount_path, _filesystem, _config} ->
      path_matches_mount?(path, mount_path)
    end)
    |> Enum.max_by(
      fn {mount_path, _filesystem, _config} ->
        String.length(mount_path)
      end,
      fn -> nil end
    )
    |> case do
      {mount_path, filesystem, config} ->
        relative_path = calculate_relative_path(path, mount_path)
        {:ok, filesystem, config, relative_path}

      nil ->
        {:error, :mount_not_found}
    end
  end

  defp path_matches_mount?(_path, mount_path) when mount_path == "/", do: true

  defp path_matches_mount?(path, mount_path) do
    String.starts_with?(path, mount_path) and
      (String.length(path) == String.length(mount_path) or
         String.at(path, String.length(mount_path)) == "/")
  end

  defp calculate_relative_path(path, "/") do
    case path do
      "/" -> "."
      "/" <> rest -> rest
      rest -> rest
    end
  end

  defp calculate_relative_path(path, mount_path) do
    case String.replace_prefix(path, mount_path, "") do
      "" -> "/"
      "/" <> rest -> rest
      rest -> rest
    end
  end

  defp normalize_path(path) do
    case path do
      "." ->
        "/"

      "./" ->
        "/"

      path ->
        path
        |> Path.expand("/")
        |> String.replace_trailing("/", "")
        |> case do
          "" -> "/"
          normalized -> normalized
        end
    end
  end
end
