defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.MixedModels do
  use Jido.AI.Agent, name: "invalid_mixed_models"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"

      models do
        model :answer, "openai:gpt-4o"
      end

      result into: :reply
    end
  end
end
