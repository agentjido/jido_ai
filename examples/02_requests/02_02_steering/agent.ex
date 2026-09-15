defmodule JidoAI.Examples.Steering.Agent do
  @moduledoc "Visible queued input continues one request and commits consumed history."
  use Jido.AI.Agent, name: "ai_steering_example"

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
      end

      controls do
        timeout(10_000)
      end

      result(nil, into: :reply)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
