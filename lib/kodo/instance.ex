defmodule Kodo.Instance do
  @moduledoc """
  Represents a complete, isolated Kodo environment with its own VFS,
  command registry, job manager, and user sessions.

  Each Instance is a supervised process that manages its own set of
  components, allowing multiple independent Kodo environments to
  run simultaneously.

  ## Design

  The Instance acts as a supervisor for:
  - Session management (multiple concurrent shell sessions)
  - Command registry (available commands for this instance)
  - Job management (background/foreground process control)
  - Virtual file system (mounted filesystem adapters)

  All components are isolated per instance and accessed through a
  registry-based lookup system for O(1) access performance.
  """
  use Supervisor
  require Logger

  @doc """
  Starts a new Kodo instance with the given name.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    Supervisor.start_link(__MODULE__, name, name: via_name(name))
  end

  @doc """
  Gets a child process from the instance by its module name.

  Returns `{:ok, pid}` if found, `{:error, :not_found}` if not found.
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

  The session supervisor manages multiple concurrent shell sessions
  within this instance, providing isolation and fault tolerance.
  """
  @spec sessions(atom()) :: {:ok, pid()} | {:error, :not_found}
  def sessions(instance_name) do
    child(instance_name, :session_supervisor)
  end

  @doc """
  Gets the command registry for this instance.

  The command registry stores all available commands for this instance,
  including built-in commands and any custom commands that have been registered.
  """
  @spec commands(atom()) :: {:ok, pid()} | {:error, :not_found}
  def commands(instance_name) do
    child(instance_name, :command_registry)
  end

  @doc """
  Gets the job manager for this instance.

  The job manager handles background and foreground process execution,
  job control operations, and process lifecycle management.
  """
  @spec jobs(atom()) :: {:ok, pid()} | {:error, :not_found}
  def jobs(instance_name) do
    child(instance_name, :job_manager)
  end



  # Supervisor callbacks

  @impl true
  def init(instance_name) do
    Logger.debug("Starting Kodo instance: #{instance_name}")

    session_registry_atom = String.to_atom("Kodo.SessionRegistry.#{instance_name}")

    children = [
      # Session registry for this instance
      {Registry, keys: :unique, name: session_registry_atom},

      # Core components (placeholder supervisors for now)
      %{
        id: :session_supervisor,
        start: {__MODULE__, :start_placeholder, [:session_supervisor, instance_name]}
      },
      %{
        id: :command_registry,
        start: {__MODULE__, :start_placeholder, [:command_registry, instance_name]}
      },
      %{
        id: :job_manager,
        start: {__MODULE__, :start_placeholder, [:job_manager, instance_name]}
      },
      # VFS filesystem supervisor
      %{
        id: :vfs_supervisor,
        start:
          {DynamicSupervisor, :start_link,
           [
             [
               strategy: :one_for_one,
               name: {:via, Registry, {Kodo.InstanceRegistry, {:vfs_supervisor, instance_name}}}
             ]
           ]},
        type: :supervisor
      },
      # VFS initialization process
      %{
        id: :vfs_init,
        start: {__MODULE__, :start_vfs_init, [instance_name]},
        restart: :transient
      }
    ]

    # Initialize VFS mount table synchronously  
    :ok = Kodo.VFS.Router.initialize_mounts_table(instance_name)

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Placeholder implementations for components not yet built
  @doc false
  def start_placeholder(component_type, instance_name) do
    GenServer.start_link(
      __MODULE__.Placeholder,
      {component_type, instance_name},
      name: component_name(component_type, instance_name)
    )
  end

  # VFS initialization
  @doc false
  def start_vfs_init(instance_name) do
    GenServer.start_link(__MODULE__.VFSInit, instance_name)
  end

  # Private functions

  defp via_name(instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {:instance, instance_name}}}
  end

  defp component_name(component_type, instance_name) do
    {:via, Registry, {Kodo.InstanceRegistry, {component_type, instance_name}}}
  end

  defp get_child_pid(instance_name, component_type) do
    key = {component_type, instance_name}

    case Registry.lookup(Kodo.InstanceRegistry, key) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end
end

defmodule Kodo.Instance.Placeholder do
  @moduledoc false
  # Placeholder GenServer for components not yet implemented
  use GenServer
  require Logger

  def init({component_type, instance_name}) do
    Logger.debug("Started placeholder #{component_type} for instance #{instance_name}")
    {:ok, %{type: component_type, instance: instance_name}}
  end

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}
  def handle_cast(_msg, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}
end

defmodule Kodo.Instance.VFSInit do
  @moduledoc false
  # GenServer for VFS initialization that mounts root filesystem
  use GenServer
  require Logger

  def init(instance_name) do
    # Mount root filesystem with InMemory adapter
    case Kodo.VFS.mount(instance_name, "/", Depot.Adapter.InMemory,
           name: :"root_fs_#{instance_name}"
         ) do
      :ok ->
        Logger.debug("VFS initialized for instance #{instance_name}")

      {:error, reason} ->
        Logger.error(
          "Failed to initialize VFS for instance #{instance_name}: #{inspect(reason)}"
        )
    end

    {:ok, %{instance: instance_name}}
  end

  def handle_call(_msg, _from, state), do: {:reply, :ok, state}
  def handle_cast(_msg, state), do: {:noreply, state}
  def handle_info(_msg, state), do: {:noreply, state}
end


