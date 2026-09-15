for {module, stream} <- [
      {JidoAI.Examples.TerminalState.Buffered, false},
      {JidoAI.Examples.TerminalState.Streamed, true}
    ] do
  defmodule module do
    use Jido.AI.Agent, name: "terminal_state"
    @stream stream

    agent do
      schema(
        Zoi.object(%{
          reply: Zoi.string() |> Zoi.default(""),
          messages: Jido.AI.Conversation.schema()
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

        requests do
          mode(:session)
          streaming(@stream)
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
end
