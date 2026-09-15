defmodule JidoAI.Examples.TRM.Agent do
  use Jido.AI.Agent, name: "recursive_reasoning"

  agent do
    schema(Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)}))

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :trm do
        model(:answer)
      end

      controls do
        max_iterations(15)
        max_model_calls(15)
        output(JidoAI.Examples.TRM.Check)
      end

      requests do
        mode(:session)
        streaming(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("ai.trm.query", ai(:assistant))
  end
end
