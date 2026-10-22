defmodule JidoAITest.Authoring.Agents.Fixtures.Double do
  use Jido.Action,
    name: "double",
    description: "Double an integer",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, context) do
    if context[:observer], do: send(context.observer, {:authoring_tool, value})
    {:ok, %{value: value * 2}}
  end
end
