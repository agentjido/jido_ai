defmodule JidoAITest.Authoring.Agents.Fixtures.Inline do
  use Jido.AI.Agent, name: "authoring_inline"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()

      instructions %{query: query}, context: context do
        {:ok, %{instructions: "Tenant #{context.tenant}: #{query}"}}
      end

      tools do
        action :echo, %{value: value},
          description: "Echo one value",
          schema: Zoi.object(%{value: Zoi.string()}),
          context: _context do
          {:ok, %{value: value}}
        end
      end

      controls do
        timeout 5_000
      end

      result into: :reply
    end
  end

  routes do
    route "case.inline", ai: :assistant
  end
end
