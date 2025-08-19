defmodule Jido.BehaviorTree.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Add any application-level supervisors here
      # For now, we don't need any persistent processes
    ]

    opts = [strategy: :one_for_one, name: Jido.BehaviorTree.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
