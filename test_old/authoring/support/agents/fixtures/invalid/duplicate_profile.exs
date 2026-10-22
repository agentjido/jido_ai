defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.DuplicateProfile do
  use Jido.AI.Agent, name: "invalid_duplicate_profile"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"
      result into: :reply
    end

    ai :assistant do
      model "openai:gpt-4o-mini"
      result into: :reply
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
