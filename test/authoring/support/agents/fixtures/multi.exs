defmodule JidoAITest.Authoring.Agents.Fixtures.Multi do
  use Jido.AI.Agent, name: "authoring_ai_multi", metadata: %{"case" => "multi"}

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-17"),
             review: Zoi.string() |> Zoi.default("")
           })

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      result into: :reply
    end

    ai :reviewer do
      model Jido.AI.Test.MockLLM.model("gpt-4o")
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      result into: :review
    end
  end

  routes do
    route "case.assistant", ai: :assistant
    route "case.reviewer", ai: :reviewer
  end
end
