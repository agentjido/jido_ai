# First production AI syntax. The integration test loads this source explicitly.
defmodule JidoAI.Examples.DesiredAssistant do
  use Jido.Agent, name: "desired_ai_assistant", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.map() |> Zoi.default(%{}),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    ai :assistant do
      instructions("Give a short answer.")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        max_iterations 2
        max_model_calls(2)
        timeout(5_000)
      end

      result(Zoi.object(%{answer: Zoi.string()}), into: :reply, max_repairs: 0)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
