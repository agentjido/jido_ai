defmodule JidoAI.Examples.StandaloneAuthoring.Add do
  use Jido.Action,
    name: "add",
    description: "Add two case values",
    schema: Zoi.object(%{a: Zoi.integer(), b: Zoi.integer()})

  def run(%{a: a, b: b}, context) do
    if context[:observer], do: send(context.observer, {:standalone_add, self(), a, b})
    {:ok, %{sum: a + b}}
  end
end
