defmodule JidoAI.Examples.ReasoningTool.Agent do
  use Jido.AI.Agent, name: "reasoning_tool"

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("case-16")
           })

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action Jido.AI.Actions.Reasoning.RunStrategy,
          as: :reason,
          forward_context: [:jido_ai_callable_profile, :ai, :jido],
          timeout: 8_000
      end

      controls do
        timeout(10_000)
      end

      requests do
        mode(:session)
        streaming(false)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "case.review", ai(:assistant)
  end
end
