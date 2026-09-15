defmodule JidoAITest.Authoring.Agents.Fixtures.Simple do
  use Jido.AI.Agent, name: "authoring_ai_simple", metadata: %{"case" => "simple"}

  agent do
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

    route "case.assistant", ai: :assistant do
      define :submit, args: [:query]
    end
  end
end
