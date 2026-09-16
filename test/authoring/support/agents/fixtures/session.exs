defmodule JidoAITest.Authoring.Agents.Fixtures.Session do
  use Jido.AI.Agent, name: "authoring_ai_session", metadata: %{"case" => "session"}

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-17"),
             messages: Jido.AI.Thread.Projection.schema()
           })

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      memory do
        history(:messages)
      end

      result into: :reply
    end
  end

  routes do
    route "case.assistant", ai: :assistant
  end
end
