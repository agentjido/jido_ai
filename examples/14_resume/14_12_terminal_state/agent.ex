defmodule JidoAI.Examples.TerminalState.Echo do
  use Jido.Action,
    name: "terminal_echo",
    description: "Report one real tool call",
    schema: Zoi.object(%{value: Zoi.integer()})

  def run(%{value: value}, context) do
    send(context.observer, {:terminal_tool, value})
    {:ok, %{value: value}}
  end
end

defmodule JidoAI.Examples.TerminalState.Control do
  @behaviour Jido.AI.Control
  def check(_, context) do
    case context[:failure] do
      nil -> :ok
      reason -> {:error, reason}
    end
  end
end

for {module, stream} <- [
      {JidoAI.Examples.TerminalState.Buffered, false},
      {JidoAI.Examples.TerminalState.Streamed, true}
    ] do
  defmodule module do
    use Jido.Agent, name: "terminal_state", extensions: [Jido.AI.DSL]
    @stream stream

    agent do
      schema(
        Zoi.object(%{
          reply: Zoi.string() |> Zoi.default(""),
          messages: Zoi.list(Zoi.map()) |> Zoi.default([])
        })
      )

      ai :assistant do
        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        tools do
          action(JidoAI.Examples.TerminalState.Echo, as: :terminal_echo, forward_context: [:observer])
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
