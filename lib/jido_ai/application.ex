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
      # Start the ConversationManager for ReqLLM tool execution pipeline
      Jido.AI.ReqLlmBridge.ConversationManager,
      # Start the Model Registry Cache for performance optimization
      Jido.AI.Model.Registry.Cache
    ]

    opts = [strategy: :one_for_one, name: Jido.AI.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
