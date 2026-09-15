defmodule JidoAI.Examples.TraceAndCycles.Agent do
  @moduledoc "The native Agent DSL uses the same tool event controls as ReAct Config."
  use Jido.AI.Agent, name: "trace_and_cycles"

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
        action JidoAI.Examples.TraceAndCycles.Check, as: :check
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
