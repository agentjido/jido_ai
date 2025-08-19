defmodule Kodo.Instance do
  @moduledoc """
  Represents a complete, isolated Kodo environment with its own VFS,
  command registry, job manager, and user sessions.

  Each Instance is a supervised process that manages its own set of
  components, allowing multiple independent Kodo environments to
  run simultaneously.
  """
  use Supervisor
  require Logger

  @doc """
  Starts a new Kodo instance.
  """
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, name, name: via_name(name))
  end

  @doc """
  Gets a child process from the instance by its module name.
  """
  @spec child(atom(), module()) :: {:ok, pid()} | {:error, :not_found}
  def child(instance_name, module) do
    case get_child_pid(instance_name, module) do
      pid when is_pid(pid) -> {:ok, pid}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Gets the session supervisor for this instance.
  """
  @spec sessions(atom()) :: {:ok, pid()} | {:error, :not_found}
  def sessions(instance_name) do
    child(instance_name, Kodo.Core.Sessions.SessionSupervisor)
  end

  @doc """
  Gets the command registry for this instance.
  """
  @spec commands(atom()) :: {:ok, pid()} | {:error, :not_found}
  def commands(instance_name) do
    child(instance_name, Kodo.Core.Commands.CommandRegistry)
  end

  @doc """
  Gets the job manager for this instance.
  """
  @spec jobs(atom()) :: {:ok, pid()} | {:error, :not_found}
  def jobs(instance_name) do
    child(instance_name, Kodo.Core.Jobs.JobManager)
  end

  @doc """
  Gets the VFS manager for this instance.
  """
  @spec vfs(atom()) :: {:ok, pid()} | {:error, :not_found}
  def vfs(instance_name) do
    child(instance_name, Kodo.VFS.Manager)
  end

  @doc """
  Starts a new session within this instance.
  """
  @spec new_session(atom()) :: {:ok, String.t(), pid()} | {:error, term()}
  def new_session(instance_name) do
    case sessions(instance_name) do
      {:ok, supervisor_pid} ->
        Kodo.Core.Sessions.SessionSupervisor.new(supervisor_pid, instance_name)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Registers a command in this instance's command registry.
  """
  @spec add_command(atom(), module()) :: :ok | {:error, term()}
  def add_command(instance_name, command_module) do
    case commands(instance_name) do
      {:ok, registry_pid} ->
        Kodo.Core.Commands.CommandRegistry.register_command(registry_pid, command_module)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Starts a job in this instance's job manager.
  """
  @spec new_job(atom(), any(), String.t(), String.t(), boolean()) ::
          {:ok, pos_integer()} | {:error, term()}
  def new_job(instance_name, execution_plan, command_string, session_id, background? \\ false) do
    case jobs(instance_name) do
      {:ok, job_manager_pid} ->
        Kodo.Core.Jobs.JobManager.start_job(
          job_manager_pid,
          execution_plan,
          command_string,
          session_id,
          background?
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Supervisor callbacks

  @impl true
  def init(instance_name) do
    Logger.debug("Starting Kodo instance", instance: instance_name)

    session_registry_atom = String.to_atom("Kodo.SessionRegistry.#{instance_name}")

    children = [
      # Session registry for this instance (using atom name, not via)
      {Registry, keys: :unique, name: session_registry_atom},

      # Session supervisor for managing shell sessions
      {Kodo.Core.Sessions.SessionSupervisor,
       [
         name: session_supervisor_name(instance_name),
         instance: instance_name
       ]},

      # Command registry for builtin commands
      {Kodo.Core.Commands.CommandRegistry,
       [
         name: command_registry_name(instance_name),
         instance: instance_name
       ]},

      # Job manager for handling background jobs
      {Kodo.Core.Jobs.JobManager,
       [
         name: job_manager_name(instance_name),
         instance: instance_name
       ]},

      # VFS supervisor for virtual filesystem
      {Kodo.VFS.Supervisor,
       [
         name: vfs_supervisor_name(instance_name),
         instance: instance_name
       ]},

      # Task to register default commands for this instance
      {Task, fn -> register_default_commands(instance_name) end}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Private functions

  defp via_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:instance, instance_name}}}
  end

  defp session_supervisor_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:session_supervisor, instance_name}}}
  end

  defp command_registry_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:command_registry, instance_name}}}
  end

  defp job_manager_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:job_manager, instance_name}}}
  end

  defp vfs_supervisor_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:vfs_supervisor, instance_name}}}
  end

  defp get_child_pid(instance_name, module) do
    key =
      case module do
        Kodo.Core.Sessions.SessionSupervisor -> {:session_supervisor, instance_name}
        Kodo.Core.Commands.CommandRegistry -> {:command_registry, instance_name}
        Kodo.Core.Jobs.JobManager -> {:job_manager, instance_name}
        Kodo.VFS.Supervisor -> {:vfs_supervisor, instance_name}
        Kodo.VFS.Manager -> {:vfs_manager, instance_name}
        _ -> nil
      end

    case key do
      nil ->
        nil

      key ->
        case Registry.lookup(Kodo.InstanceRegistry, key) do
          [{pid, _}] -> pid
          [] -> nil
        end
    end
  end

  defp register_default_commands(instance_name) do
    [
      Kodo.Commands.Help,
      Kodo.Commands.Cd,
      Kodo.Commands.Pwd,
      Kodo.Commands.Ls,
      Kodo.Commands.Env,
      Kodo.Commands.Sleep
      # DISABLED: Job control commands (require JobManager)
      # Kodo.Commands.Jobs,
      # Kodo.Commands.Fg,
      # Kodo.Commands.Bg,
      # Kodo.Commands.Kill
    ]
    |> Enum.each(fn command_module ->
      case add_command(instance_name, command_module) do
        :ok ->
          :ok

        {:error, reason} ->
          Logger.warning("Failed to register default command",
            instance: instance_name,
            command: command_module,
            reason: inspect(reason)
          )
      end
    end)
  end
end
