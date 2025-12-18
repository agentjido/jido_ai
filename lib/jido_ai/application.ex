defmodule Jido.AI.Application do
  @moduledoc """
  The Jido.AI Application module.

  Manages the application lifecycle and starts the supervision tree.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Start the Keyring GenServer
      Jido.AI.Keyring,
      # Start the Conversation Supervisor
      Jido.AI.Conversation.Supervisor
    ]

    opts = [strategy: :one_for_one, name: Jido.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
