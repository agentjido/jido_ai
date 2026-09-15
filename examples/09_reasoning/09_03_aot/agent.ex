defmodule JidoAI.Examples.AoT.Agent do
  use Jido.AI.Agent, name: "aot_puzzle"

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :algorithm_of_thoughts do
        model(:answer)
        options(profile: :short, search_style: :dfs)
      end

      controls do
        output(JidoAI.Examples.AoT.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.aot.query", ai(:assistant)
  end
end
