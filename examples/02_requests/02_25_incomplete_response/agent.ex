defmodule JidoAI.Examples.IncompleteResponse.Agent do
  @moduledoc "A native Agent that preserves provider response status and visible content."
  use Jido.Agent, name: "incomplete_response_example", extensions: [Jido.AI.DSL]

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.any() |> Zoi.default("untouched"),
        messages: Zoi.list(Zoi.map()) |> Zoi.default([])
      })
    )

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        streaming(true)
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
