defmodule JidoAI.Examples.AIRuntime.Agent do
  @moduledoc "01_07: The AI DSL composes with ordinary routes and Plugin-owned state."
  use Jido.Agent, name: "ai_runtime_example", extensions: [Jido.AI.DSL]

  agent do
    schema Zoi.object(%{
             reply: Zoi.map() |> Zoi.default(%{}),
             case_id: Zoi.string() |> Zoi.default("case-42")
           })

    plugin JidoAI.Examples.Support.CommitCounter

    ai :assistant do
      instructions("Use the tool results.")

      models do
        model :answer, JidoAI.Examples.MockLLM.model() do
          generation(temperature: 0.2)
        end
      end

      reasoning :react do
        model(:answer)
        tool_concurrency(2)
      end

      tools do
        action JidoAI.Examples.Support.Multiply, as: :multiply
        flow(JidoAI.Examples.Authoring.Support.Quote, as: :quote)
      end

      controls do
        max_iterations 4
        max_model_calls(5)
        max_tool_calls(8)
        timeout(5_000)
      end

      result(Zoi.object(%{answer: Zoi.string() |> Zoi.min(1)}), into: :reply, max_repairs: 1)
    end
  end

  routes do
    signal_source "/examples/ai/runtime"

    route "ai.ask", ai(:assistant) do
      define :answer, args: [:query]
    end

    route "case.close", JidoAI.Examples.Support.CloseCase do
      define :close, args: [:reason]
    end
  end
end
