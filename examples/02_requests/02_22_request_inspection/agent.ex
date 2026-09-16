defmodule JidoAI.Examples.RequestInspection.Agent do
  use Jido.AI.Agent, name: "request_inspection"

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.any() |> Zoi.default(nil),
        messages: Jido.AI.Thread.Projection.schema()
      })
    )

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      tools do
        action JidoAI.Examples.Support.Multiply, as: :multiply
      end

      reasoning :react do
        model(:answer)
      end

      memory do
        history(:messages)
      end

      observability do
        store_content true
        diagnostics_content true
        stream_content true
        stream_reasoning true
        store_reasoning true
        emit_signals(false)
        redact_tool_args(true)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("case.ask", ai(:assistant))
  end
end
