defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.MissingField do
  use Jido.AI.Agent, name: "invalid_missing_field"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"
      result into: :missing
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
