defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.HistoryResult do
  use Jido.AI.Agent, name: "invalid_history_result"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"

      memory do
        history(:reply)
      end

      result into: :reply
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
