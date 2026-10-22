defmodule JidoAITest.Authoring.Agents.Fixtures.Simple do
  use Jido.AI.Agent, name: "authoring_ai_simple"

  agent do
    metadata %{"case" => "simple"}
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      result into: :reply
    end
  end

  routes do
    signal_source "/authoring/ai"

    route "case.assistant", ai: :assistant, as: :submit
  end
end
