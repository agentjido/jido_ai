defmodule JidoAI.Examples.SkillAuthoring.Public do
  use Jido.AI.Agent, name: "automatic_skills"

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             messages: Jido.AI.Thread.Projection.schema()
           })

    ai :assistant do
      instructions("Base prompt")

      models do
        model(:answer, :example)
      end

      reasoning :react do
        model(:answer)
      end

      observability do
        store_content true
      end

      skills do
        skill(JidoAI.Examples.SkillAuthoring.Review)
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
