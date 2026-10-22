defmodule JidoAITest.Authoring.Agents.Fixtures.HelperEdges do
  use Jido.AI.Agent, name: "authoring_helper_edges"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      result into: :reply
    end

    ai :unrouted do
      model Jido.AI.Test.MockLLM.model()
      result into: :reply
    end

    ai :session do
      model Jido.AI.Test.MockLLM.model()

      result into: :reply
    end
  end

  routes do
    route "case.first", ai: :assistant
    route "case.second", ai: :assistant
    route "case.session", ai: :session
  end
end
