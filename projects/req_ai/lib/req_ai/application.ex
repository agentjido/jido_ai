defmodule ReqAI.Application do
  @moduledoc """
  The ReqAI Application module.
  """

  use Application

  @impl true
  def start(_type, _args) do
    ReqAI.Provider.Registry.initialize()

    children = []

    opts = [strategy: :one_for_one, name: ReqAI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
