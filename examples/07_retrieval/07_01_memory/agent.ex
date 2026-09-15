defmodule JidoAI.Examples.Retrieval.Agent do
  use Jido.AI.Agent, name: "memory_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-7")
           })

    plugin Jido.AI.Plugins.Retrieval, config: [namespace: "weather"]

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      tools do
        action Jido.AI.Actions.Retrieval.RecallMemory,
          as: :recall_memory,
          forward_context: [:state, :retrieval_store]
      end

      controls do
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "retrieval.upsert", Jido.AI.Actions.Retrieval.RunCapability
    route "retrieval.recall", Jido.AI.Actions.Retrieval.RunCapability
    route "retrieval.clear", Jido.AI.Actions.Retrieval.RunCapability
    route "case.review", ai(:assistant)
  end
end
