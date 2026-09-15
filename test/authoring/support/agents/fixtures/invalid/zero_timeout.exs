defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.ZeroTimeout do
  use Jido.AI.Agent, name: "invalid_zero_timeout"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"

      controls do
        timeout 0
      end

      result into: :reply
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
