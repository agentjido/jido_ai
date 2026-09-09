defmodule JidoAI.Examples.CallableReasoning.Run do
  use Jido.Action, name: "example_callable_reasoning"

  def run(params, context) do
    with {:ok, result} <- Jido.Exec.run(Jido.AI.Actions.Reasoning.RunStrategy, params, context) do
      {:ok, %{context.agent_state | result: result, calls: context.agent_state.calls + 1}}
    end
  end
end

defmodule JidoAI.Examples.CallableReasoning.Agent do
  use Jido.Agent, name: "callable_reasoning"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             calls: Zoi.integer() |> Zoi.default(0),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })
  end

  routes do
    route "reasoning.run", JidoAI.Examples.CallableReasoning.Run
  end
end
