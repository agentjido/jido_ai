defmodule JidoAI.Examples.StandaloneActions.Agent do
  use Jido.Agent, name: "standalone_actions"

  agent do
    schema Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)})
  end

  routes do
    signal_source "/examples/ai/14_resume/14_04"

    route "case.run" do
      action params, schema: Jido.AI.Reasoning.ReAct.Actions.Start.schema(), context: context do
        with {:ok, result} <- Jido.Exec.run(JidoAI.Examples.StandaloneActions.Flow, params, context) do
          {:ok, %{context.agent_state | result: Map.take(result, [:result, :usage, :termination_reason])}}
        end
      end

      define :run, args: [:query]
    end
  end
end
