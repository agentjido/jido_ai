defmodule JidoAITest.Authoring.Agents.Fixtures.Invalid.ConflictingSkillPaths do
  use Jido.AI.Agent, name: "invalid_skill_paths"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      model "openai:gpt-4o-mini"

      skills do
        paths(["./not-read"])
        load_path "./also-not-read"
      end

      result into: :reply
    end
  end
end
