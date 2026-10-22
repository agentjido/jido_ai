defmodule JidoAI.Examples.GoT.Agent do
  use Jido.AI.Agent, name: "graph_search"

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :graph_of_thoughts do
        model(:answer)
      end

      controls do
        output(JidoAI.Examples.GoT.Check)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.got.query", ai(:assistant)
  end
end
