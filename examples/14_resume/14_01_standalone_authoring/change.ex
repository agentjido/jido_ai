defmodule JidoAI.Examples.StandaloneAuthoring.Change do
  use Jido.Action,
    name: "change",
    description: "Change a case count",
    schema: Zoi.object(%{count: Zoi.integer()})

  def run(%{count: count}, context) do
    {:ok, %{count: count}, [Jido.AI.Effects.state(%{context.agent_state | count: count})]}
  end
end
