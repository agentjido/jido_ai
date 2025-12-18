defmodule Jido.AI.Conversation.Supervisor do
  @moduledoc """
  Supervisor for conversation-related processes.

  Manages the ConversationManager GenServer lifecycle.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Jido.AI.Conversation.Manager, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
