defmodule JidoAI.Examples.SkillAuthoring.Echo do
  use Jido.Action, name: "skill_echo", schema: Zoi.object(%{text: Zoi.string()})

  def run(%{text: text}, context) do
    send(context.observer, {:skill_echo, text})
    {:ok, %{text: text}}
  end
end

defmodule JidoAI.Examples.SkillAuthoring.Review do
  use Jido.AI.Skill,
    name: "review",
    description: "Review a document.",
    metadata: %{owner: :native_module},
    actions: [JidoAI.Examples.SkillAuthoring.Echo],
    body: "Module review instructions"
end

defmodule JidoAI.Examples.SkillAuthoring.Public do
  use Jido.AI.Agent, name: "automatic_skills"

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    ai :assistant do
      instructions("Base prompt")

      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
      end

      skills do
        skill(JidoAI.Examples.SkillAuthoring.Review)
      end

      requests do
        mode(:session)
      end

      memory do
        history(:messages)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end

defmodule JidoAI.Examples.SkillAuthoring.Trust do
  def allow(path, suffix), do: String.ends_with?(path, suffix)
end
