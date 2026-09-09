defmodule JidoAI.Examples.TraceAndCycles.Check do
  @moduledoc "Observe the real tool input while its event can hide secret values."
  use Jido.Action,
    name: "check",
    description: "Check a supplied payload",
    schema: Zoi.object(%{payload: Zoi.map()})

  def run(%{payload: payload}, context) do
    send(context.observer, {:checked_payload, payload})
    {:ok, %{checked: true}}
  end
end

defmodule JidoAI.Examples.TraceAndCycles.Agent do
  @moduledoc "The native Agent DSL uses the same tool event controls as ReAct Config."
  use Jido.Agent, name: "trace_and_cycles", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{result: Zoi.any() |> Zoi.default(nil)})

    ai :assistant do
      models do
        model(:answer, JidoAI.Examples.MockLLM.model())
      end

      reasoning :react do
        model(:answer)
      end

      tools do
        action JidoAI.Examples.TraceAndCycles.Check, as: :check, forward_context: [:observer]
      end

      requests do
        mode(:session)
        streaming(false)
      end

      observability do
        redact_tool_args(false)
      end

      result(nil, into: :result)
    end
  end

  routes do
    route "ai.ask", ai(:assistant)
  end
end
