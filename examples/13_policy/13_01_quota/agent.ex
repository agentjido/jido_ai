defmodule JidoAI.Examples.Quota.Agent do
  use Jido.AI.Agent, name: "quota_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-13")
           })

    plugin Jido.AI.Plugins.Quota, config: [scope: "dsl", max_requests: 1]

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      controls do
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "quota.status", Jido.AI.Actions.Quota.RunCapability
    route "quota.reset", Jido.AI.Actions.Quota.RunCapability
    route "case.review", ai(:assistant)
  end
end
