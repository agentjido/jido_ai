defmodule JidoAITest.Authoring.Agents.Fixtures.Structured do
  use Jido.AI.Agent, name: "authoring_ai_structured", metadata: %{"case" => "structured"}

  agent do
    schema Zoi.object(%{reply: Zoi.map() |> Zoi.default(%{}), case_id: Zoi.string() |> Zoi.default("case-17")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      result(Zoi.object(%{answer: Zoi.string()}), into: :reply)
    end
  end

  routes do
    route "case.assistant", ai: :assistant
  end
end
