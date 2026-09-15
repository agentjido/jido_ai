defmodule JidoAI.Examples.RequestInspection.Agent do
  use Jido.AI.Agent, name: "request_inspection"

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.any() |> Zoi.default(nil),
        messages: Jido.AI.Conversation.schema()
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

      requests do
        mode(:session)
        streaming(false)
      end

      memory do
        history(:messages)
      end

      observability do
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
