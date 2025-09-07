defmodule ReqLLM.Application do
  @moduledoc """
  The ReqLLM Application module.
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
