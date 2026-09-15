defmodule JidoAITest.Authoring.Agents.Fixtures.Session do
  use Jido.AI.Agent, name: "authoring_ai_session", metadata: %{"case" => "session"}

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             case_id: Zoi.string() |> Zoi.default("case-17"),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      requests do
        mode :session
        streaming true
        max_requests 3
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
