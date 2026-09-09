defmodule JidoAI.Examples.StandaloneActions.Flow do
  use Jido.Flow, name: "standalone_action_example"

  flow do
    step "start", action: Jido.AI.Reasoning.ReAct.Actions.Start, params: input()

    step "collect",
      action: Jido.AI.Reasoning.ReAct.Actions.Collect,
      params: %{events: result("start", :events)}

    output result("collect")
  end
end

defmodule JidoAI.Examples.StandaloneActions.Run do
  use Jido.Action, name: "standalone_action_agent_example"

  def run(params, context) do
    with {:ok, result} <- Jido.Exec.run(JidoAI.Examples.StandaloneActions.Flow, params, context) do
      {:ok, %{context.agent_state | result: Map.take(result, [:result, :usage, :termination_reason])}}
    end
  end
end

defmodule JidoAI.Examples.StandaloneActions.Agent do
  use Jido.Agent, name: "standalone_actions"

  agent do
    schema Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)})
  end

  routes do
    route "case.run", JidoAI.Examples.StandaloneActions.Run
  end
end
