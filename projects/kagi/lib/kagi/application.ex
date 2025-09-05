defmodule Kagi.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Kagi
    ]

    opts = [strategy: :one_for_one, name: Kagi.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
