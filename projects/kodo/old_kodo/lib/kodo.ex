defmodule Kodo do
  @moduledoc """
  Main API for interacting with Kodo instances.

  Kodo is designed around the concept of instances - isolated environments
  that each contain their own VFS, command registry, job manager, and sessions.

  ## Basic Usage

      # Start a new instance
      {:ok, _pid} = Kodo.start(:my_project)
      
      # Start a session in that instance
      {:ok, session_id, session_pid} = Kodo.session(:my_project)
      
      # Evaluate code in the session
      {:ok, result} = Kodo.eval(:my_project, session_id, "1 + 1")
      
      # List all instances
      instances = Kodo.list()
      
  ## Virtual File System (VFS)

      # Mount filesystems at different paths
      :ok = Kodo.mount(:my_project, "/data", Depot.Adapter.InMemory, name: :DataFS)
      :ok = Kodo.mount(:my_project, "/local", Depot.Adapter.Local, prefix: "/tmp/project")
      
      # Work with files across mounted filesystems
      :ok = Kodo.write(:my_project, "/data/config.json", ~s({"env": "dev"}))
      :ok = Kodo.write(:my_project, "/local/readme.txt", "Project README")
      
      # List and manage mounts
      {root_fs, mounts} = Kodo.mounts(:my_project)
      :ok = Kodo.unmount(:my_project, "/data")
  """

  @doc """
  Starts a new Kodo instance.
  """
  @spec start(atom()) :: {:ok, pid()} | {:error, term()}
  def start(name) when is_atom(name) do
    Kodo.InstanceManager.start(name)
  end

  @doc """
  Stops an existing Kodo instance.
  """
  @spec stop(atom()) :: :ok | {:error, :not_found}
  def stop(name) when is_atom(name) do
    Kodo.InstanceManager.stop(name)
  end

  @doc """
  Lists all active instances.
  """
  @spec list() :: [atom()]
  def list do
    Kodo.InstanceManager.list()
  end

  @doc """
  Checks if an instance exists.
  """
  @spec exists?(atom()) :: boolean()
  def exists?(name) when is_atom(name) do
    Kodo.InstanceManager.exists?(name)
  end

  @doc """
  Starts a new session in the given instance.
  """
  @spec session(atom()) :: {:ok, String.t(), pid()} | {:error, term()}
  def session(instance_name) when is_atom(instance_name) do
    Kodo.Instance.new_session(instance_name)
  end

  @doc """
  Evaluates an expression in a session within an instance.
  """
  @spec eval(atom(), String.t(), String.t()) :: {:ok, term()} | {:error, term()}
  def eval(instance_name, session_id, expression) when is_atom(instance_name) do
    case get_session_pid(instance_name, session_id) do
      {:ok, session_pid} ->
        Kodo.Core.Sessions.Session.eval(session_pid, expression)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the command registry for an instance.
  """
  @spec commands(atom()) :: {:ok, pid()} | {:error, :not_found}
  def commands(instance_name) when is_atom(instance_name) do
    Kodo.Instance.commands(instance_name)
  end

  @doc """
  Gets the job manager for an instance.
  """
  @spec jobs(atom()) :: {:ok, pid()} | {:error, :not_found}
  def jobs(instance_name) when is_atom(instance_name) do
    Kodo.Instance.jobs(instance_name)
  end

  @doc """
  Gets the VFS manager for an instance.
  """
  @spec vfs(atom()) :: {:ok, pid()} | {:error, :not_found}
  def vfs(instance_name) when is_atom(instance_name) do
    Kodo.Instance.vfs(instance_name)
  end

  @doc """
  Registers a command in an instance's command registry.
  """
  @spec add_command(atom(), module()) :: :ok | {:error, term()}
  def add_command(instance_name, command_module) when is_atom(instance_name) do
    Kodo.Instance.add_command(instance_name, command_module)
  end

  @doc """
  Starts a job in an instance's job manager.
  """
  @spec job(atom(), any(), String.t(), String.t(), boolean()) ::
          {:ok, pos_integer()} | {:error, term()}
  def job(instance_name, execution_plan, command_string, session_id, background? \\ false)
      when is_atom(instance_name) do
    Kodo.Instance.new_job(instance_name, execution_plan, command_string, session_id, background?)
  end

  @doc """
  Lists jobs for a specific instance, optionally filtered by session.
  """
  @spec list_jobs(atom(), String.t() | nil) :: {:ok, [term()]} | {:error, term()}
  def list_jobs(instance_name, session_id \\ nil) when is_atom(instance_name) do
    case jobs(instance_name) do
      {:ok, job_manager_pid} ->
        jobs = Kodo.Core.Jobs.JobManager.list_jobs(job_manager_pid, session_id)
        {:ok, jobs}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # VFS Operations - using streamlined VFS API

  @doc "Mount a filesystem in an instance's VFS"
  @spec mount(atom(), String.t(), module(), keyword()) :: :ok | {:error, term()}
  def mount(instance_name, mount_point, adapter, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.mount(instance_name, mount_point, adapter, opts)
  end

  @doc "Unmount a filesystem from an instance's VFS"
  @spec unmount(atom(), String.t()) :: :ok | {:error, term()}
  def unmount(instance_name, mount_point) when is_atom(instance_name) do
    Kodo.VFS.unmount(instance_name, mount_point)
  end

  @doc "List all mounted filesystems in an instance's VFS"
  @spec mounts(atom()) :: {any(), map()}
  def mounts(instance_name) when is_atom(instance_name) do
    Kodo.VFS.mounts(instance_name)
  end

  @doc "Read a file from an instance's VFS"
  @spec read(atom(), String.t(), keyword()) :: {:ok, binary()} | {:error, term()}
  def read(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.read(instance_name, path, opts)
  end

  @doc "Write a file to an instance's VFS"
  @spec write(atom(), String.t(), binary(), keyword()) :: :ok | {:error, term()}
  def write(instance_name, path, content, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.write(instance_name, path, content, opts)
  end

  @doc "Delete a file from an instance's VFS"
  @spec delete(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def delete(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.delete(instance_name, path, opts)
  end

  @doc "List directory contents in an instance's VFS"
  @spec ls(atom(), String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def ls(instance_name, path \\ ".", opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.ls(instance_name, path, opts)
  end

  @doc "Check if file exists in an instance's VFS"
  @spec exists?(atom(), String.t(), keyword()) :: boolean()
  def exists?(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.exists?(instance_name, path, opts)
  end

  @doc "Create a directory in an instance's VFS"
  @spec mkdir(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def mkdir(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.mkdir(instance_name, path, opts)
  end

  @doc "Remove a file (alias for delete)"
  @spec rm(atom(), String.t(), keyword()) :: :ok | {:error, term()}
  def rm(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.delete(instance_name, path, opts)
  end

  # Revision Operations - for version-controlled filesystems

  @doc "Commit changes to a mounted filesystem"
  @spec commit(atom(), String.t(), String.t() | nil, keyword()) :: :ok | {:error, term()}
  def commit(instance_name, mount_point, message \\ nil, opts \\ [])
      when is_atom(instance_name) do
    Kodo.VFS.commit(instance_name, mount_point, message, opts)
  end

  @doc "List revisions/commits for a path"
  @spec revisions(atom(), String.t(), keyword()) :: {:ok, [any()]} | {:error, term()}
  def revisions(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.revisions(instance_name, path, opts)
  end

  @doc "Read a file as it existed at a specific revision"
  @spec read_revision(atom(), String.t(), String.t(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def read_revision(instance_name, path, sha, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.read_revision(instance_name, path, sha, opts)
  end

  @doc "Rollback a mounted filesystem to a previous revision"
  @spec rollback(atom(), String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def rollback(instance_name, mount_point, sha, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.rollback(instance_name, mount_point, sha, opts)
  end

  # Advanced Filesystem Operations

  @doc "Get file/directory metadata (size, mtime, visibility)"
  @spec stat(atom(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def stat(instance_name, path, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.stat(instance_name, path, opts)
  end

  @doc "Check read/write permissions for a path"
  @spec access(atom(), String.t(), atom(), keyword()) :: :ok | {:error, term()}
  def access(instance_name, path, mode, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.access(instance_name, path, mode, opts)
  end

  @doc "Append content to a file"
  @spec append(atom(), String.t(), iodata(), keyword()) :: :ok | {:error, term()}
  def append(instance_name, path, content, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.append(instance_name, path, content, opts)
  end

  @doc "Resize a file to a specific byte count"
  @spec truncate(atom(), String.t(), non_neg_integer(), keyword()) :: :ok | {:error, term()}
  def truncate(instance_name, path, size, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.truncate(instance_name, path, size, opts)
  end

  @doc "Update file modification time"
  @spec utime(atom(), String.t(), DateTime.t() | non_neg_integer(), keyword()) ::
          :ok | {:error, term()}
  def utime(instance_name, path, time, opts \\ []) when is_atom(instance_name) do
    Kodo.VFS.utime(instance_name, path, time, opts)
  end

  # Private helper functions

  defp get_session_pid(instance_name, session_id) do
    session_registry_atom = String.to_atom("Kodo.SessionRegistry.#{instance_name}")

    try do
      case Registry.lookup(session_registry_atom, session_id) do
        [{pid, _}] -> {:ok, pid}
        [] -> {:error, :session_not_found}
      end
    rescue
      ArgumentError ->
        {:error, :instance_not_found}
    end
  end
end
