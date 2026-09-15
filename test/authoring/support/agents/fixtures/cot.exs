defmodule JidoAITest.Authoring.Agents.Fixtures.Cot do
  use Jido.AI.Agent, name: "authoring_ai_cot", metadata: %{"case" => "cot"}

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      reasoning :chain_of_thought
      result into: :reply
    end
  end

  routes do
    route "case.assistant", ai: :assistant
  end
end
