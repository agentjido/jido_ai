defmodule JidoAI.Examples.ReasoningCapabilities.Agent do
  use Jido.Agent, name: "reasoning_capabilities_dsl"

  agent do
    schema Zoi.object(%{
             result: Zoi.any() |> Zoi.default(nil),
             review: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-17")
           })

    plugin Jido.AI.Plugins.Reasoning.ChainOfThought,
      config: [
        profile:
          Jido.AI.Profile.new!(%{
            id: :assistant,
            model: :reasoning,
            reasoning: :chain_of_thought,
            controls: %{
              timeout: 5_000,
              max_iterations: :method_default,
              max_model_calls: :method_default,
              max_tool_calls: :method_default
            },
            requests: %{mode: :session, streaming: true},
            result: %{into: :result}
          })
      ]

    plugin Jido.AI.Plugins.Reasoning.ChainOfDraft,
      config: [
        profile:
          Jido.AI.Profile.new!(%{
            id: :assistant,
            model: :reasoning,
            reasoning: :chain_of_draft,
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
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
    route "reasoning.cod.run", Jido.AI.Actions.Reasoning.RunCapability
    route "case.set", JidoAI.Examples.Support.SetCase
  end
end
