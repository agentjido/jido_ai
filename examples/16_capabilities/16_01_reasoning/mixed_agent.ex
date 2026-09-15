defmodule JidoAI.Examples.ReasoningCapabilities.MixedAgent do
  use Jido.Agent, name: "native_and_callable_reasoning", extensions: [Jido.AI.DSL]

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
            result: %{into: :review}
          })
      ]

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning(:react, model: :answer)

      controls do
        max_iterations 2
        max_model_calls(2)
        timeout(5_000)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
    route "reasoning.cot.run", Jido.AI.Actions.Reasoning.RunCapability
  end
end
