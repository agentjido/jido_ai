defmodule JidoAI.Examples.Adaptive.Agent do
  use Jido.AI.Agent, name: "adaptive_reasoning"

  agent do
    schema Zoi.object(%{
             reply: Zoi.any() |> Zoi.default(nil),
             case_id: Zoi.string() |> Zoi.default("open")
           })

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :adaptive do
        model(:answer)
        options(method_options: %{tot: %{branching_factor: 2, max_depth: 1}})
      end

      tools do
        action JidoAI.Examples.Adaptive.Number, as: :tree_work
      end

      controls do
        max_iterations(20)
        max_model_calls(20)
        output(JidoAI.Examples.Adaptive.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      observability do
        store_content true
        stream_content true
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.adaptive.query", ai(:assistant)
    route "case.close", JidoAI.Examples.Support.CloseCase
  end
end
