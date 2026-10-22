defmodule JidoAITest.Authoring.Agents.Fixtures.MetadataBlock do
  use Jido.AI.Agent, name: "invalid_metadata_block"

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
