defmodule Kodo.VFS.Supervisor do
  @moduledoc """
  Supervisor for the Virtual Filesystem system. Manages the VFS Manager and mounted filesystems.
  """
  # Changed from DynamicSupervisor since Depot manages its own processes
  use Supervisor

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    instance = Keyword.get(opts, :instance)
    Supervisor.start_link(__MODULE__, instance, name: name)
  end

  @impl true
  def init(instance) do
    vfs_manager_name = {:via, Registry, {Kodo.InstanceRegistry, {:vfs_manager, instance}}}

    children = [
      {Kodo.VFS.Manager, [instance: instance, name: vfs_manager_name]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
