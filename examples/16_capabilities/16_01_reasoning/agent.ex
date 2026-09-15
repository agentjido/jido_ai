defmodule JidoAI.Examples.ReasoningCapabilities.Agent do
  use Jido.Agent, name: "reasoning_capabilities_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             review: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.Reasoning.ChainOfThought, config: [into: :result, timeout: 5_000]
    plugin Jido.AI.Plugins.Reasoning.ChainOfDraft, config: [into: :review, timeout: 5_000]
  end

  routes do
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
    route "reasoning.cod.run", Jido.AI.Actions.Reasoning.RunCapability
    route "case.set", JidoAI.Examples.Support.SetCase
  end
end
