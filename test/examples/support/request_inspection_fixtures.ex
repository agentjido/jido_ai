defmodule JidoAI.Examples.RequestInspection.Hold do
  use Jido.Action, name: "inspect_hold", description: "Hold a tool while its request is inspected"

  def run(_, context) do
    send(context.observer, {:inspection_tool, self()})

    receive do
      :release -> {:ok, %{checked: true}}
    end
  end
end

defmodule JidoAI.Examples.RequestInspection.CancelGate do
  use Jido.Plugin

  def admit(nil, command, opts) do
    if command.signal.type == Jido.AI.Session.cancel_type() do
      send(opts[:observer], {:cancel_admission, self()})

      receive do
        :release -> :ok
      end
    end

    {:ok, command}
  end
end

defmodule JidoAI.Examples.RequestInspection.Fail do
  use Jido.Action, name: "inspect_fail", description: "Return a known tool failure"
  def run(_, _), do: {:error, %{type: :timeout, message: "search timed out"}}
end

for {module, streaming?} <- [
      {JidoAI.Examples.RequestInspection.ReplayBuffered, false},
      {JidoAI.Examples.RequestInspection.ReplayStream, true}
    ] do
  defmodule module do
    use Jido.Agent, name: "inspection_replay", extensions: [Jido.AI.DSL]
    @streaming streaming?

    agent do
      schema(
        Zoi.object(%{
          reply: Zoi.any() |> Zoi.default(nil),
          messages: Zoi.list(Zoi.map()) |> Zoi.default([])
        })
      )

      ai :assistant do
        models do
          model(:answer, JidoAI.Examples.MockLLM.model())
        end

        tools do
          action(JidoAI.Examples.RequestInspection.Hold,
            as: :inspect_hold,
            forward_context: [:observer],
            timeout: 8_000
          )

          action(JidoAI.Examples.RequestInspection.Fail, as: :inspect_fail)
        end

        reasoning :react do
          model(:answer)
        end

        requests do
          mode(:session)
          streaming(@streaming)
        end

        memory do
          history(:messages)
        end

        result(nil, into: :reply)
      end
    end

    routes do
      route("case.ask", ai(:assistant))
    end
  end
end
