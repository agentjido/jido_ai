defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.MissingResult do
  use Jido.AI.Agent, name: "invalid_missing_result"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
