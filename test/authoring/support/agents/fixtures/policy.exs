defmodule JidoAITest.Authoring.Agents.Fixtures.Policy do
  use Jido.AI.Agent, name: "authoring_ai_policy", metadata: %{"case" => "policy"}

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default(""), case_id: Zoi.string() |> Zoi.default("case-17")})
    plugin Jido.AI.Plugins.Policy, config: [mode: :enforce]
    plugin Jido.AI.Plugins.ModelRouting, config: [routes: %{"case.assistant" => Jido.AI.Test.MockLLM.model("gpt-4o")}]

    ai :assistant do
      model Jido.AI.Test.MockLLM.model()
      instructions "Use the case facts."

      controls do
        timeout 5_000
      end

      result into: :reply
    end
  end

  routes do
    route "case.assistant", ai: :assistant
  end
end
