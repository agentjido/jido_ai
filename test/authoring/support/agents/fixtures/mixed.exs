defmodule JidoAITest.Authoring.Agents.Fixtures.Mixed do
  use Jido.AI.Agent, name: "authoring_mixed"

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             review: Zoi.string() |> Zoi.default(""),
             messages: Jido.AI.Thread.Projection.schema()
           })

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Turn instruction"

      controls do
        timeout 5_000
      end

      result into: :reply
    end

    ai :reviewer do
      model Jido.AI.Test.MockLLM.model("gpt-4o")
      instructions "Session instruction"

      controls do
        timeout 5_000
      end

      requests do
        mode :session
        streaming true
        steering true
      end

      memory do
        history(:messages)
      end

      result into: :review
    end
  end

  routes do
    route "case.assistant", ai: :assistant
    route "case.reviewer", ai: :reviewer
  end
end
