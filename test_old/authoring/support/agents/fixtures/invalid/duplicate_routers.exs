defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.DuplicateRouters do
  use Jido.AI.Agent, name: "invalid_duplicate_routers"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model :answer, "openai:gpt-4o-mini"
        router String, fallback: :answer
        router String, fallback: :answer
      end

      result into: :reply
    end
  end
end
