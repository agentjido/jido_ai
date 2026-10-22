defmodule JidoAI.Examples.SkillAuthoring.Echo do
  use Jido.Action, name: "skill_echo", schema: Zoi.object(%{text: Zoi.string()})

  def run(%{text: text}, _context) do
    {:ok, %{text: text}}
  end
end
