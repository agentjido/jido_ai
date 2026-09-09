defmodule JidoAI.Examples.Steering.ObserveQueue do
  @moduledoc "Exposes the owned queue for failure checks."
  @behaviour Jido.AI.Control
  def check(_, context) do
    send(context.observer, {:input_queue, context.jido_ai_input_queue})
    :ok
  end
end

defmodule JidoAI.Examples.Steering.Agent do
  @moduledoc "Visible queued input continues one request and commits consumed history."
  use Jido.Agent, name: "ai_steering_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.string() |> Zoi.default(""),
             messages: Zoi.list(Zoi.map()) |> Zoi.default([])
           })

    ai :assistant do
      instructions("Use the latest user corrections.")

      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      requests do
        mode(:session)
        steering(true)
      end

      memory do
        history(:messages)
      end

      tools do
        action JidoAI.Examples.AIRuntime.WaitTool,
          as: :wait,
          forward_context: [:observer],
          timeout: 8_000
      end

      controls do
        timeout(10_000)
        input(JidoAI.Examples.Steering.ObserveQueue)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
