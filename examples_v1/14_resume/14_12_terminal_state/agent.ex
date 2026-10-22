defmodule JidoAI.Examples.TerminalState.Agent do
  use Jido.AI.Agent, name: "terminal_state"

  agent do
    schema(
      Zoi.object(%{
        reply: Zoi.string() |> Zoi.default(""),
        messages: Jido.AI.Thread.Projection.schema()
      })
    )

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      tools do
        action(JidoAI.Examples.TerminalState.Echo, as: :terminal_echo)
      end

      reasoning :react do
        model(:answer)
      end

      controls do
        output(JidoAI.Examples.TerminalState.Control)
      end

      memory do
        history(:messages)
      end

      observability do
        store_content true
        diagnostics_content true
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route("ai.ask", ai(:assistant))
  end
end
