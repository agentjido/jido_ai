defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.DuplicateModel do
  use Jido.AI.Agent, name: "invalid_duplicate_model"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model :answer, "openai:gpt-4o-mini"
        model :answer, "openai:gpt-4o"
      end

      result into: :reply
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
