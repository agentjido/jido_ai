defmodule ReqLLM.Application do
  @moduledoc """
  Application module for ReqLLM.

  Providers register themselves automatically via @on_load when their modules
  are loaded by the VM. No manual bootstrapping is required.
  """

  use Application

  @impl true
  def start(_type, _args) do
    ReqLLM.Provider.Registry.initialize()

    children = []
    opts = [strategy: :one_for_one, name: ReqLLM.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
