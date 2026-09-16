defmodule JidoAI.Examples.TypedSignals.Chat do
  use Jido.AI.Agent, name: "typed_signal_chat"

  agent do
    schema Zoi.object(%{reply: Zoi.string() |> Zoi.default("")})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.TypedSignals.Echo, as: :echo
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
    route "ai.ask", ai(:assistant)
  end
end
