defmodule JidoAI.Examples.SkillRuntime.Agent do
  @moduledoc "The AI DSL binds skill Actions and saved history."
  use Jido.AI.Agent, name: "skill_runtime"

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             messages: Jido.AI.Thread.Projection.schema()
           })

    ai :assistant do
      instructions("Use the available skills.")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      observability do
        store_content true
      end

      tools do
        action Jido.AI.Actions.Skill.LoadSkill,
          as: :load_skill,
          forward_context: [
            :jido_ai_skill_session,
            :__jido_ai_skills__,
            :__jido_ai_skill_resource_provider__,
            :__jido_ai_skill_resource_policy__
          ]

        action Jido.AI.Actions.Skill.LoadResource,
          as: :load_skill_resource,
          forward_context: [
            :jido_ai_skill_session,
            :__jido_ai_skills__,
            :__jido_ai_skill_resource_provider__,
            :__jido_ai_skill_resource_policy__
          ]
      end

      memory do
        history(:messages)
      end

      requests do
        mode(:session)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
