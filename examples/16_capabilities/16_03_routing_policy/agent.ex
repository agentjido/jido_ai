defmodule JidoAI.Examples.RoutingPolicy.Agent do
  use Jido.Agent, name: "routing_policy_dsl", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             observed: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.ModelRouting, config: [routes: %{"case.review" => :capable}]
    plugin Jido.AI.Plugins.Policy

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
    route "case.review", ai(:assistant)
    route "case.note", JidoAI.Examples.RoutingPolicy.Capture
  end
end
