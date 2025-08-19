defmodule Kodo.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    Kodo.Telemetry.attach_default_handlers()

    children = [
      # Global registry for instance management
      {Registry, keys: :unique, name: Kodo.InstanceRegistry},

      # Instance manager to handle multiple Kodo environments
      Kodo.InstanceManager
    ]

    opts = [strategy: :one_for_one, name: Kodo.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
