defmodule Jido.Dialogue.Supervisor do
  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      {Jido.Dialogue.DialogueManager, []},
      {Jido.Dialogue.ScriptManager, []},
      {Jido.Dialogue.CharacterRegistry, []},
      {Jido.Dialogue.CharacterSupervisor, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
