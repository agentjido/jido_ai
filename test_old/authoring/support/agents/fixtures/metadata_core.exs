defmodule JidoAITest.Authoring.Agents.Fixtures.MetadataCore do
  use Jido.Agent, name: "metadata_core", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})
    metadata %{"owner" => "support"}

    ai :assistant do
      model "openai:gpt-4o-mini"
      result into: :reply
    end
  end

  routes do
    route "case.ask", ai: :assistant
  end
end
