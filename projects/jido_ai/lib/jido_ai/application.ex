defmodule Jido.AI.Application do
  @moduledoc """
  The Jido.AI Application module.
  """

  use Application

  @impl true
  def start(_type, _args) do
    Jido.AI.Provider.Registry.initialize()

    children = []

    opts = [strategy: :one_for_one, name: Jido.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
