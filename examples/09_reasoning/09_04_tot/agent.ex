defmodule JidoAI.Examples.ToT.Agent do
  use Jido.AI.Agent, name: "tree_search"

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :tree_of_thoughts do
        model(:answer)
        options(branching_factor: 2, max_depth: 1)
      end

      controls do
        output(JidoAI.Examples.ToT.Check)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.tot.query", ai(:assistant)
  end
end
