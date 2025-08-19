defmodule Jido.Chat.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the registry for room processes
      {Registry, keys: :unique, name: Jido.Chat.Registry},

      # Start the default bus
      {Jido.Signal.Bus, name: Jido.Chat.Bus},

      # Start the room supervisor
      {Jido.Chat.Room.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: Jido.Chat.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
