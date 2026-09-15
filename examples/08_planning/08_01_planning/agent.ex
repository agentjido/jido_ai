defmodule JidoAI.Examples.Planning.Agent do
  use Jido.Agent, name: "planning_and_reasoning"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             review: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("release-17")
           })

    plugin Jido.AI.Plugins.Planning, config: [into: :result, default_max_tokens: 512]

    plugin Jido.AI.Plugins.Reasoning.ChainOfThought,
      config: [
        profile:
          Jido.AI.Profile.new!(%{
            id: :assistant,
            model: JidoAI.Examples.MockLLM.model(),
            reasoning: :chain_of_thought,
            controls: %{
              timeout: 5_000,
              max_iterations: :method_default,
              max_model_calls: :method_default,
              max_tool_calls: :method_default
            },
            requests: %{mode: :session, streaming: true},
            result: %{into: :review}
          })
      ]
  end

  routes do
    route "planning.plan", Jido.AI.Actions.Planning.RunCapability
    route "planning.decompose", Jido.AI.Actions.Planning.RunCapability
    route "planning.prioritize", Jido.AI.Actions.Planning.RunCapability
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
    route "case.set", JidoAI.Examples.Support.SetCase
  end
end
