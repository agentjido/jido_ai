defmodule JidoAI.Examples.StructuredOutput.Agent do
  @moduledoc "A typed answer permits one repair before the request fails."
  use Jido.AI.Agent, name: "v3_example_object_agent"

  agent do
    schema Zoi.object(%{
             answer: Zoi.map() |> Zoi.default(%{}),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    ai :assistant do
      model "openai:gpt-4o-mini"
      instructions "Return a short, nonempty answer."

      controls do
        timeout 5_000
        max_model_calls 2
      end

      result(Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}),
        into: :answer,
        max_repairs: 1
      )
    end
  end

  routes do
    signal_source "/examples/ai/01_authoring/01_03"

    route "examples.ai.01_03.answer", ai: :assistant do
      define :answer, args: [:query]
    end
  end
end
