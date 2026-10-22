defmodule JidoAI.Examples.CallCounts.Agent do
  use Jido.AI.Agent, name: "call_counts"

  agent do
    schema Zoi.object(%{reply: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        input(JidoAI.Examples.CallCounts.Input)
        model(JidoAI.Examples.CallCounts.Model)
      end

      observability do
        store_content true
        stream_content true
      end

      tools do
        action JidoAI.Examples.CallCounts.Echo, as: :scope_echo
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "case.review", ai(:assistant)
  end
end
