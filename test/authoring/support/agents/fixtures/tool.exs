defmodule JidoAITest.Authoring.Agents.Fixtures.Tool do
  use Jido.AI.Agent, name: "authoring_ai_tool", metadata: %{"case" => "tool"}

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      tools do
        action JidoAITest.Authoring.Agents.Fixtures.Double, as: :double, description: "Double an integer"
      end

      result into: :reply
    end
  end

  routes do
    route "case.assistant", ai: :assistant
  end
end
